#!/bin/bash
###############################################################################
# 04_hq-srv.sh — Настройка HQ-SRV (ALT Linux)
# Модуль 1: IP, пользователи, SSH, DNS (BIND), часовой пояс
###############################################################################
set -e

# ======================== ПЕРЕМЕННЫЕ =========================================
HOSTNAME="hq-srv.au-team.irpo"
DOMAIN="au-team.irpo"

# Сетевой интерфейс
IF_LAN="ens19"
IP_LAN="192.168.0.1/26"
GW_LAN="192.168.0.62"

# DNS
DNS_SERVER_IP="192.168.0.1"
DNS_FORWARDER="77.88.8.7"

# Пользователь SSH
SSH_USER="sshuser"
SSH_USER_UID="2026"
SSH_USER_PASS="P@ssw0rd"
SSH_PORT="2024"

# DNS записи
declare -A DNS_A_RECORDS=(
    ["hq-rtr"]="192.168.0.62"
    ["hq-srv"]="192.168.0.1"
    ["hq-cli"]="192.168.0.65"
    ["hq-sw"]="192.168.0.81"
    ["br-rtr"]="192.168.1.30"
    ["br-srv"]="192.168.1.1"
)

# =============================================================================
echo "=== [1/7] Установка имени хоста ==="
hostnamectl set-hostname "$HOSTNAME"

# =============================================================================
echo "=== [2/7] Настройка IP-адреса ==="

IF_DIR="/etc/net/ifaces/$IF_LAN"
mkdir -p "$IF_DIR"

cat > "$IF_DIR/options" <<EOF
BOOTPROTO=static
TYPE=eth
CONFIG_WIRELESS=no
SYSTEMD_BOOTPROTO=static
CONFIG_IPV4=yes
DISABLED=no
NM_CONTROLLED=no
ONBOOT=yes
EOF

echo "$IP_LAN" > "$IF_DIR/ipv4address"
echo "default via $GW_LAN" > "$IF_DIR/ipv4route"

# DNS-резолвер — указываем на себя
cat > /etc/resolv.conf <<EOF
search $DOMAIN
nameserver $DNS_SERVER_IP
nameserver $DNS_FORWARDER
EOF

systemctl restart network
sleep 2
echo "  $IF_LAN -> $IP_LAN, gw $GW_LAN"

# =============================================================================
echo "=== [3/7] Создание пользователя $SSH_USER ==="

if ! id "$SSH_USER" &>/dev/null; then
    adduser "$SSH_USER" -u "$SSH_USER_UID"
    echo "$SSH_USER:$SSH_USER_PASS" | chpasswd
    usermod -aG wheel "$SSH_USER"
    echo "$SSH_USER ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
    echo "  Пользователь $SSH_USER (uid=$SSH_USER_UID) создан"
else
    echo "  Пользователь $SSH_USER уже существует"
fi

# =============================================================================
echo "=== [4/7] Настройка SSH ==="

SSHD_CONFIG="/etc/openssh/sshd_config"

# Порт
sed -i "s/^#\?Port .*/Port $SSH_PORT/" "$SSHD_CONFIG"

# Разрешённые пользователи
if ! grep -q "^AllowUsers" "$SSHD_CONFIG"; then
    echo "AllowUsers $SSH_USER" >> "$SSHD_CONFIG"
else
    sed -i "s/^AllowUsers .*/AllowUsers $SSH_USER/" "$SSHD_CONFIG"
fi

# Максимум попыток аутентификации
sed -i 's/^#\?MaxAuthTries .*/MaxAuthTries 2/' "$SSHD_CONFIG"

# Баннер
sed -i 's|^#\?Banner .*|Banner /var/banner|' "$SSHD_CONFIG"

# Создаём баннер
cat > /var/banner <<EOF
Authorized access only
EOF

systemctl enable --now sshd
systemctl restart sshd
echo "  SSH: порт $SSH_PORT, пользователь $SSH_USER, баннер включён"

# =============================================================================
echo "=== [5/7] Настройка DNS (BIND) ==="

# --- options.conf ---
cat > /etc/bind/options.conf <<'OPTEOF'
options {
    directory "/var/lib/bind/zones";
    dump-file "/var/lib/bind/cache_dump.db";
    statistics-file "/var/lib/bind/named_stats.txt";
    memstatistics-file "/var/lib/bind/named_mem_stats.txt";

    listen-on port 53 { 127.0.0.1; LISTEN_IP; };
    listen-on-v6 { none; };

    allow-query { any; };

    forwarders { FORWARDER_IP; };

    dnssec-validation yes;

    recursion yes;
};

logging {
    channel default_log {
        file "/var/log/bind/default.log" versions 3 size 5m;
        severity dynamic;
        print-time yes;
    };
    category default { default_log; };
};
OPTEOF

sed -i "s/LISTEN_IP/$DNS_SERVER_IP/" /etc/bind/options.conf
sed -i "s/FORWARDER_IP/$DNS_FORWARDER/" /etc/bind/options.conf

# Создаём каталог для логов
mkdir -p /var/log/bind
chown named:named /var/log/bind

# --- local.conf (объявление зон) ---
cat > /etc/bind/local.conf <<EOF
zone "$DOMAIN" {
    type master;
    file "$DOMAIN.db";
    allow-update { none; };
};

zone "0.168.192.in-addr.arpa" {
    type master;
    file "0.168.192.in-addr.arpa.db";
    allow-update { none; };
};

zone "1.168.192.in-addr.arpa" {
    type master;
    file "1.168.192.in-addr.arpa.db";
    allow-update { none; };
};
EOF

# --- Прямая зона ---
ZONE_DIR="/var/lib/bind/zones"
mkdir -p "$ZONE_DIR"

cat > "$ZONE_DIR/$DOMAIN.db" <<EOF
\$TTL 3600
@   IN  SOA hq-srv.$DOMAIN. admin.$DOMAIN. (
        $(date +%Y%m%d)01 ; Serial
        3600       ; Refresh
        900        ; Retry
        604800     ; Expire
        86400 )    ; Minimum TTL

@       IN  NS  hq-srv.$DOMAIN.
EOF

# Добавляем A-записи
for host in "${!DNS_A_RECORDS[@]}"; do
    ip="${DNS_A_RECORDS[$host]}"
    printf "%-16s IN  A   %s\n" "$host" "$ip" >> "$ZONE_DIR/$DOMAIN.db"
done

# --- Обратная зона 192.168.0.x ---
cat > "$ZONE_DIR/0.168.192.in-addr.arpa.db" <<EOF
\$TTL 3600
@   IN  SOA hq-srv.$DOMAIN. admin.$DOMAIN. (
        $(date +%Y%m%d)01 ; Serial
        3600       ; Refresh
        900        ; Retry
        604800     ; Expire
        86400 )    ; Minimum TTL

@       IN  NS  hq-srv.$DOMAIN.
EOF

# PTR записи для 192.168.0.x
for host in "${!DNS_A_RECORDS[@]}"; do
    ip="${DNS_A_RECORDS[$host]}"
    # Проверяем что это подсеть 192.168.0.x
    if [[ "$ip" == 192.168.0.* ]]; then
        last_octet="${ip##*.}"
        printf "%-8s IN  PTR %s.%s.\n" "$last_octet" "$host" "$DOMAIN" >> "$ZONE_DIR/0.168.192.in-addr.arpa.db"
    fi
done

# --- Обратная зона 192.168.1.x ---
cat > "$ZONE_DIR/1.168.192.in-addr.arpa.db" <<EOF
\$TTL 3600
@   IN  SOA hq-srv.$DOMAIN. admin.$DOMAIN. (
        $(date +%Y%m%d)01 ; Serial
        3600       ; Refresh
        900        ; Retry
        604800     ; Expire
        86400 )    ; Minimum TTL

@       IN  NS  hq-srv.$DOMAIN.
EOF

# PTR записи для 192.168.1.x
for host in "${!DNS_A_RECORDS[@]}"; do
    ip="${DNS_A_RECORDS[$host]}"
    if [[ "$ip" == 192.168.1.* ]]; then
        last_octet="${ip##*.}"
        printf "%-8s IN  PTR %s.%s.\n" "$last_octet" "$host" "$DOMAIN" >> "$ZONE_DIR/1.168.192.in-addr.arpa.db"
    fi
done

# Права
chown -R named:named "$ZONE_DIR"
chmod 600 "$ZONE_DIR"/*.db

# Генерация rndc ключа
rndc-confgen > /etc/bind/rndc.key 2>/dev/null || true
sed -i '6,$d' /etc/bind/rndc.key 2>/dev/null || true

# Проверка конфигурации
echo "  Проверка конфигурации DNS..."
named-checkconf || echo "  ВНИМАНИЕ: есть ошибки в конфигурации!"
named-checkconf -z 2>&1 || echo "  ВНИМАНИЕ: есть ошибки в зонах!"

# Запуск
systemctl enable --now bind
systemctl restart bind
echo "  DNS (BIND) настроен и запущен"

# =============================================================================
echo "=== [6/7] Часовой пояс ==="
timedatectl set-timezone Europe/Moscow

# =============================================================================
echo "=== [7/7] Проверка ==="
echo ""
echo "--- IP ---"
ip -c -br a
echo ""
echo "--- DNS тест ---"
sleep 2
for host in "${!DNS_A_RECORDS[@]}"; do
    echo -n "  $host.$DOMAIN -> "
    nslookup "$host.$DOMAIN" 127.0.0.1 2>/dev/null | grep -A1 "Name:" | tail -1 || echo "ОШИБКА"
done

echo ""
echo "=== HQ-SRV настроен ==="
