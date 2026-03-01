#!/bin/bash
# ============================================================
# MODULE 2 — ISP
# Задание 1: Chrony (NTP-сервер)
# Задание 4: Nginx (reverse proxy + basic auth)
# ============================================================
set -e

echo "[*] === ISP: MODULE 2 ==="

# ============================================================
# ЗАДАНИЕ 1: CHRONY — NTP-сервер
# ============================================================
echo "[*] [1] Настраиваем Chrony (NTP-сервер)..."
apt-get install -y chrony

cat > /etc/chrony.conf << 'EOF'
# ISP — NTP-сервер для HQ и BR сетей
local stratum 5
allow 172.16.1.0/28
allow 172.16.2.0/28
EOF

systemctl enable --now chronyd
systemctl restart chronyd
systemctl status chronyd --no-pager
echo "[+] Chrony настроен"

# ============================================================
# ЗАДАНИЕ 4: NGINX — Reverse Proxy
# ============================================================
echo "[*] [4] Настраиваем Nginx (reverse proxy)..."
apt-get install -y nginx apache2-utils

# Конфиг reverse proxy
cat > /etc/nginx/sites-available.d/revers.conf << 'EOF'
server {
    server_name web.au-team.irpo;

    location / {
        proxy_pass http://172.16.1.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        auth_basic "Restricted area";
        auth_basic_user_file /etc/nginx/.htpasswd;
    }
}

server {
    server_name docker.au-team.irpo;

    location / {
        proxy_pass http://172.16.2.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

# Symlink
ln -sf /etc/nginx/sites-available.d/revers.conf \
        /etc/nginx/sites-enabled.d/revers.conf 2>/dev/null || true

systemctl enable --now nginx

# Basic Auth пользователь WEBc
htpasswd -bc /etc/nginx/.htpasswd WEBc 'P@ssw0rd'

systemctl restart nginx
nginx -t && echo "[+] Nginx config OK"

echo "[+] === ISP MODULE 2: Завершено ==="
echo "[!] Клиент: открой http://web.au-team.irpo  логин: WEBc  пароль: P@ssw0rd"
