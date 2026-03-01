#!/bin/bash
# ============================================================
# MODULE 2 — ISP
# Task 1: Chrony — NTP server (allow HQ and BR networks)
# Task 4: Nginx — reverse proxy with basic auth for web.au-team.irpo
# Task 5: Yandex Browser (N/A on ISP — client only)
# PDF ref: Второй.pdf task 1 (ISP Chrony), task 4 (ISP Nginx)
# ============================================================
set -e

echo "[*] ========================================"
echo "[*]  MODULE 2 — ISP"
echo "[*] ========================================"

# ============================================================
# TASK 1: CHRONY — NTP SERVER
# ============================================================
echo ""
echo "[*] [Task 1] Configuring Chrony as NTP server..."
apt-get install -y chrony

# Per PDF: configure ISP as stratum 5 local clock,
# allow NTP queries from HQ (172.16.1.0/28) and BR (172.16.2.0/28)
# Comment out / remove default pool lines
cat > /etc/chrony.conf << 'EOF'
# ISP NTP Server — serves HQ and BR networks
# local stratum makes ISP the time reference even without upstream NTP
local stratum 5

# Allow NTP queries from HQ network
allow 172.16.1.0/28
# Allow NTP queries from BR network
allow 172.16.2.0/28
EOF

systemctl enable --now chronyd
systemctl restart chronyd
sleep 2
echo "[+] Chrony NTP server configured"
echo "    Stratum: 5 (local)"
echo "    Allow: 172.16.1.0/28, 172.16.2.0/28"
chronyc tracking 2>/dev/null | head -5 || true

# ============================================================
# TASK 4: NGINX — REVERSE PROXY
# ============================================================
echo ""
echo "[*] [Task 4] Configuring Nginx reverse proxy..."
apt-get install -y nginx apache2-utils

# Disable default site if present
rm -f /etc/nginx/sites-enabled.d/default.conf 2>/dev/null || true
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

# Per PDF: reverse proxy config
# web.au-team.irpo -> HQ-RTR:8080 (which DNATs to HQ-SRV:80)
# docker.au-team.irpo -> BR-RTR:8080 (which DNATs to BR-SRV:8080)
# web.au-team.irpo requires basic auth (user: WEBc, password: P@ssw0rd)
mkdir -p /etc/nginx/sites-available.d
mkdir -p /etc/nginx/sites-enabled.d

cat > /etc/nginx/sites-available.d/revers.conf << 'EOF'
server {
    server_name web.au-team.irpo;

    location / {
        proxy_pass          http://172.16.1.1:8080;
        proxy_set_header    Host              $host;
        proxy_set_header    X-Real-IP         $remote_addr;
        proxy_set_header    X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header    X-Forwarded-Proto $scheme;
        auth_basic          "Restricted area";
        auth_basic_user_file /etc/nginx/.htpasswd;
    }
}

server {
    server_name docker.au-team.irpo;

    location / {
        proxy_pass          http://172.16.2.1:8080;
        proxy_set_header    Host              $host;
        proxy_set_header    X-Real-IP         $remote_addr;
        proxy_set_header    X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header    X-Forwarded-Proto $scheme;
    }
}
EOF

# Symlink into sites-enabled
ln -sf /etc/nginx/sites-available.d/revers.conf \
       /etc/nginx/sites-enabled.d/revers.conf

systemctl enable --now nginx

# Create htpasswd file with user WEBc
# -c flag creates/overwrites the file, -b reads password from command line
htpasswd -bc /etc/nginx/.htpasswd WEBc 'P@ssw0rd'
echo "[+] htpasswd created: user=WEBc password=P@ssw0rd"

# Verify config and restart
nginx -t && echo "[+] Nginx config: OK"
systemctl restart nginx
echo "[+] Nginx reverse proxy configured"

# --- Final verification ---
echo ""
echo "[*] --- Verification ---"
echo "    Chrony: $(systemctl is-active chronyd)"
echo "    Nginx:  $(systemctl is-active nginx)"
echo "    htpasswd file: $(ls -la /etc/nginx/.htpasswd 2>/dev/null)"
echo ""
echo "[!] Client test:"
echo "    Browser: http://web.au-team.irpo"
echo "    Login:   WEBc / P@ssw0rd"
echo ""
echo "[+] ========================================"
echo "[+]  ISP MODULE 2 — COMPLETE"
echo "[+] ========================================"
