#!/bin/bash
# ============================================================
# MODULE 3 — HQ-SRV
# Task 2: Certificate Authority (GOST2012 TLS)
# Task 5: Print server CUPS
# Task 6: Centralized logging — Rsyslog server + logrotate
# Task 7: Monitoring — Prometheus + Grafana
# Task 9: Fail2ban (SSH brute-force protection)
# PDF ref: Третий.pdf tasks 2, 5, 6, 7, 9
# ============================================================
set -e

echo "[*] ========================================"
echo "[*]  MODULE 3 — HQ-SRV"
echo "[*] ========================================"

# ============================================================
# TASK 2: CERTIFICATE AUTHORITY (GOST2012)
# ============================================================
echo ""
echo "[*] [Task 2] Setting up Certificate Authority (GOST2012)..."
apt-get install -y openssl openssl-gost-engine

# Enable GOST engine in OpenSSL
control openssl-gost enabled 2>/dev/null || true
echo "[+] OpenSSL GOST engine enabled"

# Create PKI directory structure
echo "[*] Creating PKI directory structure..."
mkdir -p /etc/pki/CA/private
mkdir -p /etc/pki/CA/certs
mkdir -p /etc/pki/CA/newcerts
mkdir -p /etc/pki/CA/crl
touch /etc/pki/CA/index.txt
echo 1000 > /etc/pki/CA/serial
chmod 700 /etc/pki/CA/private
echo "[+] PKI dirs: /etc/pki/CA/{private,certs,newcerts,crl}"

# Generate CA private key (GOST2012_256, paramset TCB)
echo "[*] Generating CA private key (GOST2012_256 TCB)..."
openssl genkey \
  -algorithm gost2012_256 \
  -pkeyopt paramset:TCB \
  -out /etc/pki/CA/private/ca.key
echo "[+] CA key: /etc/pki/CA/private/ca.key"

# Generate self-signed CA certificate (10 years)
# Per PDF: subj = /CN=AU-TEAM Root CA (no country/org fields per instructor note)
echo "[*] Generating self-signed CA certificate (3650 days)..."
openssl req -x509 -new \
  -md_gost12_256 \
  -key /etc/pki/CA/private/ca.key \
  -out /etc/pki/CA/certs/ca.crt \
  -days 3650 \
  -subj "/CN=AU-TEAM Root CA"
echo "[+] CA cert: /etc/pki/CA/certs/ca.crt"

# Generate keys and sign certificates for web and docker sites
for SITE in web.au-team.irpo docker.au-team.irpo; do
  echo "[*] Generating key for ${SITE}..."
  openssl genpkey \
    -algorithm gost2012_256 \
    -pkeyopt paramset:A \
    -out /etc/pki/CA/private/${SITE}.key

  echo "[*] Generating CSR for ${SITE}..."
  openssl req -new \
    -md_gost12_256 \
    -key /etc/pki/CA/private/${SITE}.key \
    -out /etc/pki/CA/newcerts/${SITE}.csr \
    -subj "/CN=${SITE}"

  echo "[*] Signing certificate for ${SITE} (30 days)..."
  openssl x509 -req \
    -in /etc/pki/CA/newcerts/${SITE}.csr \
    -CA /etc/pki/CA/certs/ca.crt \
    -CAkey /etc/pki/CA/private/ca.key \
    -CAcreateserial \
    -out /etc/pki/CA/certs/${SITE}.crt \
    -days 30

  echo "[+] ${SITE}: key and certificate created"
done

# Copy certificates to NFS share (HQ-CLI will trust CA from there)
if mountpoint -q /raid; then
  mkdir -p /raid/nfs
  cp /etc/pki/CA/certs/ca.crt                   /raid/nfs/
  cp /etc/pki/CA/certs/web.au-team.irpo.crt      /raid/nfs/
  cp /etc/pki/CA/certs/docker.au-team.irpo.crt   /raid/nfs/
  cp /etc/pki/CA/private/web.au-team.irpo.key    /raid/nfs/
  cp /etc/pki/CA/private/docker.au-team.irpo.key /raid/nfs/
  echo "[+] Certificates copied to /raid/nfs/"
else
  echo "[!] /raid not mounted — copy certs manually to NFS share"
fi

echo ""
echo "[!] NEXT STEPS after CA setup:"
echo "  On HQ-CLI (client trust CA):"
echo "    cp /mnt/nfs/ca.crt /etc/pki/ca-trust/source/anchors/"
echo "    update-ca-trust"
echo ""
echo "  On ISP (Nginx SSL — see Task 4 in Module 2):"
echo "    scp -P 2026 sshuser@172.16.1.1:/raid/nfs/web.au-team.irpo.crt /etc/nginx/ssl/"
echo "    scp -P 2026 sshuser@172.16.1.1:/raid/nfs/web.au-team.irpo.key /etc/nginx/ssl/private/"

# ============================================================
# TASK 5: CUPS PRINT SERVER
# ============================================================
echo ""
echo "[*] [Task 5] Configuring CUPS print server..."
apt-get install -y cups cups-pdf

CUPS_CFG=/etc/cups/cupsd.conf

# Per PDF: change Listen address to allow remote access
sed -i 's|^Listen localhost.*|Listen hq-srv.au-team.irpo:631|' "$CUPS_CFG" || \
  sed -i 's|^Listen .*:631|Listen hq-srv.au-team.irpo:631|'     "$CUPS_CFG"
echo "[+] CUPS Listen set to hq-srv.au-team.irpo:631"

# Per PDF: comment out 'Order allow,deny' in 3 Location blocks, add 'Allow any'
python3 << 'PYEOF'
import re

with open('/etc/cups/cupsd.conf', 'r') as f:
    content = f.read()

# Replace 'Order allow,deny' with 'Allow any' (comment the deny, add allow)
content = re.sub(r'(\s+)Order allow,deny', r'\1#Order allow,deny\n\1Allow any', content)
# Also handle 'Order Deny,Allow' variant
content = re.sub(r'(\s+)Order Deny,Allow', r'\1#Order Deny,Allow\n\1Allow any', content)

with open('/etc/cups/cupsd.conf', 'w') as f:
    f.write(content)

print("[+] cupsd.conf: Order allow,deny replaced with Allow any")
PYEOF

systemctl enable --now cups
systemctl restart cups
echo "[+] CUPS started at https://hq-srv.au-team.irpo:631"
echo "[!] Add printer via browser:"
echo "    URL:  https://hq-srv.au-team.irpo:631"
echo "    Auth: root / toor"
echo "    Administration -> Add Printer -> CUPS-PDF -> Continue"
echo "    Check 'Share this printer' -> Continue"
echo "    Make: Generic -> CUPS-PDF -> Add Printer"

# ============================================================
# TASK 6: RSYSLOG — CENTRALIZED LOGGING SERVER
# ============================================================
echo ""
echo "[*] [Task 6] Configuring Rsyslog as central log server..."
apt-get install -y rsyslog

# Per PDF: enable imjournal, imuxsock, imklog, immark, imtcp (port 514)
# Filter incoming logs by source IP into separate files
cat > /etc/rsyslog.d/rsys.conf << 'EOF'
# Load input modules
module(load="imjournal")
module(load="imuxsock")
module(load="imklog")
module(load="immark")

# Accept TCP syslog on port 514
module(load="imtcp")
input(type="imtcp" port="514")

# Local auth log
authpriv.* /var/log/auth.log

# Remote host log routing by source IP
# HQ-RTR
if $fromhost-ip contains '192.168.0.62' then {
  *.warn /opt/hq-rtr/hq-rtr.log
}
# BR-RTR (via tunnel IP 10.5.5.2)
if $fromhost-ip contains '10.5.5.2' then {
  *.warn /opt/br-rtr/br-rtr.log
}
# BR-SRV
if $fromhost-ip contains '192.168.1.1' then {
  *.warn /opt/br-srv/br-srv.log
}
EOF

# Create log directories and files
mkdir -p /opt/hq-rtr /opt/br-rtr /opt/br-srv
touch /opt/hq-rtr/hq-rtr.log
touch /opt/br-rtr/br-rtr.log
touch /opt/br-srv/br-srv.log
chmod 640 /opt/{hq-rtr,br-rtr,br-srv}/*.log
echo "[+] Log directories created: /opt/{hq-rtr,br-rtr,br-srv}/"

systemctl enable --now rsyslog
systemctl restart rsyslog
echo "[+] Rsyslog server started (TCP port 514)"

# Logrotate for remote logs
# Per PDF: rotate when file reaches 10M, compress
cat >> /etc/logrotate.conf << 'EOF'

/opt/hq-rtr/*.log
/opt/br-rtr/*.log
/opt/br-srv/*.log
{
  minsize 10M
  compress
}
EOF
echo "[+] logrotate config added for /opt/ log files"

systemctl enable logrotate 2>/dev/null || true
logrotate -d /etc/logrotate.conf 2>&1 | grep -E 'error|warn' || \
  echo "[+] logrotate config valid"

# Verify log structure
echo "[*] Log directory tree:"
find /opt/ -type f 2>/dev/null

# ============================================================
# TASK 7: MONITORING — PROMETHEUS + GRAFANA
# ============================================================
echo ""
echo "[*] [Task 7] Configuring Prometheus + Grafana monitoring..."
apt-get install -y prometheus grafana prometheus-node_exporter 2>/dev/null || \
  echo "[!] Some packages unavailable — check repo configuration"

# Prometheus config — scrape HQ-SRV and BR-SRV node_exporters
cat > /etc/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval:     15s
  evaluation_interval: 15s
  external_labels:
    monitor: 'example'

alerting:
  alertmanagers:
    - static_configs:
      - targets: ['localhost:9093']

scrape_configs:
  # Prometheus self-monitoring
  - job_name: 'prometheus'
    scrape_interval: 5s
    scrape_timeout: 5s
    static_configs:
      - targets: ['localhost:9090']

  # Node exporters on HQ-SRV and BR-SRV
  - job_name: 'node'
    static_configs:
      - targets: ['hq-srv:9100', 'br-srv:9100']
EOF
echo "[+] prometheus.yml configured with node_exporter targets"

systemctl enable --now prometheus
systemctl enable --now prometheus-node_exporter
systemctl enable --now grafana-server
echo "[+] Prometheus, node_exporter, and Grafana started"

echo ""
echo "[!] Grafana setup (client browser: http://hq-srv:3000):"
echo "    Login: admin / admin -> change to P@ssw0rd"
echo "    Profile (top right) -> Preferences -> Language -> Russian"
echo "    Left: Grafana icon -> Connections -> Data sources"
echo "    Add data source -> Prometheus"
echo "    Connection URL: http://localhost:9090"
echo "    Save & Test"
echo "    Left: Grafana icon -> Dashboards -> New -> Import"
echo "    Dashboard ID: 11074 -> Load"
echo "    DS_VICTORIAMETRICS -> prometheus -> Import"
echo "    Edit dashboard -> Title: 'Server Information' (or per task spec) -> Save"

# ============================================================
# TASK 9: FAIL2BAN
# ============================================================
echo ""
echo "[*] [Task 9] Configuring Fail2ban..."
apt-get install -y fail2ban python3-module-systemd 2>/dev/null || \
  apt-get install -y fail2ban

# Per PDF: protect SSH (port 2026 externally), ban after 2 attempts, 1 min ban
# Note: logpath points to auth.log which we set up in Rsyslog above
cat > /etc/fail2ban/jail.local << 'EOF'
[sshd]
enabled  = true
logpath  = /var/log/auth.log
backend  = systemd
filter   = sshd
action   = nftables[name=ssh, port=2026, protocol=tcp]
maxretry = 2
bantime  = 1m
EOF

systemctl enable --now fail2ban
sleep 2
systemctl status fail2ban --no-pager | head -5

echo "[+] Fail2ban configured"
echo "[!] Test: try SSH with wrong password 2 times from another host"
echo "[!] Check: fail2ban-client status sshd"

# --- Final verification ---
echo ""
echo "[*] --- Verification ---"
echo "    CUPS:         $(systemctl is-active cups)"
echo "    Rsyslog:      $(systemctl is-active rsyslog)"
echo "    Prometheus:   $(systemctl is-active prometheus)"
echo "    node_exporter:$(systemctl is-active prometheus-node_exporter)"
echo "    Grafana:      $(systemctl is-active grafana-server)"
echo "    Fail2ban:     $(systemctl is-active fail2ban)"
echo "    CA cert:      $(ls -la /etc/pki/CA/certs/ 2>/dev/null)"
echo ""
echo "[+] ========================================"
echo "[+]  HQ-SRV MODULE 3 — COMPLETE"
echo "[+] ========================================"
