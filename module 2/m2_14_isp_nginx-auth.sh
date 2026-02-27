#!/bin/bash
###############################################################################
# m2_14_isp_nginx-auth.sh — Nginx Web-based аутентификация на ISP (ALT Linux)
# Задание 10: htpasswd аутентификация для web.au-team.irpo
###############################################################################
set -e

# ======================== ПЕРЕМЕННЫЕ =========================================
DOMAIN="au-team.irpo"
HQ_RTR_IP="172.16.1.1"

# htpasswd
HTPASSWD_FILE="/etc/nginx/.htpasswd"
AUTH_USER="WEB"
AUTH_PASS="P@ssw0rd"

# Nginx
NGINX_CONF_DIR="/etc/nginx/sites-available"
NGINX_ENABLED_DIR="/etc/nginx/sites-enabled"
CONF_FILE="$NGINX_CONF_DIR/revers.conf"

# =============================================================================
echo "=== [1/3] Создание htpasswd ==="

# Создаём пользователя (-c создаёт новый файл, -b берёт пароль из аргумента)
if command -v htpasswd &>/dev/null; then
    htpasswd -cb "$HTPASSWD_FILE" "$AUTH_USER" "$AUTH_PASS"
else
    # Альтернатива без htpasswd (через openssl)
    HASH=$(openssl passwd -apr1 "$AUTH_PASS")
    echo "$AUTH_USER:$HASH" > "$HTPASSWD_FILE"
fi

chmod 640 "$HTPASSWD_FILE"
chown root:nginx "$HTPASSWD_FILE" 2>/dev/null || true

echo "  Пользователь $AUTH_USER создан в $HTPASSWD_FILE"

# =============================================================================
echo "=== [2/3] Настройка Nginx с аутентификацией ==="

mkdir -p "$NGINX_CONF_DIR" "$NGINX_ENABLED_DIR"

cat > "$CONF_FILE" <<EOF
# Proxy для web.$DOMAIN с аутентификацией
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

# Proxy для docker.$DOMAIN (без аутентификации)
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
echo "  Конфигурация Nginx создана"

# Проверка
nginx -t 2>&1 || {
    echo "  ОШИБКА конфигурации Nginx!"
    exit 1
}

# =============================================================================
echo "=== [3/3] Перезапуск Nginx ==="

systemctl enable --now nginx
systemctl restart nginx

echo ""
echo "=== Проверка ==="
echo "  Логин: $AUTH_USER"
echo "  Пароль: $AUTH_PASS"
echo ""
echo "  Тест: curl -u $AUTH_USER:$AUTH_PASS http://<ISP_IP> -H 'Host: web.$DOMAIN'"
echo ""
echo "=== Web-based аутентификация настроена ==="
