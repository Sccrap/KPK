#!/bin/bash
###############################################################################
# 02_hq-rtr.sh — HQ-RTR configuration (ALT Linux)
# Module 1: hostname · forwarding · NAT · VLAN (OVS) · GRE · OSPF · DHCP · user
#
# PRE-REQUISITE (manual, before running this script):
#   ens19 = 172.16.1.1/28, gateway 172.16.1.14  (WAN towards ISP)
#   ens20, ens21, ens22 — no IP needed (used as OVS trunk ports)
#   See: module 1/README.md → "Step 0 — Manual IP Configuration"
###############################################################################
set -e

# ======================== VARIABLES ==========================================
HOSTNAME="hq-rtr.au-team.irpo"

# WAN interface (used for NAT and GRE source) — IP already set manually
IF_WAN="ens19"
IP_WAN="172.16.1.1/28"
GW_WAN="172.16.1.14"
TUN_LOCAL="172.16.1.1"

# OVS trunk ports
IF_SRV="ens20"    # VLAN 100 -> HQ-SRV
IF_CLI="ens21"    # VLAN 200 -> HQ-CLI
IF_SW="ens22"     # VLAN 999 -> HQ-SW (management)

# VLAN gateway IPs
IP_VLAN100="192.168.0.62/26"
IP_VLAN200="192.168.0.78/28"
IP_VLAN999="192.168.0.86/29"

# GRE tunnel
TUN_NAME="tun1"
TUN_REMOTE="172.16.2.1"
TUN_IP="10.5.5.1/30"

# OSPF
OSPF_PASS="P@ssw0rd"
OSPF_NETWORKS=(
    "10.5.5.0/30"
    "192.168.0.0/26"
    "192.168.0.64/28"
    "192.168.0.80/29"
)

# DHCP server (for HQ-CLI on VLAN200)
DHCP_IFACE="vlan200"
DHCP_SUBNET="192.168.0.64"
DHCP_NETMASK="255.255.255.240"
DHCP_RANGE_START="192.168.0.65"
DHCP_RANGE_END="192.168.0.75"
DHCP_ROUTER="192.168.0.78"
DHCP_DNS="192.168.0.1"
DHCP_DOMAIN="au-team.irpo"

# Local user
USER_NAME="net_admin"
USER_PASS='P@$$word'

# =============================================================================
echo "=== [0/8] Installing required software ==="
apt-get update -y
apt-get install -y nftables openvswitch NetworkManager frr dhcp-server
echo "  Software installed"

# =============================================================================
echo "=== [1/8] Setting hostname ==="
hostnamectl set-hostname "$HOSTNAME"

# =============================================================================
echo "=== [1.5/8] Configuring interface IP addresses ==="

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

# Configure WAN (ens19) — IP + default gateway
configure_interface "$IF_WAN" "$IP_WAN"
echo "default via $GW_WAN" > "/etc/net/ifaces/$IF_WAN/ipv4route"
echo "  $IF_WAN route -> default via $GW_WAN"

# Configure OVS trunk ports (no IP — used as tagged ports)
for iface in "$IF_SRV" "$IF_CLI" "$IF_SW"; do
    mkdir -p "/etc/net/ifaces/$iface"
    if [ ! -f "/etc/net/ifaces/$iface/options" ]; then
        cat > "/etc/net/ifaces/$iface/options" <<EOF
BOOTPROTO=static
TYPE=eth
CONFIG_WIRELESS=no
CONFIG_IPV4=no
DISABLED=no
NM_CONTROLLED=no
ONBOOT=yes
EOF
    fi
    echo "  $iface -> trunk port (no IP)"
done

systemctl restart network
sleep 2
echo "  Network restarted"

# =============================================================================
echo "=== [2/8] Enabling IP forwarding ==="

SYSCTL_FILE="/etc/net/sysctl.conf"
if grep -q "^net.ipv4.ip_forward" "$SYSCTL_FILE"; then
    sed -i 's/^net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/' "$SYSCTL_FILE"
else
    echo "net.ipv4.ip_forward = 1" >> "$SYSCTL_FILE"
fi
sysctl -w net.ipv4.ip_forward=1

# =============================================================================
echo "=== [3/8] Configuring NAT (nftables) ==="

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
echo "=== [4/8] Configuring VLANs via Open vSwitch ==="

systemctl enable --now openvswitch
systemctl enable --now NetworkManager
sleep 2

ovs-vsctl --if-exists del-br hq-sw
ovs-vsctl add-br hq-sw
ovs-vsctl add-port hq-sw "$IF_SRV" tag=100
ovs-vsctl add-port hq-sw "$IF_CLI" tag=200
ovs-vsctl add-port hq-sw "$IF_SW"  tag=999

ovs-vsctl add-port hq-sw vlan100 tag=100 -- set interface vlan100 type=internal
ovs-vsctl add-port hq-sw vlan200 tag=200 -- set interface vlan200 type=internal
ovs-vsctl add-port hq-sw vlan999 tag=999 -- set interface vlan999 type=internal

systemctl restart openvswitch
systemctl restart NetworkManager
sleep 2

ip link set hq-sw up

ip addr flush dev vlan100 2>/dev/null || true
ip addr flush dev vlan200 2>/dev/null || true
ip addr flush dev vlan999 2>/dev/null || true

ip addr add $IP_VLAN100 dev vlan100
ip addr add $IP_VLAN200 dev vlan200
ip addr add $IP_VLAN999 dev vlan999

ip link set vlan100 up
ip link set vlan200 up
ip link set vlan999 up

echo "  VLAN100: $IP_VLAN100"
echo "  VLAN200: $IP_VLAN200"
echo "  VLAN999: $IP_VLAN999"

# Restore VLAN IPs on login (OVS does not persist them across reboots)
cat > /root/ip.sh <<SCRIPT
#!/bin/bash
ip link set hq-sw up 2>/dev/null
sleep 1
ip addr flush dev vlan100 2>/dev/null
ip addr flush dev vlan200 2>/dev/null
ip addr flush dev vlan999 2>/dev/null
ip addr add $IP_VLAN100 dev vlan100
ip addr add $IP_VLAN200 dev vlan200
ip addr add $IP_VLAN999 dev vlan999
ip link set vlan100 up
ip link set vlan200 up
ip link set vlan999 up
SCRIPT
chmod +x /root/ip.sh

if ! grep -q "ip.sh" /root/.bashrc 2>/dev/null; then
    echo "bash /root/ip.sh 2>/dev/null" >> /root/.bashrc
fi

# =============================================================================
echo "=== [5/8] Configuring GRE tunnel ==="

systemctl enable --now NetworkManager
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
echo "=== [6/8] Configuring OSPF (FRR) ==="

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
echo "=== [7/8] Configuring DHCP server (HQ-CLI via VLAN200) ==="

DHCPD_SYSCONFIG="/etc/sysconfig/dhcpd"
if [ -f "$DHCPD_SYSCONFIG" ]; then
    sed -i "s/^DHCPDARGS=.*/DHCPDARGS=$DHCP_IFACE/" "$DHCPD_SYSCONFIG"
else
    echo "DHCPDARGS=$DHCP_IFACE" > "$DHCPD_SYSCONFIG"
fi

cat > /etc/dhcp/dhcpd.conf <<EOF
# DHCP for HQ-CLI (VLAN200)
authoritative;

subnet $DHCP_SUBNET netmask $DHCP_NETMASK {
    range $DHCP_RANGE_START $DHCP_RANGE_END;
    option domain-name-servers $DHCP_DNS;
    option domain-name "$DHCP_DOMAIN";
    option routers $DHCP_ROUTER;
    default-lease-time 6000;
    max-lease-time 7200;
}
EOF

systemctl enable --now dhcpd
echo "  DHCP: pool $DHCP_RANGE_START - $DHCP_RANGE_END"

# =============================================================================
echo "=== [8/8] Creating user ==="

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
ovs-vsctl show
echo ""
echo "=== HQ-RTR configured ==="
echo "!!! After configuring BR-RTR, both routers may need a reboot !!!"
