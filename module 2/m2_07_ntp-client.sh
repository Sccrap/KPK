#!/bin/bash
###############################################################################
# m2_07_ntp-client.sh — NTP-клиент (ALT Linux, chrony)
# Задание 4 (продолжение): Синхронизация времени (клиент)
# Запускать на: HQ-RTR, BR-RTR, HQ-SRV, BR-SRV, HQ-CLI, HQ-SW
###############################################################################
set -e

# ======================== ПЕРЕМЕННЫЕ =========================================
# IP NTP-сервера (ISP)
NTP_SERVER="172.16.1.14"

# =============================================================================
echo "=== [1/2] Настройка chrony как NTP-клиент ==="

cat > /etc/chrony.conf <<EOF
# NTP-клиент — синхронизация с ISP
server $NTP_SERVER iburst prefer

# Файл дрифта
driftfile /var/lib/chrony/drift

# Логирование
log tracking measurements statistics
logdir /var/log/chrony
EOF

echo "  chrony.conf настроен (сервер: $NTP_SERVER)"

# =============================================================================
echo "=== [2/2] Запуск chronyd ==="

systemctl enable --now chronyd
systemctl restart chronyd

sleep 2

echo ""
echo "=== Проверка ==="
chronyc sources 2>/dev/null
echo ""
echo "=== NTP-клиент настроен ==="
