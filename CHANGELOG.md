# RivWRT AX6600 更新记录

## Initial RivWRT Release Plan

基础仓库：

- PurpleRed-River/Openwrt-AX6600

上游来源：

- ones20250/Openwrt-AX6600

## 架构调整

- 固定 RivWRT AX6600 为主要发布方案
- 保留原项目 GitHub Actions 云编译框架
- 保留 JDCloud RE-CS-02（雅典娜 AX6600）硬件适配
- 保留 qualcommax/ipq60xx 镜像生成方式
- 保留 NSS 硬件加速框架
- 保留 ath11k/QCA 无线支持

## 网络功能

- 增强 IPv6 支持
- 使用 firewall4 + nftables 防火墙方案
- 集成 dae 代理框架
- DNS 分流规划：mosdns + smartdns
- 规则来源规划：geosite / geoip

## LuCI 与服务组件

- 集成 Aurora LuCI 主题
- 集成 Athena LED 控制
- 集成 Bandix Plus 流量统计
- 集成 WOL Plus 网络唤醒
- 增加 Podman 容器环境规划

## 无线优化记录

雅典娜三频默认建议：

- 2.4G：信道 11，20MHz
- 5G-1：信道 44，160MHz
- 5G-2：信道 149，80MHz

通用：

- 地区 US
- 发射功率 24dBm
- WPA2-PSK + CCMP

## 刷机说明

设备通过 U-Boot Web 刷入时：

首次刷入：

`qualcommax-ipq60xx-jdcloud_re-cs-02-squashfs-factory.bin`

系统升级：

`qualcommax-ipq60xx-jdcloud_re-cs-02-squashfs-sysupgrade.bin`

## 存储规划

设备 eMMC 剩余空间不在固件阶段自动重分区。

Podman、容器镜像以及长期数据建议在刷机后根据实际需求手动规划独立存储空间。
