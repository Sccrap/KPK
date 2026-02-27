#!/bin/bash
###############################################################################
# 03_br-rtr.sh — Настройка BR-RTR (ALT Linux)
# Модуль 1: IP, forwarding, NAT, GRE-туннель, OSPF
###############################################################################
set -e

# ======================== ПЕРЕМЕННЫЕ =========================================
HOSTNAME="br-rtr.au-team.irpo"

# Интерфейс в сторону ISP
IF_WAN="ens19"
IP_WAN="172.16.2.1/28"
GW_WAN="172.16.2.14"

# Интерфейс в сторону BR-SRV
IF_LAN="ens20"
IP_LAN="192.168.1.30/27"

# GRE-туннель
TUN_NAME="tun1"
TUN_LOCAL="172.16.2.1"
TUN_REMOTE="172.16.1.1"
TUN_IP="10.5.5.2/30"

# OSPF
OSPF_PASS="P@ssw0rd"
OSPF_NETWORKS=(
    "10.5.5.0/30"
    "192.168.1.0/27"
)

# Пользователь
USER_NAME="net_admin"
USER_PASS='P@$$word'

# =============================================================================
echo "=== [1/8] Установка имени хоста ==="
hostnamectl set-hostname "$HOSTNAME"

# =============================================================================
echo "=== [2/8] Настройка интерфейсов ==="

configure_interface() {
    local iface="$1"
    local ip="$2"
    local gw="$3"
    local dir="/etc/net/ifaces/$iface"

    mkdir -p "$dir"

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

    echo "$ip" > "$dir/ipv4address"
    echo "  $iface -> $ip"

    if [ -n "$gw" ]; then
        echo "default via $gw" > "$dir/ipv4route"
        echo "  Шлюз: $gw"
    fi
}

configure_interface "$IF_WAN" "$IP_WAN" "$GW_WAN"
configure_interface "$IF_LAN" "$IP_LAN" ""

# =============================================================================
echo "=== [3/8] Включение IP forwarding ==="

SYSCTL_FILE="/etc/net/sysctl.conf"
if grep -q "^net.ipv4.ip_forward" "$SYSCTL_FILE"; then
    sed -i 's/^net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/' "$SYSCTL_FILE"
else
    echo "net.ipv4.ip_forward = 1" >> "$SYSCTL_FILE"
fi
sysctl -w net.ipv4.ip_forward=1

# =============================================================================
echo "=== [4/8] Настройка NAT (nftables) ==="

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
echo "=== [5/8] Перезапуск сети ==="
systemctl restart network
sleep 2

# =============================================================================
echo "=== [6/8] Настройка GRE-туннеля ==="

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
echo "=== [7/8] Настройка OSPF (FRR) ==="

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

echo "  OSPF настроен"

# =============================================================================
echo "=== [8/8] Создание пользователя ==="

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
ip -c -br r
echo ""
echo "=== BR-RTR настроен ==="
echo "!!! После настройки HQ-RTR может потребоваться перезагрузка обоих роутеров !!!"
