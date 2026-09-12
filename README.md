<div align="center">

# █ RivWRT

**AX6600 雅典娜 · 个人定制固件**

*基于 [ones20250/Openwrt-AX6600](https://github.com/ones20250/Openwrt-AX6600) 纯净基座*

`IPQ6010` `4×A53` `1G RAM` `128G eMMC` `NSS 加速` `dae eBPF` `kernel 6.18`

*" Flow downstream, not upstream. "*

</div>

---

## 目录

- [定制组件](#-定制组件)
- [固件特性](#-固件特性)
- [网口定义](#-网口定义已互换)
- [默认参数](#-默认参数)
- [云编译与刷机](#-云编译与刷机)
- [使用指南](#-使用指南)
- [构建系统说明](#-构建系统说明)
- [目录结构](#-目录结构)

---

## ✨ 定制组件

| 组件 | 来源 | 说明 |
|------|------|------|
| **aurora 主题** | [eamonxg/luci-theme-aurora](https://github.com/eamonxg/luci-theme-aurora) | 现代界面，编译期设为默认 |
| **aurora 设置界面** | [eamonxg/luci-app-aurora-config](https://github.com/eamonxg/luci-app-aurora-config) | 预设/浅深色/布局/主题商店 |
| **Athena LED 点阵屏** | 上游树内官方版 | 网速/天气/农历，预编译二进制零下载 |
| **bandix-plus 流量统计** | [timsaya/openwrt-bandix-plus](https://github.com/timsaya/openwrt-bandix-plus) + [前端](https://github.com/timsaya/luci-app-bandix-plus) | eBPF 旁路观察（见[使用注意](#使用注意)） |
| **daede 透明代理** | [kenzok8/openwrt-daede](https://github.com/kenzok8/openwrt-daede) | dae eBPF 内核 + daed + 统一管理页 |
| **partexp 分区管理** | [sirpdboy/luci-app-partexp](https://github.com/sirpdboy/luci-app-partexp) | Web 一键格式化/扩容/挂载 |
| **wolultra 网络唤醒** | [ones20250/packages](https://github.com/ones20250/packages) | 上游 wolplus 继任包 |
| **ksmbd 文件共享** | 上游 feeds | 内核态 SMB，替换基座 Samba4（省 34MB） |
| **NSS 加速管理页** | 本项目自建 `luci-app-rivwrt-nss` | 引擎开关 + 每 Core 负载实时状态 |
| **podman-compose** | 本项目自建包（PyPI 1.6.0） | CLI 容器编排 |
| **statistics / vnstat** | 上游 feeds | 历史图表 / 接口流量总量 |

基座沿用上游：**NSS 硬件加速全套**、**firewall4/nftables**、ath11k 三频、内存水位调优、自动挂载。

定制细节：[`Config/GENERAL_AX6600_RIVWRT.txt`](Config/GENERAL_AX6600_RIVWRT.txt) ·
[`Scripts/Packages.sh`](Scripts/Packages.sh) · [`Scripts/Settings.sh`](Scripts/Settings.sh)（均逐行中文注释）

---

## 🔧 固件特性

- **NSS 满血加速**：直连流量硬件转发（CPU 近零）；代理流量由 dae 内核态接管，互不抢道
- **内核原生 BTF**：`CONFIG_DEBUG_INFO_BTF=y`，eBPF 程序开箱即用
- **网口语义化**：DTS 层互换端口名，系统名 = 物理丝印 = 角色（见下表）
- **FullCone NAT**：游戏机/P2P 友好，默认开启（防火墙页可关）
- **eMMC 寿命关怀**：数据盘独立分区 + 每周 fstrim + 高频写服务默认关闭
- **无默认密码**：登录与 WiFi 均默认开放，首刷请立即加固

---

## 🔌 网口定义（已互换）

| 物理丝印 | 系统设备名 | 角色 |
|---|---|---|
| **2.5G**（原印 WAN） | `lan1` | **内网**（br-lan 成员） |
| **LAN1**（千兆） | `wan` | **WAN**（接光猫） |
| LAN2-LAN4（千兆） | `lan2`~`lan4` | 内网 |

> 丝印 WAN 口 = 内网 2.5G 口；丝印 LAN1 = WAN 口。**光猫接丝印 LAN1**。
> 通过 DTS 端口 label 互换实现（`Settings.sh` 构建期注入），刷机即生效。

---

## 📡 默认参数

| 项 | 值 |
|----|----|
| 管理地址 | `192.168.100.1` |
| 主机名 | `RivWRT` |
| 登录密码 | 默认无（**首刷请立即设置**） |
| WiFi | 三 SSID 分频，**默认开放**（见下） |

| SSID | 频段 | 信道 | 带宽 |
|---|---|---|---|
| `RivWRT` | 2.4G | 11 | 20MHz |
| `RivWRT-5.2G` | 5G 游戏段（4×4） | 44 | 160MHz |
| `RivWRT-5.8G` | 5G 影音段 | 149 | 80MHz |

通用：地区 US · 功率 24dBm（ones20250 官方推荐）。首次启动由 `rivwrt-wifi` 服务自动固化（按总线自动区分 5G 频段，探测失败回落非 DFS 安全值）。

---

## 🖥 云编译与刷机

| Workflow | 用途 |
|---|---|
| `QCA-ALL` | 正式编译（源码：ones20250/immortalwrt_ipq main） |
| `WRT-TEST` | 仅生成 `.config`（几分钟，验证配置） |
| `WRT-PKG-TEST` | 单包链编译验证（快速定位组件问题） |

- 固件命名：`RivWRT-时间-ipq60xx-jdcloud_re-cs-02-squashfs-factory/sysupgrade.bin`
- 适配分区：**12MiB 内核 + 2GiB rootfs**（chenxin527 GPT，A 槽）
- 首刷走 U-Boot Web 上传 `factory`；系统内升级用 `sysupgrade`（独立数据分区不受影响）
- 详细流程：[Docs/刷机救砖教程.md](Docs/刷机救砖教程.md)

---

## 📖 使用指南

<details>
<summary><b>NSS 加速与代理的分工</b></summary>

- 直连流量：NSS 硬件转发，CPU 近零
- 代理流量：dae 在内核态接管（eBPF），与 NSS 天然分工
- 页面：**服务 → NSS 加速**（开关 + 每 Core 负载，5 秒轮询）；**服务 → daede**（节点/规则配置）
- 防火墙页"路由/NAT 卸载"保持**无**——NSS 独立工作，软件卸载会干扰

</details>

<details>
<summary><b>bandix 流量统计的定位</b></summary>

- eBPF 旁路观察，不影响转发性能；**管控/限速功能勿开**（NSS 下不生效）
- NSS 加速的流量不计入其统计（数字偏低属正常），需要精确报表时在 NSS 页面临时停用加速
- 长周期总量看 vnstat（接口计数器，NSS 流量照数）

</details>

<details>
<summary><b>文件共享（ksmbd）与存储规划</b></summary>

- 先用 partexp 把剩余空间格式化为 ext4 并挂载 `/opt`
- ksmbd 共享目录指向 `/opt/share`（LuCI 服务 → 网络共享）
- 容器数据 → `/opt/containers`，compose 文件 → `/opt/compose`
- 系统日志写内存（tmpfs）不伤 eMMC；每周 fstrim 已内置
- ksmbd 无打印共享与域控；macOS Time Machine 支持有限

</details>

<details>
<summary><b>容器（podman CLI）</b></summary>

```sh
mkdir -p /opt/compose && cd /opt/compose
vim docker-compose.yml        # 定义服务栈
podman-compose up -d
```

- podman 常驻 API 服务默认关闭（省 45MB）；需要远程 API 时 `/etc/init.d/podman start`
- 容器数据建议 `/opt/containers`（storage.conf 可改 graphroot）

</details>

<details>
<summary><b>登录横幅</b></summary>

SSH 登录显示点阵 RivWRT 标志 + 项目格言 + 组件清单，由 `Settings.sh` 构建期生成（`/etc/banner`）。

</details>

---

## 🛠 构建系统说明

```
.github/workflows/
  QCA-ALL.yml        正式编译（RIVWRT 单 profile）
  WRT-TEST.yml       配置验证（TEST=true 只出 .config）
  WRT-PKG-TEST.yml   单包链编译验证 + 关键符号自动检查
  WRT-CORE.yml       编译核心（环境/缓存/发布）
Scripts/
  Packages.sh        外部组件克隆注入（RivWRT 组件清单在此维护）
  Settings.sh        构建期定制（主题/banner/无线固化/DTS 互换/
                     KERNEL_SIZE/uci-defaults 生成/自建包生成）
Config/
  IPQ60XX-WIFI-YES.txt        平台与设备（RE-CS-02）
  GENERAL_AX6600.txt          通用基座（NSS/防火墙/无线，跟随上游）
  GENERAL_AX6600_RIVWRT.txt   RivWRT 增量（全部定制项，中文注释）
```

生成包说明：`luci-app-rivwrt-nss` 与 `podman-compose` 由 `Settings.sh` 在构建期生成于
`package/`（上游 feeds 无此二包），版本与哈希钉死在生成块内，升级只改生成块中的版本号。

## 更新日志

见 [CHANGELOG.md](CHANGELOG.md)。

## 免责声明

本项目固件仅供个人学习与研究使用。刷机有风险，操作前请备份分区并确认设备型号匹配，
因刷机造成的设备损坏或数据丢失由使用者自行承担。
