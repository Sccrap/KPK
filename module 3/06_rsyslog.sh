#!/bin/bash
# ============================================================
# ЗАДАНИЕ 6: Централизованное логирование Rsyslog
# Использование: ./06_rsyslog.sh [hq-srv|hq-rtr|br-rtr|br-srv]
# ============================================================

ROLE="${1:-hq-srv}"

# IP адреса (можно изменить)
HQ_SRV_IP="192.168.0.1"
HQ_RTR_IP="192.168.0.62"
BR_RTR_IP="10.5.5.2"
BR_SRV_IP="192.168.1.1"

case "$ROLE" in

# =============================================
# HQ-SRV — сервер логирования
# =============================================
hq-srv)
    echo "=== ЗАДАНИЕ 6: Rsyslog SERVER (HQ-SRV) ==="

    echo "[1/5] Создание директорий для логов..."
    mkdir -p /opt/hq-rtr /opt/br-rtr /opt/br-srv
    touch /opt/hq-rtr/hq-rtr.log /opt/br-rtr/br-rtr.log /opt/br-srv/br-srv.log
    echo "[OK] Директории /opt/{hq-rtr,br-rtr,br-srv} созданы"

    echo "[2/5] Настройка /etc/rsyslog.d/00_common.conf..."
    cp /etc/rsyslog.d/00_common.conf /etc/rsyslog.d/00_common.conf.bak 2>/dev/null || true

    # Раскомментируем нужные модули
    sed -i 's|^#module(load="imjournal")|module(load="imjournal")|g' /etc/rsyslog.d/00_common.conf
    sed -i 's|^#module(load="imuxsock")|module(load="imuxsock")|g' /etc/rsyslog.d/00_common.conf

    echo "[3/5] Создание /etc/rsyslog.d/rsys.conf..."
    cat > /etc/rsyslog.d/rsys.conf << EOF
# === Rsyslog server конфиг ===

module(load="imjournal")
module(load="imuxsock")
module(load="imklog")
module(load="immark")

# TCP приём логов
module(load="imtcp")
input(type="imtcp" port="514")

# Локальные auth-логи
authpriv.* /var/log/auth.log

# Логи с HQ-RTR
if \$fromhost-ip contains '${HQ_RTR_IP}' then {
    *.warn /opt/hq-rtr/hq-rtr.log
    stop
}

# Логи с BR-RTR
if \$fromhost-ip contains '${BR_RTR_IP}' then {
    *.warn /opt/br-rtr/br-rtr.log
    stop
}

# Логи с BR-SRV
if \$fromhost-ip contains '${BR_SRV_IP}' then {
    *.warn /opt/br-srv/br-srv.log
    stop
}
EOF
    echo "[OK] rsys.conf создан"

    echo "[4/5] Настройка logrotate..."
    # Проверяем, нет ли уже такой секции
    grep -q "/opt/hq-rtr" /etc/logrotate.conf || cat >> /etc/logrotate.conf << 'LOGROTATE'

/opt/hq-rtr/*.log
/opt/br-rtr/*.log
/opt/br-srv/*.log
{
    minsize 10M
    compress
    rotate 7
    daily
    missingok
    notifempty
}
LOGROTATE
    echo "[OK] logrotate настроен"

    echo "[5/5] Запуск rsyslog..."
    systemctl enable --now rsyslog
    systemctl restart rsyslog
    echo "[OK] Rsyslog запущен"

    echo ""
    echo "=== ПРОВЕРКА ==="
    echo "Структура /opt/:"
    tree /opt/ 2>/dev/null || ls -R /opt/
    echo ""
    systemctl status rsyslog --no-pager | head -5
    echo ""
    echo "Проверка logrotate: logrotate -d /etc/logrotate.conf"
    ;;

# =============================================
# HQ-RTR / BR-RTR / BR-SRV — клиент логирования
# =============================================
hq-rtr|br-rtr|br-srv)
    echo "=== ЗАДАНИЕ 6: Rsyslog CLIENT (${ROLE}) ==="

    echo "[1/2] Настройка /etc/rsyslog.d/rsys.conf..."
    mkdir -p /etc/rsyslog.d/
    cat > /etc/rsyslog.d/rsys.conf << EOF
# === Rsyslog client конфиг для ${ROLE} ===

module(load="imjournal")
module(load="imuxsock")

# Отправляем WARNING+ на HQ-SRV по TCP
*.warn @@${HQ_SRV_IP}:514
EOF
    echo "[OK] rsys.conf создан (форвардинг на ${HQ_SRV_IP}:514)"

    echo "[2/2] Запуск rsyslog..."
    systemctl enable --now rsyslog
    systemctl restart rsyslog
    echo "[OK] Rsyslog запущен"

    echo ""
    echo "=== ПРОВЕРКА ==="
    systemctl status rsyslog --no-pager | head -5
    echo ""
    echo "Тест отправки лога: logger -p warn 'TEST from ${ROLE}'"
    ;;

*)
    echo "Использование: $0 [hq-srv|hq-rtr|br-rtr|br-srv]"
    exit 1
    ;;
esac
