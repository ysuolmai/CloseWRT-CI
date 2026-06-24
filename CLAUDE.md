# CloseWRT-CI 项目说明

> 供 Claude Code 自动读取的上下文文档。

## 项目概述

基于 padavanonly/openwrt-21.02（kernel 6.6，闭源硬件加速）的多设备 CI 固件构建项目。
GitHub: https://github.com/ysuolmai/CloseWRT-CI

与 OpenWRT-CI 的区别：
- kernel 6.6（OpenWRT-CI 是 6.18）
- 闭源 MTK WiFi 驱动（硬件加速）
- DTS 用 `mt7981.dtsi`（不是 `mt7981b.dtsi`），无 spi-cal-* 属性，需显式 memory 节点

## 目标设备

| 设备 | 平台 | 备注 |
|------|------|------|
| sx_7981r128 | MTK filogic (MT7981B) | 主要设备，需 CI 注入 |
| nokia_ea0326gmp | MTK filogic (MT7981B) | 白名单保留 |
| cmcc_rax3000m | MTK filogic (MT7981B) | 白名单保留 |

## SX 7981R128 硬件信息

- **SoC**: MediaTek MT7981B (Cortex-A53 × 2)
- **RAM**: 512MB **DDR3**（已确认）
- **Flash**: 128MB SPIM-NAND
- **2.5G PHY**: Airoha EN8801S，接 MT7531 switch port@5（label: lan2）
- **Switch**: MediaTek MT7531
- **SFP 笼**: 接 gmac1（eth1），wan2
- **WiFi**: MT7976（双频 Wi-Fi 6）

### 网口分配
```
lan1  → 千兆 LAN
lan2  → EN8801S 2.5G → 默认 WAN（主要）
eth1  → SFP 笼 → wan2（次要，uci-defaults 配置）
```

### MAC 分配
```
factory/Factory offset 0x04 → base MAC
lan/label_mac               → base
lan2 主 WAN                 → base + 1
eth1 / SFP wan2             → base + 2（uci-defaults 设置）
```

### NAND 分区布局
```
0x000000 - 0x100000  BL2        (1MB)
0x100000 - 0x180000  u-boot-env (512KB)
0x180000 - 0x380000  Factory    (2MB)
0x380000 - 0x580000  FIP        (2MB)
0x580000 - 0x7780000 UBI        (114688KB raw range)
0x7780000 - 0x8000000 reserved  (NMBM/BMT tail)
```

## 关键脚本说明

### WRT-CORE.yml 完整 job 执行顺序
```
Combine Disks          ← easimon/maximize-build-space，合并根+/mnt → ~55GB，挂载到 /mnt
→ Initialization Environment
→ Clone Code
→ Check Caches / Update Caches
→ Update Feeds
→ Custom Packages       ← Scripts/Packages.sh + Scripts/Handles.sh
→ Custom Settings:
    cat Config/*.txt >> .config
    → Scripts/Settings.sh
    → Scripts/diy.sh    ← 最后执行，改动优先级最高
    → make defconfig
→ Download Packages
→ Compile Firmware
→ Package Firmware
→ Release Firmware
```

### Free Disk Space 说明
手动删除 runner 预装无用工具，替代 `easimon/maximize-build-space`：

**为何不用 easimon/maximize-build-space**：新 runner (ubuntu-24.04 v20260518+) 根分区已有 145GB，action 的 `root-reserve-mb` 参数存在 bug，无论设多少都会把根分区吃光（测试过 1024 和 10240 均如此），导致 apt update 报 "No space left on device"。

**当前方案**：
- 删除 dotnet / Android SDK / GHC / CodeQL / Docker 镜像，释放 ~20GB
- 编译直接在 `$GITHUB_WORKSPACE/wrt`（根分区），可用约 **110GB**
- 不再 symlink 到 /mnt

### Scripts/diy.sh 各节职责
| 节 | 内容 |
|----|------|
| 0 | MTK 设备白名单（只保留 3 个设备） |
| 1 | 移除不需要的包（easytier、qbittorrent、vnt、kmod-wireguard） |
| 2 | UPDATE_PACKAGE 安装额外包（poweroff、adguardhome、bandix、jell 批量等；smartdns 已移除，kenzok8/jell Makefile URL 损坏） |
| 3 | provided_config_lines 写入 .config |
| 4 | 通用 Makefile 修复（cmake、getifaddr、v2ray-geodata 等） |
| 4b | CSS 颜色修复 + uci-defaults 文件内置（ttyd、argon、dropbear、网络等） |
| 5 | sx_7981r128 设备注入（DTS、filogic.mk、02_network、01_leds、platform.sh、uci-defaults） |

### Scripts/dts/mt7981b-sx-7981r128.dts（kernel 6.6 版本）
- 使用 `mt7981.dtsi`（**不是** mt7981b.dtsi）
- **无** spi-cal-* 属性
- 显式 memory 节点: `<0 0x40000000 0 0x20000000>` = 512MB
- GPIO 头文件需显式 include
- factory 分区提供 WiFi EEPROM 和 MAC base nvmem cell
- gmac0 使用 base，gmac1/SFP 使用 base+2；lan2 主 WAN 由 board.d 设置为 base+1

## FIP / U-Boot

**本仓库产 `sysupgrade.bin`（sysupgrade-tar）和 `factory.bin`（append-ubi），不掺和 U-Boot/FIP/BL2。**

FIP / preloader 在独立仓库构建：<https://github.com/ysuolmai/UBOOT-CI>
- 设备硬件：MT7981B + 512MB DDR3-1866（SK Hynix H5TQ4G63EFR-RDC）+ 128MB SPIM-NAND

## 内置脚本文件（Scripts/ 目录）

| 文件 | 用途 |
|------|------|
| `99_ttyd-nopass.sh` | ttyd 免密登录 |
| `99_set_argon_primary` | argon 主题色 #31A1A1 |
| `99_dropbear_setup.sh` | SSH 配置 |
| `991_set-network.sh` | IPv6 DHCPv6/SLAAC 初始化 |
| `99-distfeeds.conf` | opkg 镜像源（mirrors.vsean.net） |
| `ddns-go.init` | ddns-go procd 启动脚本 |
| `rust-makefile.patch` | rust 编译修复 |

## 重要约定

- **Git commit co-author**: `Co-Authored-By: bugwriter <noreply@wahlau.top>`
- **push 冲突**：先 `git pull --rebase`，不要 force push，除非明确要求
- **WireGuard 已移除**
- **Docker/EMMC 相关不适用**（MTK SPIM-NAND 跑不了）
