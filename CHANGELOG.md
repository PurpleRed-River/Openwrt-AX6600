# RivWRT AX6600 更新记录

## 2026-09-11 · 基于 ones20250 纯净版重建（RivWRT v1）

本次为全量重写：上游编译机制原样保留，定制全部收敛到 RIVWRT 单 profile。

### 修复

- `QCA-ALL.yml`：还原上游骨架并改为单 matrix（`PROFILE: [RIVWRT]`）。
  此前 fork 的 `PROFILE: RIVWRT` 未同步 `WRT-CORE.yml` 白名单，触发 `exit 1`，一跑即失败。
- 移除 GPT 残留的格式错误配置（裸包名列表，不符合 `.config` 片段的 `CONFIG_*` 格式）。

### 工作流

- `WRT-CORE.yml`：profile 白名单加入 `RIVWRT`；固件命名改为
  `RivWRT-时间-ipq60xx-jdcloud_re-cs-02-*.bin`；Release 文案更新为 RivWRT 组件清单。
- `WRT-TEST.yml`：PROFILE 选项与默认值改为 RIVWRT，默认参数与正式编译一致。
- 默认值：主机名/SSID `RivWRT`、WiFi 密码 `1qaz!QAZ`、管理地址 `192.168.100.1`、默认主题 aurora。

### 组件（Scripts/Packages.sh RivWRT 注入块）

- aurora 主题（eamonxg 版）+ 编译期默认主题替换（Settings.sh）
- Athena LED 点阵屏控制（unraveloop 版，pkg 模式提取两子包；树内旧版 athena-led-control 先删后装）
- bandix-plus 流量统计（后端 + LuCI 前端，eBPF 旁路观察定位）
- daede 透明代理（dae + daed + luci-app-daede 一体包，pkg 模式提取三子包）

### 配置（Config/GENERAL_AX6600_RIVWRT.txt 新增）

- 显式开启：dae / luci-app-daede / bandix-plus 双包 / luci-theme-aurora / luci-app-athena-led
- Podman 容器环境（kmod-veth 覆盖基座 =n）、IPv6（odhcp6c / odhcpd-ipv6only）
- kmod-nft-fullcone（fullcone NAT）、vnstat（接口级总量统计，NSS 流量照数）
- 关闭：mosdns / smartdns（DNS 分流由 dae 内置模块承担）、树内旧版 LED 包

### 定位说明

- NSS 优先：直连流量满血硬件加速；dae 代理流量内核态接管，二者天然分工。
- bandix 纯观察：不影响转发性能；精确报表需临时停用 NSS ecm（README 有操作说明）。
- Config/GENERAL_AX6600_PLUS.txt 与 GPT 版 RIVWRT_AX6600.txt 已删除；Docs 三个半成品文档已删除，
  保留上游原文《刷机救砖教程.md》。

---

## 上游历史（fork 自 ones20250/Openwrt-AX6600）

上游按 PURE（纯净）/ PLUS（预装 OpenClash、PassWall2、Docker 等）双版本发布，机制详见上游仓库。
本仓库不再构建 PURE/PLUS，仅维护 RivWRT 定制版。
