#!/bin/bash
# SPDX-License-Identifier: MIT
#
# diy.sh — 自定义设备注入 + 设备白名单
# 由 WRT-CORE.yml 的 Custom Settings step 调用（Config 写入 .config 之后，make defconfig 之前）
# 工作目录为 wrt/

echo "================================================================"
echo "[diy] 自定义设备注入开始"
echo "================================================================"

# ---------------------------------------------------------------
# 0. MTK 设备白名单 — 只保留指定设备，其余从 .config 删除
# ---------------------------------------------------------------
mtk_keep="\(sx_7981r128\|nokia_ea0326gmp\|cmcc_rax3000m\)=y$"
sed -i "/^CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_/{
    /$mtk_keep/!d
}" ./.config
echo "[diy] .config 设备白名单已应用（保留：sx_7981r128 nokia_ea0326gmp cmcc_rax3000m）"

# ---------------------------------------------------------------
# 1. 复制 DTS（kernel 6.6 padavanonly 版本）
# ---------------------------------------------------------------
DTS_SRC="$GITHUB_WORKSPACE/Scripts/dts/mt7981b-sx-7981r128.dts"
DTS_DST="./target/linux/mediatek/dts/mt7981b-sx-7981r128.dts"
if [ -f "$DTS_SRC" ]; then
    cp -f "$DTS_SRC" "$DTS_DST"
    echo "[diy] DTS 已复制"
else
    echo "[diy] 警告：DTS 源文件不存在，跳过"
fi

# ---------------------------------------------------------------
# 2. 注入 filogic.mk 设备条目
# ---------------------------------------------------------------
FILOGIC_MK="./target/linux/mediatek/image/filogic.mk"
if [ -f "$FILOGIC_MK" ] && ! grep -q '^define Device/sx_7981r128' "$FILOGIC_MK"; then
    cat >> "$FILOGIC_MK" << 'FILOGIC_EOF'

define Device/sx_7981r128
  DEVICE_VENDOR := SX
  DEVICE_MODEL := 7981R128
  DEVICE_DTS := mt7981b-sx-7981r128
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-mt7915e kmod-mt7981-firmware mt7981-wo-firmware kmod-usb3
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

# ---------------------------------------------------------------
# 3. 注入 board.d/02_network
#    lan1（千兆）→ LAN，lan2（2.5G EN8801SC）→ WAN
#    eth1（SFP 笼）通过 uci-defaults 配置为 wan2
# ---------------------------------------------------------------
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

# ---------------------------------------------------------------
# 4. uci-defaults 首次启动初始化脚本
#    - 启用 WiFi（radio0/radio1）
#    - 补全 wan6（2.5G 主WAN IPv6）
#    - 添加 wan2/wan2_6（SFP 笼 IPv4/IPv6）并加入防火墙 WAN zone
# ---------------------------------------------------------------
UCI_DEFAULTS_DIR="./package/base-files/files/etc/uci-defaults"
mkdir -p "$UCI_DEFAULTS_DIR"
cat > "$UCI_DEFAULTS_DIR/98_sx_7981r128_init.sh" << 'UCI_EOF'
#!/bin/sh
[ "$(cat /tmp/sysinfo/board_name 2>/dev/null)" = "sx,7981r128" ] || exit 0

# --- WiFi：启用双频射频 ---
uci set wireless.radio0.disabled=0
uci set wireless.radio1.disabled=0
uci commit wireless

# --- 网络接口 ---
# wan6：2.5G 主WAN IPv6（ucidef 只创建 wan，需手动补 wan6）
uci set network.wan6=interface
uci set network.wan6.device=lan2
uci set network.wan6.proto=dhcpv6
# wan2/wan2_6：SFP 笼 IPv4/IPv6
uci set network.wan2=interface
uci set network.wan2.device=eth1
uci set network.wan2.proto=dhcp
uci set network.wan2_6=interface
uci set network.wan2_6.device=eth1
uci set network.wan2_6.proto=dhcpv6
uci commit network

# --- 防火墙：wan2/wan2_6 加入 WAN zone ---
wan_zone_idx=""
i=0
while uci get "firewall.@zone[$i]" >/dev/null 2>&1; do
    if [ "$(uci get firewall.@zone[$i].name 2>/dev/null)" = "wan" ]; then
        wan_zone_idx=$i
        break
    fi
    i=$((i + 1))
done
if [ -n "$wan_zone_idx" ]; then
    uci add_list firewall.@zone[$wan_zone_idx].network=wan2
    uci add_list firewall.@zone[$wan_zone_idx].network=wan2_6
    uci commit firewall
fi

exit 0
UCI_EOF
chmod +x "$UCI_DEFAULTS_DIR/98_sx_7981r128_init.sh"
echo "[diy] uci-defaults 98_sx_7981r128_init.sh 已注入"

echo "================================================================"
echo "[diy] sx_7981r128 设备注入完成"
echo "================================================================"
