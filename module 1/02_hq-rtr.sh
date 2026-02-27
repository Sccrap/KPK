#!/bin/bash
###############################################################################
# 02_hq-rtr.sh — Настройка HQ-RTR (ALT Linux)
# Модуль 1: IP, forwarding, NAT, VLAN (OVS), GRE-туннель, OSPF, DHCP
###############################################################################
set -e

# ======================== ПЕРЕМЕННЫЕ =========================================
HOSTNAME="hq-rtr.au-team.irpo"
DOMAIN="au-team.irpo"

# Интерфейс в сторону ISP
IF_WAN="ens19"
IP_WAN="172.16.1.1/28"
GW_WAN="172.16.1.14"

# Интерфейсы для VLAN (через OVS)
IF_SRV="ens20"    # VLAN 100 -> HQ-SRV
IF_CLI="ens21"    # VLAN 200 -> HQ-CLI
IF_SW="ens22"     # VLAN 999 -> HQ-SW (management)

# IP-адреса VLAN
IP_VLAN100="192.168.0.62/26"   # Шлюз для HQ-SRV
IP_VLAN200="192.168.0.78/28"   # Шлюз для HQ-CLI
IP_VLAN999="192.168.0.86/29"   # Шлюз для HQ-SW

# GRE-туннель
TUN_NAME="tun1"
TUN_LOCAL="172.16.1.1"
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

# DHCP (для VLAN200 — HQ-CLI)
DHCP_IFACE="vlan200"
DHCP_SUBNET="192.168.0.64"
DHCP_NETMASK="255.255.255.240"
DHCP_RANGE_START="192.168.0.65"
DHCP_RANGE_END="192.168.0.75"
DHCP_ROUTER="192.168.0.78"
DHCP_DNS="192.168.0.1"
DHCP_DOMAIN="au-team.irpo"

# Пользователь
USER_NAME="net_admin"
USER_PASS='P@$$word'

# =============================================================================
echo "=== [1/10] Установка имени хоста ==="
hostnamectl set-hostname "$HOSTNAME"

# =============================================================================
echo "=== [2/10] Настройка WAN-интерфейса ($IF_WAN) ==="

WAN_DIR="/etc/net/ifaces/$IF_WAN"
mkdir -p "$WAN_DIR"

cat > "$WAN_DIR/options" <<EOF
BOOTPROTO=static
TYPE=eth
CONFIG_WIRELESS=no
SYSTEMD_BOOTPROTO=static
CONFIG_IPV4=yes
DISABLED=no
NM_CONTROLLED=no
ONBOOT=yes
EOF

echo "$IP_WAN" > "$WAN_DIR/ipv4address"
echo "default via $GW_WAN" > "$WAN_DIR/ipv4route"
echo "  $IF_WAN -> $IP_WAN, gw $GW_WAN"

# =============================================================================
echo "=== [3/10] Включение IP forwarding ==="

SYSCTL_FILE="/etc/net/sysctl.conf"
if grep -q "^net.ipv4.ip_forward" "$SYSCTL_FILE"; then
    sed -i 's/^net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/' "$SYSCTL_FILE"
else
    echo "net.ipv4.ip_forward = 1" >> "$SYSCTL_FILE"
fi
sysctl -w net.ipv4.ip_forward=1

# =============================================================================
echo "=== [4/10] Настройка NAT (nftables) ==="

NFTABLES_CONF="/etc/nftables/nftables.nft"

if ! grep -q "table inet nat" "$NFTABLES_CONF" 2>/dev/null; then
    cat >> "$NFTABLES_CONF" <<EOF

table inet nat {
    chain postrouting {
        type nat hook postrouting priority srcnat;
        oifname "$IF_WAN" masquerade
    }
}
EOF
fi
systemctl enable --now nftables

# =============================================================================
echo "=== [5/10] Перезапуск сети ==="
systemctl restart network
sleep 2

# =============================================================================
echo "=== [6/10] Настройка VLAN через Open vSwitch ==="

systemctl enable --now openvswitch
systemctl enable --now NetworkManager
sleep 2

# Удаляем мост если существует (для идемпотентности)
ovs-vsctl --if-exists del-br hq-sw

# Создаём мост и порты
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

# Назначаем IP на VLAN-интерфейсы
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

# Создаём скрипт восстановления VLAN IP после перезагрузки
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

# Добавляем в .bashrc для автозапуска
if ! grep -q "ip.sh" /root/.bashrc 2>/dev/null; then
    echo "bash /root/ip.sh 2>/dev/null" >> /root/.bashrc
fi

# =============================================================================
echo "=== [7/10] Настройка GRE-туннеля ==="

# Создаём GRE через nmcli
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
echo "=== [8/10] Настройка OSPF (FRR) ==="

# Активируем ospfd
FRR_DAEMONS="/etc/frr/daemons"
if [ -f "$FRR_DAEMONS" ]; then
    sed -i 's/^ospfd=no/ospfd=yes/' "$FRR_DAEMONS"
fi

systemctl enable --now frr
sleep 2

# Конфигурируем OSPF через vtysh
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

echo "  OSPF настроен"

# =============================================================================
echo "=== [9/10] Настройка DHCP-сервера (для HQ-CLI через VLAN200) ==="

# Указываем интерфейс DHCP
DHCPD_SYSCONFIG="/etc/sysconfig/dhcpd"
if [ -f "$DHCPD_SYSCONFIG" ]; then
    sed -i "s/^DHCPDARGS=.*/DHCPDARGS=$DHCP_IFACE/" "$DHCPD_SYSCONFIG"
else
    echo "DHCPDARGS=$DHCP_IFACE" > "$DHCPD_SYSCONFIG"
fi

# Создаём конфигурацию DHCP
cat > /etc/dhcp/dhcpd.conf <<EOF
# DHCP конфигурация для HQ-CLI (VLAN200)
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
echo "  DHCP: пул $DHCP_RANGE_START - $DHCP_RANGE_END"

# =============================================================================
echo "=== [10/10] Создание пользователя ==="

if ! id "$USER_NAME" &>/dev/null; then
    adduser "$USER_NAME"
    echo "$USER_NAME:$USER_PASS" | chpasswd
    usermod -aG wheel "$USER_NAME"
    echo "$USER_NAME ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers
    echo "  Пользователь $USER_NAME создан"
else
    echo "  Пользователь $USER_NAME уже существует"
fi

# Часовой пояс
timedatectl set-timezone Europe/Moscow

echo ""
echo "=== Проверка ==="
ip -c -br a
echo "---"
ovs-vsctl show
echo ""
echo "=== HQ-RTR настроен ==="
echo "!!! После настройки BR-RTR может потребоваться перезагрузка обоих роутеров !!!"
