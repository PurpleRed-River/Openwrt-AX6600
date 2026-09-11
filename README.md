# RivWRT — AX6600 雅典娜定制固件

> 基于 [ones20250/Openwrt-AX6600](https://github.com/ones20250/Openwrt-AX6600) 纯净版的个人定制固件。
> 编译机制（GitHub Actions 双 workflow、配置拼接、缓存与发布）完全沿用上游，感谢上游作者的持续维护。
> 设备：京东云无线宝 AX6600 雅典娜 `RE-CS-02`（IPQ6010 / 1G RAM / 128G eMMC）。

---

## 与上游的差异（本仓库全部定制点）

上游每次编译同时产出 PURE / PLUS 两个版本；本仓库固定产出**单一 RivWRT 定制版**，
即"上游 PURE 纯净基座 + 以下组件"：

| 组件 | 来源仓库 | 说明 |
|------|----------|------|
| 🌃 aurora 主题 | [eamonxg/luci-theme-aurora](https://github.com/eamonxg/luci-theme-aurora) | Vite + Tailwind 现代界面，编译期设为默认主题 |
| 💡 Athena LED | [unraveloop/JDC-AX6600-Athena-LED-Controller](https://github.com/unraveloop/JDC-AX6600-Athena-LED-Controller) | 点阵屏控制器（网速/天气/农历/MQTT），替换源码树内旧版 |
| 📊 bandix-plus | [timsaya/openwrt-bandix-plus](https://github.com/timsaya/openwrt-bandix-plus) + [luci-app-bandix-plus](https://github.com/timsaya/luci-app-bandix-plus) | 设备级流量统计（eBPF 旁路观察，见下方使用注意） |
| 🚀 daede 代理 | [kenzok8/openwrt-daede](https://github.com/kenzok8/openwrt-daede) | dae eBPF 透明代理内核 + daed + luci-app-daede 统一管理界面 |

基座能力（来自上游，未改动）：**NSS 硬件加速全套**（ecm/pppoe/qdisc/bridge/vlan）、
**firewall4 / nftables**（iptables 已关闭）、ath11k QCA 无线三频、无线内存水位调优、
samba4 / wolplus / partexp / 自动挂载等常用组件。

RivWRT 增量配置见 [`Config/GENERAL_AX6600_RIVWRT.txt`](Config/GENERAL_AX6600_RIVWRT.txt)（逐行中文注释）。

---

## 默认参数（刷机后首次启动）

| 项 | 值 |
|----|----|
| 管理地址 | `192.168.100.1` |
| 主机名 | `RivWRT` |
| 管理密码 | 无（首次 SSH 登录后请立即设置） |
| WiFi 名称 | `RivWRT` |
| WiFi 密码 | `1qaz!QAZ` |

WiFi 推荐调优（雅典娜三频）：2.4G 信道 11 / 20MHz；5G-1 游戏频段 信道 44 / 160MHz（不稳则退 80MHz）；
5G-2 影音频段 信道 149 / 80MHz；通用：地区 US、功率 24dBm、WPA2-PSK（CCMP）。

---

## 云编译

- **正式编译**：Actions → `QCA-ALL` → Run workflow。源码自动拉取
  [ones20250/immortalwrt_ipq](https://github.com/ones20250/immortalwrt_ipq)（main，含 NSS 优化）。
- **快速验证**：Actions → `WRT-TEST` → Run workflow（`TEST=true` 只生成最终 `.config` 不编译，几分钟出结果，
  可确认组件包名与依赖是否就位）。
- 固件命名：`RivWRT-时间-ipq60xx-jdcloud_re-cs-02-squashfs-factory/sysupgrade.bin`，
  Release 同时附带 `.config` 快照、外部组件 commit 记录（`Packages-*.txt`）与 `sha256sums.txt`。
- 缓存：PURE/PLUS 时代的工具链缓存机制保留，按源码提交滚动清理（`Auto-Clean` / `Cache-Clean`）。

---

## 刷机提示（12M 内核 + 2G rootfs 布局）

- 本固件适配已刷 [chenxin527/uboot-qsdk12.5-build](https://github.com/chenxin527/uboot-qsdk12.5-build)
  且分区为 **12M 内核 + 2G rootfs** 的 GPT 布局。
- 首次从原厂/U-Boot 刷入用 `factory` 后缀；OpenWrt/ImmortalWrt 系统内升级用 `sysupgrade` 后缀。
- 刷入方式：U-Boot Web 刷入；详细开 SSH / 备份 / 救砖流程见
  [Docs/刷机救砖教程.md](Docs/刷机救砖教程.md)（上游原文，全流程通用）。
- 刷机前务必核对 `sha256sums.txt`；eMMC 剩余空间（约 109G）刷机后自行分区挂载，插件数据建议独立分区。

---

## 使用注意（务必阅读）

### NSS × dae：直连满血、代理接管

- **直连流量**（国内网站、LAN 互访）：NSS 硬件加速满血，CPU 几乎无负载。
- **代理流量**：由 dae 在内核态（eBPF）接管转发，本来就不适合（也不需要）NSS 加速，两者天然分工、互不干扰。
- 首刷后建议验证代理分流是否正常；如个别连接出现"该代理却直连"，属 ecm 学习期抢跑，重启 dae 服务即可。

### bandix-plus：观察定位

- bandix 为 eBPF 旁路统计，**不在转发路径上，不影响 NSS 性能**。
- 但被 NSS 加速的直连流量不经过内核统计点，bandix 的设备用量数字会**偏低**（代理流量与新连接可见）。
- 需要看**精确报表**时：LuCI → NSS（或 `/etc/init.d/qca-nss-ecm stop`）临时停用硬件加速，
  流量全部回落内核后 bandix 即数全；看完再启动恢复满血。切换期间为 CPU 软转发，家用宽带无感。
- 接口级总量统计由 vnstat 承担（基于网卡计数器，NSS 流量照数，永远准确）。

### DNS 分流

- 内外网分流与防污染由 **dae 内置 DNS 模块**承担（geosite/geoip 规则），在 dae 配置文件中编辑；
- dnsmasq 仅负责 DHCP 与内网自定义解析（如 `address=/域名/<内网IP>` 的 split-horizon 场景）；
- 未集成 mosdns/smartdns：功能与 dae DNS 重叠，1G RAM 下不值得多养一个常驻进程。

---

## 目录结构

```
.github/workflows/   CI/CD：QCA-ALL(编译) / WRT-TEST(验证) / Auto-Clean / Cache-Clean / WRT-CORE(核心)
Scripts/Packages.sh  外部组件克隆注入（RivWRT 组件清单在此维护）
Scripts/Settings.sh  默认主题 / 主机名 / SSID / 管理地址 / banner 设置
Config/IPQ60XX-WIFI-YES.txt      平台与设备定义（qualcommax-ipq60xx / RE-CS-02）
Config/GENERAL_AX6600.txt        通用基座（NSS / firewall4 / 无线调优，跟随上游）
Config/GENERAL_AX6600_RIVWRT.txt RivWRT 增量（五个定制组件 + IPv6 + fullcone + Podman）
Docs/刷机救砖教程.md              上游原文刷机救砖全流程
```

## 更新日志

见 [CHANGELOG.md](CHANGELOG.md)。

## 免责声明

本项目固件仅供个人学习与研究使用。刷机有风险，操作前请备份分区并确认设备型号匹配，
因刷机造成的设备损坏或数据丢失由使用者自行承担。
