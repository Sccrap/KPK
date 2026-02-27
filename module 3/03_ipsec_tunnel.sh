#!/bin/bash
# ============================================================
# ЗАДАНИЕ 3: IP-туннель GRE + IPSec (StrongSwan)
# Выполняется на: HQ-RTR и BR-RTR
# Использование: ./03_ipsec_tunnel.sh [hq-rtr|br-rtr]
# ============================================================

ROLE="${1:-hq-rtr}"

case "$ROLE" in

hq-rtr)
    echo "=== ЗАДАНИЕ 3: IPSec GRE туннель (HQ-RTR) ==="

    LOCAL_IP="10.5.5.1"
    REMOTE_IP="10.5.5.2"

    echo "[1/3] Настройка /etc/strongswan/ipsec.conf..."
    # Сохраняем бэкап
    cp /etc/strongswan/ipsec.conf /etc/strongswan/ipsec.conf.bak 2>/dev/null || true

    cat >> /etc/strongswan/ipsec.conf << EOF

conn gre
    type=tunnel
    authby=secret
    left=${LOCAL_IP}
    right=${REMOTE_IP}
    leftprotoport=gre
    rightprotoport=gre
    auto=start
    pfs=no
EOF
    echo "[OK] ipsec.conf настроен (HQ-RTR)"

    echo "[2/3] Настройка /etc/strongswan/ipsec.secrets..."
    grep -q "${LOCAL_IP} ${REMOTE_IP}" /etc/strongswan/ipsec.secrets 2>/dev/null \
        || echo "${LOCAL_IP} ${REMOTE_IP} : PSK \"P@ssw0rd\"" >> /etc/strongswan/ipsec.secrets
    echo "[OK] PSK добавлен"

    echo "[3/3] Запуск strongswan..."
    systemctl enable --now strongswan-starter.service
    systemctl restart strongswan-starter.service
    echo "[OK] StrongSwan запущен"

    echo ""
    echo "=== ПРОВЕРКА ==="
    sleep 2
    ipsec status || true
    echo ""
    echo "Для захвата ESP-трафика: tcpdump -i ens18 -n -p esp"
    ;;

br-rtr)
    echo "=== ЗАДАНИЕ 3: IPSec GRE туннель (BR-RTR) ==="

    LOCAL_IP="10.5.5.2"
    REMOTE_IP="10.5.5.1"

    echo "[1/3] Настройка /etc/strongswan/ipsec.conf..."
    cp /etc/strongswan/ipsec.conf /etc/strongswan/ipsec.conf.bak 2>/dev/null || true

    cat >> /etc/strongswan/ipsec.conf << EOF

conn gre
    type=tunnel
    authby=secret
    left=${LOCAL_IP}
    right=${REMOTE_IP}
    leftprotoport=gre
    rightprotoport=gre
    auto=start
    pfs=no
EOF
    echo "[OK] ipsec.conf настроен (BR-RTR)"

    echo "[2/3] Настройка /etc/strongswan/ipsec.secrets..."
    grep -q "${LOCAL_IP} ${REMOTE_IP}" /etc/strongswan/ipsec.secrets 2>/dev/null \
        || echo "${LOCAL_IP} ${REMOTE_IP} : PSK \"P@ssw0rd\"" >> /etc/strongswan/ipsec.secrets
    echo "[OK] PSK добавлен"

    echo "[3/3] Запуск strongswan..."
    systemctl enable --now strongswan-starter.service
    systemctl restart strongswan-starter.service
    echo "[OK] StrongSwan запущен"

    echo ""
    echo "=== ПРОВЕРКА ==="
    sleep 2
    ipsec status || true
    echo ""
    echo "Для захвата ESP-трафика: tcpdump -i ens18 -n -p esp"
    ;;

*)
    echo "Использование: $0 [hq-rtr|br-rtr]"
    exit 1
    ;;
esac
