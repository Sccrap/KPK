#!/bin/bash
###############################################################################
# m2_isp.sh — ISP configuration (Module 2, ALT Linux)
# Tasks: NTP server · Nginx web-auth proxy
###############################################################################
set -e

# ======================== VARIABLES ==========================================
# NTP
STRATUM=5
ALLOW_NETS=(
    "172.16.1.0/28"
    "172.16.2.0/28"
)

# Nginx / htpasswd
DOMAIN="au-team.irpo"
HQ_RTR_IP="172.16.1.1"
HTPASSWD_FILE="/etc/nginx/.htpasswd"
AUTH_USER="WEB"
AUTH_PASS="P@ssw0rd"
NGINX_CONF_DIR="/etc/nginx/sites-available"
NGINX_ENABLED_DIR="/etc/nginx/sites-enabled"
CONF_FILE="$NGINX_CONF_DIR/revers.conf"

# =============================================================================
echo "=== [0/3] Installing required software ==="
apt-get update -y
apt-get install -y chrony nginx openssl
echo "  Software installed"

# =============================================================================
echo "=== [1/3] Configuring NTP server (chrony) ==="

cat > /etc/chrony.conf <<EOF
# NTP server — ISP
local stratum $STRATUM

$(for net in "${ALLOW_NETS[@]}"; do echo "allow $net"; done)

driftfile /var/lib/chrony/drift
log tracking measurements statistics
logdir /var/log/chrony
EOF

systemctl enable --now chronyd
systemctl restart chronyd
echo "  NTP server: stratum $STRATUM, allowed: ${ALLOW_NETS[*]}"

# =============================================================================
echo "=== [2/3] Configuring Nginx web-auth proxy ==="

# Create htpasswd (use openssl if htpasswd not available)
if command -v htpasswd &>/dev/null; then
    htpasswd -cb "$HTPASSWD_FILE" "$AUTH_USER" "$AUTH_PASS"
else
    HASH=$(openssl passwd -apr1 "$AUTH_PASS")
    echo "$AUTH_USER:$HASH" > "$HTPASSWD_FILE"
fi
chmod 640 "$HTPASSWD_FILE"
chown root:nginx "$HTPASSWD_FILE" 2>/dev/null || true
echo "  htpasswd user $AUTH_USER created"

mkdir -p "$NGINX_CONF_DIR" "$NGINX_ENABLED_DIR"

cat > "$CONF_FILE" <<EOF
# Proxy for web.$DOMAIN with authentication
server {
    listen 80;
    server_name web.$DOMAIN;

    auth_basic "Restricted area";
    auth_basic_user_file $HTPASSWD_FILE;

    location / {
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_pass http://$HQ_RTR_IP;
    }
}

# Proxy for docker.$DOMAIN (no authentication)
server {
    listen 80;
    server_name docker.$DOMAIN;

    location / {
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_pass http://$HQ_RTR_IP;
    }
}
EOF

ln -sf "$CONF_FILE" "$NGINX_ENABLED_DIR/revers.conf"
nginx -t 2>&1 || { echo "  ERROR in Nginx config!"; exit 1; }
systemctl enable --now nginx
systemctl restart nginx
echo "  Nginx auth proxy configured"
echo "  Auth: $AUTH_USER / $AUTH_PASS"

# =============================================================================
echo "=== [3/3] Verification ==="
chronyc tracking 2>/dev/null | head -3
echo ""
systemctl is-active nginx && echo "  nginx: active" || echo "  nginx: INACTIVE"
echo ""
echo "=== ISP (Module 2) configured ==="
