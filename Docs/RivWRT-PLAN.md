# RivWRT AX6600 定制计划

## 项目基础

开发仓库：

- PurpleRed-River/Openwrt-AX6600

上游来源：

- ones20250/Openwrt-AX6600

## 设备目标

- JDCloud RE-CS-02（雅典娜 AX6600）
- Qualcomm IPQ6010
- qualcommax/ipq60xx
- U-Boot Web 刷入

## 底层原则

保留原项目：

- kernel 路线
- NSS 硬件加速框架
- ath11k 无线适配
- 设备 image 生成规则

不主动替换底层硬件支持。

## 功能规划

### 网络

- firewall4
- nftables
- IPv6
- NSS 加速

### 无线

- firmware_qca-wireless
- 三频 WiFi 默认优化

推荐：

- 2.4G：信道 11，20MHz
- 5G-1：信道 44，160MHz
- 5G-2：信道 149，80MHz

### 代理

采用：

- dae

节点配置由用户自行导入。

### DNS

采用：

- mosdns/smartdns
- geosite/geoip 规则

用于国内外分流和污染处理。

### 系统扩展

- Aurora LuCI 主题
- Athena LED Controller
- Bandix Plus
- WOL Plus
- Podman 容器环境

## 固件输出

保留设备原有命名方式：

- qualcommax-ipq60xx-jdcloud_re-cs-02-squashfs-factory.bin
- qualcommax-ipq60xx-jdcloud_re-cs-02-squashfs-sysupgrade.bin

factory 用于 U-Boot Web 首刷。

sysupgrade 用于系统内升级。

## 默认参数

- 固件名称：RivWRT
- SSID：RivWRT
- WiFi密码：1qaz!QAZ
- LAN：192.168.100.1

## 注意

所有新增配置文件和脚本使用中文注释，方便后续维护。