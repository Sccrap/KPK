#!/bin/bash
###############################################################################
# 05_hq-cli.sh — HQ-CLI configuration (ALT Linux)
# Module 1: hostname · timezone · DHCP на интерфейсе
#
# Интерфейс определяется АВТОМАТИЧЕСКИ — первый физический интерфейс
###############################################################################
set -e

HOSTNAME="hq-cli.au-team.irpo"

# ======================== AUTO-DETECT INTERFACE ==============================
detect_interface() {
    echo "  Scanning network interfaces..."
    ALL_IFACES=( $(ls /sys/class/net/ | grep -vE '^(lo|vlan|tun|gre|ovs|docker|br-)' | sort) )
    echo "  Found interfaces: ${ALL_IFACES[*]}"

    if [ ${#ALL_IFACES[@]} -lt 1 ]; then
        echo "ERROR: no network interfaces found"
        exit 1
    fi

    # Берём первый физический интерфейс
    IF_LAN="${ALL_IFACES[0]}"
    echo "  LAN (DHCP): $IF_LAN"
}

# =============================================================================
echo "=== [1/3] Setting hostname ==="
hostnamectl set-hostname "$HOSTNAME"

# =============================================================================
echo "=== [2/3] Auto-detecting and configuring interface (DHCP) ==="
detect_interface

DIR="/etc/net/ifaces/$IF_LAN"
mkdir -p "$DIR"
cat > "$DIR/options" <<OPTS
BOOTPROTO=dhcp
TYPE=eth
CONFIG_WIRELESS=no
SYSTEMD_BOOTPROTO=dhcp
CONFIG_IPV4=yes
DISABLED=no
NM_CONTROLLED=no
ONBOOT=yes
OPTS
echo "  $IF_LAN -> DHCP"

systemctl restart network
sleep 3
echo "  Network restarted"

# =============================================================================
echo "=== [3/3] Timezone ==="
timedatectl set-timezone Europe/Moscow

echo ""
echo "=== Verification ==="
echo "  LAN=$IF_LAN"
ip -c -br a
echo "---"
ip -c -br r
echo "=== HQ-CLI configured ==="
