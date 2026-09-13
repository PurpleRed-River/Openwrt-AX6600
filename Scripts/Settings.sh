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
# 无线 SSID/密码（编译期写入生成器模板）
# -------------------------------------------------------

WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
[ -f "$WIFI_UC" ] && sed -i "s/ssid='.*'/ssid='$WRT_SSID'/g" $WIFI_UC

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
   RivWRT %V, %C
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
LUCI_DEPENDS:=+luci-base +kmod-qca-nss-ecm
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

# -------------------------------------------------------
# RivWRT：无线三频固化 init.d 脚本
# 生成到 base-files 的 init.d + rc.d 链接（固件层启用，首启自动执行一次）
# 硬件拓扑：radio0(5G ahb) / radio1(2.4G ahb) / radio2(QCN9074 PCIe 5G)
# 频段分配：radio0=5G-1 游戏(44/HT160)、radio1=2.4G(11/HT20)、radio2=5G-2 影音(149/HE80)
# 法规：US / 24dBm（ones20250 推荐）
# -------------------------------------------------------

mkdir -p "./package/base-files/files/etc/init.d" "./package/base-files/files/etc/rc.d"
WIFI_INIT="./package/base-files/files/etc/init.d/rivwrt-wifi"
cat > "$WIFI_INIT" <<'RIVWRT_WIFI'
#!/bin/sh /etc/rc.common
START=99
MARKER=/etc/.rivwrt-wifi-named
start_service() {
	[ -f "$MARKER" ] && return 0
	i=0
	while [ $i -lt 60 ]; do
		ubus -q call network.wireless status >/dev/null 2>&1 && break
		i=$((i+1)); sleep 2
	done
	ubus -q call network.wireless status > /tmp/.wlan-status.json || return 1
	CHANGED=0
	for RADIO in $(uci -q show wireless | sed -n "s/^\\(wireless\\.radio[0-9]*\\)\\.type=.*/\\1/p"); do
		BAND=$(uci -q get wireless.$RADIO.band)
		IFACE=$(uci -q show wireless | sed -n "s/^\\(wireless\\.[a-z_0-9]*\\)\\.device=.$RADIO.$/\\1/p" | head -1)
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
						uci -q set wireless.$RADIO.channel='149'
						uci -q set wireless.$RADIO.htmode='HE80'
						[ -n "$IFACE" ] && uci -q set wireless.$IFACE.ssid='RivWRT-5.8G'
						;;
					*ahb*)
						uci -q set wireless.$RADIO.channel='44'
						uci -q set wireless.$RADIO.htmode='HT160'
						[ -n "$IFACE" ] && uci -q set wireless.$IFACE.ssid='RivWRT-5.2G'
						;;
					*)
						uci -q set wireless.$RADIO.channel='149'
						uci -q set wireless.$RADIO.htmode='HE80'
						[ -n "$IFACE" ] && uci -q set wireless.$IFACE.ssid='RivWRT-5G'
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
	fi
	touch "$MARKER"
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
