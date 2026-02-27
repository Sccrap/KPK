#!/bin/bash
###############################################################################
# 04_hq-srv.sh — HQ-SRV configuration (ALT Linux)
# Module 1: hostname · user · SSH (port 2024) · DNS/BIND · timezone
#
# PRE-REQUISITE (manual, before running this script):
#   ens19 = 192.168.0.1/26, gateway 192.168.0.62  (towards HQ-RTR vlan100)
#   resolv.conf pointing to self:
#     echo -e "search au-team.irpo\nnameserver 192.168.0.1\nnameserver 77.88.8.7" > /etc/resolv.conf
#   See: module 1/README.md → "Step 0 — Manual IP Configuration"
###############################################################################
set -e

# ======================== VARIABLES ==========================================
HOSTNAME="hq-srv.au-team.irpo"
DOMAIN="au-team.irpo"

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

# =============================================================================
echo "=== [0/6] Installing required software ==="
apt-get update -y
apt-get install -y bind openssh-server
echo "  Software installed"

# =============================================================================
echo "=== [1/6] Setting hostname ==="
hostnamectl set-hostname "$HOSTNAME"

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

if ! grep -q "^AllowUsers" "$SSHD_CONFIG"; then
    echo "AllowUsers $SSH_USER" >> "$SSHD_CONFIG"
else
    sed -i "s/^AllowUsers .*/AllowUsers $SSH_USER/" "$SSHD_CONFIG"
fi

sed -i 's/^#\?MaxAuthTries .*/MaxAuthTries 2/' "$SSHD_CONFIG"
sed -i 's|^#\?Banner .*|Banner /var/banner|' "$SSHD_CONFIG"

cat > /var/banner <<EOF
Authorized access only
EOF

systemctl enable --now sshd
systemctl restart sshd
echo "  SSH: port $SSH_PORT, user $SSH_USER, banner enabled"

# =============================================================================
echo "=== [4/6] Configuring DNS (BIND) ==="

# Point resolver to self before starting bind
cat > /etc/resolv.conf <<EOF
search $DOMAIN
nameserver $DNS_SERVER_IP
nameserver $DNS_FORWARDER
EOF

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

mkdir -p /var/log/bind
chown named:named /var/log/bind

# --- local.conf ---
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

# --- Forward zone ---
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

for host in "${!DNS_A_RECORDS[@]}"; do
    ip="${DNS_A_RECORDS[$host]}"
    printf "%-16s IN  A   %s\n" "$host" "$ip" >> "$ZONE_DIR/$DOMAIN.db"
done

# --- Reverse zone 192.168.0.x ---
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

for host in "${!DNS_A_RECORDS[@]}"; do
    ip="${DNS_A_RECORDS[$host]}"
    if [[ "$ip" == 192.168.0.* ]]; then
        last_octet="${ip##*.}"
        printf "%-8s IN  PTR %s.%s.\n" "$last_octet" "$host" "$DOMAIN" \
            >> "$ZONE_DIR/0.168.192.in-addr.arpa.db"
    fi
done

# --- Reverse zone 192.168.1.x ---
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

for host in "${!DNS_A_RECORDS[@]}"; do
    ip="${DNS_A_RECORDS[$host]}"
    if [[ "$ip" == 192.168.1.* ]]; then
        last_octet="${ip##*.}"
        printf "%-8s IN  PTR %s.%s.\n" "$last_octet" "$host" "$DOMAIN" \
            >> "$ZONE_DIR/1.168.192.in-addr.arpa.db"
    fi
done

chown -R named:named "$ZONE_DIR"
chmod 600 "$ZONE_DIR"/*.db

rndc-confgen > /etc/bind/rndc.key 2>/dev/null || true
sed -i '6,$d' /etc/bind/rndc.key 2>/dev/null || true

echo "  Checking DNS configuration..."
named-checkconf     || echo "  WARNING: errors in configuration!"
named-checkconf -z 2>&1 || echo "  WARNING: errors in zones!"

systemctl enable --now bind
systemctl restart bind
echo "  DNS (BIND) configured and started"

# =============================================================================
echo "=== [5/6] Timezone ==="
timedatectl set-timezone Europe/Moscow

# =============================================================================
echo "=== [6/6] Verification ==="
ip -c -br a
echo ""
echo "--- DNS test ---"
sleep 2
for host in "${!DNS_A_RECORDS[@]}"; do
    echo -n "  $host.$DOMAIN -> "
    nslookup "$host.$DOMAIN" 127.0.0.1 2>/dev/null | grep -A1 "Name:" | tail -1 || echo "ERROR"
done

echo ""
echo "=== HQ-SRV configured ==="
