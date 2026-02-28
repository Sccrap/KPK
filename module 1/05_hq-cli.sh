#!/bin/bash
###############################################################################
# 05_hq-cli.sh — HQ-CLI configuration (ALT Linux)
# Module 1: hostname · timezone
#
# PRE-REQUISITE (manual, before running this script):
#   ens19 — DHCP client (gets IP from HQ-RTR DHCP, pool 192.168.0.65-75)
#   HQ-RTR must already be configured and running (script 02_hq-rtr.sh)
#   See: module 1/README.md → "Step 0 — Manual IP Configuration"
###############################################################################
set -e

HOSTNAME="hq-cli.au-team.irpo"
IF_LAN="ens19"

echo "=== [1/2] Setting hostname ==="
hostnamectl set-hostname "$HOSTNAME"
echo "  Hostname: $HOSTNAME"

echo "=== [1.5/2] Configuring interface (DHCP) ==="

DIR="/etc/net/ifaces/$IF_LAN"
mkdir -p "$DIR"
if [ ! -f "$DIR/options" ]; then
    cat > "$DIR/options" <<EOF
BOOTPROTO=dhcp
TYPE=eth
CONFIG_WIRELESS=no
SYSTEMD_BOOTPROTO=dhcp
CONFIG_IPV4=yes
DISABLED=no
NM_CONTROLLED=no
ONBOOT=yes
EOF
else
    sed -i 's/^BOOTPROTO=.*/BOOTPROTO=dhcp/' "$DIR/options"
fi
echo "  $IF_LAN -> DHCP"

systemctl restart network
sleep 3
echo "  Network restarted"

echo "=== [3/3] Timezone ==="
timedatectl set-timezone Europe/Moscow

echo ""
echo "=== Verification ==="
ip -c -br a
echo "---"
ip -c -br r
echo ""
echo "=== HQ-CLI configured ==="
