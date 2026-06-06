#!/bin/bash
# SPDX-License-Identifier: MIT
#
# diy.sh — 设备白名单 + 包管理 + 设备注入
# 由 WRT-CORE.yml 的 Custom Settings step 调用
# 执行顺序：cat Config/*.txt >> .config → Settings.sh → diy.sh → make defconfig
# 工作目录：wrt/

echo "================================================================"
echo "[diy] 开始"
echo "================================================================"

# ---------------------------------------------------------------
# 0. MTK 设备白名单 — 只保留指定设备
# ---------------------------------------------------------------
mtk_keep="\(mediatek_7981r128\|nokia_ea0326gmp\|cmcc_rax3000m\)=y$"
sed -i "/^CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_/{
    /$mtk_keep/!d
}" ./.config
echo "[diy] 设备白名单已应用（保留：mediatek_7981r128 nokia_ea0326gmp cmcc_rax3000m）"

# ---------------------------------------------------------------
# 1. 移除不需要的包
# ---------------------------------------------------------------
keywords_to_delete=(
    "easytier" "qbittorrent" "vnt" "kmod-wireguard" "uugamebooster" "luci-app-wol" "luci-i18n-wol-zh-cn" "CONFIG_TARGET_INITRAMFS" "ddns" "luci-app-advancedplus" "mihomo" "nikki"
    "smartdns" "kucat" "bootstrap" "luci-app-partexp" "luci-app-upnp" "samba"
)
for keyword in "${keywords_to_delete[@]}"; do
    sed -i "/$keyword/d" ./.config
done
echo "[diy] 已从 .config 移除: ${keywords_to_delete[*]}"

# ---------------------------------------------------------------
# 2. 安装额外软件包（Packages.sh 未覆盖的部分）
#    工作目录为 wrt/，clone 目标为 package/$REPO_NAME
# ---------------------------------------------------------------
UPDATE_PACKAGE() {
    local PKG_NAME=$1
    local PKG_REPO=$2
    local PKG_BRANCH=$3
    local PKG_SPECIAL=$4

    read -ra PKG_NAMES <<< "$PKG_NAME"
    for NAME in "${PKG_NAMES[@]}"; do
        find feeds/luci/ feeds/packages/ package/ -maxdepth 3 -type d \
            \( -name "$NAME" -o -name "luci-*-$NAME" \) -exec rm -rf {} + 2>/dev/null
    done

    if [[ $PKG_REPO == http* ]]; then
        local REPO_NAME=$(basename "$PKG_REPO" .git)
    else
        local REPO_NAME=$(echo "$PKG_REPO" | cut -d '/' -f 2)
        PKG_REPO="https://github.com/$PKG_REPO.git"
    fi

    if ! git clone --depth=1 --single-branch --branch "$PKG_BRANCH" "$PKG_REPO" "package/$REPO_NAME"; then
        echo "错误: 克隆失败 $PKG_REPO"
        return 1
    fi

    case "$PKG_SPECIAL" in
        "pkg")
            for NAME in "${PKG_NAMES[@]}"; do
                find "./package/$REPO_NAME" -maxdepth 3 -type d \
                    \( -name "$NAME" -o -name "luci-*-$NAME" \) -print0 | \
                    xargs -0 -I {} cp -rf {} ./package/ 2>/dev/null
            done
            rm -rf "./package/$REPO_NAME/"
            ;;
        "name")
            rm -rf "./package/$PKG_NAME"
            mv -f "./package/$REPO_NAME" "./package/$PKG_NAME"
            ;;
    esac
}

UPDATE_PACKAGE "luci-app-poweroff" "esirplayground/luci-app-poweroff" "main"
UPDATE_PACKAGE "luci-app-tailscale" "asvow/luci-app-tailscale" "main"
UPDATE_PACKAGE "openwrt-gecoosac" "ysuolmai/openwrt-gecoosac" "main"
# gecoosac 上游作者 (kiss19776) 经常覆盖同名 release asset，PKG_HASH 跟不上
# 把 PKG_HASH:=xxxxx 改成 PKG_HASH:=skip 跳过校验
if [ -f ./package/openwrt-gecoosac/gecoosac/Makefile ]; then
    sed -i 's/^PKG_HASH:=.*/PKG_HASH:=skip/' ./package/openwrt-gecoosac/gecoosac/Makefile
    echo "[diy] openwrt-gecoosac PKG_HASH 设为 skip"
fi
UPDATE_PACKAGE "luci-app-openlist2" "sbwml/luci-app-openlist2" "main"

#small-package
UPDATE_PACKAGE "xray-core xray-plugin dns2tcp dns2socks haproxy hysteria \
        naiveproxy v2ray-core v2ray-geodata v2ray-geoview v2ray-plugin \
        tuic-client chinadns-ng ipt2socks tcping trojan-plus simple-obfs shadowsocksr-libev \
        luci-app-passwall smartdns luci-app-smartdns v2dat mosdns luci-app-mosdns \
        taskd luci-lib-xterm luci-lib-taskd luci-app-passwall2 \
        luci-app-store quickstart luci-app-quickstart luci-app-cloudflarespeedtest \
        luci-theme-argon netdata luci-app-netdata \
        frp luci-app-ddns-go ddns-go" "kenzok8/jell" "main" "pkg"

#speedtest
UPDATE_PACKAGE "luci-app-netspeedtest" "https://github.com/sbwml/openwrt_pkgs.git" "main" "pkg"
UPDATE_PACKAGE "speedtest-cli" "https://github.com/sbwml/openwrt_pkgs.git" "main" "pkg"

UPDATE_PACKAGE "luci-app-adguardhome" "https://github.com/ysuolmai/luci-app-adguardhome.git" "apk"
UPDATE_PACKAGE "luci-app-tailscale" "asvow/luci-app-tailscale" "main"

UPDATE_PACKAGE "openwrt-podman" "https://github.com/breeze303/openwrt-podman" "main"
UPDATE_PACKAGE "luci-app-quickfile" "https://github.com/sbwml/luci-app-quickfile" "main"
sed -i 's|$(INSTALL_BIN) $(PKG_BUILD_DIR)/quickfile-$(ARCH_PACKAGES) $(1)/usr/bin/quickfile|$(INSTALL_BIN) $(PKG_BUILD_DIR)/quickfile-aarch64_generic $(1)/usr/bin/quickfile|' package/luci-app-quickfile/quickfile/Makefile

# bandix
UPDATE_PACKAGE "openwrt-bandix" "timsaya/openwrt-bandix" "main"
UPDATE_PACKAGE "luci-app-bandix" "timsaya/luci-app-bandix" "main"

UPDATE_PACKAGE "luci-theme-shadcn" "ysuolmai/luci-theme-shadcn" "main"


# ---------------------------------------------------------------
# 3. .config 追加包配置
# ---------------------------------------------------------------
provided_config_lines=(
    # 翻墙 / DNS（只留 homeproxy，sing-box 后端够用）
    "CONFIG_PACKAGE_luci-app-homeproxy=y"
    "CONFIG_PACKAGE_luci-i18n-homeproxy-zh-cn=y"

    # AdGuardHome（DNS 过滤 + 拦广告）
    "CONFIG_PACKAGE_luci-app-adguardhome=y"
    "CONFIG_PACKAGE_luci-i18n-adguardhome-zh-cn=y"

    # VPN（zerotier 比 tailscale 轻一些，选一个就够）
    "CONFIG_PACKAGE_luci-app-zerotier=y"
    "CONFIG_PACKAGE_luci-i18n-zerotier-zh-cn=y"

    # 内网穿透 / DDNS
    "CONFIG_PACKAGE_luci-app-frpc=y"
    "CONFIG_PACKAGE_luci-app-ddns-go=y"
    "CONFIG_PACKAGE_luci-i18n-ddns-go-zh-cn=y"

    # 系统基础工具
    "CONFIG_PACKAGE_luci-app-poweroff=y"
    "CONFIG_PACKAGE_luci-i18n-poweroff-zh-cn=y"
    "CONFIG_PACKAGE_luci-app-ttyd=y"
    "CONFIG_PACKAGE_luci-i18n-ttyd-zh-cn=y"
    "CONFIG_PACKAGE_ttyd=y"
    "CONFIG_PACKAGE_luci-app-cpufreq=y"
    "CONFIG_PACKAGE_luci-i18n-cpufreq-zh-cn=y"
    "CONFIG_PACKAGE_luci-app-filetransfer=y"
    "CONFIG_PACKAGE_luci-app-vlmcsd=y"
    "CONFIG_PACKAGE_luci-app-netspeedtest=y"

    # 监控（轻量流量统计）
    #"CONFIG_PACKAGE_luci-app-bandix=y"

    # 主题 / 默认配置
    #"CONFIG_PACKAGE_luci-app-gecoosac=y"
    #"CONFIG_PACKAGE_luci-app-argon-config=y"
    "CONFIG_PACKAGE_luci-theme-shadcn=y"

    # opkg
    "CONFIG_OPKG_USE_CURL=y"
    "CONFIG_PACKAGE_opkg=y"
    "CONFIG_USE_APK=n"

    "CONFIG_PACKAGE_luci-app-tailscale=y"
    
    "CONFIG_PACKAGE_luci-app-passwall=y"
    "CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadowsocks_Libev_Client=y"
    "CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Shadowsocks_Libev_Server=y"
    "CONFIG_PACKAGE_luci-app-passwall_INCLUDE_ShadowsocksR_Libev_Client=n"
    "CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Simple_Obfs=n"
    "CONFIG_PACKAGE_luci-app-passwall_INCLUDE_SingBox=n"
    "CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Trojan_Plus=n"
    "CONFIG_PACKAGE_luci-app-passwall_INCLUDE_V2ray_Plugin=n"
)

[[ ${WRT_CONFIG,,} == *"mediatek"* || ${WRT_CONFIG,,} == *"mtk"* || $WRT_CONFIG == *"7981"* ]] && provided_config_lines+=(
    "CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_mediatek_7981r128=y"
)

# 故意不装的"EMMC 才合适"的重型应用（NAND 设备装不下也用不上）：
#   passwall / passwall2 / openclash（一个 homeproxy 已够，省 40+ MB）
#   mosdns（adguardhome 已覆盖 DNS 过滤）
#   openlist2 / quickfile（文件管理器，NAND 没空间）
#   cifs-mount + kmod-fs-cifs + cifsmount（不挂 SMB 共享）
#   netdata + luci-app-netdata（监控太重，bandix 够看）
#   diskman（无硬盘可管）
#   cloudflarespeedtest（要用就 opkg install）
#   tailscale（zerotier 二选一）
for line in "${provided_config_lines[@]}"; do
    echo "$line" >> .config
done
echo "[diy] provided_config_lines 已写入 .config"

# ---------------------------------------------------------------
# 4. 通用 Makefile 修复
# ---------------------------------------------------------------
if ! grep -q "CMAKE_POLICY_VERSION_MINIMUM" include/cmake.mk 2>/dev/null; then
    echo 'CMAKE_OPTIONS += -DCMAKE_POLICY_VERSION_MINIMUM=3.5' >> include/cmake.mk
fi

find ./ -name "getifaddr.c" -exec sed -i 's/return 1;/return 0;/g' {} \;

if [ -f ./package/v2ray-geodata/Makefile ]; then
    sed -i 's/VER)-\$(PKG_RELEASE)/VER)-r\$(PKG_RELEASE)/g' ./package/v2ray-geodata/Makefile
fi
if [ -f ./package/luci-app-openclash/Makefile ]; then
    sed -i '/^PKG_VERSION:=/a PKG_RELEASE:=1' ./package/luci-app-openclash/Makefile
fi

# sbwml/luci-theme-argon 的 25.12 分支依赖 wget-any，但 padavanonly 6.6
# 源码没有这个虚拟包；改成该分支已有的 wget-ssl，避免 package/install 失败。
ARGON_MAKEFILE=$(find ./package/ ./feeds/luci/ -maxdepth 4 -type f -path "*/luci-theme-argon/Makefile" 2>/dev/null | head -n 1)
if [ -f "$ARGON_MAKEFILE" ] && grep -q "wget-any" "$ARGON_MAKEFILE"; then
    sed -i 's/+wget-any/+wget-ssl/g; s/ wget-any/ wget-ssl/g' "$ARGON_MAKEFILE"
    echo "[diy] luci-theme-argon 依赖已从 wget-any 修正为 wget-ssl"
fi

# ---------------------------------------------------------------
# 4e. 批量修复 kenzok8/jell 包的 PKG_VERSION 格式（X.Y.Z-N → X.Y.Z + RELEASE）
# 表现：opkg 版本比较失败，依赖不满足
# 注：只处理「有 X.Y.Z-N 格式但缺 PKG_RELEASE」的，已声明 PKG_RELEASE 的跳过
# ---------------------------------------------------------------
echo "[diy] 批量修复 package/ 中 PKG_VERSION:=X.Y.Z-N 格式..."
_pkgver_fixed=0
while IFS= read -r _mk; do
    if grep -qE '^PKG_VERSION:=[0-9]+\.[0-9]+(\.[0-9]+)?-[0-9]+$' "$_mk" && \
       ! grep -q '^PKG_RELEASE:=' "$_mk"; then
        sed -i -E 's/^(PKG_VERSION:=[0-9]+\.[0-9]+(\.[0-9]+)?)-([0-9]+)$/\1\nPKG_RELEASE:=\3/' "$_mk"
        _pkgver_fixed=$((_pkgver_fixed + 1))
    fi
done < <(find ./package/ -maxdepth 2 -name "Makefile" 2>/dev/null)
echo "[diy] PKG_VERSION 格式修复完成，共处理 $_pkgver_fixed 个文件"

# ---------------------------------------------------------------
# 4b. CSS 颜色修复 & uci-defaults 文件内置
# ---------------------------------------------------------------
find ./ -name "cascade.css" -exec sed -i 's/#5e72e4/#31A1A1/g; s/#483d8b/#31A1A1/g' {} \;
find ./ -name "dark.css" -exec sed -i 's/#5e72e4/#31A1A1/g; s/#483d8b/#31A1A1/g' {} \;
find ./ -name "cascade.less" -exec sed -i 's/#5e72e4/#31A1A1/g; s/#483d8b/#31A1A1/g' {} \;
find ./ -name "dark.less" -exec sed -i 's/#5e72e4/#31A1A1/g; s/#483d8b/#31A1A1/g' {} \;
echo "[diy] CSS 颜色修复完成"

install -Dm755 "${GITHUB_WORKSPACE}/Scripts/99_ttyd-nopass.sh"  "package/base-files/files/etc/uci-defaults/99_ttyd-nopass"
install -Dm755 "${GITHUB_WORKSPACE}/Scripts/99_set_argon_primary" "package/base-files/files/etc/uci-defaults/99_set_argon_primary"
install -Dm755 "${GITHUB_WORKSPACE}/Scripts/99_dropbear_setup.sh" "package/base-files/files/etc/uci-defaults/99_dropbear_setup"
install -Dm755 "${GITHUB_WORKSPACE}/Scripts/991_set-network.sh"  "package/base-files/files/etc/uci-defaults/991_set-network"
echo "[diy] uci-defaults 脚本已内置"

# 99-distfeeds.conf（依赖 default-settings 包，存在才注入）
if [ -d "./package/emortal/default-settings" ]; then
    install -Dm755 "${GITHUB_WORKSPACE}/Scripts/99-distfeeds.conf" "package/emortal/default-settings/files/99-distfeeds.conf"
    sed -i '/define Package\/default-settings\/install/a \
\t$(INSTALL_DIR) $(1)/etc\n\t$(INSTALL_DATA) ./files/99-distfeeds.conf $(1)/etc/99-distfeeds.conf' \
        package/emortal/default-settings/Makefile
    sed -i "/exit 0/i\\
[ -f '/etc/99-distfeeds.conf' ] && mv '/etc/99-distfeeds.conf' '/etc/opkg/distfeeds.conf'\n\
sed -ri '/check_signature/s@^[^#]@#\&@' /etc/opkg.conf\n" \
        "package/emortal/default-settings/files/99-default-settings"
    echo "[diy] 99-distfeeds.conf 已注入 default-settings"
fi

# ddns-go.init 替换
if [ -f "./package/luci-app-ddns-go/ddns-go/file/ddns-go.init" ]; then
    cp "${GITHUB_WORKSPACE}/Scripts/ddns-go.init" "./package/luci-app-ddns-go/ddns-go/file/ddns-go.init"
    chmod +x "./package/luci-app-ddns-go/ddns-go/file/ddns-go.init"
    echo "[diy] ddns-go.init 已替换"
fi

# rust Makefile 修复（ci-llvm=false + patch 补充 Host/Patch define）
RUST_FILE=$(find ./feeds/packages/ -maxdepth 3 -type f -wholename "*/rust/Makefile")
if [ -f "$RUST_FILE" ]; then
    sed -i 's/ci-llvm=true/ci-llvm=false/g' "$RUST_FILE"
    patch "$RUST_FILE" "${GITHUB_WORKSPACE}/Scripts/rust-makefile.patch" 2>/dev/null \
        && echo "[diy] rust-makefile.patch 已应用" \
        || echo "[diy] rust-makefile.patch 跳过（已应用或不适用）"
fi
echo "[diy] 文件内置完成"

# ---------------------------------------------------------------
# 4c. 升级 golang 工具链（解决 frp 编译失败）
#
# 失败现象（compile log）：
#   go: ../../go.mod requires go >= 1.24.0 (running go 1.23.12; GOTOOLCHAIN=local)
#
# padavanonly 6.6 fork 自带的 golang feed 是 1.23.x，但 kenzok8/jell 仓库
# 里的 frp 0.66.0（被 luci-app-frpc 依赖）要求 go >= 1.24.0。
# GOTOOLCHAIN=local 又禁止 Go 在线下载工具链。
#
# 修复：从 openwrt/packages 主仓库 sparse-checkout 拉最新 lang/golang
# 覆盖 feed 里的旧版，重装 golang。OpenWRT-CI 早就用这套方法解决了。
# ---------------------------------------------------------------
echo "================================================================"
echo "[diy] 升级 golang 工具链"
echo "================================================================"
WRT_DIR=$(pwd)
GO_TMP_DIR=/tmp/openwrt-packages
rm -rf feeds/packages/lang/golang
rm -rf "$GO_TMP_DIR"
git clone https://github.com/openwrt/packages --depth=1 --filter=blob:none --sparse "$GO_TMP_DIR"
cd "$GO_TMP_DIR" && git sparse-checkout set lang/golang
cp -r "$GO_TMP_DIR/lang/golang" "$WRT_DIR/feeds/packages/lang/golang"
cd "$WRT_DIR"
GO_DEFAULT_VERSION=$(sed -n 's/^GO_DEFAULT_VERSION:=//p' feeds/packages/lang/golang/golang-values.mk | head -n 1)

# feeds install -a 已在 workflow 前面执行过；替换 feed 文件后必须刷新索引并强制重装。
rm -rf package/feeds/packages/golang*
./scripts/feeds update -i packages
./scripts/feeds install -f golang "golang${GO_DEFAULT_VERSION}"

# CI 会缓存 staging_dir/host*，清掉旧 Go，避免继续复用 go1.25.x 的 host 工具链。
rm -rf staging_dir/hostpkg/lib/go-* \
       staging_dir/hostpkg/stamp/.golang* \
       staging_dir/hostpkg/stamp/.go* \
       build_dir/hostpkg/golang*

echo "[diy] golang feed 已替换为 openwrt/packages 最新版，默认版本：${GO_DEFAULT_VERSION}"

# ---------------------------------------------------------------
# 4d. cmake 4.0 兼容（移植自 OpenWRT-CI）
#
# 部分 ImmortalWrt 分支已用 cmake 4.0+ 作为 host cmake，但许多 C/C++ 包
# CMakeLists.txt 还写 cmake_minimum_required(VERSION 3.5)，cmake 4.0 默认拒绝。
# 加 -DCMAKE_POLICY_VERSION_MINIMUM=3.5 让 cmake 容忍老 policy。
# 注：仅在 include/cmake.mk 存在且尚未含此选项时追加，幂等无害。
# ---------------------------------------------------------------
if [ -f include/cmake.mk ] && ! grep -q "CMAKE_POLICY_VERSION_MINIMUM" include/cmake.mk; then
    echo 'CMAKE_OPTIONS += -DCMAKE_POLICY_VERSION_MINIMUM=3.5' >> include/cmake.mk
    echo "[diy] cmake.mk 已追加 CMAKE_POLICY_VERSION_MINIMUM=3.5"
else
    echo "[diy] cmake.mk 已含 CMAKE_POLICY_VERSION_MINIMUM 或文件不存在，跳过"
fi

# ---------------------------------------------------------------
# 5. sx_7981r128 设备注入
#    FIP / U-Boot / BL2 在独立仓库 https://github.com/ysuolmai/UBOOT-CI
#    本仓库只产 sysupgrade.bin（sysupgrade-tar）
# ---------------------------------------------------------------
echo "================================================================"
echo "[diy] mediatek_7981r128 upstream profile check"
echo "================================================================"

FILOGIC_MK="./target/linux/mediatek/image/filogic.mk"
if [ -f "$FILOGIC_MK" ] && grep -q '^define Device/mediatek_7981r128' "$FILOGIC_MK"; then
    echo "[diy] mediatek_7981r128 profile exists"
else
    echo "[diy] error: mediatek_7981r128 profile not found in filogic.mk"
    exit 1
fi

DTS_FILE="./target/linux/mediatek/dts/mt7981b-mediatek-7981r128.dts"
if [ -f "$DTS_FILE" ]; then
    echo "[diy] mediatek_7981r128 DTS exists"
else
    echo "[diy] error: mediatek_7981r128 DTS not found"
    exit 1
fi

# 5.1 复制 DTS
if false; then
DTS_SRC="$GITHUB_WORKSPACE/Scripts/dts/mt7981b-sx-7981r128.dts"
if [ -f "$DTS_SRC" ]; then
    cp -f "$DTS_SRC" "./target/linux/mediatek/dts/mt7981b-sx-7981r128.dts"
    echo "[diy] DTS 已复制"
else
    echo "[diy] 警告：DTS 源文件不存在，跳过"
fi

# 5.2 注入 filogic.mk 设备条目
FILOGIC_MK="./target/linux/mediatek/image/filogic.mk"
if [ -f "$FILOGIC_MK" ] && ! grep -q '^define Device/sx_7981r128' "$FILOGIC_MK"; then
    cat >> "$FILOGIC_MK" << 'FILOGIC_EOF'

define Device/sx_7981r128
  DEVICE_VENDOR := SX
  DEVICE_MODEL := 7981R128
  DEVICE_DTS := mt7981b-sx-7981r128
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware kmod-usb3 \
                     kmod-sfp kmod-i2c-gpio
  SUPPORTED_DEVICES := sx,7981r128 mediatek,mt7981-spim-snand-7981r128
  KERNEL_IN_UBI := 1
  UBOOTENV_IN_UBI := 1
  BLOCKSIZE := 128k
  PAGESIZE := 2048
  IMAGE_SIZE := 65536k
  UBINIZE_OPTS := -E 5
  IMAGES := sysupgrade.bin
  IMAGE/sysupgrade.bin := sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += sx_7981r128
FILOGIC_EOF
    echo "[diy] filogic.mk 设备条目已注入"
else
    echo "[diy] filogic.mk 设备条目已存在，跳过"
fi

# 5.3 注入 board.d/02_network
BOARD_NETWORK="./target/linux/mediatek/filogic/base-files/etc/board.d/02_network"
if [ -f "$BOARD_NETWORK" ] && ! grep -q 'sx,7981r128' "$BOARD_NETWORK"; then
    awk '
        !done && /^\t\*\)$/ {
            print "\tsx,7981r128)"
            print "\t\tucidef_set_interfaces_lan_wan \"lan1\" \"lan2\""
            print "\t\t;;"
            done = 1
        }
        { print }
    ' "$BOARD_NETWORK" > "$BOARD_NETWORK.new" && mv "$BOARD_NETWORK.new" "$BOARD_NETWORK"
    echo "[diy] 02_network case 已注入"
else
    echo "[diy] 02_network 已存在或文件不存在，跳过"
fi

# 5.4 uci-defaults 首次启动初始化
UCI_DEFAULTS_DIR="./package/base-files/files/etc/uci-defaults"
mkdir -p "$UCI_DEFAULTS_DIR"
cat > "$UCI_DEFAULTS_DIR/98_sx_7981r128_init.sh" << 'UCI_EOF'
#!/bin/sh
[ "$(cat /tmp/sysinfo/board_name 2>/dev/null)" = "sx,7981r128" ] || exit 0

# WiFi 开机启用
uci set wireless.radio0.disabled=0
uci set wireless.radio1.disabled=0
uci commit wireless

# wan6（2.5G 主WAN IPv6）+ wan2/wan2_6（SFP 笼）
uci set network.wan6=interface
uci set network.wan6.device=lan2
uci set network.wan6.proto=dhcpv6
uci set network.wan2=interface
uci set network.wan2.device=eth1
uci set network.wan2.proto=dhcp
uci set network.wan2_6=interface
uci set network.wan2_6.device=eth1
uci set network.wan2_6.proto=dhcpv6
uci commit network

# wan2/wan2_6 加入防火墙 WAN zone
wan_zone_idx=""
i=0
while uci get "firewall.@zone[$i]" >/dev/null 2>&1; do
    if [ "$(uci get firewall.@zone[$i].name 2>/dev/null)" = "wan" ]; then
        wan_zone_idx=$i; break
    fi
    i=$((i + 1))
done
if [ -n "$wan_zone_idx" ]; then
    uci add_list firewall.@zone[$wan_zone_idx].network=wan2
    uci add_list firewall.@zone[$wan_zone_idx].network=wan2_6
    uci commit firewall
fi

# LED: green:lan (GPIO 8) 绑到 2.5G 物理口 lan2
# 实机点灯测试确认 green:lan 物理位置在 2.5G 网口旁
uci add system led
uci set system.@led[-1].name='led_lan2'
uci set system.@led[-1].sysfs='green:lan'
uci set system.@led[-1].trigger='netdev'
uci set system.@led[-1].dev='lan2'
uci set system.@led[-1].mode='link tx rx'
uci commit system

exit 0
UCI_EOF
chmod +x "$UCI_DEFAULTS_DIR/98_sx_7981r128_init.sh"
echo "[diy] uci-defaults 98_sx_7981r128_init.sh 已注入"
fi

echo "================================================================"
echo "[diy] 完成"
echo "================================================================"
