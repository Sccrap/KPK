#!/bin/bash
###############################################################################
# m3_isp.sh — ISP configuration (Module 3, ALT Linux)
# Tasks: Copy GOST certs from HQ-SRV · Configure Nginx TLS
#
# PRE-REQUISITE: m3_hq-srv.sh must be run first (generates certs to /raid/nfs/)
###############################################################################
set -e

# ======================== VARIABLES ==========================================
DOMAIN="au-team.irpo"
HQ_SRV_IP="172.16.1.1"   # HQ-SRV reachable IP from ISP side (via DNAT/WAN)
SSH_PORT_SRV="2026"
SSH_USER="sshuser"

NGINX_ENABLED_D="/etc/nginx/sites-enabled.d"
NGINX_ENABLED_DIR="/etc/nginx/sites-enabled"

# =============================================================================
echo "=== [0/2] Installing required software ==="
apt-get update -y
apt-get install -y openssl-gost-engine nginx
echo "  Software installed"

# =============================================================================
echo "=== [1/2] Copying certificates and configuring Nginx TLS ==="

mkdir -p /etc/nginx/ssl/private "$NGINX_ENABLED_D" "$NGINX_ENABLED_DIR"

echo "  Copying certs from HQ-SRV ($HQ_SRV_IP) via scp port $SSH_PORT_SRV..."
scp -P "$SSH_PORT_SRV" "$SSH_USER@${HQ_SRV_IP}:/raid/nfs/web.$DOMAIN.crt"    /etc/nginx/ssl/
scp -P "$SSH_PORT_SRV" "$SSH_USER@${HQ_SRV_IP}:/raid/nfs/web.$DOMAIN.key"    /etc/nginx/ssl/private/
scp -P "$SSH_PORT_SRV" "$SSH_USER@${HQ_SRV_IP}:/raid/nfs/docker.$DOMAIN.crt" /etc/nginx/ssl/
scp -P "$SSH_PORT_SRV" "$SSH_USER@${HQ_SRV_IP}:/raid/nfs/docker.$DOMAIN.key" /etc/nginx/ssl/private/
echo "  Certificates copied"

# Append TLS server blocks to existing revers.conf
CONF_TARGET="$NGINX_ENABLED_D/revers.conf"
[ ! -f "$CONF_TARGET" ] && CONF_TARGET="$NGINX_ENABLED_DIR/revers.conf"

cat >> "$CONF_TARGET" <<EOF

# --- WEB TLS ---
server {
    listen 443 ssl;
    server_name web.$DOMAIN;

    ssl_certificate     /etc/nginx/ssl/web.$DOMAIN.crt;
    ssl_certificate_key /etc/nginx/ssl/private/web.$DOMAIN.key;
    ssl_protocols       TLSv1.2;
    ssl_ciphers         GOST2012-KUZNYECHIK-KUZNYECHIKOMAC;
    ssl_prefer_server_ciphers on;

    location / {
        proxy_pass http://192.168.0.1;
    }
}

# --- DOCKER TLS ---
server {
    listen 443 ssl;
    server_name docker.$DOMAIN;

    ssl_certificate     /etc/nginx/ssl/docker.$DOMAIN.crt;
    ssl_certificate_key /etc/nginx/ssl/private/docker.$DOMAIN.key;
    ssl_protocols       TLSv1.2;
    ssl_ciphers         GOST2012-KUZNYECHIK-KUZNYECHIKOMAC;
    ssl_prefer_server_ciphers on;

    location / {
        proxy_pass http://192.168.0.1;
    }
}
EOF
echo "  TLS server blocks added to $CONF_TARGET"

# =============================================================================
echo "=== [2/2] Restarting Nginx ==="

nginx -t 2>&1 && systemctl restart nginx \
    && echo "  Nginx restarted successfully" \
    || { echo "  ERROR in Nginx config!"; exit 1; }

echo ""
echo "=== Verification ==="
nginx -t 2>&1
echo ""
echo "=== ISP (Module 3) configured ==="
echo "Test: curl -k https://web.$DOMAIN"
echo "Test: curl -k https://docker.$DOMAIN"
