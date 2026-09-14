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
- 默认值：主机名/SSID `RivWRT`、管理地址 `192.168.100.1`、默认主题 aurora；WiFi 默认开放（无密码）。

### 组件（Scripts/Packages.sh RivWRT 注入块）

- aurora 主题（eamonxg 版）+ 编译期默认主题替换（Settings.sh）
- Athena LED 点阵屏控制：回退上游树内官方版 `luci-app-athena-led`
  （ones20250 同款，预编译二进制零下载）；unraveloop 增强版 release 资产已 404 无法构建
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

## 2026-09-12 · 运行时修复与增强批次

### 修复（编译层已验证通过后的运行时问题）

- `Settings.sh`：UDIR 变量未定义（删网口互换块时误删定义）→
  所有 uci-defaults 写根目录失败，菜单归拢/FullCone/podman 关闭/网络纠正全部未生效（模拟树验证修复）
- 无线 init.d 缺 rc.d 启用链接 → 三频固化未执行（补 S99rivwrt-wifi 链接）
- 无线 init.d：jsonfilter -s 误用（应 -i）→ 5G 频段探测失败；
  加固：探测失败回落 149/HT80 非 DFS 安全值，不残留生成器的 DFS 默认信道
- NSS 页面 JS：重复定义 render + fs.exec 参数误用 → 重写（bun 语法校验）
- Config 漏 `CONFIG_PACKAGE_luci-app-rivwrt-nss=y` → NSS 页面未进固件（已补）
- `podman-compose`：上游 immortalwrt/packages 无此包（死配置行）→
  自建 PyPI 打包（1.6.0 sdist + sha256 钉死，依赖 python3-yaml/dotenv）

### 新增

- DTS 端口 label 互换（wan↔lan1）：系统名 = 物理丝印 = 角色语义一致；
  弃 uci-defaults 网口互换方案（实测拔插确认丝印 WAN=dp5、丝印 LAN1=dp1）
- 网络配置纠正 uci-defaults（98-rivwrt-net-fix）：兼容旧命名配置升级
- ksmbd 替换 Samba4（省 ~34MB 常驻；上游无打印/域控需求，纯收益）
- `CONFIG_VERSION_DIST="RivWRT"`：banner/openwrt_release/系统 ID 品牌化
- `CONFIG_DEBUG_INFO_BTF=y`：内核原生 BTF（vmlinux-btf 包仍作 dae 依赖兜底）
- podman API 服务默认关闭（省 ~45MB；podman 包 init 无条件常驻 system service）
- banner：figlet 字样 + 项目格言 "Flow downstream, not upstream."
- FullCone NAT 固化开启（96-rivwrt-fullcone）
- 分区适配：KERNEL_SIZE=12288k（实测 A 槽 0:HLOS=12288KB，GPT 对齐）

### 文档

- README 全量重构（组件表/网口表/无线表/使用指南折叠块/构建系统说明）
- CHANGELOG 补运行时修复批次（本段）

---

## 2026-09-14 · NSS 页面完善与无线首启修复

### 无线（首次刷机后 5G 起不来）

- **根因**：ath11k 的 phy 级 regd 更新走 workqueue，三个 radio 并发启动时相互竞争，
  部分 phy 更新失败（日志实证 `hostapd: Frequency 5180/5745 is not allowed`），
  导致两个 5G 起不来；重启一次即恢复。
- **改法**：`rivwrt-wifi` 改为「参数比对 → 对未就绪的 radio 逐个串行重启 → 仍不行则兜底重启一次」，并用
  `/etc/.rivwrt-wifi-rebooted` 守卫防止无限重启循环。
  ★ 不可用 `wifi reload` 重试——读 `/sbin/wifi` 源码可知它忽略设备参数、执行全量
  `ubus call network reload`，会把三个 radio 一起重启，反而加剧竞争。
- SSID：2.4G 改为 `RivWRT-2.4G`（三频分名一致）

### NSS 加速页

修复（均为实测复现）：

| 问题 | 影响 |
|---|---|
| 负载图取**行内首个百分比**（= Min 列） | 曲线长期显示为低谷；应取 Avg 列 |
| `rrdtool fetch` 输出 `ts: value` 的冒号未剥离 → 拼出 `ts::v` | 前端 split 得 3 段全丢弃，**历史图永远空白** |
| `draw()` 清空 svg 后未补挂悬停层 | 页面停留 5 秒后悬停十字线永久消失，且不报错 |
| 样本数 <2 时 `monotone()` 返回空串、`xOf()` 以 `n-1` 为分母 | 单点历史产出 `d=" LNaN,… LNaN,… Z"`，整条曲线画不出 |
| `readStatus()` 无条件吞掉错误 | ACL 失效/脚本缺失只表现为"图表一直空着"，提示却说"等待约 30 秒" |
| 自启状态取 `rc.list` 的 `enabled` 字段 | **恒报未启用**：`rc.c` 只读 init 脚本前 11 行，而 `qca-nss-ecm` 有 16 行版权头、`START=26` 在第 18 行；改为直接判定 `/etc/rc.d/S??qca-nss-ecm` 链接 |
| 引擎状态用 `lsmod` 检测 | busybox 未编译该 applet 时恒判"已停用"；改用 `/proc/modules` |
| 连接数按"纯数字"解析 | ECM 实际给的是 `tcp X udp Y other Z total W` 文本 → 页面永远显示 `—` |

新增：

- **频率档位**按钮（748.8 / 1497.6 MHz），走上游 `/usr/bin/nss_freq`，写 proc 并存入 UCI
- **加速连接数** KPI（判断"加速是否在工作"最直接的指标）
- 负载历史图支持 2 小时 / 12 小时 / 1 天 / 1 周切换，含悬浮读数
- 开关改用 LuCI 标准组件（`ui.Checkbox`）与官方 `ubus rc.init` 接口，外观交给主题

> 页面不提供 Auto/Fixed 调频切换：上游 `qca-nss-pbuf` 开机即把 NSS 时钟锁频
> （`auto_scale=0`），这是其 pbuf/N2H offload 配置的前提，不该反着改。

### 测试

- 新增 `Scripts/nss-page-test.js`（前端，46 项）与 `Scripts/nss-status-test.sh`（后端解析，10 项），
  直接从 `Settings.sh` 取代码运行，无需编译固件。已用缺陷注入验证其有效性
  （移除修复即失败）。
- README 补「目录结构」章节（修掉 TOC 里的死链）与 NSS 读数含义说明。

---

## 上游历史（fork 自 ones20250/Openwrt-AX6600）

上游按 PURE（纯净）/ PLUS（预装 OpenClash、PassWall2、Docker 等）双版本发布，机制详见上游仓库。
本仓库不再构建 PURE/PLUS，仅维护 RivWRT 定制版。
