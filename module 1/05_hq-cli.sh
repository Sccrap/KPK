#!/bin/bash
###############################################################################
# 05_hq-cli.sh — HQ-CLI configuration (ALT Linux)
# Module 1: Hostname, DHCP client, timezone
###############################################################################
set -e

# ======================== VARIABLES ==========================================
HOSTNAME="hq-cli.au-team.irpo"
IF_LAN="ens19"

# =============================================================================
echo "=== [1/3] Setting hostname ==="
hostnamectl set-hostname "$HOSTNAME"

# =============================================================================
echo "=== [2/3] Configuring DHCP client on $IF_LAN ==="

IF_DIR="/etc/net/ifaces/$IF_LAN"
mkdir -p "$IF_DIR"

cat > "$IF_DIR/options" <<EOF
BOOTPROTO=dhcp
TYPE=eth
CONFIG_WIRELESS=no
SYSTEMD_BOOTPROTO=dhcp
CONFIG_IPV4=yes
DISABLED=no
NM_CONTROLLED=no
ONBOOT=yes
EOF

# Remove static settings if present
rm -f "$IF_DIR/ipv4address" "$IF_DIR/ipv4route"

systemctl restart network
sleep 3

echo "  Interface $IF_LAN configured for DHCP"

# =============================================================================
echo "=== [3/3] Timezone ==="
timedatectl set-timezone Europe/Moscow

echo ""
echo "=== Verification ==="
ip -c -br a
echo "---"
ip -c -br r
echo ""
echo "=== HQ-CLI configured ==="
