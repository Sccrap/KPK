#!/bin/bash
###############################################################################
# 03_br-rtr.sh — BR-RTR configuration (ALT Linux)
# Module 1: hostname · forwarding · NAT · GRE tunnel · OSPF · user
#
# Интерфейсы определяются АВТОМАТИЧЕСКИ:
#   WAN  — интерфейс с IP из сети 172.16.2.x (смотрит на ISP)
#   LAN  — первый оставшийся интерфейс (смотрит на BR-SRV)
###############################################################################
set -e

# ======================== FIXED VARIABLES ====================================
HOSTNAME="br-rtr.au-team.irpo"

IP_WAN="172.16.2.1/28"
GW_WAN="172.16.2.14"
TUN_LOCAL="172.16.2.1"
IP_LAN="192.168.1.30/27"

TUN_NAME="tun1"
TUN_REMOTE="172.16.1.1"
TUN_IP="10.5.5.2/30"

OSPF_PASS="P@ssw0rd"
OSPF_NETWORKS=(
    "10.5.5.0/30"
    "192.168.1.0/27"
)

USER_NAME="net_admin"
USER_PASS='P@$$word'

# ======================== AUTO-DETECT INTERFACES =============================
detect_interfaces() {
    echo "  Scanning network interfaces..."

    ALL_IFACES=( $(ls /sys/class/net/ | grep -vE '^(lo|vlan|tun|gre|ovs|docker|br-)' | sort) )
    echo "  Found interfaces: ${ALL_IFACES[*]}"

    if [ ${#ALL_IFACES[@]} -lt 2 ]; then
        echo "ERROR: need at least 2 interfaces, found: ${ALL_IFACES[*]}"
        exit 1
    fi

    # WAN — ищем интерфейс с IP 172.16.2.x
    IF_WAN=""
    for iface in "${ALL_IFACES[@]}"; do
        if ip addr show "$iface" 2>/dev/null | grep -qE "172\.16\.2\."; then
            IF_WAN="$iface"
            break
        fi
    done

    if [ -z "$IF_WAN" ]; then
        echo "  WARNING: no 172.16.2.x IP found, using first interface as WAN"
        IF_WAN="${ALL_IFACES[0]}"
    fi

    # LAN — первый интерфейс не WAN
    IF_LAN=""
    for iface in "${ALL_IFACES[@]}"; do
        if [ "$iface" != "$IF_WAN" ]; then
            IF_LAN="$iface"
            break
        fi
    done

    if [ -z "$IF_LAN" ]; then
        echo "ERROR: no LAN interface found"
        exit 1
    fi

    echo "  WAN (to ISP)   : $IF_WAN"
    echo "  LAN (to BR-SRV): $IF_LAN"
}

configure_iface_static() {
    local iface="$1"
    local ip="$2"
    local dir="/etc/net/ifaces/$iface"
    mkdir -p "$dir"
    cat > "$dir/options" <<OPTS
BOOTPROTO=static
TYPE=eth
CONFIG_WIRELESS=no
SYSTEMD_BOOTPROTO=static
CONFIG_IPV4=yes
DISABLED=no
NM_CONTROLLED=no
ONBOOT=yes
OPTS
    echo "$ip" > "$dir/ipv4address"
    echo "  $iface -> $ip"
}

# =============================================================================
echo "=== [0/6] Installing required software ==="
apt-get update -y
apt-get install -y nftables frr
echo "  Done"

# =============================================================================
echo "=== [1/6] Setting hostname ==="
hostnamectl set-hostname "$HOSTNAME"

# =============================================================================
echo "=== [1.5/6] Auto-detecting and configuring interfaces ==="
detect_interfaces

configure_iface_static "$IF_WAN" "$IP_WAN"
echo "default via $GW_WAN" > "/etc/net/ifaces/$IF_WAN/ipv4route"

configure_iface_static "$IF_LAN" "$IP_LAN"

systemctl restart network
sleep 2
echo "  Network restarted"

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
[ ! -f "$NFTABLES_CONF" ] && printf '#!/usr/sbin/nft -f\nflush ruleset\n' > "$NFTABLES_CONF"

if ! grep -q "table inet nat" "$NFTABLES_CONF"; then
    cat >> "$NFTABLES_CONF" <<NFTEOF

table inet nat {
    chain postrouting {
        type nat hook postrouting priority srcnat;
        oifname "$IF_WAN" masquerade
    }
}
NFTEOF
fi
systemctl enable --now nftables

# =============================================================================
echo "=== [4/6] Configuring GRE tunnel ==="
TUN_DIR="/etc/net/ifaces/$TUN_NAME"
mkdir -p "$TUN_DIR"
cat > "$TUN_DIR/options" <<TUNEOF
TYPE=iptun
TUNTYPE=gre
TUNLOCAL=$TUN_LOCAL
TUNREMOTE=$TUN_REMOTE
TUNOPTIONS='ttl 64'
HOST=$IF_WAN
TUNEOF
echo "$TUN_IP" > "$TUN_DIR/ipv4address"

systemctl restart network
sleep 2
echo "  GRE: $TUN_LOCAL -> $TUN_REMOTE ($TUN_IP)"

# =============================================================================
echo "=== [5/6] Configuring OSPF (FRR) ==="
FRR_DAEMONS="/etc/frr/daemons"
[ -f "$FRR_DAEMONS" ] && sed -i 's/^ospfd=no/ospfd=yes/' "$FRR_DAEMONS"
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
fi
timedatectl set-timezone Europe/Moscow

echo ""
echo "=== Verification ==="
echo "  WAN=$IF_WAN  LAN=$IF_LAN"
ip -c -br a
echo "---"
ip -c -br r
echo "=== BR-RTR configured ==="
