# RivWRT AX6600 配置说明

## 编译定位

本项目基于：

- PurpleRed-River/Openwrt-AX6600

上游：

- ones20250/Openwrt-AX6600

## 默认参数

```text
固件名称: RivWRT
SSID: RivWRT
WiFi密码: 1qaz!QAZ
LAN地址: 192.168.100.1
```

## 无线默认优化

雅典娜三频：

```text
2.4G
信道: 11
带宽: 20MHz

5G-1
信道: 44
带宽: HE160

5G-2
信道: 149
带宽: HE80
```

地区：US

加密：WPA2-PSK / CCMP

## 网络方案

防火墙：

- firewall4
- nftables

IPv6：

- 开启
- RA/DHCPv6 支持

## 代理

使用：

- dae

节点配置由用户自行导入。

不默认集成多套代理框架，避免资源浪费和规则冲突。

## DNS

方案：

- mosdns
- smartdns
- geosite/geoip

用于国内外分流和污染处理。

## 存储

设备使用 eMMC。

默认不自动重新规划剩余空间。

Podman、容器镜像、下载目录建议刷机后根据需求单独规划。

## 维护规范

新增脚本和配置统一加入中文注释，说明用途、来源和影响范围。