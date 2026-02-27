#!/bin/bash
###############################################################################
# 06_hq-sw.sh — HQ-SW configuration (ALT Linux)
# Module 1: Hostname, IP, timezone
###############################################################################
set -e

# ======================== VARIABLES ==========================================
HOSTNAME="hq-sw.au-team.irpo"
IF_LAN="ens19"
IP_LAN="192.168.0.81/29"
GW_LAN="192.168.0.86"

# =============================================================================
echo "=== [1/3] Setting hostname ==="
hostnamectl set-hostname "$HOSTNAME"

# =============================================================================
echo "=== [2/3] Configuring IP address ==="

IF_DIR="/etc/net/ifaces/$IF_LAN"
mkdir -p "$IF_DIR"

cat > "$IF_DIR/options" <<EOF
BOOTPROTO=static
TYPE=eth
CONFIG_WIRELESS=no
SYSTEMD_BOOTPROTO=static
CONFIG_IPV4=yes
DISABLED=no
NM_CONTROLLED=no
ONBOOT=yes
EOF

echo "$IP_LAN" > "$IF_DIR/ipv4address"
echo "default via $GW_LAN" > "$IF_DIR/ipv4route"

systemctl restart network
sleep 2
echo "  $IF_LAN -> $IP_LAN, gw $GW_LAN"

# =============================================================================
echo "=== [3/3] Timezone ==="
timedatectl set-timezone Europe/Moscow

echo ""
echo "=== Verification ==="
ip -c -br a
echo ""
echo "=== HQ-SW configured ==="
