#!/bin/bash
###############################################################################
# 05_hq-cli.sh — Настройка HQ-CLI (ALT Linux)
# Модуль 1: Имя хоста, DHCP-клиент, часовой пояс
###############################################################################
set -e

# ======================== ПЕРЕМЕННЫЕ =========================================
HOSTNAME="hq-cli.au-team.irpo"
IF_LAN="ens19"

# =============================================================================
echo "=== [1/3] Установка имени хоста ==="
hostnamectl set-hostname "$HOSTNAME"

# =============================================================================
echo "=== [2/3] Настройка DHCP-клиента на $IF_LAN ==="

IF_DIR="/etc/net/ifaces/$IF_LAN"
mkdir -p "$IF_DIR"

cat > "$IF_DIR/options" <<EOF
BOOTPROTO=dhcp
TYPE=eth
CONFIG_WIRELESS=no
SYSTEMD_BOOTPROTO=dhcp
CONFIG_IPV4=yes
DISABLED=no
NM_CONTROLLED=no
ONBOOT=yes
EOF

# Убираем статические настройки если есть
rm -f "$IF_DIR/ipv4address" "$IF_DIR/ipv4route"

systemctl restart network
sleep 3

echo "  Интерфейс $IF_LAN настроен на DHCP"

# =============================================================================
echo "=== [3/3] Часовой пояс ==="
timedatectl set-timezone Europe/Moscow

echo ""
echo "=== Проверка ==="
ip -c -br a
echo "---"
ip -c -br r
echo ""
echo "=== HQ-CLI настроен ==="
