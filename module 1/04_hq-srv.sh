#!/bin/bash
###############################################################################
# 04_hq-srv.sh — HQ-SRV configuration (ALT Linux)
# Module 1: hostname · user · SSH · DNS/BIND · timezone
#
# Интерфейс определяется АВТОМАТИЧЕСКИ:
#   LAN — интерфейс с IP 192.168.x.x, или первый физический
###############################################################################
set -e

# ======================== FIXED VARIABLES ====================================
HOSTNAME="hq-srv.au-team.irpo"
DOMAIN="au-team.irpo"

IP_LAN="192.168.0.1/26"
GW_LAN="192.168.0.62"
DNS_SERVER_IP="192.168.0.1"
DNS_FORWARDER="77.88.8.7"

SSH_USER="sshuser"
SSH_USER_UID="2026"
SSH_USER_PASS="P@ssw0rd"
SSH_PORT="2024"

# DNS записи (по таблице из PDF)
declare -A DNS_A_RECORDS=(
    ["hq-rtr"]="192.168.0.62"
    ["hq-srv"]="192.168.0.1"
    ["hq-cli"]="192.168.0.65"
    ["hq-sw"]="192.168.0.81"
    ["br-rtr"]="192.168.1.30"
    ["br-srv"]="192.168.1.1"
)

# ======================== AUTO-DETECT INTERFACE ==============================
detect_interface() {
    echo "  Scanning network interfaces..."
    ALL_IFACES=( $(ls /sys/class/net/ | grep -vE '^(lo|vlan|tun|gre|ovs|docker|br-)' | sort) )
    echo "  Found interfaces: ${ALL_IFACES[*]}"

    IF_LAN=""
    for iface in "${ALL_IFACES[@]}"; do
        if ip addr show "$iface" 2>/dev/null | grep -qE "192\.168\."; then
            IF_LAN="$iface"
            break
        fi
    done

    if [ -z "$IF_LAN" ]; then
        echo "  WARNING: no 192.168.x.x IP found, using first interface"
        IF_LAN="${ALL_IFACES[0]}"
    fi
    echo "  LAN (to HQ-RTR): $IF_LAN"
}

configure_iface_static() {
    local iface="$1"
    local ip="$2"
    local dir="/etc/net/ifaces/$iface"
    mkdir -p "$dir"
    cat > "$dir/options" <<OPTS
BOOTPROTO=static
TYPE=eth
CONFIG_WIRELESS=no
SYSTEMD_BOOTPROTO=static
CONFIG_IPV4=yes
DISABLED=no
NM_CONTROLLED=no
ONBOOT=yes
OPTS
    echo "$ip" > "$dir/ipv4address"
    echo "  $iface -> $ip"
}

# =============================================================================
echo "=== [0/6] Installing required software ==="
apt-get update -y
apt-get install -y bind openssh-server
echo "  Done"

# =============================================================================
echo "=== [1/6] Setting hostname ==="
hostnamectl set-hostname "$HOSTNAME"

# =============================================================================
echo "=== [1.5/6] Auto-detecting and configuring interface ==="
detect_interface

configure_iface_static "$IF_LAN" "$IP_LAN"
echo "default via $GW_LAN" > "/etc/net/ifaces/$IF_LAN/ipv4route"

# DNS указывает на себя (как в PDF)
echo -e "search $DOMAIN\nnameserver $DNS_SERVER_IP\nnameserver $DNS_FORWARDER" > /etc/resolv.conf

systemctl restart network
sleep 2
echo "  Network restarted"

# =============================================================================
echo "=== [2/6] Creating user $SSH_USER ==="
if ! id "$SSH_USER" &>/dev/null; then
    adduser "$SSH_USER" -u "$SSH_USER_UID"
    echo "$SSH_USER:$SSH_USER_PASS" | chpasswd
    usermod -aG wheel "$SSH_USER"
    echo "$SSH_USER ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
    echo "  User $SSH_USER (uid=$SSH_USER_UID) created"
else
    echo "  User $SSH_USER already exists"
fi

# =============================================================================
echo "=== [3/6] Configuring SSH ==="
SSHD_CONFIG="/etc/openssh/sshd_config"
sed -i "s/^#\?Port .*/Port $SSH_PORT/" "$SSHD_CONFIG"
grep -q "^AllowUsers" "$SSHD_CONFIG" \
    && sed -i "s/^AllowUsers .*/AllowUsers $SSH_USER/" "$SSHD_CONFIG" \
    || echo "AllowUsers $SSH_USER" >> "$SSHD_CONFIG"
sed -i 's/^#\?MaxAuthTries .*/MaxAuthTries 2/' "$SSHD_CONFIG"
sed -i 's|^#\?Banner .*|Banner /var/banner|' "$SSHD_CONFIG"
echo "Authorized access only" > /var/banner
systemctl enable --now sshd
systemctl restart sshd
echo "  SSH port=$SSH_PORT user=$SSH_USER"

# =============================================================================
echo "=== [4/6] Configuring DNS (BIND) ==="

# --- /etc/bind/options.conf ---
# Точно как в PDF: listen-on, listen-on-v6 none, forwarders, allow-query, dnssec-validation
cat > /etc/bind/options.conf <<OPTEOF
options {
    listen-on port 53 { 127.0.0.1; $DNS_SERVER_IP; };
    listen-on-v6 { none; };

    forwarders { $DNS_FORWARDER; };

    allow-query { any; };

    dnssec-validation yes;

    managed-keys-directory "/var/lib/bind";
    recursion yes;
};
OPTEOF
chown named:named /etc/bind/options.conf
chmod 640 /etc/bind/options.conf

# Runtime директория для named (NTA/managed-keys файлы)
mkdir -p /var/lib/bind
chown named:named /var/lib/bind
chmod 770 /var/lib/bind

# Запуск named только в IPv4-режиме — отключаем IPv6 (нет connectivity)
mkdir -p /etc/systemd/system/bind.service.d
cat > /etc/systemd/system/bind.service.d/ipv4only.conf <<SDEOF
[Service]
ExecStart=
ExecStart=/usr/sbin/named -f -4
SDEOF
systemctl daemon-reload

# --- /etc/bind/local.conf ---
# Точно как в PDF: прямая зона au-team.irpo + обратная 0.168.192.in-addr.arpa
cat > /etc/bind/local.conf <<LOCALEOF
zone "$DOMAIN" {
    type master;
    file "$DOMAIN.db";
};

zone "0.168.192.in-addr.arpa" {
    type master;
    file "0.168.192.in-addr.arpa.db";
};

zone "1.168.192.in-addr.arpa" {
    type master;
    file "1.168.192.in-addr.arpa.db";
};
LOCALEOF

# --- Файлы зон ---
ZONE_DIR="/etc/bind/zone"
mkdir -p "$ZONE_DIR"

# Прямая зона (au-team.irpo.db) — как в PDF
cat > "$ZONE_DIR/$DOMAIN.db" <<ZEOF
\$TTL 3600
@   IN  SOA hq-srv.$DOMAIN. admin.$DOMAIN. (
            $(date +%Y%m%d)01 ; Serial
            3600              ; Refresh
            900               ; Retry
            604800            ; Expire
            86400 )           ; Minimum TTL
;
@       IN      NS      hq-srv.$DOMAIN.
ZEOF
# A-записи
for host in "${!DNS_A_RECORDS[@]}"; do
    printf "%-16s IN  A   %s\n" "$host" "${DNS_A_RECORDS[$host]}" >> "$ZONE_DIR/$DOMAIN.db"
done

# Обратная зона 192.168.0.x
cat > "$ZONE_DIR/0.168.192.in-addr.arpa.db" <<ZEOF
\$TTL 3600
@   IN  SOA hq-srv.$DOMAIN. admin.$DOMAIN. (
            $(date +%Y%m%d)01 ; Serial
            3600              ; Refresh
            900               ; Retry
            604800            ; Expire
            86400 )           ; Minimum TTL
;
@       IN      NS      hq-srv.$DOMAIN.
ZEOF
for host in "${!DNS_A_RECORDS[@]}"; do
    ip="${DNS_A_RECORDS[$host]}"
    [[ "$ip" == 192.168.0.* ]] && printf "%-8s IN  PTR  %s.%s.\n" "${ip##*.}" "$host" "$DOMAIN" \
        >> "$ZONE_DIR/0.168.192.in-addr.arpa.db"
done

# Обратная зона 192.168.1.x
cat > "$ZONE_DIR/1.168.192.in-addr.arpa.db" <<ZEOF
\$TTL 3600
@   IN  SOA hq-srv.$DOMAIN. admin.$DOMAIN. (
            $(date +%Y%m%d)01 ; Serial
            3600              ; Refresh
            900               ; Retry
            604800            ; Expire
            86400 )           ; Minimum TTL
;
@       IN      NS      hq-srv.$DOMAIN.
ZEOF
for host in "${!DNS_A_RECORDS[@]}"; do
    ip="${DNS_A_RECORDS[$host]}"
    [[ "$ip" == 192.168.1.* ]] && printf "%-8s IN  PTR  %s.%s.\n" "${ip##*.}" "$host" "$DOMAIN" \
        >> "$ZONE_DIR/1.168.192.in-addr.arpa.db"
done

# Права на файлы зон — точно как в PDF: chown named, chmod 600
chown named:named "$ZONE_DIR"
chmod 750 "$ZONE_DIR"
chown named "$ZONE_DIR/$DOMAIN.db"
chown named "$ZONE_DIR/0.168.192.in-addr.arpa.db"
chown named "$ZONE_DIR/1.168.192.in-addr.arpa.db"
chmod 600 "$ZONE_DIR/$DOMAIN.db"
chmod 600 "$ZONE_DIR/0.168.192.in-addr.arpa.db"
chmod 600 "$ZONE_DIR/1.168.192.in-addr.arpa.db"

# rndc.key — точно как в PDF
rndc-confgen > /etc/bind/rndc.key
sed -i '6,$d' /etc/bind/rndc.key

# Проверка конфигурации (как в PDF: named-checkconf, named-checkconf -z)
echo "  Checking configuration..."
named-checkconf    && echo "  named-checkconf: OK" || echo "  WARNING: config errors!"
named-checkconf -z && echo "  named-checkconf -z: OK" || echo "  WARNING: zone errors!"

systemctl enable --now bind
systemctl restart bind
echo "  DNS configured"

# =============================================================================
echo "=== [5/6] Timezone ==="
timedatectl set-timezone Europe/Moscow

# =============================================================================
echo "=== [6/6] Verification ==="
echo "  LAN=$IF_LAN"
ip -c -br a
echo ""
echo "--- DNS test (nslookup) ---"
sleep 2
for host in "${!DNS_A_RECORDS[@]}"; do
    echo -n "  $host.$DOMAIN -> "
    nslookup "$host.$DOMAIN" 127.0.0.1 2>/dev/null | grep "Address:" | tail -1 || echo "ERROR"
done
echo ""
echo "=== HQ-SRV configured ==="