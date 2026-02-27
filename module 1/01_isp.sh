#!/bin/bash
###############################################################################
# 01_isp.sh — ISP configuration (ALT Linux)
# Module 1: Basic network infrastructure setup
###############################################################################
set -e

# ======================== VARIABLES (change if needed) =======================
HOSTNAME="isp"

# Internet-facing interface (DHCP) — already configured
IF_INET="ens19"

# Interface towards HQ-RTR
IF_HQ="ens20"
IP_HQ="172.16.1.14/28"

# Interface towards BR-RTR
IF_BR="ens21"
IP_BR="172.16.2.14/28"

# =============================================================================
echo "=== [0/5] Installing required software ==="
apt-get update -y
apt-get install -y nftables
echo "  Software installed"

# =============================================================================
echo "=== [1/5] Setting hostname ==="
hostnamectl set-hostname "$HOSTNAME"
echo "  Hostname: $HOSTNAME"

# =============================================================================
echo "=== [2/5] Configuring interface IP addresses ==="

configure_interface() {
    local iface="$1"
    local ip="$2"
    local dir="/etc/net/ifaces/$iface"

    mkdir -p "$dir"

    if [ ! -f "$dir/options" ]; then
        cat > "$dir/options" <<EOF
BOOTPROTO=static
TYPE=eth
CONFIG_WIRELESS=no
SYSTEMD_BOOTPROTO=static
CONFIG_IPV4=yes
DISABLED=no
NM_CONTROLLED=no
ONBOOT=yes
EOF
    else
        sed -i 's/^BOOTPROTO=.*/BOOTPROTO=static/' "$dir/options"
    fi

    echo "$ip" > "$dir/ipv4address"
    echo "  $iface -> $ip"
}

configure_interface "$IF_HQ" "$IP_HQ"
configure_interface "$IF_BR" "$IP_BR"

# ISP does not need a default gateway on these interfaces
# (default gateway comes via DHCP on IF_INET)

# =============================================================================
echo "=== [3/5] Enabling IP forwarding ==="

SYSCTL_FILE="/etc/net/sysctl.conf"
if grep -q "^net.ipv4.ip_forward" "$SYSCTL_FILE"; then
    sed -i 's/^net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/' "$SYSCTL_FILE"
else
    echo "net.ipv4.ip_forward = 1" >> "$SYSCTL_FILE"
fi
sysctl -w net.ipv4.ip_forward=1

# =============================================================================
echo "=== [4/5] Configuring NAT (nftables) ==="

NFTABLES_CONF="/etc/nftables/nftables.nft"

# Create directory and base config file if missing
mkdir -p /etc/nftables
if [ ! -f "$NFTABLES_CONF" ]; then
    cat > "$NFTABLES_CONF" <<EOF
#!/usr/sbin/nft -f
flush ruleset
EOF
    echo "  Created $NFTABLES_CONF"
fi

if ! grep -q "table inet nat" "$NFTABLES_CONF" 2>/dev/null; then
    cat >> "$NFTABLES_CONF" <<EOF

table inet nat {
    chain postrouting {
        type nat hook postrouting priority srcnat;
        oifname "$IF_INET" masquerade
    }
}
EOF
    echo "  NAT added (masquerade via $IF_INET)"
else
    echo "  NAT already configured"
fi

systemctl enable --now nftables
echo "  nftables enabled"

# =============================================================================
echo "=== [5/5] Restarting network ==="
systemctl restart network
sleep 2

echo ""
echo "=== Verification ==="
ip -c -br a
echo "---"
ip -c -br r
echo ""
echo "=== ISP configured ==="
