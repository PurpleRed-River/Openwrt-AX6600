#!/bin/bash

apply_sed_to_matches() {
	local SEARCH_DIR=$1
	local FILE_NAME=$2
	local SED_EXPR=$3
	local MATCHES

	MATCHES=$(find "$SEARCH_DIR" -type f -name "$FILE_NAME" 2>/dev/null)
	if [ -n "$MATCHES" ]; then
		while IFS= read -r TARGET_FILE; do
			sed -i "$SED_EXPR" "$TARGET_FILE"
		done <<< "$MATCHES"
	fi
}

#移除luci-app-attendedsysupgrade
apply_sed_to_matches "./feeds/luci/collections/" "Makefile" "/attendedsysupgrade/d"

#修改默认主题（RivWRT：aurora；WRT_THEME 为空或 bootstrap 时不替换）
if [ -n "$WRT_THEME" ] && [ "$WRT_THEME" != "bootstrap" ]; then
	sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")
	echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config
fi

#修改immortalwrt.lan关联IP
apply_sed_to_matches "./feeds/luci/modules/luci-mod-system/" "flash.js" "s/192\\.168\\.[0-9]*\\.[0-9]*/$WRT_IP/g"
#添加编译日期标识
apply_sed_to_matches "./feeds/luci/modules/luci-mod-status/" "10_system.js" "s/(\\(luciversion || ''\\))/(\\1) + (' \\/ $WRT_MARK-$WRT_DATE')/g"

WIFI_SH=$(find ./target/linux/{mediatek/filogic,qualcommax}/base-files/etc/uci-defaults/ -type f -name "*set-wireless.sh" 2>/dev/null)
WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
if [ -f "$WIFI_SH" ]; then
	#修改WIFI名称
	sed -i "s/BASE_SSID='.*'/BASE_SSID='$WRT_SSID'/g" "$WIFI_SH"
	#修改WIFI密码
	sed -i "s/BASE_WORD='.*'/BASE_WORD='$WRT_WORD'/g" "$WIFI_SH"
elif [ -f "$WIFI_UC" ]; then
	#修改WIFI名称
	sed -i "s/ssid='.*'/ssid='$WRT_SSID'/g" $WIFI_UC
	#修改WIFI密码
	sed -i "s/key='.*'/key='$WRT_WORD'/g" $WIFI_UC
	#修改WIFI地区
	#sed -i "s/country='.*'/country='US'/g" $WIFI_UC
	#修改WIFI加密
	#sed -i "s/encryption='.*'/encryption='psk2+ccmp'/g" $WIFI_UC
fi

CFG_FILE="./package/base-files/files/bin/config_generate"
#修改默认IP地址
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" "$CFG_FILE"
#修改默认主机名
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" "$CFG_FILE"

#配置文件修改
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
#echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config
#echo "CONFIG_PACKAGE_luci-app-$WRT_THEME-config=y" >> ./.config

#手动调整的插件
if [ -n "$WRT_PACKAGE" ]; then
	echo -e "$WRT_PACKAGE" >> ./.config
fi

#高通平台调整
DTS_PATH="./target/linux/qualcommax/dts/"
if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then
	#无WIFI配置调整Q6大小
	if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
		find "$DTS_PATH" -type f ! -iname '*nowifi*' -exec sed -i 's/ipq\(6018\|8074\).dtsi/ipq\1-nowifi.dtsi/g' {} +
		echo "qualcommax set up nowifi successfully!"
	fi
fi

# =========================================================
# 智能系统调优：优化内存水位线 (min_free_kbytes)
# =========================================================

MIN_FREE_VAL=16384
CONF_FILE="./package/base-files/files/etc/sysctl.conf"

# 提取当前值（只匹配非注释、行首）
CURRENT_VAL=$(sed -n 's/^vm\.min_free_kbytes=\([0-9]\+\).*/\1/p' "$CONF_FILE")

if [ -z "$CURRENT_VAL" ]; then
    echo "" >> "$CONF_FILE"
    echo "vm.min_free_kbytes=$MIN_FREE_VAL" >> "$CONF_FILE"
    echo "Memory patch: value not found, added $MIN_FREE_VAL."
else
    if [ "$CURRENT_VAL" -lt "$MIN_FREE_VAL" ]; then
        sed -i "s/^vm\.min_free_kbytes=.*/vm.min_free_kbytes=$MIN_FREE_VAL/" "$CONF_FILE"
        echo "Memory patch: upgraded $CURRENT_VAL -> $MIN_FREE_VAL."
    else
        echo "Memory patch: current value ($CURRENT_VAL) is sufficient, skipped."
    fi
fi

# =========================================================
# RivWRT：banner 标识（简短一行，注明上游来源与定制身份）
# =========================================================
for BANNER in $(find ./package ./target -type f -path "*base-files*/etc/banner" 2>/dev/null); do
	if ! grep -q "RivWRT" "$BANNER"; then
		cat >> "$BANNER" <<'RIVWRT_BANNER'

RivWRT (based on ones20250/Openwrt-AX6600) | aurora / athena-led / bandix-plus / daede
RIVWRT_BANNER
	fi
done

# =========================================================
# RivWRT：网口互换（首刷自动生效）
# 默认布局：wan = 2.5G 口，lan1-4 = 千兆
# 定制布局：2.5G 口(wan)并入 br-lan 做内网，原 lan1 改做 WAN
# 用途：千兆宽带接原 LAN1 丝印口，2.5G 口留给内网高速互访
# =========================================================
UDIR="./package/base-files/files/etc/uci-defaults"
mkdir -p "$UDIR"
cat > "$UDIR/99-rivwrt-lan-wan-swap" <<'RIVWRT_SWAP'
#!/bin/sh
# 仅对京东云雅典娜 RE-CS-02 生效，其他设备跳过
[ "$(cat /tmp/sysinfo/board_name 2>/dev/null)" = "jdcloud,re-cs-02" ] || exit 0
# br-lan：移出 lan1，加入 2.5G 口（设备名 wan）
for DEV in 0 1 2 3 4; do
	NAME=$(uci -q get network.@device[$DEV].name)
	[ "$NAME" = "br-lan" ] && uci set network.@device[$DEV].ports='wan lan2 lan3 lan4'
done
# wan 接口：物理设备从 2.5G 口改为 lan1
uci -q set network.wan.device='lan1'
uci -q set network.wan6.device='lan1'
uci commit network
RIVWRT_SWAP
chmod +x "$UDIR/99-rivwrt-lan-wan-swap"

# =========================================================
# RivWRT：内核分区尺寸适配（匹配已刷 GPT 的 A 槽布局）
# 实测分区：0:HLOS(p16)=12288KB，rootfs(p18)=2GiB（chenxin527 uboot 双分区）。
# 上游树默认 KERNEL_SIZE=6144k（官方 B 槽尺寸），factory/sysupgrade 的
# kernel 段须 pad 到 12288k 才与 GPT 对齐，否则 rootfs 起点错位无法启动
# =========================================================
IMG_MK="./target/linux/qualcommax/image/ipq60xx.mk"
if [ -f "$IMG_MK" ]; then
	sed -i "/Device\/jdcloud_re-cs-02/,/TARGET_DEVICES += jdcloud_re-cs-02/ s/KERNEL_SIZE := 6144k/KERNEL_SIZE := 12288k/" "$IMG_MK"
	echo "RivWRT: KERNEL_SIZE -> 12288k (A槽 12MiB 内核分区)"
fi
