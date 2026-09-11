# RivWRT AX6600

基于 `PurpleRed-River/Openwrt-AX6600`

上游来源：`ones20250/Openwrt-AX6600`

适配设备：

- JDCloud RE-CS-02（京东云雅典娜 AX6600）
- Qualcomm IPQ6010
- qualcommax / ipq60xx

## 项目定位

RivWRT 是针对雅典娜 AX6600 的定制固件方案，保留原项目硬件适配和 GitHub Actions 云编译框架，专注于稳定、高性能网络体验。

## 核心特性

- NSS 硬件加速引擎
- Qualcomm QCA / ath11k 无线支持
- 三频 WiFi 优化
- firewall4 + nftables 防火墙
- IPv6 支持
- dae 代理框架
- mosdns + smartdns DNS 分流
- geosite / geoip 规则支持
- Aurora LuCI 主题
- Athena LED 控制
- Bandix Plus 网络行为统计
- WOL Plus 网络唤醒
- Podman 容器环境支持

## 固件刷入

设备已安装 U-Boot 后，通过 U-Boot Web 页面刷入。

首次刷入使用：

```text
*-squashfs-factory.bin
```

系统内升级使用：

```text
*-squashfs-sysupgrade.bin
```

## WiFi 推荐设置

雅典娜三频建议：

| WiFi | 信道 | 带宽 |
|---|---|---|
| 2.4G | 11 | 20MHz |
| 5G-1 游戏频段 | 44 | 160MHz |
| 5G-2 影音频段 | 149 | 80MHz |

通用建议：

- 地区：US
- 发射功率：24 dBm
- 加密：WPA2-PSK + CCMP

## 网络方案

### 代理

默认仅集成 dae。

节点配置由用户自行导入，不预置多套代理框架，减少资源占用。

### DNS

采用：

- mosdns
- smartdns

规则：

- geosite
- geoip

用于国内外分流及 DNS 污染处理。

## 存储规划

设备 eMMC 大容量空间不在固件阶段自动调整。

Podman 容器、镜像及长期数据建议刷机后根据需求规划独立存储。

## 构建

主要配置：

```text
Config/RIVWRT_AX6600.txt
```

基础无线配置：

```text
Config/IPQ60XX-WIFI-YES.txt
```

## 第三方组件

详细说明：

```text
Docs/第三方组件说明.md
```

## 免责声明

刷机存在风险，请提前备份重要分区和配置。