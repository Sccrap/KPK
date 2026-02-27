#!/bin/bash
###############################################################################
# 03_br-rtr.sh — BR-RTR configuration (ALT Linux)
# Module 1: hostname · forwarding · NAT · GRE tunnel · OSPF · user
#
# PRE-REQUISITE (manual, before running this script):
#   ens19 = 172.16.2.1/28, gateway 172.16.2.14  (WAN towards ISP)
#   ens20 = 192.168.1.30/27                      (LAN towards BR-SRV)
#   See: module 1/README.md → "Step 0 — Manual IP Configuration"
###############################################################################
set -e

# ======================== VARIABLES ==========================================
HOSTNAME="br-rtr.au-team.irpo"

# WAN interface (used for NAT and GRE source)
IF_WAN="ens19"
TUN_LOCAL="172.16.2.1"

# GRE tunnel
TUN_NAME="tun1"
TUN_REMOTE="172.16.1.1"
TUN_IP="10.5.5.2/30"

# OSPF
OSPF_PASS="P@ssw0rd"
OSPF_NETWORKS=(
    "10.5.5.0/30"
    "192.168.1.0/27"
)

# Local user
USER_NAME="net_admin"
USER_PASS='P@$$word'

# =============================================================================
echo "=== [0/6] Installing required software ==="
apt-get update -y
apt-get install -y nftables NetworkManager frr
echo "  Software installed"

# =============================================================================
echo "=== [1/6] Setting hostname ==="
hostnamectl set-hostname "$HOSTNAME"

# =============================================================================
echo "=== [2/6] Enabling IP forwarding ==="

SYSCTL_FILE="/etc/net/sysctl.conf"
if grep -q "^net.ipv4.ip_forward" "$SYSCTL_FILE"; then
    sed -i 's/^net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/' "$SYSCTL_FILE"
else
    echo "net.ipv4.ip_forward = 1" >> "$SYSCTL_FILE"
fi
sysctl -w net.ipv4.ip_forward=1

# =============================================================================
echo "=== [3/6] Configuring NAT (nftables) ==="

NFTABLES_CONF="/etc/nftables/nftables.nft"
mkdir -p /etc/nftables
if [ ! -f "$NFTABLES_CONF" ]; then
    cat > "$NFTABLES_CONF" <<EOF
#!/usr/sbin/nft -f
flush ruleset
EOF
fi

if ! grep -q "table inet nat" "$NFTABLES_CONF" 2>/dev/null; then
    cat >> "$NFTABLES_CONF" <<EOF

table inet nat {
    chain postrouting {
        type nat hook postrouting priority srcnat;
        oifname "$IF_WAN" masquerade
    }
}
EOF
    echo "  NAT added (masquerade via $IF_WAN)"
else
    echo "  NAT already configured"
fi
systemctl enable --now nftables

# =============================================================================
echo "=== [4/6] Configuring GRE tunnel ==="

systemctl enable --now NetworkManager
sleep 2

nmcli connection delete "$TUN_NAME" 2>/dev/null || true

nmcli connection add type ip-tunnel \
    ifname "$TUN_NAME" \
    con-name "$TUN_NAME" \
    mode gre \
    remote "$TUN_REMOTE" \
    local "$TUN_LOCAL" \
    ip-tunnel.parent "$IF_WAN" \
    ipv4.method manual \
    ipv4.addresses "$TUN_IP" \
    connection.autoconnect yes

nmcli connection modify "$TUN_NAME" ip-tunnel.ttl 64
nmcli connection up "$TUN_NAME"
echo "  GRE: $TUN_LOCAL -> $TUN_REMOTE, IP: $TUN_IP"

# =============================================================================
echo "=== [5/6] Configuring OSPF (FRR) ==="

FRR_DAEMONS="/etc/frr/daemons"
if [ -f "$FRR_DAEMONS" ]; then
    sed -i 's/^ospfd=no/ospfd=yes/' "$FRR_DAEMONS"
fi

systemctl enable --now frr
sleep 2

vtysh <<VTYSH_EOF
configure terminal
router ospf
  passive-interface default
$(for net in "${OSPF_NETWORKS[@]}"; do echo "  network $net area 0"; done)
  area 0 authentication
exit
interface $TUN_NAME
  no ip ospf passive
  ip ospf authentication
  ip ospf authentication-key $OSPF_PASS
exit
exit
write memory
VTYSH_EOF

echo "  OSPF configured"

# =============================================================================
echo "=== [6/6] Creating user ==="

if ! id "$USER_NAME" &>/dev/null; then
    adduser "$USER_NAME"
    echo "$USER_NAME:$USER_PASS" | chpasswd
    usermod -aG wheel "$USER_NAME"
    echo "$USER_NAME ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers
    echo "  User $USER_NAME created"
else
    echo "  User $USER_NAME already exists"
fi

timedatectl set-timezone Europe/Moscow

echo ""
echo "=== Verification ==="
ip -c -br a
echo "---"
ip -c -br r
echo ""
echo "=== BR-RTR configured ==="
echo "!!! After configuring HQ-RTR, both routers may need a reboot !!!"
