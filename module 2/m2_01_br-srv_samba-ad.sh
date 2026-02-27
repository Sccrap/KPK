#!/bin/bash
###############################################################################
# m2_01_br-srv_samba-ad.sh — Samba AD Domain Controller (BR-SRV, ALT Linux)
# Задание 1: Настройте доменный контроллер Samba
###############################################################################
set -e

# ======================== ПЕРЕМЕННЫЕ =========================================
DOMAIN="au-team.irpo"
REALM="AU-TEAM.IRPO"
WORKGROUP="AU-TEAM"
ADMIN_PASS="P@ssw0rd"
DNS_FORWARDER="77.88.8.7"
SERVER_IP="192.168.1.1"

# =============================================================================
echo "=== [1/5] Подготовка — удаление старой конфигурации ==="

# Останавливаем службы если запущены
systemctl stop samba 2>/dev/null || true
systemctl stop smb 2>/dev/null || true
systemctl stop winbind 2>/dev/null || true

# Удаляем старый smb.conf
rm -f /etc/samba/smb.conf

# Удаляем старые базы данных Samba (для чистой настройки)
rm -rf /var/lib/samba/private/*.tdb
rm -rf /var/lib/samba/private/*.ldb
rm -rf /var/lib/samba/*.tdb
rm -rf /var/lib/samba/*.ldb
rm -rf /var/cache/samba/*

echo "  Старая конфигурация удалена"

# =============================================================================
echo "=== [2/5] Автоматическая настройка Samba AD ==="

# samba-tool domain provision в неинтерактивном режиме
samba-tool domain provision \
    --use-rfc2307 \
    --realm="$REALM" \
    --domain="$WORKGROUP" \
    --server-role=dc \
    --dns-backend=SAMBA_INTERNAL \
    --adminpass="$ADMIN_PASS" \
    --option="dns forwarder = $DNS_FORWARDER"

echo "  Домен $REALM настроен"

# =============================================================================
echo "=== [3/5] Настройка Kerberos ==="

cp /var/lib/samba/private/krb5.conf /etc/krb5.conf
echo "  krb5.conf скопирован"

# =============================================================================
echo "=== [4/5] Настройка resolv.conf ==="

cat > /etc/resolv.conf <<EOF
search $DOMAIN
nameserver 127.0.0.1
nameserver $SERVER_IP
EOF

echo "  resolv.conf настроен"

# =============================================================================
echo "=== [5/5] Запуск Samba ==="

systemctl enable --now samba
sleep 3

# Проверка
echo ""
echo "=== Проверка домена ==="
samba-tool domain info 127.0.0.1 2>/dev/null || echo "  (домен ещё инициализируется)"

echo ""
echo "=== Проверка DNS ==="
host -t SRV _ldap._tcp.$DOMAIN 127.0.0.1 2>/dev/null || echo "  DNS SRV запись пока недоступна"
host -t SRV _kerberos._tcp.$DOMAIN 127.0.0.1 2>/dev/null || echo "  Kerberos SRV запись пока недоступна"

echo ""
echo "=== Samba AD настроен ==="
echo "!!! РЕКОМЕНДУЕТСЯ ПЕРЕЗАГРУЗИТЬ СЕРВЕР: reboot !!!"
echo ""
echo "После перезагрузки проверьте:"
echo "  samba-tool domain info 127.0.0.1"
echo "  samba-tool user list"
