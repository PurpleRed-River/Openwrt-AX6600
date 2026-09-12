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
BANNER="./package/base-files/files/etc/banner"
[ -f "$BANNER" ] && cat > "$BANNER" <<'RIVWRT_BANNER'
==================================================
  RivWRT  -  based on ones20250/Openwrt-AX6600
  aurora / athena-led / bandix-plus / daede / nss
  %D %V, %C
==================================================

RIVWRT_BANNER

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

# =========================================================
# RivWRT：DTS 端口 label 互换（根治网口互换）
# 实测映射（拔插测试）：丝印 WAN(2.5G)=DSA dp5(wan)，丝印 LAN1=DSA dp1(lan1)。
# 设备树 label 对调后系统名与物理丝印语义一致，
# 官方默认配置（lan=lan1-4, wan=wan）自动实现 2.5G=LAN / LAN1=WAN，
# 原先的网口互换 uci-defaults 不再需要（已删除）。
# 注意：label-mac-device 仍指向 dp1，MAC 分配不变。
# =========================================================
DTS_FILE="./target/linux/qualcommax/dts/ipq6010-re-cs-02.dts"
sed -i "/&dp1 {/,/};/ s/label = \"lan1\"/label = \"wan\"/" "$DTS_FILE"
sed -i "/&dp5 {/,/};/ s/label = \"wan\"/label = \"lan1\"/" "$DTS_FILE"
echo "RivWRT: DTS port labels swapped (wan<->lan1)"

# =========================================================
# RivWRT：daede 全局暗色标志补丁
# daede 的 config.js 会在页面加载时探测背景亮度，低于阈值就往 <html>
# 设置 data-darkmode=true（全局属性），aurora 响应后整站变暗。
# 屏蔽该设置点：daede 自身卡片默认亮色设计不受影响，主题保持稳定浅色
# =========================================================
CFG_JS=$(find ./package/luci-app-daede -name "config.js" 2>/dev/null | head -1)
[ -n "$CFG_JS" ] && sed -i "s#document\.documentElement\.setAttribute('data-darkmode', 'true');#/* RivWRT: keep global dark-mode flag untouched */#" "$CFG_JS" && echo "RivWRT: daede dark-mode patch applied"

# =========================================================
# RivWRT：uci-defaults 目标目录（后续所有首启脚本写入此处）
# =========================================================
UDIR="./package/base-files/files/etc/uci-defaults"
mkdir -p "$UDIR"

# =========================================================
# RivWRT：FullCone NAT 固化开启（IPv4；FullConeNAT6 有争议默认不动）
# 对应防火墙页"启用 FullConeNAT"开关，游戏机/P2P 的 NAT 行为更友好
# =========================================================
cat > "$UDIR/96-rivwrt-fullcone" <<'RIVWRT_FC'
#!/bin/sh
uci -q set firewall.@defaults[0].fullcone='1'
uci commit firewall
RIVWRT_FC
chmod +x "$UDIR/96-rivwrt-fullcone"

# =========================================================
# RivWRT：网络配置对新端口命名的纠正
# 覆盖从旧命名（wan=2.5G 进桥 / wan 接口绑 lan1）升级上来的配置；
# 新刷机时等幂（与官方默认一致，无副作用）
# =========================================================
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

# =========================================================
# RivWRT：podman API 服务默认关闭
# podman 包自带 init 脚本会常驻 "podman system service"（实测 ~45MB），
# 纯 CLI 用法不需要；需要远程 API（如接 Portainer）时 /etc/init.d/podman start
# =========================================================
cat > "$UDIR/99-rivwrt-podman" <<'RIVWRT_PODMAN'
#!/bin/sh
/etc/init.d/podman stop 2>/dev/null
/etc/init.d/podman disable 2>/dev/null
RIVWRT_PODMAN
chmod +x "$UDIR/99-rivwrt-podman"

# =========================================================
# RivWRT：菜单归拢（消除单项目录）
# wolultra：管控(control) -> 服务；samba4：NAS -> 服务（ImmortalWrt 魔改路径还原）
# =========================================================
cat > "$UDIR/99-rivwrt-menus" <<'RIVWRT_MENUS'
#!/bin/sh
[ -f /usr/share/luci/menu.d/luci-app-wolultra.json ] && \
	sed -i "s#\"admin/control/wolultra\"#\"admin/services/wolultra\"#" /usr/share/luci/menu.d/luci-app-wolultra.json
[ -f /usr/share/luci/menu.d/luci-app-samba4.json ] && \
	sed -i "s#\"admin/nas/samba4\"#\"admin/services/samba4\"#" /usr/share/luci/menu.d/luci-app-samba4.json
# bandix：网络 -> 服务
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
LUCI_DEPENDS:=+luci-base +qca-nss-ecm
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

define Package/$(PKG_NAME)/description
  RivWRT 定制：NSS 硬件加速开关与实时状态（引擎负载/时钟/加速连接数）
endef
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
			"ubus": { "service": ["list"] },
			"file": {
				"/usr/libexec/rivwrt/nss-status": ["exec"]
			}
		},
		"write": {
			"file": {
				"/etc/init.d/qca-nss-ecm": ["exec"]
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

var callExec = rpc.declare({
	object: 'file',
	method: 'exec',
	params: [ 'command', 'params' ],
	expect: { code: 0 }
});

function readStatus() {
	return callExec('/usr/libexec/rivwrt/nss-status', []).then(function (res) {
		var out = {};
		(res.stdout || '').split('\n').forEach(function (line) {
			var m = line.match(/^([a-z_0-9]+)=(.*)$/);
			if (m) out[m[1]] = m[2];
		});
		return out;
	}).catch(function () { return {}; });
}

function control(action) {
	return callExec('/etc/init.d/qca-nss-ecm', [ action ]);
}

return view.extend({
	load: function () {
		return readStatus();
	},

	render: function (st) {
		var self = this;
		this.table = E('table', { 'class': 'table' });

		var body = E([
			E('h2', _('NSS 硬件加速')),
			E('p', { 'style': 'margin-bottom:1em' },
				_('qca-nss-ecm 硬件加速引擎状态与开关。停用后流量回退内核软转发（bandix 统计将变准确，吞吐下降）；启用后直连流量由 NSS 硬件加速。防火墙页的路由/NAT卸载选项请保持“无”。')),
			E('div', { 'class': 'cbi-section' },
				E('div', { 'class': 'cbi-section-node' }, this.table)),
			E('div', { 'class': 'cbi-page-actions', 'style': 'margin-top:1em' }, [
				E('button', {
					'class': 'btn cbi-button-action',
					'click': ui.createHandlerFn(this, function () {
						return control('start').then(function () { return self.refresh(); });
					})
				}, _('启用 NSS 加速')),
				' ',
				E('button', {
					'class': 'btn cbi-button-negative',
					'click': ui.createHandlerFn(this, function () {
						return control('stop').then(function () { return self.refresh(); });
					})
				}, _('停用 NSS 加速')),
				' ',
				E('button', {
					'class': 'btn',
					'click': ui.createHandlerFn(this, function () {
						return readStatus().then(function (s) {
							return control(s.autostart === '1' ? 'disable' : 'enable');
						}).then(function () { return self.refresh(); });
					})
				}, _('切换开机自启'))
			]),
			E('div', { 'style': 'margin-top:1em;font-size:90%;opacity:.6' },
				_('状态每 5 秒自动刷新。'))
		]);

		poll.add(function () { return self.refresh(); }, 5);
		dom.content(this.table, this.renderRows(st));
		return body;
	},

	renderRows: function (st) {
		var rows = [];
		function row(label, value) {
			rows.push(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left', 'width': '33%' }, label),
				E('td', { 'class': 'td left' }, value)
			]));
		}
		if (st && st.ecm === 'running')
			row(_('ECM 引擎状态'), E('span', { 'class': 'label label-success' }, _('运行中')));
		else
			row(_('ECM 引擎状态'), E('span', { 'class': 'label label-warning' }, _('已停用（软转发）')));

		row(_('开机自启'), (st && st.autostart === '1') ? _('是') : _('否'));

		if (!st || st.stats === 'unavailable') {
			row(_('NSS 引擎负载'), _('暂不可用（debugfs 未就绪）'));
		} else {
			var cores = Object.keys(st).filter(function (k) { return k.indexOf('load_') === 0; }).sort();
			if (cores.length === 0) {
				row(_('NSS 引擎负载'), _('暂无数据'));
			} else {
				cores.forEach(function (k) {
					row(_('NSS 引擎负载 (Core %s)').format(k.replace('load_', '')),
						'%s%'.format(st[k]));
				});
			}
		}
		return E('tbody', rows);
	},

	refresh: function () {
		var self = this;
		return readStatus().then(function (st) {
			dom.content(self.table, self.renderRows(st));
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
echo "ts=$(date +%s)"
# 服务运行状态（procd 注册）
if ubus -q call service list 2>/dev/null | grep -q '"qca-nss-ecm"'; then
	echo "ecm=running"
else
	echo "ecm=stopped"
fi
# 开机自启状态
/etc/init.d/qca-nss-ecm enabled 2>/dev/null && echo "autostart=1" || echo "autostart=0"
# debugfs（NSS 统计所在，未挂载则自动挂）
# 引擎负载：stats/cpu_load_ubi（实测路径），Core N 块取 Avg 值
D=/sys/kernel/debug/qca-nss-drv/stats
mount | grep -q "debugfs" || mount -t debugfs none /sys/kernel/debug 2>/dev/null
if [ -r "$D/cpu_load_ubi" ]; then
	echo "stats=ok"
	awk '/^Core [0-9]+:/{c=$2; gsub(":","",c)} $3 ~ /%$/ {n=$2; gsub("%","",n); print "load_" c "=" n}' "$D/cpu_load_ubi"
else
	echo "stats=unavailable"
fi
EOF
chmod +x $PKGDIR/root/usr/libexec/rivwrt/nss-status

# =========================================================
# RivWRT：无线固化（三频分明 / US 法规 / 非 DFS 信道）
# 背景：生成器 mac80211.uc 默认 country=CN 且信道可能落 DFS（如信道 100），
# CN 法规下 DFS 信道 AP 直接禁用（首启一个 5G radio 起不来的根因）。
# 时序说明：radio 配置由 netifd 启动时硬件检测生成，uci-defaults 跑得太早
# （wireless 段尚不存在会空转），故全部逻辑放 init.d S99（无线就绪后执行一次）。
# 硬件拓扑：2.4G(ahb) / 5G-1 游戏 4x4(ahb, 44/160MHz) / 5G-2 影音(QCN9074 PCIe, 149/80MHz)
# 参数采用 ones20250 官方推荐：US 法规 / 功率 24dBm / 信道 11-44-149
# =========================================================
mkdir -p "./package/base-files/files/etc/init.d"
cat > "./package/base-files/files/etc/init.d/rivwrt-wifi" <<'RIVWRT_WIFI'
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=0
MARKER=/etc/.rivwrt-wifi-named
start_service() {
	[ -f "$MARKER" ] && return 0
	# 等 wireless 就绪（最多 120 秒）
	i=0
	while [ $i -lt 60 ]; do
		ubus -q call network.wireless status >/dev/null 2>&1 && break
		i=$((i+1)); sleep 2
	done
	ubus -q call network.wireless status > /tmp/.wlan-status.json || return 1
	CHANGED=0
	for RADIO in $(uci -q show wireless | sed -n "s/^\(wireless\.radio[0-9]*\)\.type=.*/\1/p"); do
		BAND=$(uci -q get wireless.$RADIO.band)
		IFACE=$(uci -q show wireless | sed -n "s/^\(wireless\.[a-z_0-9]*\)\.device=.$RADIO.$/\1/p" | head -1)
		# 法规统一 US + 功率 24dBm（ones20250 推荐配置）
		uci -q set wireless.$RADIO.country='US'
		uci -q set wireless.$RADIO.txpower='24'
		case "$BAND" in
			2g)
				uci -q set wireless.$RADIO.channel='11'
				uci -q set wireless.$RADIO.htmode='HT20'
				[ -n "$IFACE" ] && uci -q set wireless.$IFACE.ssid='RivWRT'
				CHANGED=1
				;;
			5g)
				PHY=$(jsonfilter -i /tmp/.wlan-status.json -e "$RADIO.interfaces[0].ifname" 2>/dev/null | cut -d- -f1)
				DEVPATH=$(readlink -f /sys/class/ieee80211/$PHY/device 2>/dev/null)
				case "$DEVPATH" in
					*pci*)
						# 5G-2 影音频段：QCN9074 PCIe，2x2 80MHz
						uci -q set wireless.$RADIO.channel='149'
						uci -q set wireless.$RADIO.htmode='HT80'
						[ -n "$IFACE" ] && uci -q set wireless.$IFACE.ssid='RivWRT-5.8G'
						;;
					*ahb*)
						# 5G-1 游戏频段：IPQ6010 内建 4x4 160MHz
						uci -q set wireless.$RADIO.channel='44'
						uci -q set wireless.$RADIO.htmode='HT160'
						[ -n "$IFACE" ] && uci -q set wireless.$IFACE.ssid='RivWRT-5.2G'
						;;
					*)
						# 探测失败（ubus 数据未就绪等）：回落非 DFS 安全值，
						# 保证不残留生成器的 DFS 默认信道导致 AP 起不来
						uci -q set wireless.$RADIO.channel='149'
						uci -q set wireless.$RADIO.htmode='HT80'
						[ -n "$IFACE" ] && uci -q set wireless.$IFACE.ssid='RivWRT-5G'
						;;
				esac
				CHANGED=1
				;;
		esac
	done
	# 所有 iface 默认开放（无密码）；需要加密时在 LuCI 无线页自行设置
	for IFACE in $(uci -q show wireless | sed -n "s/^\(wireless\.[a-z_0-9]*\)\.device=.*/\1/p"); do
		uci -q set wireless.$IFACE.encryption='none'
		uci -q delete wireless.$IFACE.key 2>/dev/null
		CHANGED=1
	done
	if [ "$CHANGED" = "1" ]; then
		uci commit wireless
		wifi reload
	fi
	touch "$MARKER"
}
RIVWRT_WIFI
chmod +x "./package/base-files/files/etc/init.d/rivwrt-wifi"
# 生成 rc.d 启动链接（固件层启用，否则首启不会执行）
mkdir -p "./package/base-files/files/etc/rc.d"
ln -sf ../init.d/rivwrt-wifi "./package/base-files/files/etc/rc.d/S99rivwrt-wifi"
