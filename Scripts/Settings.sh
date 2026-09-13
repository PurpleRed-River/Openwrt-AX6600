#!/bin/bash
# =========================================================
# RivWRT 构建期定制脚本
# 由 WRT-CORE.yml 在 make defconfig 之前调用（cwd = wrt 源码树根）
#
# 本脚本产出的内容：
#   /etc/uci-defaults  96-fullcone · 98-net-fix · 99-podman · 99-menus
#   /etc/init.d        rivwrt-wifi（三频固化，S99 自启）+ banner
#   /package/          自建包：luci-app-rivwrt-nss · podman-compose
#   树内补丁（白名单）：DTS 端口互换 · KERNEL_SIZE=12288k ·
#                      daede 暗色屏蔽 · 主题依赖/SSID/内存水位线
#
# 自建包清单与提取模式见本文件"组件注入"区块；
# 配置增量见 Config/GENERAL_AX6600_RIVWRT.txt。
# =========================================================

# -------------------------------------------------------
# 工具函数
# -------------------------------------------------------

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

# -------------------------------------------------------
# 移除不需要的包
# -------------------------------------------------------

apply_sed_to_matches "./feeds/luci/collections/" "Makefile" "/attendedsysupgrade/d"

# -------------------------------------------------------
# 主题设置（aurora + 编译期默认替换）
# -------------------------------------------------------

if [ -n "$WRT_THEME" ] && [ "$WRT_THEME" != "bootstrap" ]; then
	sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")
fi

# -------------------------------------------------------
# IP 与主机名
# -------------------------------------------------------

apply_sed_to_matches "./feeds/luci/modules/luci-mod-system/" "flash.js" "s/192\\.168\\.[0-9]*\\.[0-9]*/$WRT_IP/g"
apply_sed_to_matches "./feeds/luci/modules/luci-mod-status/" "10_system.js" "s/(\\(luciversion || ''\\))/(\\1) + (' \\/ $WRT_MARK-$WRT_DATE')/g"

# -------------------------------------------------------
# 无线 SSID：编译期按频段写入生成器模板（三频分开命名）
# -------------------------------------------------------
# 原版 mac80211.uc 第 112 行：
#     set ${si}.ssid='${defaults?.ssid || 'OWRT'}'
# board.wlan.defaults 在 jdcloud 设备上无定义 → 回退 'OWRT'（三频同名）。
#
# 曾两次走弯路：
#   ① 全局 sed 把三个频段替换成同一个 SSID → 三频合一
#   ② 交给 init.d 运行时设置 → /etc/config/wireless 由 netifd 首次启动才生成，
#      S99 跑在其之前导致空转；且旧版无条件 touch marker → 此后永久不再尝试
#      （实测：刷完仍全是 OWRT）
# 故改为编译期直接生成正确 SSID，与运行时无关、必定生效。
#
# 设备频段布局（轴线实测）：radio1=2.4G / radio0=5G(ahb,IPQ6010内建) /
# radio2=5G(QCN9074 PCIe)。模板中 band_name('2g'/'5g') 与 name('radioN') 均可用。

WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
if [ -f "$WIFI_UC" ]; then
	# SSID：按频段分名（band_name='2g'；两个 5G 用 radio 编号区分）
	sed -i "s#^set \${si}\.ssid=.*#set \${si}.ssid='\${defaults?.ssid || ((band_name == '2g') ? '$WRT_SSID' : ((name == 'radio0') ? '$WRT_SSID-5.2G' : '$WRT_SSID-5.8G'))}'#" "$WIFI_UC"

	# 信道与带宽：生成器默认 channel=auto、且 5G 强制 width<=80
	# （源码：else if (width > 80) width = 80），无法表达 HE160。
	# 故编译期按频段写死；init.d 运行时再兜底一次（双保险，避免时序问题）。
	# 取值依据：11/HT20（2.4G 非重叠）、44/HE160（5G-1 游戏，160MHz 主信道）、
	#           149/HE80（5G-2 影音，非 DFS）。
	sed -i "s#^set \${s}\.channel=.*#set \${s}.channel='\${((band_name == '2g') ? '11' : ((name == 'radio0') ? '44' : '149'))}'#" "$WIFI_UC"
	sed -i "s#^set \${s}\.htmode=.*#set \${s}.htmode='\${((band_name == '2g') ? 'HT20' : ((name == 'radio0') ? 'HE160' : 'HE80'))}'#" "$WIFI_UC"

	# 国家码：生成器默认 'CN'（board.wlan.defaults 在本设备无定义 → 回落）。
	# ★ 必须编译期设定：ath11k 对【运行时】切换国家码脆弱 —— 实测 dmesg 报
	#   WARNING at net/wireless/reg.c:4035 reg_get_max_bandwidth [cfg80211]
	#   Call trace: ath11k_regd_update → regulatory_set_wiphy_regd
	#   → ath11k_pci: failed to perform regd update : -22
	#   （init.d 里 uci set country 再 wifi reload 即触发该热切换）
	sed -i "s#^set \${s}\.country=.*#set \${s}.country='US'#" "$WIFI_UC"

	echo "RivWRT: per-band SSID + channel + htmode + country(US) injected"
fi

# -------------------------------------------------------
# 默认 IP / 主机名
# -------------------------------------------------------

CFG_FILE="./package/base-files/files/bin/config_generate"
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" "$CFG_FILE"
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" "$CFG_FILE"

echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config

# -------------------------------------------------------
# RivWRT 增量配置兜底拼接（不依赖 workflow 层的 WRT_EXTRA_CONFIG）
# 实测 6dfacd3 固件：VERSION_DIST 与 rivwrt-nss 行均未生效，而同在
# 基座 GENERAL_AX6600.txt 的 qca-nss-ecm 生效 → 疑似增量文件未被拼接。
# 这里无条件再拼一次（kconfig 对重复行取最后值，幂等安全）。
# -------------------------------------------------------
RIVWRT_CFG="$GITHUB_WORKSPACE/Config/GENERAL_AX6600_RIVWRT.txt"
if [ -f "$RIVWRT_CFG" ]; then
	cat "$RIVWRT_CFG" >> ./.config
	echo "RivWRT: increment config appended (fallback, $(grep -c '^CONFIG' "$RIVWRT_CFG") lines)"
fi

# -------------------------------------------------------
# 高通平台 DTS 调整
# -------------------------------------------------------

if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then
	DTS_PATH="./target/linux/qualcommax/dts/"
	if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
		find "$DTS_PATH" -type f ! -iname '*nowifi*' -exec sed -i 's/ipq\(6018\|8074\).dtsi/ipq\1-nowifi.dtsi/g' {} +
		echo "qualcommax set up nowifi successfully!"
	fi
fi

# -------------------------------------------------------
# 内存水位线调优
# -------------------------------------------------------

MIN_FREE_VAL=16384
CONF_FILE="./package/base-files/files/etc/sysctl.conf"
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

# -------------------------------------------------------
# RivWRT：登录 banner（figlet 字样 + 格言 + 组件行）
# -------------------------------------------------------

BANNER="./package/base-files/files/etc/banner"
[ -f "$BANNER" ] && cat > "$BANNER" <<'RIVWRT_BANNER'
'||''|.    ||           '|| '||'  '|' '||''|.   |''||''| 
 ||   ||  ...  .... ...  '|. '|.  .'   ||   ||     ||    
 ||''|'    ||   '|.  |    ||  ||  |    ||''|'      ||    
 ||   |.   ||    '|.|      ||| |||     ||   |.     ||    
.||.  '|' .||.    '|        |   |     .||.  '|'   .||.    

           " Flow downstream, not upstream. "

 =======================================================
   RivWRT - based on ones20250/Openwrt-AX6600
   aurora / athena-led / bandix-plus / daede / nss
   ImmortalWrt %V, %C
 =======================================================
RIVWRT_BANNER

# -------------------------------------------------------
# RivWRT：openwrt_release 品牌硬钉（不依赖 kconfig 的 VERSION_DIST）
# CONFIG_VERSION_DIST 的 prompt 挂在 "if DEVEL" 下，defconfig 可能丢弃
# 用户值回落 default "ImmortalWRT"（实测 6dfacd3 固件未生效）。
# 故直接改 base-files 的 openwrt_release 模板：DISTRIB_ID/DESCRIPTION
# 硬编码 RivWRT，%V/%C 仍由构建系统展开（版本号/revision 照常显示）。
# 该模板会被 VERSION_SED 处理，属官方机制内的注入点，升级安全。
# -------------------------------------------------------
RELEASE_FILE="./package/base-files/files/etc/openwrt_release"
if [ -f "$RELEASE_FILE" ]; then
	sed -i "s/^DISTRIB_ID=.*/DISTRIB_ID='RivWRT'/" "$RELEASE_FILE"
	sed -i "s/^DISTRIB_DESCRIPTION=.*/DISTRIB_DESCRIPTION='RivWRT %V %C'/" "$RELEASE_FILE"
	echo "RivWRT: openwrt_release branded (DISTRIB_ID/DESCRIPTION)"
fi
# -------------------------------------------------------
# RivWRT：内核分区尺寸适配（A 槽 12MiB 内核）
# -------------------------------------------------------

IMG_MK="./target/linux/qualcommax/image/ipq60xx.mk"
if [ -f "$IMG_MK" ]; then
	sed -i "/Device\/jdcloud_re-cs-02/,/TARGET_DEVICES += jdcloud_re-cs-02/ s/KERNEL_SIZE := 6144k/KERNEL_SIZE := 12288k/" "$IMG_MK"
	echo "RivWRT: KERNEL_SIZE -> 12288k (A槽 12MiB 内核分区)"
fi

# -------------------------------------------------------
# RivWRT：DTS 端口 label 互换（根治网口互换）
# 实测映射：丝印 WAN(2.5G)=dp5(wan)，丝印 LAN1=dp1(lan1)
# 互换后：系统名 = 物理丝印 = 角色语义一致
# -------------------------------------------------------

DTS_FILE="./target/linux/qualcommax/dts/ipq6010-re-cs-02.dts"
sed -i "/&dp1 {/,/};/ s/label = \"lan1\"/label = \"wan\"/" "$DTS_FILE"
sed -i "/&dp5 {/,/};/ s/label = \"wan\"/label = \"lan1\"/" "$DTS_FILE"

# -------------------------------------------------------
# RivWRT：daede 暗色屏蔽
# -------------------------------------------------------

CFG_JS=$(find ./package/luci-app-daede -name "config.js" 2>/dev/null | head -1)
[ -n "$CFG_JS" ] && sed -i "s#document\.documentElement\.setAttribute('data-darkmode', 'true');#/* RivWRT: keep global dark-mode flag untouched */#" "$CFG_JS"

# -------------------------------------------------------
# RivWRT：uci-defaults 目标目录
# -------------------------------------------------------

UDIR="./package/base-files/files/etc/uci-defaults"
mkdir -p "$UDIR"

# -------------------------------------------------------
# uci-defaults：FullCone NAT（IPv4）
# -------------------------------------------------------

cat > "$UDIR/96-rivwrt-fullcone" <<'RIVWRT_FC'
#!/bin/sh
uci -q set firewall.@defaults[0].fullcone='1'
uci commit firewall
RIVWRT_FC
chmod +x "$UDIR/96-rivwrt-fullcone"

# -------------------------------------------------------
# uci-defaults：网络配置对新端口命名的纠正
# -------------------------------------------------------

cat > "$UDIR/98-rivwrt-net-fix" <<'RIVWRT_NETFIX'
#!/bin/sh
for DEV in 0 1 2 3 4; do
	NAME=$(uci -q get network.@device[$DEV].name)
	[ "$NAME" = "br-lan" ] && uci set network.@device[$DEV].ports='lan1 lan2 lan3 lan4'
done
uci -q set network.wan.device='wan'
uci -q set network.wan6.device='wan'
uci commit network
RIVWRT_NETFIX
chmod +x "$UDIR/98-rivwrt-net-fix"

# -------------------------------------------------------
# uci-defaults：podman API 服务默认关闭
# -------------------------------------------------------

cat > "$UDIR/99-rivwrt-podman" <<'RIVWRT_PODMAN'
#!/bin/sh
/etc/init.d/podman stop 2>/dev/null
/etc/init.d/podman disable 2>/dev/null
RIVWRT_PODMAN
chmod +x "$UDIR/99-rivwrt-podman"

# -------------------------------------------------------
# uci-defaults：菜单归拢
# -------------------------------------------------------

cat > "$UDIR/99-rivwrt-menus" <<'RIVWRT_MENUS'
#!/bin/sh
[ -f /usr/share/luci/menu.d/luci-app-wolultra.json ] && \
	sed -i "s#\"admin/control/wolultra\"#\"admin/services/wolultra\"#" /usr/share/luci/menu.d/luci-app-wolultra.json
[ -f /usr/share/luci/menu.d/luci-app-samba4.json ] && \
	sed -i "s#\"admin/nas/samba4\"#\"admin/services/samba4\"#" /usr/share/luci/menu.d/luci-app-samba4.json
[ -f /usr/share/luci/menu.d/luci-app-bandix-plus.json ] && \
	sed -i "s#admin/network/bandix_plus#admin/services/bandix_plus#g" /usr/share/luci/menu.d/luci-app-bandix-plus.json
RIVWRT_MENUS
chmod +x "$UDIR/99-rivwrt-menus"


# =========================================================
# RivWRT：podman-compose 包（上游 feeds 无此包，自建）
# PyPI sdist 打包，依赖 python3 + python3-yaml + python3-dotenv
# 版本与哈希已钉死，纯 Python 无需编译
# =========================================================
PCDIR=./package/podman-compose
mkdir -p $PCDIR
cat > $PCDIR/Makefile <<'EOF'
include $(TOPDIR)/rules.mk

PKG_NAME:=podman-compose
PKG_VERSION:=1.6.0
PKG_RELEASE:=1

PKG_SOURCE:=podman_compose-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://files.pythonhosted.org/packages/1f/80/a6ada19562b12ed466dac5c3e02aef5ed7c8d0881864d80e0d94d0dc71f5/
PKG_HASH:=c83fd9bcbaa635100d581ce52a7a4b712ee0d457481232aff392efe3ebc5a217
PKG_BUILD_DIR:=$(BUILD_DIR)/podman_compose-$(PKG_VERSION)

PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=RivWRT

include $(INCLUDE_DIR)/package.mk

define Package/podman-compose
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=docker-compose implementation for podman (CLI)
  DEPENDS:=+python3 +python3-yaml +python3-dotenv +podman
endef

define Package/podman-compose/description
  podman-compose: run docker-compose.yml stacks with podman (CLI only).
endef

Build/Compile:=:

define Package/podman-compose/install
	$(INSTALL_DIR) $(1)/usr/lib/podman-compose
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/podman_compose.py $(1)/usr/lib/podman-compose/podman_compose.py
	$(INSTALL_DIR) $(1)/usr/bin
	$(LN) ../lib/podman-compose/podman_compose.py $(1)/usr/bin/podman-compose
endef

$(eval $(call BuildPackage,podman-compose))
EOF

# =========================================================
# RivWRT：luci-app-rivwrt-nss —— NSS 开关与状态页（独立包）
# =========================================================
PKGDIR=./package/luci-app-rivwrt-nss
mkdir -p $PKGDIR/root/usr/share/luci/menu.d \
	$PKGDIR/root/usr/share/rpcd/acl.d \
	$PKGDIR/root/www/luci-static/resources/view/rivwrt \
	$PKGDIR/root/usr/libexec/rivwrt

cat > $PKGDIR/Makefile <<'EOF'
include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-rivwrt-nss
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

LUCI_TITLE:=RivWRT NSS acceleration toggle and live status
LUCI_DEPENDS:=+luci-base
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

define Package/$(PKG_NAME)/description
  RivWRT 定制：NSS 硬件加速开关与实时状态（引擎负载/时钟/加速连接数）
endef

# call BuildPackage - OpenWrt buildroot signature
EOF

cat > $PKGDIR/root/usr/share/luci/menu.d/luci-app-rivwrt-nss.json <<'EOF'
{
	"admin/services/rivwrt_nss": {
		"title": "NSS 加速",
		"order": 30,
		"action": { "type": "firstchild" },
		"depends": { "acl": [ "luci-app-rivwrt-nss" ], "fs": { "/etc/init.d/qca-nss-ecm": "file" } }
	},
	"admin/services/rivwrt_nss/status": {
		"title": "状态与开关",
		"order": 10,
		"action": { "type": "view", "path": "rivwrt/nss" },
		"depends": { "acl": [ "luci-app-rivwrt-nss" ] }
	}
}
EOF

cat > $PKGDIR/root/usr/share/rpcd/acl.d/luci-app-rivwrt-nss.json <<'EOF'
{
	"luci-app-rivwrt-nss": {
		"description": "Grant access to RivWRT NSS control and status",
		"read": {
			"ubus": {
				"service": [ "list" ],
				"file": [ "exec" ]
			},
			"file": {
				"/usr/libexec/rivwrt/nss-status": [ "exec" ],
				"/usr/libexec/rivwrt/nss-status 2h": [ "exec" ],
				"/usr/libexec/rivwrt/nss-status 12h": [ "exec" ],
				"/usr/libexec/rivwrt/nss-status 1d": [ "exec" ],
				"/usr/libexec/rivwrt/nss-status 1w": [ "exec" ],
				"/etc/init.d/qca-nss-ecm enabled": [ "exec" ]
			}
		},
		"write": {
			"ubus": {
				"file": [ "exec" ]
			},
			"file": {
				"/usr/libexec/rivwrt/nss-status": [ "exec" ],
				"/usr/libexec/rivwrt/nss-status 2h": [ "exec" ],
				"/usr/libexec/rivwrt/nss-status 12h": [ "exec" ],
				"/usr/libexec/rivwrt/nss-status 1d": [ "exec" ],
				"/usr/libexec/rivwrt/nss-status 1w": [ "exec" ],
				"/etc/init.d/qca-nss-ecm enabled": [ "exec" ],
				"/etc/init.d/qca-nss-ecm start": [ "exec" ],
				"/etc/init.d/qca-nss-ecm stop": [ "exec" ],
				"/etc/init.d/qca-nss-ecm enable": [ "exec" ],
				"/etc/init.d/qca-nss-ecm disable": [ "exec" ]
			}
		}
	}
}
EOF

cat > $PKGDIR/root/www/luci-static/resources/view/rivwrt/nss.js <<'EOF'
'use strict';
'require view';
'require poll';
'require rpc';
'require dom';
'require ui';

/* RivWRT NSS 加速：开关 + 负载历史图
   数据源：/usr/libexec/rivwrt/nss-status（debugfs 实时 + RRD 历史）
   控制：/etc/init.d/qca-nss-ecm start|stop|enable|disable
   样式沿用 aurora 主题 token（var(--brand) 等，附 sRGB 回退值） */

var NS = 'http://www.w3.org/2000/svg';
var RANGES = { '2h': '2 小时', '12h': '12 小时', '1d': '1 天', '1w': '1 周' };
var LABEL = { '2h': '30s 采样', '12h': '2.5min 聚合', '1d': '5min 聚合', '1w': '30min 聚合' };

/* 不设 expect: {code:0}：命令失败时 Promise 会被 reject，错误被 LuCI 吞掉，
   用户只看到"点击没反应"。改为手动检查 code 并把 stderr 展示出来。 */
var callExec = rpc.declare({
	object: 'file', method: 'exec',
	params: [ 'command', 'params' ]
});

function sx(tag, attrs) {
	var e = document.createElementNS(NS, tag);
	for (var k in (attrs || {}))
		e.setAttribute(k, attrs[k]);
	return e;
}

function readStatus(range) {
	return callExec('/usr/libexec/rivwrt/nss-status', [ range || '2h' ]).then(function (res) {
		var out = { load: {} };
		(res.stdout || '').split('\n').forEach(function (line) {
			var m = line.match(/^([a-z_0-9]+)=(.*)$/);
			if (!m) return;
			if (m[1].indexOf('load_') === 0)
				out.load[m[1].substring(5)] = m[2];
			else
				out[m[1]] = m[2];
		});
		return out;
	}).catch(function () { return { load: {} }; });
}

function notifyError(msg) {
	ui.addNotification(null, E('p', {}, msg), 'error');
}

/* 执行 qca-nss-ecm 的 init 动作，失败时把退出码与 stderr 显示给用户
   （原实现错误被静默吞掉，表现为"点击没反应"）。 */
function control(action) {
	var labels = { start: _('启用'), stop: _('停用'), enable: _('开启自启'), disable: _('关闭自启') };
	return callExec('/etc/init.d/qca-nss-ecm', [ action ]).then(function (res) {
		if (!res || res.code !== 0) {
			var detail = (res && res.stderr ? String(res.stderr).trim() : '') || _('无输出');
			notifyError(_('%s失败（退出码 %s）：%s').format(
				labels[action] || action, (res && res.code !== undefined) ? res.code : '?', detail));
		}
		return res;
	}).catch(function (err) {
		notifyError(_('%s时调用出错：%s').format(labels[action] || action, err && err.message ? err.message : err));
	});
}

/* 单调三次插值（Fritsch–Carlson）：平滑且不过冲 0~100 */
function monotone(xs, ys) {
	var n = xs.length, i;
	if (n < 2) return '';
	var dx = [], dy = [], m = [];
	for (i = 0; i < n - 1; i++) {
		dx[i] = xs[i + 1] - xs[i];
		dy[i] = ys[i + 1] - ys[i];
		m[i] = dx[i] ? dy[i] / dx[i] : 0;
	}
	var t = new Array(n);
	t[0] = m[0]; t[n - 1] = m[n - 2];
	for (i = 1; i < n - 1; i++) {
		if (m[i - 1] * m[i] <= 0) t[i] = 0;
		else {
			var w1 = 2 * dx[i] + dx[i - 1], w2 = dx[i] + 2 * dx[i - 1];
			t[i] = (w1 + w2) / (w1 / m[i - 1] + w2 / m[i]);
		}
	}
	var d = 'M' + xs[0].toFixed(2) + ',' + ys[0].toFixed(2);
	for (i = 0; i < n - 1; i++) {
		var x1 = xs[i] + dx[i] / 3, y1 = ys[i] + t[i] * dx[i] / 3;
		var x2 = xs[i + 1] - dx[i] / 3, y2 = ys[i + 1] - t[i + 1] * dx[i] / 3;
		d += ' C' + x1.toFixed(2) + ',' + y1.toFixed(2) + ' ' + x2.toFixed(2) + ',' + y2.toFixed(2) +
			' ' + xs[i + 1].toFixed(2) + ',' + ys[i + 1].toFixed(2);
	}
	return d;
}

function fmtTime(ts, range) {
	var d = new Date(ts * 1000);
	function z(x) { return (x < 10 ? '0' : '') + x; }
	if (range === '1w' || range === '1d')
		return (d.getMonth() + 1) + '/' + d.getDate() + ' ' + z(d.getHours()) + ':' + z(d.getMinutes());
	return z(d.getHours()) + ':' + z(d.getMinutes()) + ':' + z(d.getSeconds());
}

var CSS = [
'.rw-root{max-width:74rem}',
'.rw-hd{display:flex;align-items:flex-start;justify-content:space-between;gap:18px;flex-wrap:wrap;margin-bottom:22px}',
'.rw-hd h1{font-size:22px;font-weight:700;letter-spacing:-.02em;margin:0}',
'.rw-hd p{font-size:13.5px;color:var(--text-muted,#5f666d);margin:6px 0 0;line-height:1.6}',
'.rw-tag{display:inline-flex;align-items:center;gap:8px;padding:6px 13px;border-radius:999px;font-size:12.5px;font-weight:600;border:1px solid var(--hairline,rgba(18,26,34,.13));background:var(--surface,#fff);box-shadow:var(--app-shadow-sm,0 1px 3px rgba(0,0,0,.06))}',
'.rw-tag i{width:7px;height:7px;border-radius:50%;background:var(--text-subtle,#7f858b);flex-shrink:0;display:block}',
'.rw-tag[data-s=run]{color:var(--success,#004f3e);border-color:color-mix(in oklab,var(--success,#004f3e) 30%,var(--hairline,rgba(18,26,34,.13)));background:var(--success-surface,#eefaf5)}',
'.rw-tag[data-s=run] i{background:var(--success,#004f3e)}',
'.rw-tag[data-s=stop]{color:var(--danger,#8d1925);border-color:color-mix(in oklab,var(--danger,#8d1925) 30%,var(--hairline,rgba(18,26,34,.13)));background:var(--danger-surface,#fdeef0)}',
'.rw-tag[data-s=stop] i{background:var(--danger,#8d1925)}',
'.rw-hero{display:flex;align-items:center;justify-content:space-between;gap:28px;flex-wrap:wrap;background:var(--surface,#fff);border:1px solid var(--hairline,rgba(18,26,34,.13));border-radius:calc(var(--radius-base,.5rem)*2);box-shadow:var(--app-shadow-md,0 4px 16px rgba(0,0,0,.08));padding:24px 26px}',
'.rw-hero-info{flex:1 1 20rem;min-width:min(100%,24ch)}',
'.rw-hero h2{font-size:16.5px;font-weight:700;letter-spacing:-.015em;margin:0}',
'.rw-desc{font-size:13.5px;color:var(--text-muted,#5f666d);margin:8px 0 0;line-height:1.65;max-width:52ch}',
'.rw-ctl{display:flex;align-items:center;gap:14px;flex-shrink:0}',
'.rw-ctl-txt{text-align:right;min-width:8.5em}',
'.rw-ctl-txt b{display:block;font-size:13.5px;font-weight:700}',
'.rw-ctl-txt span{display:block;font-size:12px;color:var(--text-muted,#5f666d);margin-top:2px}',
'.rw-tgl{position:relative;width:58px;height:33px;border-radius:999px;cursor:pointer;appearance:none;border:1px solid var(--hairline,rgba(18,26,34,.13));background:var(--surface-sunken,#f4f7fa);transition:.22s;flex-shrink:0;padding:0}',
'.rw-tgl:after{content:"";position:absolute;top:3px;left:3px;width:25px;height:25px;border-radius:50%;background:var(--surface,#fff);box-shadow:var(--app-shadow-sm,0 1px 3px rgba(0,0,0,.06));transition:.22s cubic-bezier(.4,0,.2,1)}',
'.rw-tgl[aria-checked=true]{background:var(--brand,#0085b5);border-color:var(--brand,#0085b5)}',
'.rw-tgl[aria-checked=true]:after{transform:translateX(25px)}',
'.rw-tgl.rw-sm{width:50px;height:29px}',
'.rw-tgl.rw-sm:after{width:21px;height:21px}',
'.rw-tgl.rw-sm[aria-checked=true]:after{transform:translateX(21px)}',
'.rw-chart{background:var(--surface,#fff);border:1px solid var(--hairline,rgba(18,26,34,.13));border-radius:calc(var(--radius-base,.5rem)*2);box-shadow:var(--app-shadow-md,0 4px 16px rgba(0,0,0,.08));padding:20px 24px 14px;margin-top:20px}',
'.rw-ch-head{display:flex;align-items:flex-start;justify-content:space-between;gap:18px;flex-wrap:wrap}',
'.rw-ch-head h2{font-size:11.5px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;color:var(--text-subtle,#7f858b);margin:0}',
'.rw-ch-val{display:flex;align-items:baseline;gap:6px;margin-top:7px}',
'.rw-ch-val b{font-family:var(--font-mono,monospace);font-size:34px;font-weight:500;letter-spacing:-.045em;line-height:1}',
'.rw-ch-val u{text-decoration:none;font-size:15px;color:var(--text-muted,#5f666d);font-weight:600}',
'.rw-ch-val span{font-size:12px;color:var(--text-subtle,#7f858b);margin-left:5px}',
'.rw-seg{display:inline-flex;padding:3px;gap:2px;border:1px solid var(--hairline,rgba(18,26,34,.13));border-radius:calc(var(--radius-base,.5rem)*.875);background:var(--surface-sunken,#f4f7fa)}',
'.rw-seg button{font:inherit;font-size:12.5px;font-weight:600;padding:6px 13px;border:0;cursor:pointer;background:transparent;color:var(--text-muted,#5f666d);border-radius:calc(var(--radius-base,.5rem)*.625);transition:.14s}',
'.rw-seg button:hover{color:var(--text,#121a22)}',
'.rw-seg button[aria-selected=true]{background:var(--surface,#fff);color:var(--brand,#0085b5);box-shadow:var(--app-shadow-sm,0 1px 3px rgba(0,0,0,.06))}',
'.rw-wrap{position:relative;margin-top:14px}',
'.rw-svg{display:block;width:100%;height:238px;overflow:visible}',
'.rw-tip{position:absolute;top:0;left:0;pointer-events:none;opacity:0;transition:opacity .12s;background:var(--surface,#fff);border:1px solid var(--hairline,rgba(18,26,34,.13));border-radius:var(--radius-base,.5rem);box-shadow:var(--app-shadow-md,0 4px 16px rgba(0,0,0,.08));padding:8px 11px;white-space:nowrap;z-index:3}',
'.rw-tip.on{opacity:1}',
'.rw-tip-t{display:block;font-family:var(--font-mono,monospace);font-size:10.5px;color:var(--text-subtle,#7f858b)}',
'.rw-tip-v{display:block;font-family:var(--font-mono,monospace);font-size:15px;font-weight:600;margin-top:3px}',
'.rw-ch-foot{display:flex;justify-content:space-between;gap:14px;flex-wrap:wrap;margin-top:12px;padding-top:11px;border-top:1px solid var(--hairline,rgba(18,26,34,.13));font-family:var(--font-mono,monospace);font-size:11px;color:var(--text-subtle,#7f858b)}',
'.rw-kpis{display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:16px;margin-top:20px}',
'.rw-kpi{background:var(--surface,#fff);border:1px solid var(--hairline,rgba(18,26,34,.13));border-radius:calc(var(--radius-base,.5rem)*1.5);box-shadow:var(--app-shadow-sm,0 1px 3px rgba(0,0,0,.06));padding:18px 20px}',
'.rw-kpi em{display:block;font-style:normal;font-size:11.5px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;color:var(--text-subtle,#7f858b);margin-bottom:10px}',
'.rw-v{font-family:var(--font-mono,monospace);font-size:23px;font-weight:500;letter-spacing:-.03em;display:flex;align-items:baseline;gap:3px}',
'.rw-v u{text-decoration:none;font-size:12.5px;color:var(--text-muted,#5f666d);font-weight:400}',
'.rw-kpi.rw-row{display:flex;align-items:center;justify-content:space-between;gap:14px}',
'.rw-kpi.rw-row em{margin-bottom:0}',
'.rw-mini{display:flex;align-items:center;gap:11px}',
'.rw-lb{font-size:12.5px;font-weight:600;color:var(--text-muted,#5f666d)}',
'.rw-note{margin-top:20px;font-size:12.5px;color:var(--text-subtle,#7f858b);line-height:1.75;max-width:80ch}',
'.rw-empty{font-size:12.5px;color:var(--text-subtle,#7f858b);padding:28px 0;text-align:center}',
'@media(max-width:720px){.rw-hero{flex-direction:column;align-items:stretch}.rw-ctl{justify-content:space-between}.rw-ctl-txt{text-align:left}}'
].join('\n');

return view.extend({
	load: function () {
		return readStatus('2h');
	},

	render: function (st) {
		var self = this;
		this.st = st || { load: {} };
		this.range = '2h';
		this.parseHist(this.st);

		/* ── 页头 ── */
		this.tagDot = E('i');
		this.tagTxt = E('span');
		this.tagEl = E('span', { 'class': 'rw-tag' }, [ this.tagDot, this.tagTxt ]);
		var header = E('div', { 'class': 'rw-hd' }, [
			E('div', {}, [
				E('h1', {}, _('NSS 硬件加速')),
				E('p', {}, _('直连流量由 NSS 引擎硬件转发；代理流量交由 dae 内核态接管'))
			]),
			this.tagEl
		]);

		/* ── 主控卡：硬件加速开关 ── */
		this.swRun = E('button', {
			'class': 'rw-tgl', 'role': 'switch', 'aria-checked': 'false', 'aria-label': _('硬件加速开关'),
			'click': ui.createHandlerFn(this, function () { return this.toggleRun(); })
		});
		this.lbRun = E('span');
		this.descEl = E('p', { 'class': 'rw-desc' });
		var hero = E('section', { 'class': 'rw-hero' }, [
			E('div', { 'class': 'rw-hero-info' }, [ E('h2', {}, _('引擎控制')), this.descEl ]),
			E('div', { 'class': 'rw-ctl' }, [
				E('span', { 'class': 'rw-ctl-txt' }, [ E('b', {}, _('硬件加速')), this.lbRun ]),
				this.swRun
			])
		]);

		/* ── 图表卡 ── */
		this.segEl = E('div', { 'class': 'rw-seg' });
		Object.keys(RANGES).forEach(function (r) {
			self.segEl.appendChild(E('button', {
				'data-range': r,
				'aria-selected': (r === '2h') ? 'true' : 'false',
				'click': ui.createHandlerFn(self, function () { return self.setRange(r); })
			}, _(RANGES[r])));
		});

		this.svg = sx('svg', { 'viewBox': '0 0 940 238', 'preserveAspectRatio': 'none', 'class': 'rw-svg' });
		this.tipT = E('span', { 'class': 'rw-tip-t' });
		this.tipV = E('span', { 'class': 'rw-tip-v' });
		this.tip = E('div', { 'class': 'rw-tip' }, [ this.tipT, this.tipV ]);
		this.wrap = E('div', { 'class': 'rw-wrap' }, [ this.svg, this.tip ]);

		this.nowEl = E('b', {}, '—');
		this.nowLbl = E('span', {}, _('当前'));
		this.footEl = E('span');
		var chart = E('section', { 'class': 'rw-chart' }, [
			E('div', { 'class': 'rw-ch-head' }, [
				E('div', {}, [
					E('h2', {}, _('NSS 核心负载')),
					E('div', { 'class': 'rw-ch-val' }, [ this.nowEl, E('u', {}, '%'), this.nowLbl ])
				]),
				this.segEl
			]),
			this.wrap,
			E('div', { 'class': 'rw-ch-foot' }, [ this.footEl, E('span', {}, _('RRD 历史 · tmpfs')) ])
		]);

		/* ── KPI：频率 / 调频模式 / 开机自启开关 ── */
		this.freqEl = E('span', {}, '—');
		this.modeEl = E('span', {}, '—');
		this.swAuto = E('button', {
			'class': 'rw-tgl rw-sm', 'role': 'switch', 'aria-checked': 'false', 'aria-label': _('开机自启开关'),
			'click': ui.createHandlerFn(this, function () { return this.toggleAuto(); })
		});
		this.lbAuto = E('span', { 'class': 'rw-lb' });
		var kpis = E('section', { 'class': 'rw-kpis' }, [
			E('div', { 'class': 'rw-kpi' }, [ E('em', {}, _('NSS 频率')),
				E('div', { 'class': 'rw-v' }, [ this.freqEl, E('u', {}, 'MHz') ]) ]),
			E('div', { 'class': 'rw-kpi' }, [ E('em', {}, _('调频模式')),
				E('div', { 'class': 'rw-v' }, [ this.modeEl ]) ]),
			E('div', { 'class': 'rw-kpi rw-row' }, [ E('em', {}, _('开机自启')),
				E('div', { 'class': 'rw-mini' }, [ this.lbAuto, this.swAuto ]) ])
		]);

		var note = E('p', { 'class': 'rw-note' }, _('停用 NSS 后直连流量回退内核软转发，bandix 的统计会变准确（NSS 加速的流量不计入其统计），但吞吐下降。防火墙页的「路由 / NAT 卸载」请保持「无」——NSS 独立工作，软件卸载会与之冲突。'));

		this.apply();
		this.draw();
		this.bindHover();

		poll.add(L.bind(function () { return this.refresh(); }, this), 5);

		return E('div', { 'class': 'rw-root' }, [ E('style', {}, CSS), header, hero, chart, kpis, note ]);
	},

	parseHist: function (st) {
		this.hist = [];
		if (!st || !st.hist) return;
		st.hist.split(',').forEach(L.bind(function (seg) {
			var p = seg.split(':');
			if (p.length !== 2) return;
			var t = parseInt(p[0], 10), v = parseFloat(p[1]);
			if (isFinite(t) && isFinite(v))
				this.hist.push({ t: t, v: Math.max(0, Math.min(100, v)) });
		}, this));
	},

	live: function () {
		var k = Object.keys(this.st.load || {});
		return k.length ? parseFloat(this.st.load[k[0]]) : null;
	},

	/* 状态 → UI */
	apply: function () {
		var st = this.st, on = (st.ecm === 'running'), auto = (st.autostart === '1');

		this.tagEl.setAttribute('data-s', on ? 'run' : 'stop');
		this.tagTxt.textContent = on ? _('运行中') : _('已停用');

		this.swRun.setAttribute('aria-checked', on ? 'true' : 'false');
		this.lbRun.textContent = on ? _('已启用') : _('已停用');
		this.descEl.textContent = on
			? _('当前由硬件加速转发。停用后流量回退内核软转发，bandix 流量统计会变得更准确，但吞吐下降。')
			: _('当前为内核软转发。bandix 统计准确，但吞吐低于硬件加速路径。启用后直连流量将由 NSS 接管。');

		this.swAuto.setAttribute('aria-checked', auto ? 'true' : 'false');
		this.lbAuto.textContent = auto ? _('已启用') : _('已关闭');

		this.freqEl.textContent = st.freq || '—';
		this.modeEl.textContent = st.freqmode || '—';

		var lv = this.live();
		this.nowEl.textContent = (lv === null) ? '—' : lv.toFixed(1);
	},

	/* 画主图 */
	draw: function () {
		var svg = this.svg, W = 940, H = 238, L = 44, R = 14, T = 14, B = 30;
		while (svg.firstChild) svg.removeChild(svg.firstChild);

		var h = this.hist, n = h.length;
		this.geom = { W: W, H: H, L: L, R: R, T: T, B: B, n: n, t0: n ? h[0].t : 0, t1: n ? h[n - 1].t : 0 };
		if (!n) {
			var t0 = sx('text', { x: W / 2, y: H / 2, 'text-anchor': 'middle',
				'font-size': '13', fill: 'var(--text-subtle,#7f858b)' });
			t0.textContent = _('暂无历史数据（首次采集需等待约 30 秒）');
			svg.appendChild(t0);
			this.footEl.textContent = '';
			return;
		}
		var xOf = this.geom.xOf = function (i) { return L + (W - L - R) * i / (n - 1); };
		var yOf = this.geom.yOf = function (v) { return T + (H - T - B) * (1 - v / 100); };

		/* Y 轴网格 + 刻度 */
		[0, 25, 50, 75, 100].forEach(function (v) {
			var y = yOf(v);
			svg.appendChild(sx('line', { x1: L, x2: W - R, y1: y, y2: y,
				stroke: 'var(--hairline,rgba(18,26,34,.13))', 'stroke-width': 1,
				'stroke-dasharray': v === 0 ? '0' : '1 3' }));
			var t = sx('text', { x: L - 10, y: y + 3.5, 'text-anchor': 'end',
				'font-family': 'var(--font-mono,monospace)', 'font-size': '10.5',
				fill: 'var(--text-subtle,#7f858b)' });
			t.textContent = v;
			svg.appendChild(t);
		});

		/* 时间轴（5 刻度） */
		var self = this;
		for (var i = 0; i < 5; i++) {
			var frac = i / 4, idx = Math.round(frac * (n - 1));
			var x = xOf(idx);
			svg.appendChild(sx('line', { x1: x, x2: x, y1: T, y2: H - B,
				stroke: 'var(--hairline,rgba(18,26,34,.13))', 'stroke-width': 1,
				'stroke-dasharray': '1 3', 'stroke-opacity': .7 }));
			var lt = sx('text', { x: x, y: H - B + 16,
				'text-anchor': frac < .05 ? 'start' : frac > .95 ? 'end' : 'middle',
				'font-family': 'var(--font-mono,monospace)', 'font-size': '10.5',
				fill: 'var(--text-subtle,#7f858b)' });
			lt.textContent = fmtTime(h[idx].t, this.range);
			svg.appendChild(lt);
		}

		/* 渐变面积 */
		var defs = sx('defs');
		var gid = 'rwg';
		var lg = sx('linearGradient', { id: gid, x1: 0, y1: 0, x2: 0, y2: 1 });
		var off = (this.st.ecm !== 'running');
		lg.appendChild(sx('stop', { offset: '0%', 'stop-color': 'var(--brand,#0085b5)', 'stop-opacity': off ? '.10' : '.32' }));
		lg.appendChild(sx('stop', { offset: '65%', 'stop-color': 'var(--brand,#0085b5)', 'stop-opacity': off ? '.04' : '.10' }));
		lg.appendChild(sx('stop', { offset: '100%', 'stop-color': 'var(--brand,#0085b5)', 'stop-opacity': '0' }));
		defs.appendChild(lg);
		svg.appendChild(defs);

		var xs = h.map(function (_, k) { return xOf(k); });
		var ys = h.map(function (d) { return yOf(d.v); });
		var dline = monotone(xs, ys);
		svg.appendChild(sx('path', { d: dline + ' L' + xOf(n - 1) + ',' + (H - B) + ' L' + xOf(0) + ',' + (H - B) + ' Z', fill: 'url(#' + gid + ')' }));
		svg.appendChild(sx('path', { d: dline, fill: 'none', stroke: 'var(--brand,#0085b5)',
			'stroke-width': 2.3, 'stroke-linejoin': 'round', 'stroke-linecap': 'round',
			'stroke-opacity': off ? '.42' : '1' }));

		/* 端点 */
		svg.appendChild(sx('circle', { cx: xOf(n - 1), cy: ys[n - 1], r: 8,
			fill: 'var(--brand,#0085b5)', 'fill-opacity': .18 }));
		svg.appendChild(sx('circle', { cx: xOf(n - 1), cy: ys[n - 1], r: 3.6,
			fill: 'var(--brand,#0085b5)' }));

		/* 页脚统计 */
		var sum = 0, mx = -Infinity, mn = Infinity;
		h.forEach(function (d) { sum += d.v; if (d.v > mx) mx = d.v; if (d.v < mn) mn = d.v; });
		this.footEl.textContent = _('均 %s%% · 峰 %s%% · 谷 %s%%').format((sum / n).toFixed(1), mx.toFixed(0), mn.toFixed(0))
			+ ' · ' + _(LABEL[this.range] || '');
	},

	/* 悬浮读数 */
	bindHover: function () {
		var self = this, wrap = this.wrap, svg = this.svg;
		var cross = sx('line', { y1: 0, y2: 0, stroke: 'var(--brand,#0085b5)', 'stroke-width': 1,
			'stroke-dasharray': '3 3', 'stroke-opacity': .55, visibility: 'hidden' });
		var dot = sx('circle', { r: 4, fill: 'var(--brand,#0085b5)', stroke: 'var(--surface,#fff)',
			'stroke-width': 2, visibility: 'hidden' });
		svg.appendChild(cross);
		svg.appendChild(dot);

		function clear() {
			self.tip.classList.remove('on');
			cross.setAttribute('visibility', 'hidden');
			dot.setAttribute('visibility', 'hidden');
		}

		wrap.addEventListener('mousemove', function (ev) {
			var g = self.geom;
			if (!g || !g.n) return;
			var r = svg.getBoundingClientRect();
			var px = (ev.clientX - r.left) / r.width * g.W;
			var frac = (px - g.L) / (g.W - g.L - g.R);
			var i = Math.max(0, Math.min(g.n - 1, Math.round(frac * (g.n - 1))));
			var d = self.hist[i];
			var x = g.xOf(i), y = g.yOf(d.v);
			cross.setAttribute('x1', x); cross.setAttribute('x2', x);
			cross.setAttribute('y1', g.T); cross.setAttribute('y2', g.H - g.B);
			cross.setAttribute('visibility', 'visible');
			dot.setAttribute('cx', x); dot.setAttribute('cy', y);
			dot.setAttribute('visibility', 'visible');
			self.tipT.textContent = fmtTime(d.t, self.range);
			self.tipV.textContent = d.v.toFixed(1) + ' %';
			var left = Math.min(Math.max(px / g.W * r.width - 52, 4), r.width - 116);
			self.tip.style.left = left + 'px';
			self.tip.style.top = Math.max(y / g.H * r.height - 62, 2) + 'px';
			self.tip.classList.add('on');
		});
		wrap.addEventListener('mouseleave', clear);
	},

	/* 切时间范围 */
	setRange: function (r) {
		var self = this;
		if (r === this.range) return;
		this.range = r;
		Array.prototype.forEach.call(this.segEl.children, function (b) {
			b.setAttribute('aria-selected', b.getAttribute('data-range') === r ? 'true' : 'false');
		});
		return readStatus(r).then(function (st) {
			self.st = st;
			self.parseHist(st);
			self.apply();
			self.draw();
		}).catch(function (err) {
			notifyError(_('读取历史数据失败：%s').format(err && err.message ? err.message : err));
		});
	},

	/* 开关动作 */
	toggleRun: function () {
		var self = this, on = (this.st.ecm === 'running');
		return control(on ? 'stop' : 'start').then(function () { return self.refresh(); });
	},
	toggleAuto: function () {
		var self = this, on = (this.st.autostart === '1');
		return control(on ? 'disable' : 'enable').then(function () { return self.refresh(); });
	},

	refresh: function () {
		var self = this;
		return readStatus(this.range).then(function (st) {
			self.st = st;
			self.parseHist(st);
			self.apply();
			self.draw();
		});
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
EOF

cat > $PKGDIR/root/usr/libexec/rivwrt/nss-status <<'EOF'
#!/bin/sh
# RivWRT NSS 状态采集：输出 key=value 供 LuCI 页面解析
# 用法：nss-status [range]   range ∈ 2h|12h|1d|1w（默认 2h，仅影响 history 段）
echo "ts=$(date +%s)"

# ── 引擎运行状态 ──
# ECM 是内核模块：其 init.d 的 start_service() 只做 modprobe、未 procd_open_service，
# 故不出现在 ubus service list。曾用 ubus 检测 → 恒判 stopped、按钮看似无效。
if lsmod 2>/dev/null | grep -q '^ecm '; then
	echo "ecm=running"
else
	echo "ecm=stopped"
fi

# ── 开机自启（rc.common 标准命令，不依赖 procd 注册）──
if /etc/init.d/qca-nss-ecm enabled >/dev/null 2>&1; then
	echo "autostart=1"
else
	echo "autostart=0"
fi

# ── NSS 时钟（路径同上游 nss_diag）──
FREQ=$(cat /proc/sys/dev/nss/clock/current_freq 2>/dev/null)
case "$FREQ" in
	''|*[!0-9]*) : ;;
	*) echo "freq=$(awk -v h="$FREQ" 'BEGIN{printf "%.1f", h/1000000}')" ;;
esac
if [ "$(cat /proc/sys/dev/nss/clock/auto_scale 2>/dev/null)" = "1" ]; then
	echo "freqmode=Auto"
else
	echo "freqmode=Fixed"
fi

# ── 实时负载（debugfs cpu_load_ubi，取 Avg 列）──
D=/sys/kernel/debug/qca-nss-drv/stats
mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug 2>/dev/null
if [ -r "$D/cpu_load_ubi" ]; then
	echo "stats=ok"
	awk '
		/^Core [0-9]+:/ { core = $2; sub(":", "", core); has = 1; next }
		has && /%/ {
			n = split($0, a, /[ \t]+/)
			for (i = 1; i <= n; i++)
				if (a[i] ~ /%$/) { gsub("%", "", a[i]); print "load_" core "=" a[i]; break }
			has = 0
		}
	' "$D/cpu_load_ubi"
else
	echo "stats=unavailable"
fi

# ── 历史序列（RRD；需 rrdtool1 包）──
RANGE="${1:-2h}"
case "$RANGE" in
	12h) SPAN=43200 ;;
	1d)  SPAN=86400 ;;
	1w)  SPAN=604800 ;;
	*)   SPAN=7200 ;;
esac
echo "histrange=$RANGE"
RRD=$(ls /tmp/rrd/*/nss-load/gauge-core0.rrd 2>/dev/null | head -1)
if [ -n "$RRD" ] && [ -x /usr/bin/rrdtool ]; then
	H=$(/usr/bin/rrdtool fetch "$RRD" AVERAGE -s "NOW-$SPAN" -e NOW 2>/dev/null | \
		awk '/^[0-9]+:/ { v = $2; if (v ~ /^[0-9.eE+-]+$/) printf "%s:%.1f,", $1, v }')
	[ -n "$H" ] && echo "hist=${H%,}"
fi
exit 0
EOF
chmod +x $PKGDIR/root/usr/libexec/rivwrt/nss-status

# -------------------------------------------------------
# RivWRT：无线三频固化 init.d 脚本
# 生成到 base-files 的 init.d + rc.d 链接（固件层启用，首启自动执行一次）
# 硬件拓扑：radio0(5G ahb) / radio1(2.4G ahb) / radio2(QCN9074 PCIe 5G)
# 频段分配：radio0=5G-1 游戏(44/HE160)、radio1=2.4G(11/HT20)、radio2=5G-2 影音(149/HE80)
# 法规：US / 24dBm（ones20250 推荐）
# -------------------------------------------------------

mkdir -p "./package/base-files/files/etc/init.d" "./package/base-files/files/etc/rc.d"
WIFI_INIT="./package/base-files/files/etc/init.d/rivwrt-wifi"
cat > "$WIFI_INIT" <<'RIVWRT_WIFI'
#!/bin/sh /etc/rc.common
START=99
MARKER=/etc/.rivwrt-wifi-named
start() {
	[ -f "$MARKER" ] && return 0
	# 等 /etc/config/wireless 生成：该文件由 netifd 首次启动时才写入；若 S99
	# 跑在其之前，uci 读不到任何 radio。旧版用 ubus 判定 + 无条件 touch marker，
	# 一旦空转就永久不再重试（实测刷完 SSID 仍是 OWRT）。
	# 改用 uci 判定（不依赖 ubus），中途主动触发一次配置生成。
	i=0
	while [ $i -lt 90 ]; do
		[ -n "$(uci -q get wireless.radio0.band)" ] && break
		[ $i -eq 20 ] && wifi config >/dev/null 2>&1
		i=$((i+1)); sleep 2
	done
	[ -n "$(uci -q get wireless.radio0.band)" ] || return 1
	CHANGED=0
	for RADIO in $(uci -q show wireless | sed -n "s/^\\(wireless\\.radio[0-9]*\\)\\.type=.*/\\1/p"); do
		BAND=$(uci -q get wireless.$RADIO.band)
		IFACE=$(uci -q show wireless | sed -n "s/^\\(wireless\\.[a-z_0-9]*\\)\\.device=.$RADIO.$/\\1/p" | head -1)
		uci -q set wireless.$RADIO.txpower='24'
		# ★ 不在此设置 country：ath11k 对运行时国家码切换（regd update）脆弱，
		#   uci set country + wifi reload 会触发 cfg80211 内核 WARNING（实测
		#   reg.c:4035 reg_get_max_bandwidth）并伴随 regd update -22 失败。
		#   country 已由编译期写入 mac80211.uc（'US'），radio 首启即带正确值。
		# 射频参数按频段设置（全部非 DFS 主信道，避免 CAC 静默期与雷达避让）。
		# ★ 教训：曾误用 htmode='HT160' —— 该值不在合法枚举内
		#   （合法含 160 的仅 VHT160/HE160/EHT160，HT 系列最高 HT40±），
		#   导致 5G 主 radio 无法启动（"5.2G 挂了"）。此处用 WiFi6 的 HE 系列。
		case "$BAND" in
			2g)
				uci -q set wireless.$RADIO.channel='11'
				uci -q set wireless.$RADIO.htmode='HT20'
				[ -n "$IFACE" ] && uci -q set wireless.$IFACE.ssid='RivWRT'
				CHANGED=1
				;;
			5g)
				# 两个 5G 按 radio 编号区分（与编译期 mac80211.uc 同一规则）：
				#   radio0 = IPQ6010 内建 4x4（游戏段）→ 44 / HE160
				#   radio2 = QCN9074 PCIe（影音段）  → 149 / HE80
				case "$RADIO" in
					radio0)
						uci -q set wireless.$RADIO.channel='44'
						uci -q set wireless.$RADIO.htmode='HE160'
						[ -n "$IFACE" ] && uci -q set wireless.$IFACE.ssid='RivWRT-5.2G'
						;;
					*)
						uci -q set wireless.$RADIO.channel='149'
						uci -q set wireless.$RADIO.htmode='HE80'
						[ -n "$IFACE" ] && uci -q set wireless.$IFACE.ssid='RivWRT-5.8G'
						;;
				esac
				CHANGED=1
				;;
		esac
	done
	for IFACE in $(uci -q show wireless | sed -n "s/^\\(wireless\\.[a-z_0-9]*\\)\\.device=.*/\\1/p"); do
		uci -q set wireless.$IFACE.encryption='none'
		uci -q delete wireless.$IFACE.key 2>/dev/null
		CHANGED=1
	done
	if [ "$CHANGED" = "1" ]; then
		uci commit wireless
		wifi reload
		# 仅成功施加配置后才落 marker；失败则下次启动重试
		touch "$MARKER"
	fi
}
RIVWRT_WIFI
chmod +x "$WIFI_INIT"

# rc.d 启动链接（固件层启用，否则首启不会执行）
mkdir -p "./package/base-files/files/etc/rc.d"
ln -sf ../init.d/rivwrt-wifi "./package/base-files/files/etc/rc.d/S99rivwrt-wifi"

# -------------------------------------------------------
# RivWRT：swap 分区默认启用（eMMC mmcblk0p26）
# 上游树对 jdcloud_re-cs-02 未做 swap 自动挂载；1G RAM 设备启用 swap
# 承载跑分/插件缓存。传统 rc.common start() 风格（非 procd），
# 避免 USE_PROCD 差异带来的 start_service 不调用问题。
# -------------------------------------------------------
SWAP_INIT="./package/base-files/files/etc/init.d/rivwrt-swap"
cat > "$SWAP_INIT" <<'RIVWRT_SWAP'
#!/bin/sh /etc/rc.common
START=20
start() {
	[ -b /dev/mmcblk0p26 ] || return 0
	# 幂等：未格式化才 mkswap（原厂/旧固件已格式化为 swap 则跳过）
	blkid -t TYPE=swap /dev/mmcblk0p26 >/dev/null 2>&1 || mkswap /dev/mmcblk0p26 >/dev/null 2>&1
	swapon /dev/mmcblk0p26 2>/dev/null
}
RIVWRT_SWAP
chmod +x "$SWAP_INIT"
ln -sf ../init.d/rivwrt-swap "./package/base-files/files/etc/rc.d/S20rivwrt-swap"

# -------------------------------------------------------
# RivWRT：NSS 负载历史采集（collectd exec → RRD）
#
# 接线链（每环独立验证过）：
#   ① init.d rivwrt-nss-stat (root, START=25)
#        等 debugfs 就绪 → chmod 644 cpu_load_ubi
#        （collectd 硬性拒绝以 root 跑 exec，见 collectd-exec.pod CAVEATS）
#   ② uci-defaults 99-rivwrt-nss-stat
#        开 collectd_exec 插件 + 注册采集脚本（cmduser=nobody，见下）
#        rrdtool.backup=1 → 关机时打包，重启恢复（平时 RRD 在 /tmp 不写 eMMC）
#   ③ collectd exec 插件每 30s fork nss-collectd.sh（以 nobody 身份）
#        解析 "Core 0: / Min Avg Max / 7% 7% 34%" 取 Avg → PUTVAL（plugin=nss-load）
#   ④ RRD /tmp/rrd/<host>/nss-load/gauge-core0.rrd
#        页面经 rrdtool1 fetch 读取
# -------------------------------------------------------

# ① 放开 debugfs 统计文件读权限（collectd 以非 root 身份运行）
NSSSTAT_INIT="./package/base-files/files/etc/init.d/rivwrt-nss-stat"
cat > "$NSSSTAT_INIT" <<'RIVWRT_NSSSTAT'
#!/bin/sh /etc/rc.common
START=25
start() {
	# 等 NSS 驱动建好 debugfs 节点（最多 60s）
	i=0
	while [ $i -lt 30 ]; do
		[ -r /sys/kernel/debug/qca-nss-drv/stats/cpu_load_ubi ] && break
		mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug 2>/dev/null
		i=$((i+1)); sleep 2
	done
	F=/sys/kernel/debug/qca-nss-drv/stats/cpu_load_ubi
	[ -f "$F" ] || return 0
	# 只放开这一个只读统计文件；debugfs 其余保持原权限
	chmod 644 "$F" 2>/dev/null
}
RIVWRT_NSSSTAT
chmod +x "$NSSSTAT_INIT"
ln -sf ../init.d/rivwrt-nss-stat "./package/base-files/files/etc/rc.d/S25rivwrt-nss-stat"

# ③ 采集脚本：debugfs → collectd PUTVAL
NSSCOLLECT="./package/base-files/files/usr/libexec/rivwrt/nss-collectd.sh"
mkdir -p "$(dirname "$NSSCOLLECT")"
cat > "$NSSCOLLECT" <<'RIVWRT_NSSCOLLECT'
#!/bin/sh
# 采集 NSS 核心负载，输出 collectd exec 协议（PUTVAL）。
#
# ★ 常驻循环，不退出：collectd exec 插件把 STDERR 接到管道，程序一旦退出
#   （或重定向 fd2）该管道即 EOF，被判为异常并记日志：
#       exec plugin: Program `...' has closed STDERR.
#   （源码 exec.c 的 NOTICE 分支；且文档明说 exec 本就设计给长期运行的
#    可执行文件："perfectly legal ... run for a long time and continuously
#     write values to STDOUT"）
#   故此处循环采集、持续持有 STDERR，退出由 collectd 发 SIGTERM 触发。
#   采集周期取自 collectd 注入的环境变量 COLLECTD_INTERVAL（默认 30s）。
#
# 输入格式（设备实测）：
#   CPU Utilization:
#   Note: Averaged over 1 second
#   Core 0:
#   Min     Avg     Max
#    7%      7%      34%
# 取 avg 列（第 2 个百分比）。单核设备仅有 Core 0（AX6600=IPQ6010）。
F=/sys/kernel/debug/qca-nss-drv/stats/cpu_load_ubi
INTERVAL="${COLLECTD_INTERVAL:-30}"
case "$INTERVAL" in ''|*[!0-9]*) INTERVAL=30 ;; esac

while :; do
	if [ -r "$F" ]; then
		awk '
			/^Core [0-9]+:/ { core = $2; sub(":", "", core); has_core = 1; next }
			has_core && /%/ {
				n = split($0, a, /[ \t]+/)
				for (i = 1; i <= n; i++) {
					if (a[i] ~ /%$/) {
						gsub("%", "", a[i])
						print "RivWRT/nss-load/gauge-core" core " N:" a[i]
						break
					}
				}
				has_core = 0
			}
		' "$F"
	fi
	sleep "$INTERVAL"
done
RIVWRT_NSSCOLLECT
chmod +x "$NSSCOLLECT"


# ② uci-defaults：开 exec 插件 + 注册采集脚本（cmduser root）
#    注：collectd 硬性拒绝以 root 运行 exec（collectd-exec.pod CAVEATS：
#    "The user ... may not have root privileges"），故 cmduser 必须非 root。
#    debugfs 默认仅 root 可读，由 ① 的 init.d 预先 chmod 644，nobody 即可读取。
NSSSTAT_UDIR="./package/base-files/files/etc/uci-defaults/99-rivwrt-nss-stat"
mkdir -p "$(dirname "$NSSSTAT_UDIR")"
cat > "$NSSSTAT_UDIR" <<'RIVWRT_NSSUDIR'
#!/bin/sh
# 开启 collectd exec 插件
uci -q set luci_statistics.collectd_exec=statistics
uci -q set luci_statistics.collectd_exec.enable='1'
# 注册 NSS 负载采集（每 30s 一次，跟随全局 Interval）
uci -q delete luci_statistics.rivwrt_nss
uci -q set luci_statistics.rivwrt_nss=collectd_exec_input
uci -q set luci_statistics.rivwrt_nss.cmdline='/usr/libexec/rivwrt/nss-collectd.sh'
uci -q set luci_statistics.rivwrt_nss.cmduser='nobody'
# RRD 历史：开启关机备份（平时数据在 /tmp 内存，关机时才落盘一次，护 eMMC）
uci -q set luci_statistics.collectd_rrdtool.backup='1'
uci -q set luci_statistics.collectd_rrdtool.RRATimespans='2hour 1day 1week 1month'
uci -q commit luci_statistics
# 重启采集使配置生效（首启时 collectd 可能尚未安装完成，失败可忽略）
[ -x /etc/init.d/luci_statistics ] && /etc/init.d/luci_statistics restart >/dev/null 2>&1
[ -x /etc/init.d/collectd ] && /etc/init.d/collectd restart >/dev/null 2>&1
exit 0
RIVWRT_NSSUDIR
chmod +x "$NSSSTAT_UDIR"
