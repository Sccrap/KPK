#!/bin/bash
###############################################################################
# m3_hq-srv.sh — HQ-SRV configuration (Module 3, ALT Linux)
# Tasks: CA setup (GOST) · CUPS print server · Rsyslog server ·
#        Prometheus + Grafana · Fail2ban
###############################################################################
set -e

# ======================== VARIABLES ==========================================
DOMAIN="au-team.irpo"
HQ_SRV_IP="192.168.0.1"
HQ_RTR_IP="192.168.0.62"
BR_RTR_IP="10.5.5.2"
BR_SRV_IP="192.168.1.1"
CUPS_HOSTNAME="hq-srv.au-team.irpo"

# =============================================================================
echo "=== [0/5] Installing required software ==="
apt-get update -y
apt-get install -y openssl-gost-engine cups rsyslog \
    prometheus prometheus-node_exporter grafana-server \
    python3-module-systemd fail2ban
echo "  Software installed"

# =============================================================================
echo "=== [1/5] Configuring Certificate Authority (GOST 2012) ==="

control openssl-gost enabled 2>/dev/null || true

mkdir -p /etc/pki/CA/{private,certs,newcerts,crl}
touch /etc/pki/CA/index.txt
echo 1000 > /etc/pki/CA/serial
chmod 700 /etc/pki/CA/private
echo "  PKI structure /etc/pki/CA created"

openssl genkey \
    -algorithm gost2012_256 \
    -pkeyopt paramset:TCB \
    -out /etc/pki/CA/private/ca.key
echo "  CA key (GOST 2012-256) created"

openssl req -x509 -new \
    -md_gost12_256 \
    -key /etc/pki/CA/private/ca.key \
    -out /etc/pki/CA/certs/ca.crt \
    -days 3650 \
    -subj "/C=RU/ST=Moscow/L=Moscow/O=AU-TEAM/OU=WEB/CN=AU-TEAM Root CA"
echo "  CA certificate created (10 years)"

openssl genpkey -algorithm gost2012_256 -pkeyopt paramset:A \
    -out /etc/pki/CA/private/web.$DOMAIN.key
openssl genpkey -algorithm gost2012_256 -pkeyopt paramset:A \
    -out /etc/pki/CA/private/docker.$DOMAIN.key
echo "  Keys for web.$DOMAIN and docker.$DOMAIN created"

openssl req -new -md_gost12_256 \
    -key /etc/pki/CA/private/web.$DOMAIN.key \
    -out /etc/pki/CA/newcerts/web.$DOMAIN.csr \
    -subj "/CN=web.$DOMAIN"
openssl req -new -md_gost12_256 \
    -key /etc/pki/CA/private/docker.$DOMAIN.key \
    -out /etc/pki/CA/newcerts/docker.$DOMAIN.csr \
    -subj "/CN=docker.$DOMAIN"

openssl x509 -req \
    -in /etc/pki/CA/newcerts/web.$DOMAIN.csr \
    -CA /etc/pki/CA/certs/ca.crt \
    -CAkey /etc/pki/CA/private/ca.key \
    -CAcreateserial \
    -out /etc/pki/CA/certs/web.$DOMAIN.crt \
    -days 30
openssl x509 -req \
    -in /etc/pki/CA/newcerts/docker.$DOMAIN.csr \
    -CA /etc/pki/CA/certs/ca.crt \
    -CAkey /etc/pki/CA/private/ca.key \
    -CAcreateserial \
    -out /etc/pki/CA/certs/docker.$DOMAIN.crt \
    -days 30
echo "  Certificates for web.$DOMAIN and docker.$DOMAIN signed (30 days)"

mkdir -p /raid/nfs/
cp /etc/pki/CA/certs/ca.crt                   /raid/nfs/
cp /etc/pki/CA/certs/web.$DOMAIN.crt          /raid/nfs/
cp /etc/pki/CA/certs/docker.$DOMAIN.crt       /raid/nfs/
cp /etc/pki/CA/private/web.$DOMAIN.key        /raid/nfs/
cp /etc/pki/CA/private/docker.$DOMAIN.key     /raid/nfs/
echo "  Certs copied to /raid/nfs/"
echo "  Next step: run m3_isp.sh on ISP, m3_hq-cli.sh on HQ-CLI"

# =============================================================================
echo "=== [2/5] Configuring CUPS print server ==="

CUPS_CONF="/etc/cups/cupsd.conf"
cp "$CUPS_CONF" "${CUPS_CONF}.bak"
sed -i "s|Listen localhost:631|Listen ${CUPS_HOSTNAME}:631|g" "$CUPS_CONF"
sed -i "s|Listen localhost|Listen ${CUPS_HOSTNAME}:631|g"     "$CUPS_CONF"

python3 - <<'PYEOF'
import re

with open("/etc/cups/cupsd.conf", "r") as f:
    content = f.read()

def patch_location(block):
    block = re.sub(r'(\s*)(Order allow,deny)', r'\1#Order allow,deny', block)
    if "Allow any" not in block:
        block = re.sub(r'(#Order allow,deny)', r'\1\n  Allow any', block)
    return block

content = re.sub(
    r'(<Location.*?>.*?</Location>)',
    lambda m: patch_location(m.group(0)),
    content,
    flags=re.DOTALL
)

with open("/etc/cups/cupsd.conf", "w") as f:
    f.write(content)
print("  cupsd.conf updated")
PYEOF

systemctl restart cups
systemctl enable cups
echo "  CUPS configured"
echo "  Web UI: https://${CUPS_HOSTNAME}:631"
echo "  Add printer: Printers -> Add -> CUPS-PDF -> Generic CUPS-PDF"

# =============================================================================
echo "=== [3/5] Configuring Rsyslog server ==="

mkdir -p /opt/hq-rtr /opt/br-rtr /opt/br-srv
touch /opt/hq-rtr/hq-rtr.log /opt/br-rtr/br-rtr.log /opt/br-srv/br-srv.log

cp /etc/rsyslog.d/00_common.conf /etc/rsyslog.d/00_common.conf.bak 2>/dev/null || true
sed -i 's|^#module(load="imjournal")|module(load="imjournal")|g' /etc/rsyslog.d/00_common.conf
sed -i 's|^#module(load="imuxsock")|module(load="imuxsock")|g'   /etc/rsyslog.d/00_common.conf

cat > /etc/rsyslog.d/rsys.conf <<EOF
# Rsyslog server config (HQ-SRV)
module(load="imjournal")
module(load="imuxsock")
module(load="imklog")
module(load="immark")

module(load="imtcp")
input(type="imtcp" port="514")

authpriv.* /var/log/auth.log

if \$fromhost-ip contains '${HQ_RTR_IP}' then {
    *.warn /opt/hq-rtr/hq-rtr.log
    stop
}

if \$fromhost-ip contains '${BR_RTR_IP}' then {
    *.warn /opt/br-rtr/br-rtr.log
    stop
}

if \$fromhost-ip contains '${BR_SRV_IP}' then {
    *.warn /opt/br-srv/br-srv.log
    stop
}
EOF
echo "  rsys.conf created"

grep -q "/opt/hq-rtr" /etc/logrotate.conf || cat >> /etc/logrotate.conf <<'LOGROTATE'

/opt/hq-rtr/*.log
/opt/br-rtr/*.log
/opt/br-srv/*.log
{
    minsize 10M
    compress
    rotate 7
    daily
    missingok
    notifempty
}
LOGROTATE
echo "  logrotate configured"

systemctl enable --now rsyslog
systemctl restart rsyslog
echo "  Rsyslog server started (TCP:514)"

# =============================================================================
echo "=== [4/5] Configuring monitoring (Prometheus + Grafana) ==="

cp /etc/prometheus/prometheus.yml /etc/prometheus/prometheus.yml.bak 2>/dev/null || true

cat > /etc/prometheus/prometheus.yml <<'PROMCONF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['localhost:9093']

rule_files:

scrape_configs:
  - job_name: 'prometheus'
    scrape_interval: 5s
    scrape_timeout: 5s
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node'
    static_configs:
      - targets: ['hq-srv:9100', 'br-srv:9100']
PROMCONF

systemctl enable --now grafana-server
systemctl enable --now prometheus
systemctl enable --now prometheus-node_exporter
systemctl restart grafana-server
systemctl restart prometheus
systemctl restart prometheus-node_exporter
echo "  Prometheus + Grafana + node_exporter started"
echo ""
echo "  Grafana: http://hq-srv:3000  (login: admin / admin -> new password: P@ssw0rd)"
echo "  Add data source: Prometheus -> http://localhost:9090"
echo "  Import dashboard ID: 11074 -> rename to 'Server information'"

# =============================================================================
echo "=== [5/5] Configuring Fail2ban ==="

touch /var/log/auth.log
grep -q "authpriv" /etc/rsyslog.d/rsys.conf 2>/dev/null \
    || echo 'authpriv.* /var/log/auth.log' >> /etc/rsyslog.d/rsys.conf
systemctl restart rsyslog 2>/dev/null || true

cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.conf.bak 2>/dev/null || true

cat > /etc/fail2ban/jail.local <<'JAIL'
[DEFAULT]
bantime  = 1m
findtime = 5m
maxretry = 2

[sshd]
enabled  = true
filter   = sshd
logpath  = /var/log/auth.log
backend  = systemd
action   = nftables[name=ssh, port=2026, protocol=tcp]
maxretry = 2
bantime  = 1m
JAIL

systemctl enable --now fail2ban
systemctl restart fail2ban
sleep 2
echo "  Fail2ban started (SSH port 2026, maxretry=2, bantime=1m)"

echo ""
echo "=== Verification ==="
for svc in cups rsyslog prometheus grafana-server prometheus-node_exporter fail2ban; do
    STATUS=$(systemctl is-active "$svc" 2>/dev/null)
    echo "  $svc: $STATUS"
done
echo ""
echo "  Test fail2ban: fail2ban-client status sshd"
echo "  Test rsyslog:  logger -p warn 'TEST from hq-srv'"
echo ""
echo "=== HQ-SRV (Module 3) configured ==="
