#!/bin/bash
###############################################################################
# 02_hq-rtr.sh — HQ-RTR configuration (ALT Linux)
# Module 1: hostname · forwarding · NAT · VLAN (OVS) · GRE · OSPF · DHCP · user
#
# Интерфейсы определяются АВТОМАТИЧЕСКИ:
#   WAN  — интерфейс с IP из сети 172.16.1.x (смотрит на ISP)
#   LAN  — все остальные физические интерфейсы по порядку (для OVS/VLAN)
###############################################################################
set -e

# ======================== FIXED VARIABLES ====================================
HOSTNAME="hq-rtr.au-team.irpo"

IP_WAN="172.16.1.1/28"
GW_WAN="172.16.1.14"
TUN_LOCAL="172.16.1.1"

IP_VLAN100="192.168.0.62/26"
IP_VLAN200="192.168.0.78/28"
IP_VLAN999="192.168.0.86/29"

TUN_NAME="tun1"
TUN_REMOTE="172.16.2.1"
TUN_IP="10.5.5.1/30"

OSPF_PASS="P@ssw0rd"
OSPF_NETWORKS=(
    "10.5.5.0/30"
    "192.168.0.0/26"
    "192.168.0.64/28"
    "192.168.0.80/29"
)

DHCP_IFACE="vlan200"
DHCP_SUBNET="192.168.0.64"
DHCP_NETMASK="255.255.255.240"
DHCP_RANGE_START="192.168.0.65"
DHCP_RANGE_END="192.168.0.75"
DHCP_ROUTER="192.168.0.78"
DHCP_DNS="192.168.0.1"
DHCP_DOMAIN="au-team.irpo"

USER_NAME="net_admin"
USER_PASS='P@$$word'

# ======================== AUTO-DETECT INTERFACES =============================
detect_interfaces() {
    echo "  Scanning network interfaces..."

    # Все физические интерфейсы (не lo, не виртуальные), отсортированные по имени
    ALL_IFACES=( $(ls /sys/class/net/ | grep -vE '^(lo|vlan|tun|gre|ovs|hq-sw|docker|br-)' | sort) )

    echo "  Found interfaces: ${ALL_IFACES[*]}"

    if [ ${#ALL_IFACES[@]} -lt 2 ]; then
        echo "ERROR: need at least 2 interfaces, found: ${ALL_IFACES[*]}"
        exit 1
    fi

    # WAN — ищем интерфейс у которого уже есть IP 172.16.1.x (базовая сеть)
    IF_WAN=""
    for iface in "${ALL_IFACES[@]}"; do
        if ip addr show "$iface" 2>/dev/null | grep -qE "172\.16\.1\."; then
            IF_WAN="$iface"
            break
        fi
    done

    # Если не нашли по IP — берём первый (WAN всегда первый по схеме)
    if [ -z "$IF_WAN" ]; then
        echo "  WARNING: no 172.16.1.x IP found, using first interface as WAN"
        IF_WAN="${ALL_IFACES[0]}"
    fi

    # LAN — все кроме WAN, по порядку
    LAN_IFACES=()
    for iface in "${ALL_IFACES[@]}"; do
        [ "$iface" != "$IF_WAN" ] && LAN_IFACES+=("$iface")
    done

    if [ ${#LAN_IFACES[@]} -lt 3 ]; then
        echo "ERROR: need 3 LAN interfaces for VLANs, found ${#LAN_IFACES[@]}: ${LAN_IFACES[*]}"
        exit 1
    fi

    IF_SRV="${LAN_IFACES[0]}"   # VLAN100 -> HQ-SRV
    IF_CLI="${LAN_IFACES[1]}"   # VLAN200 -> HQ-CLI
    IF_SW="${LAN_IFACES[2]}"    # VLAN999 -> management

    echo "  WAN (to ISP)   : $IF_WAN"
    echo "  SRV (VLAN100)  : $IF_SRV"
    echo "  CLI (VLAN200)  : $IF_CLI"
    echo "  SW  (VLAN999)  : $IF_SW"
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

configure_iface_trunk() {
    local iface="$1"
    local dir="/etc/net/ifaces/$iface"
    mkdir -p "$dir"
    cat > "$dir/options" <<OPTS
BOOTPROTO=static
TYPE=eth
CONFIG_WIRELESS=no
CONFIG_IPV4=no
DISABLED=no
NM_CONTROLLED=no
ONBOOT=yes
OPTS
    echo "  $iface -> trunk (no IP)"
}

# =============================================================================
echo "=== [0/8] Installing required software ==="
apt-get update -y
apt-get install -y nftables openvswitch frr dhcp-server
echo "  Done"

# =============================================================================
echo "=== [1/8] Setting hostname ==="
hostnamectl set-hostname "$HOSTNAME"

# =============================================================================
echo "=== [1.5/8] Auto-detecting and configuring interfaces ==="
detect_interfaces

configure_iface_static "$IF_WAN" "$IP_WAN"
echo "default via $GW_WAN" > "/etc/net/ifaces/$IF_WAN/ipv4route"

configure_iface_trunk "$IF_SRV"
configure_iface_trunk "$IF_CLI"
configure_iface_trunk "$IF_SW"

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
echo "=== [4/8] Configuring VLANs via Open vSwitch ==="
systemctl enable --now openvswitch
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

echo "  VLAN100: $IP_VLAN100  VLAN200: $IP_VLAN200  VLAN999: $IP_VLAN999"

# vlan.sh — восстановление IP после перезагрузки (OVS не сохраняет IP)
cat > /root/vlan.sh << 'VSCRIPT'
#!/bin/bash
ip a add 192.168.0.62/26 dev vlan100 2>/dev/null || true
ip a add 192.168.0.78/28 dev vlan200 2>/dev/null || true
ip a add 192.168.0.86/29 dev vlan999 2>/dev/null || true
systemctl restart dhcpd
VSCRIPT
chmod +x /root/vlan.sh
grep -q "vlan.sh" /root/.bashrc 2>/dev/null || echo "bash /root/vlan.sh 2>/dev/null" >> /root/.bashrc

# =============================================================================
echo "=== [5/8] Configuring GRE tunnel ==="
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
echo "=== [6/8] Configuring OSPF (FRR) ==="
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
echo "=== [7/8] Configuring DHCP ==="
DHCPD_SYSCONFIG="/etc/sysconfig/dhcpd"
if [ -f "$DHCPD_SYSCONFIG" ]; then
    sed -i "s/^DHCPDARGS=.*/DHCPDARGS=$DHCP_IFACE/" "$DHCPD_SYSCONFIG"
else
    echo "DHCPDARGS=$DHCP_IFACE" > "$DHCPD_SYSCONFIG"
fi

cat > /etc/dhcp/dhcpd.conf <<DHCPEOF
authoritative;
subnet $DHCP_SUBNET netmask $DHCP_NETMASK {
    range $DHCP_RANGE_START $DHCP_RANGE_END;
    option domain-name-servers $DHCP_DNS;
    option domain-name "$DHCP_DOMAIN";
    option routers $DHCP_ROUTER;
    default-lease-time 6000;
    max-lease-time 7200;
}
DHCPEOF
systemctl enable --now dhcpd

# =============================================================================
echo "=== [8/8] Creating user ==="
if ! id "$USER_NAME" &>/dev/null; then
    adduser "$USER_NAME"
    echo "$USER_NAME:$USER_PASS" | chpasswd
    usermod -aG wheel "$USER_NAME"
    echo "$USER_NAME ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers
fi
timedatectl set-timezone Europe/Moscow

echo ""
echo "=== Verification ==="
echo "  WAN=$IF_WAN  SRV=$IF_SRV  CLI=$IF_CLI  SW=$IF_SW"
ip -c -br a
echo "---"
ovs-vsctl show
echo "=== HQ-RTR configured ==="
