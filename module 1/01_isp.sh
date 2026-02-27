#!/bin/bash
###############################################################################
# 01_isp.sh — Настройка ISP (ALT Linux)
# Модуль 1: Базовая настройка сетевой инфраструктуры
###############################################################################
set -e

# ======================== ПЕРЕМЕННЫЕ (изменить при необходимости) =============
HOSTNAME="isp"

# Интерфейс в сторону интернета (DHCP) — уже настроен
IF_INET="ens19"

# Интерфейс в сторону HQ-RTR
IF_HQ="ens20"
IP_HQ="172.16.1.14/28"

# Интерфейс в сторону BR-RTR
IF_BR="ens21"
IP_BR="172.16.2.14/28"

# =============================================================================
echo "=== [1/5] Установка имени хоста ==="
hostnamectl set-hostname "$HOSTNAME"
echo "Имя хоста: $HOSTNAME"

# =============================================================================
echo "=== [2/5] Настройка IP-адресов интерфейсов ==="

configure_interface() {
    local iface="$1"
    local ip="$2"
    local dir="/etc/net/ifaces/$iface"

    mkdir -p "$dir"

    # Создаём/перезаписываем файл options если его нет
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
        # Убеждаемся что BOOTPROTO=static
        sed -i 's/^BOOTPROTO=.*/BOOTPROTO=static/' "$dir/options"
    fi

    echo "$ip" > "$dir/ipv4address"
    echo "  $iface -> $ip"
}

configure_interface "$IF_HQ" "$IP_HQ"
configure_interface "$IF_BR" "$IP_BR"

# ISP не нуждается в шлюзе по умолчанию на этих интерфейсах
# (шлюз по умолчанию идёт через DHCP на IF_INET)

# =============================================================================
echo "=== [3/5] Включение IP forwarding ==="

SYSCTL_FILE="/etc/net/sysctl.conf"
if grep -q "^net.ipv4.ip_forward" "$SYSCTL_FILE"; then
    sed -i 's/^net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/' "$SYSCTL_FILE"
else
    echo "net.ipv4.ip_forward = 1" >> "$SYSCTL_FILE"
fi
sysctl -w net.ipv4.ip_forward=1

# =============================================================================
echo "=== [4/5] Настройка NAT (nftables) ==="

NFTABLES_CONF="/etc/nftables/nftables.nft"

# Проверяем, есть ли уже таблица nat
if ! grep -q "table inet nat" "$NFTABLES_CONF" 2>/dev/null; then
    cat >> "$NFTABLES_CONF" <<EOF

table inet nat {
    chain postrouting {
        type nat hook postrouting priority srcnat;
        oifname "$IF_INET" masquerade
    }
}
EOF
    echo "  NAT добавлен (masquerade через $IF_INET)"
else
    echo "  NAT уже настроен"
fi

systemctl enable --now nftables
echo "  nftables включён"

# =============================================================================
echo "=== [5/5] Перезапуск сети ==="
systemctl restart network
sleep 2

echo ""
echo "=== Проверка ==="
ip -c -br a
echo "---"
ip -c -br r
echo ""
echo "=== ISP настроен ==="
