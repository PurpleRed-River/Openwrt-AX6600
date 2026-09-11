# RivWRT AX6600 更新记录

## Initial RivWRT Planning

基础仓库：

- PurpleRed-River/Openwrt-AX6600

上游来源：

- ones20250/Openwrt-AX6600

## 定制方向

- 保留 JDCloud RE-CS-02 (IPQ6010) 硬件适配
- 保留 qualcommax/ipq60xx 镜像生成方式
- 保留 NSS 硬件加速框架
- 保留 ath11k 无线支持
- 增加 RivWRT 固件标识
- 增强 IPv6 支持
- 集成 dae 代理框架
- 集成 DNS 分流方案
- 集成 Aurora LuCI 主题
- 集成 Athena LED 控制
- 集成 Bandix Plus 流量统计
- 集成 WOL Plus 网络唤醒
- 规划 Podman 容器环境

## 刷机说明

设备通过 U-Boot Web 刷入时，继续使用项目生成的：

`qualcommax-ipq60xx-jdcloud_re-cs-02-squashfs-factory.bin`

系统升级使用：

`qualcommax-ipq60xx-jdcloud_re-cs-02-squashfs-sysupgrade.bin`

## 存储规划

设备 eMMC 剩余空间不在固件阶段自动重分区。

Podman、容器镜像以及长期数据建议在刷机后手动规划独立存储空间。
