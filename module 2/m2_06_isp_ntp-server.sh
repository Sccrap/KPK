#!/bin/bash
###############################################################################
# m2_06_isp_ntp-server.sh — NTP-сервер на ISP (ALT Linux, chrony)
# Задание 4: Синхронизация времени (сервер)
###############################################################################
set -e

# ======================== ПЕРЕМЕННЫЕ =========================================
STRATUM=5
ALLOW_NETS=(
    "172.16.1.0/28"
    "172.16.2.0/28"
)

# =============================================================================
echo "=== [1/2] Настройка chrony как NTP-сервер ==="

cat > /etc/chrony.conf <<EOF
# NTP-сервер ISP
# Локальный источник времени (stratum $STRATUM)
local stratum $STRATUM

# Разрешённые сети
$(for net in "${ALLOW_NETS[@]}"; do echo "allow $net"; done)

# Файл дрифта
driftfile /var/lib/chrony/drift

# Логирование
log tracking measurements statistics
logdir /var/log/chrony
EOF

echo "  chrony.conf настроен (stratum $STRATUM)"

# =============================================================================
echo "=== [2/2] Запуск chronyd ==="

systemctl enable --now chronyd
systemctl restart chronyd

echo ""
echo "=== Проверка ==="
chronyc tracking 2>/dev/null | head -5
echo ""
echo "=== NTP-сервер на ISP настроен ==="
echo "Разрешённые сети: ${ALLOW_NETS[*]}"
