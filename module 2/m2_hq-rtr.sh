#!/bin/bash
###############################################################################
# m2_hq-rtr.sh — HQ-RTR configuration (Module 2, ALT Linux)
# Tasks: NTP client · Port forwarding (DNAT) · Nginx reverse proxy
###############################################################################
set -e

# ======================== VARIABLES ==========================================
# NTP
NTP_SERVER="172.16.1.14"

# DNAT
WAN_IP="172.16.1.1"
HQ_SRV_IP="192.168.0.1"
IF_WAN="ens19"
DNAT_RULES=(
    "80:$HQ_SRV_IP:80"
    "2024:$HQ_SRV_IP:2024"
)
NFTABLES_CONF="/etc/nftables/nftables.nft"

# Nginx reverse proxy
DOMAIN="au-team.irpo"
WEB_BACKEND="http://192.168.0.1:80"
DOCKER_BACKEND="http://192.168.1.1:8080"
NGINX_CONF_DIR="/etc/nginx/sites-available"
NGINX_ENABLED_DIR="/etc/nginx/sites-enabled"
CONF_FILE="$NGINX_CONF_DIR/revers.conf"

# =============================================================================
echo "=== [0/3] Installing required software ==="
apt-get update -y
apt-get install -y chrony nginx
echo "  Software installed"

# =============================================================================
echo "=== [1/3] Configuring NTP client ==="

cat > /etc/chrony.conf <<EOF
# NTP client — sync with ISP
server $NTP_SERVER iburst prefer

driftfile /var/lib/chrony/drift
log tracking measurements statistics
logdir /var/log/chrony
EOF

systemctl enable --now chronyd
systemctl restart chronyd
sleep 2
echo "  NTP client: server $NTP_SERVER"

# =============================================================================
echo "=== [2/3] Configuring port forwarding (DNAT) ==="

if grep -q "chain prerouting" "$NFTABLES_CONF" 2>/dev/null; then
    echo "  chain prerouting exists — replacing"
    sed -i '/chain prerouting/,/^[[:space:]]*}/d' "$NFTABLES_CONF"
fi

for rule in "${DNAT_RULES[@]}"; do
    IFS=':' read -r ext_port dst_ip dst_port <<< "$rule"
    echo "  $WAN_IP:$ext_port -> $dst_ip:$dst_port"
done

if grep -q "table inet nat" "$NFTABLES_CONF"; then
    python3 <<PYEOF
import re

with open("$NFTABLES_CONF", "r") as f:
    content = f.read()

dnat_block = """    chain prerouting {
        type nat hook prerouting priority filter;
$(for rule in "${DNAT_RULES[@]}"; do
    IFS=':' read -r ext_port dst_ip dst_port <<< "$rule"
    echo "        ip daddr $WAN_IP tcp dport $ext_port dnat ip to $dst_ip:$dst_port"
done)
    }"""

pattern = r'(table inet nat \{.*?)(^\})'
replacement = r'\1' + dnat_block + '\n}'
content_new = re.sub(pattern, replacement, content, flags=re.DOTALL | re.MULTILINE)

with open("$NFTABLES_CONF", "w") as f:
    f.write(content_new)
PYEOF
else
    echo "  ERROR: table inet nat not found in $NFTABLES_CONF"
    echo "  Add NAT table via module 1 script (02_hq-rtr.sh) first"
    exit 1
fi

systemctl restart nftables
echo "  DNAT configured"

# =============================================================================
echo "=== [3/3] Configuring Nginx reverse proxy ==="

mkdir -p "$NGINX_CONF_DIR" "$NGINX_ENABLED_DIR"

cat > "$CONF_FILE" <<EOF
# Reverse proxy for web.$DOMAIN -> HQ-SRV
server {
    listen 80;
    server_name web.$DOMAIN;

    location / {
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_pass $WEB_BACKEND;
    }
}

# Reverse proxy for docker.$DOMAIN -> BR-SRV
server {
    listen 80;
    server_name docker.$DOMAIN;

    location / {
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_pass $DOCKER_BACKEND;
    }
}
EOF

ln -sf "$CONF_FILE" "$NGINX_ENABLED_DIR/revers.conf"
nginx -t 2>&1 || { echo "  ERROR in Nginx config!"; exit 1; }
systemctl enable --now nginx
systemctl reload nginx 2>/dev/null || systemctl restart nginx
echo "  Nginx reverse proxy: web.$DOMAIN -> $WEB_BACKEND, docker.$DOMAIN -> $DOCKER_BACKEND"

echo ""
echo "=== Verification ==="
chronyc sources 2>/dev/null | head -5
echo ""
nft list ruleset | grep -A3 "prerouting" || echo "  No prerouting rules found"
echo ""
echo "=== HQ-RTR (Module 2) configured ==="
