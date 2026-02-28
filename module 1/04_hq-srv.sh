#!/bin/bash
###############################################################################
# 04_hq-srv.sh — HQ-SRV configuration (ALT Linux)
# Module 1: hostname · user · SSH · DNS/BIND · timezone
#
# Интерфейс определяется АВТОМАТИЧЕСКИ:
#   LAN — единственный физический интерфейс (или с IP 192.168.x.x)
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

    # Ищем интерфейс с IP из 192.168.x.x (базовая сеть уже настроена)
    IF_LAN=""
    for iface in "${ALL_IFACES[@]}"; do
        if ip addr show "$iface" 2>/dev/null | grep -qE "192\.168\."; then
            IF_LAN="$iface"
            break
        fi
    done

    # Если не нашли — берём первый физический интерфейс
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

cat > /etc/bind/options.conf <<OPTEOF
options {
    directory "/etc/bind/zone";

    listen-on port 53 { 127.0.0.1; $DNS_SERVER_IP; };
    listen-on-v6 { none; };

    allow-query { any; };
    forwarders { $DNS_FORWARDER; };

    # Отключаем IPv6 в резолвере — нет IPv6 connectivity
    filter-aaaa-on-v4 yes;

    dnssec-validation yes;
    recursion yes;
};
OPTEOF

# Отключаем IPv6 на уровне ОС для named
if ! grep -q "OPTIONS" /etc/sysconfig/named 2>/dev/null; then
    echo 'OPTIONS="-4"' >> /etc/sysconfig/named
else
    sed -i 's/^OPTIONS=.*/OPTIONS="-4"/' /etc/sysconfig/named
fi
chown named:named /etc/bind/options.conf
chmod 640 /etc/bind/options.conf

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

ZONE_DIR="/etc/bind/zone"
mkdir -p "$ZONE_DIR"
chown named:named "$ZONE_DIR"
chmod 750 "$ZONE_DIR"

# Forward zone
cat > "$ZONE_DIR/$DOMAIN.db" <<ZEOF
\$TTL 3600
@   IN  SOA hq-srv.$DOMAIN. admin.$DOMAIN. (
        $(date +%Y%m%d)01 ; Serial
        3600    ; Refresh
        900     ; Retry
        604800  ; Expire
        86400 ) ; Minimum TTL
@       IN  NS  hq-srv.$DOMAIN.
ZEOF
for host in "${!DNS_A_RECORDS[@]}"; do
    printf "%-16s IN  A   %s\n" "$host" "${DNS_A_RECORDS[$host]}" >> "$ZONE_DIR/$DOMAIN.db"
done

# Reverse zone 192.168.0.x
cat > "$ZONE_DIR/0.168.192.in-addr.arpa.db" <<ZEOF
\$TTL 3600
@   IN  SOA hq-srv.$DOMAIN. admin.$DOMAIN. (
        $(date +%Y%m%d)01 ; Serial
        3600    ; Refresh
        900     ; Retry
        604800  ; Expire
        86400 ) ; Minimum TTL
@       IN  NS  hq-srv.$DOMAIN.
ZEOF
for host in "${!DNS_A_RECORDS[@]}"; do
    ip="${DNS_A_RECORDS[$host]}"
    [[ "$ip" == 192.168.0.* ]] && printf "%-8s IN  PTR %s.%s.\n" "${ip##*.}" "$host" "$DOMAIN" \
        >> "$ZONE_DIR/0.168.192.in-addr.arpa.db"
done

# Reverse zone 192.168.1.x
cat > "$ZONE_DIR/1.168.192.in-addr.arpa.db" <<ZEOF
\$TTL 3600
@   IN  SOA hq-srv.$DOMAIN. admin.$DOMAIN. (
        $(date +%Y%m%d)01 ; Serial
        3600    ; Refresh
        900     ; Retry
        604800  ; Expire
        86400 ) ; Minimum TTL
@       IN  NS  hq-srv.$DOMAIN.
ZEOF
for host in "${!DNS_A_RECORDS[@]}"; do
    ip="${DNS_A_RECORDS[$host]}"
    [[ "$ip" == 192.168.1.* ]] && printf "%-8s IN  PTR %s.%s.\n" "${ip##*.}" "$host" "$DOMAIN" \
        >> "$ZONE_DIR/1.168.192.in-addr.arpa.db"
done

chown -R named:named "$ZONE_DIR"
chmod 640 "$ZONE_DIR"/*.db

# Комментируем rndc.conf (ALT Linux quirk)
grep -q "rndc.conf" /etc/bind/named.conf 2>/dev/null \
    && sed -i 's|^include.*rndc.conf|//&|' /etc/bind/named.conf

named-checkconf    || echo "  WARNING: config errors!"
named-checkconf -z || echo "  WARNING: zone errors!"
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
echo "--- DNS test ---"
sleep 2
for host in "${!DNS_A_RECORDS[@]}"; do
    echo -n "  $host.$DOMAIN -> "
    nslookup "$host.$DOMAIN" 127.0.0.1 2>/dev/null | grep "Address:" | tail -1 || echo "ERROR"
done
echo "=== HQ-SRV configured ==="