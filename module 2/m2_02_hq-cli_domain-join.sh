#!/bin/bash
###############################################################################
# m2_02_hq-cli_domain-join.sh — Ввод HQ-CLI в домен Samba AD (ALT Linux)
# Задание 1 (продолжение): Ввод клиента в домен
###############################################################################
set -e

# ======================== ПЕРЕМЕННЫЕ =========================================
DOMAIN="au-team.irpo"
REALM="AU-TEAM.IRPO"
WORKGROUP="AU-TEAM"
DC_IP="192.168.1.1"
ADMIN_PASS="P@ssw0rd"
HOSTNAME_SHORT="hq-cli"

# =============================================================================
echo "=== [1/4] Настройка resolv.conf ==="

cat > /etc/resolv.conf <<EOF
search $DOMAIN
nameserver $DC_IP
EOF

echo "  DNS указывает на DC: $DC_IP"

# =============================================================================
echo "=== [2/4] Проверка доступности контроллера домена ==="

if ! ping -c 2 -W 3 "$DC_IP" &>/dev/null; then
    echo "  ОШИБКА: DC $DC_IP недоступен! Проверьте маршрутизацию."
    echo "  Скрипт продолжит выполнение, но join может не пройти."
fi

# Проверяем DNS
if host -t SRV _ldap._tcp.$DOMAIN $DC_IP &>/dev/null; then
    echo "  DNS DC доступен, SRV записи найдены"
else
    echo "  ПРЕДУПРЕЖДЕНИЕ: SRV записи не найдены. DC может быть ещё не готов."
fi

# =============================================================================
echo "=== [3/4] Настройка Kerberos ==="

cat > /etc/krb5.conf <<EOF
[libdefaults]
    default_realm = $REALM
    dns_lookup_realm = false
    dns_lookup_kdc = true

[realms]
    $REALM = {
        default_domain = $DOMAIN
    }

[domain_realm]
    .$DOMAIN = $REALM
    $DOMAIN = $REALM
EOF

echo "  krb5.conf настроен"

# =============================================================================
echo "=== [4/4] Ввод в домен ==="

# Используем system-auth для присоединения через CLI
# Вариант 1: через net ads join (если установлен samba-client)
if command -v net &>/dev/null; then
    echo "$ADMIN_PASS" | net ads join -U Administrator --no-dns-updates 2>&1 || true
    echo "  Попытка join через net ads"
fi

# Вариант 2: через system-auth (ACC - ALT Control Center) CLI
if command -v system-auth &>/dev/null; then
    system-auth write ad \
        "$DOMAIN" \
        "$HOSTNAME_SHORT" \
        "$WORKGROUP" \
        "Administrator" \
        "$ADMIN_PASS" 2>&1 || true
    echo "  Попытка join через system-auth"
fi

# Вариант 3: через realm join (если sssd-ad установлен)
if command -v realm &>/dev/null; then
    echo "$ADMIN_PASS" | realm join --user=Administrator "$DOMAIN" 2>&1 || true
    echo "  Попытка join через realm"
fi

echo ""
echo "=== Ввод в домен завершён ==="
echo ""
echo "Проверьте вручную:"
echo "  kinit Administrator  (пароль: $ADMIN_PASS)"
echo "  klist"
echo ""
echo "Если join через CLI не сработал, используйте GUI:"
echo "  Центр управления системой → Аутентификация → Домен Active Directory"
echo "  Домен: $DOMAIN"
echo "  Рабочая группа: $WORKGROUP"
echo "  Имя компьютера: $HOSTNAME_SHORT"
