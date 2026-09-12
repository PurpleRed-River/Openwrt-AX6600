# RivWRT — AX6600 雅典娜定制固件

> 基于 [ones20250/Openwrt-AX6600](https://github.com/ones20250/Openwrt-AX6600) 纯净版的个人定制固件。
> 编译机制（GitHub Actions、配置拼接、缓存与发布）沿用上游，感谢上游作者的持续维护。
> 设备：京东云无线宝 AX6600 雅典娜 `RE-CS-02`（IPQ6010 / 1G RAM / 128G eMMC）。

---

## 与上游的差异（本仓库全部定制点）

上游每次编译产出 PURE / PLUS 双版本；本仓库固定产出**单一 RivWRT 定制版**，即“上游 PURE 纯净基座 + 以下内容”：

| 组件 | 来源 | 说明 |
|------|------|------|
| aurora 主题 | [eamonxg/luci-theme-aurora](https://github.com/eamonxg/luci-theme-aurora) | 现代界面，编译期设为默认主题 |
| aurora 主题设置 | [eamonxg/luci-app-aurora-config](https://github.com/eamonxg/luci-app-aurora-config) | 预设/浅深色/导航布局/背景/主题商店 |
| Athena LED 点阵屏 | 上游树内 `luci-app-athena-led` | ones20250 同款，自带预编译二进制零下载 |
| bandix-plus 流量统计 | [timsaya/openwrt-bandix-plus](https://github.com/timsaya/openwrt-bandix-plus) + [luci-app-bandix-plus](https://github.com/timsaya/luci-app-bandix-plus) | eBPF 旁路观察（用法见下） |
| daede 代理 | [kenzok8/openwrt-daede](https://github.com/kenzok8/openwrt-daede) | dae eBPF 透明代理内核 + daed + 统一管理界面 |
| partexp 分区管理 | [sirpdboy/luci-app-partexp](https://github.com/sirpdboy/luci-app-partexp) | Web 一键格式化/扩容/挂载剩余存储 |
| wolultra 网络唤醒 | ones20250/packages | 上游 wolplus 的继任包 |
| ksmbd 文件共享 | 上游 feeds | 内核态 SMB，替换基座 Samba4（省约 34MB 常驻） |
| podman + podman-compose | 上游 feeds + 自建包 | 纯 CLI 容器与编排（PyPI sdist 打包，版本与哈希钉死） |
| NSS 加速管理页 | 本项目自建 `luci-app-rivwrt-nss` | 引擎开关 + 每 Core 负载实时状态 |
| statistics / vnstat | 上游 feeds | 历史图表与接口流量总量 |

基座能力（沿用上游）：**NSS 硬件加速全套**、**firewall4 / nftables**（iptables 关闭）、ath11k QCA 三频、无线内存水位调优、自动挂载等。

定制细节见 [`Config/GENERAL_AX6600_RIVWRT.txt`](Config/GENERAL_AX6600_RIVWRT.txt)、
[`Scripts/Packages.sh`](Scripts/Packages.sh)、[`Scripts/Settings.sh`](Scripts/Settings.sh)（均逐行中文注释）。

---

## 网口互换（已固化进设备树）

应需求将内置网口角色互换，并在 DTS 层完成（系统名 = 物理丝印 = 角色语义一致）：

| 物理丝印 | 系统设备名 | 角色 |
|---|---|---|
| 2.5G 口（原印 WAN） | `lan1` | **内网**（br-lan 成员） |
| 千兆 LAN1（原印 LAN1） | `wan` | **WAN**（接光猫拨号/DHCP） |

请在线缆与机壳贴标签避免混淆。首次升级会自动纠正旧命名的网络配置。

---

## 默认参数

| 项 | 值 |
|----|----|
| 管理地址 | `192.168.100.1` |
| 主机名 | `RivWRT` |
| 登录密码 | 默认无（**首次登录后请立即设置**） |
| WiFi | 三频分明，**默认开放无密码**（见下表） |

| SSID | 频段 | 信道 | 带宽 | 说明 |
|---|---|---|---|---|
| `RivWRT` | 2.4G | 11 | 20MHz | 抗干扰优先 |
| `RivWRT-5.2G` | 5G-1（4x4 游戏段） | 44 | 160MHz | 不稳可退 80MHz |
| `RivWRT-5.8G` | 5G-2（影音段） | 149 | 80MHz | 非 DFS |

通用：地区 US、功率 24dBm（ones20250 官方推荐）。需要加密时在 LuCI 无线页自行设置。

---

## 云编译

- **正式编译**：Actions → `QCA-ALL` → Run workflow（源码：ones20250/immortalwrt_ipq main）
- **配置验证**：Actions → `WRT-TEST`（仅生成 `.config`，几分钟）
- **单包验证**：Actions → `WRT-PKG-TEST`（编指定包链 + 关键 config 符号自动检查，用于快速定位组件问题）
- 固件命名：`RivWRT-时间-ipq60xx-jdcloud_re-cs-02-squashfs-factory/sysupgrade.bin`，Release 附 `.config` 快照、外部组件 commit 记录与 `sha256sums.txt`

---

## 刷机提示

- 适配已刷 [chenxin527/uboot-qsdk12.5-build](https://github.com/chenxin527/uboot-qsdk12.5-build) 的 **12MiB 内核 + 2GiB rootfs** 双分区（A 槽）布局，`KERNEL_SIZE` 已适配为 12288k。
- 首刷走 U-Boot Web 上传 `factory` 固件；系统内升级用 `sysupgrade`。
- 流程细节见 [Docs/刷机救砖教程.md](Docs/刷机救砖教程.md)（上游原文）。
- overlay 自动使用 rootfs 分区剩余空间，无需手动扩容；剩余 eMMC 可用 partexp 一键建分区挂 `/opt`。

---

## 使用注意

### NSS 加速

- 独立页面：**服务 → NSS 加速**（启用/停用/开机自启 + 每 Core 引擎负载，5 秒轮询）
- **防火墙页的“路由/NAT 卸载”保持“无”**——NSS 引擎独立工作，软件卸载会干扰
- 直连流量走 NSS 硬件加速；代理流量由 dae 内核态接管，两者天然分工

### bandix 流量统计

- 纯观察，不影响转发性能；NSS 加速的流量不计入其统计（数字偏低属正常）
- 需要精确报表时在 NSS 页面“停用 NSS 加速”，看完再启用
- **不要开启 bandix 自身的管控/限速功能**（NSS 下不生效）
- 接口级总量统计由 vnstat 承担（NSS 流量照数）

### 代理（daede）

- 建议后端选 **dae**（省内存）；节点/规则自行导入
- DNS 内外网分流与防污染由 dae 内置模块承担（geosite/geoip），未集成 mosdns/smartdns
- 面板监听地址与密码请自行加固（默认监听全部接口）

### 文件共享（ksmbd）

- 位置：LuCI → 服务 → 网络共享
- 无打印共享与域控；macOS Time Machine 支持有限
- 共享目录建议指向 `/opt`（大分区），并自行决定是否启用匿名访问

### 容器（podman CLI）

```sh
mkdir -p /opt/compose && cd /opt/compose
# 编写 docker-compose.yml 后：
podman-compose up -d
```

- podman 的常驻 API 服务默认关闭（省内存）；需要远程 API 时 `/etc/init.d/podman start`
- 容器数据建议放 `/opt`，避免占用系统 overlay

---

## 目录结构

```
.github/workflows/   QCA-ALL(编译) / WRT-TEST(配置验证) / WRT-PKG-TEST(单包验证) / WRT-CORE(核心) / Auto-Clean / Cache-Clean
Scripts/Packages.sh  外部组件克隆注入（aurora/bandix/daede/partexp/wolultra）
Scripts/Settings.sh  构建期定制：主题/banner/无线固化/DTS 端口互换/KERNEL_SIZE/
                     菜单归拢/FullCone/daede 暗色屏蔽/自建包生成(NSS 页面、podman-compose)
Config/IPQ60XX-WIFI-YES.txt      平台与设备定义
Config/GENERAL_AX6600.txt        通用基座（跟随上游，未改动）
Config/GENERAL_AX6600_RIVWRT.txt RivWRT 增量（组件/BPF 工具链/内核 BTF/fullcone 等）
Docs/刷机救砖教程.md              上游原文
```

## 更新日志

见 [CHANGELOG.md](CHANGELOG.md)。

## 免责声明

本项目固件仅供个人学习与研究使用。刷机有风险，操作前请备份分区并确认设备型号匹配，
因刷机造成的设备损坏或数据丢失由使用者自行承担。
