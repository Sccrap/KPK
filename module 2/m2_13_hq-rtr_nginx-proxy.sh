#!/bin/bash
###############################################################################
# m2_13_hq-rtr_nginx-proxy.sh — Nginx Reverse Proxy на HQ-RTR (ALT Linux)
# Задание 9: Обратный прокси-сервер
###############################################################################
set -e

# ======================== ПЕРЕМЕННЫЕ =========================================
DOMAIN="au-team.irpo"

# Бэкенды
WEB_BACKEND="http://192.168.0.1:80"      # HQ-SRV (web через DNAT)
DOCKER_BACKEND="http://192.168.1.1:8080"  # BR-SRV (docker через DNAT)

# Nginx
NGINX_CONF_DIR="/etc/nginx/sites-available"
NGINX_ENABLED_DIR="/etc/nginx/sites-enabled"
CONF_FILE="$NGINX_CONF_DIR/revers.conf"

# =============================================================================
echo "=== [1/3] Создание конфигурации Nginx ==="

mkdir -p "$NGINX_CONF_DIR" "$NGINX_ENABLED_DIR"

cat > "$CONF_FILE" <<EOF
# Reverse proxy для web.$DOMAIN -> HQ-SRV
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

# Reverse proxy для docker.$DOMAIN -> BR-SRV
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

echo "  $CONF_FILE создан"
echo "  web.$DOMAIN -> $WEB_BACKEND"
echo "  docker.$DOMAIN -> $DOCKER_BACKEND"

# =============================================================================
echo "=== [2/3] Включение конфигурации ==="

# Создаём символическую ссылку
ln -sf "$CONF_FILE" "$NGINX_ENABLED_DIR/revers.conf"
echo "  Символическая ссылка создана"

# Проверяем конфигурацию
nginx -t 2>&1 || {
    echo "  ОШИБКА в конфигурации Nginx!"
    exit 1
}

# =============================================================================
echo "=== [3/3] Запуск Nginx ==="

systemctl enable --now nginx
systemctl reload nginx 2>/dev/null || systemctl restart nginx

echo ""
echo "=== Проверка ==="
echo "  nginx -t"
nginx -t 2>&1
echo ""
echo "Для тестирования с HQ-CLI:"
echo "  curl -H 'Host: web.$DOMAIN' http://172.16.1.1"
echo "  curl -H 'Host: docker.$DOMAIN' http://172.16.1.1"
echo ""
echo "Убедитесь, что DNS записи web.$DOMAIN и docker.$DOMAIN"
echo "указывают на IP HQ-RTR (172.16.1.1 или WAN-адрес)"
echo ""
echo "=== Nginx reverse proxy настроен ==="
