#!/bin/bash
###############################################################################
# m3_hq-rtr.sh — HQ-RTR configuration (Module 3, ALT Linux)
# Tasks: IPSec GRE tunnel · nftables firewall · Rsyslog client
###############################################################################
set -e

# ======================== VARIABLES ==========================================
# IPSec
LOCAL_IP="10.5.5.1"
REMOTE_IP="10.5.5.2"
IPSEC_PSK="P@ssw0rd"

# Rsyslog
HQ_SRV_IP="192.168.0.1"

NFTABLES_CONF="/etc/nftables/nftables.nft"

# =============================================================================
echo "=== [0/3] Installing required software ==="
apt-get update -y
apt-get install -y strongswan rsyslog
echo "  Software installed"

# =============================================================================
echo "=== [1/3] Configuring IPSec GRE tunnel ==="

cp /etc/strongswan/ipsec.conf /etc/strongswan/ipsec.conf.bak 2>/dev/null || true

cat >> /etc/strongswan/ipsec.conf <<EOF

conn gre
    type=tunnel
    authby=secret
    left=${LOCAL_IP}
    right=${REMOTE_IP}
    leftprotoport=gre
    rightprotoport=gre
    auto=start
    pfs=no
EOF
echo "  ipsec.conf configured"

grep -q "${LOCAL_IP} ${REMOTE_IP}" /etc/strongswan/ipsec.secrets 2>/dev/null \
    || echo "${LOCAL_IP} ${REMOTE_IP} : PSK \"${IPSEC_PSK}\"" >> /etc/strongswan/ipsec.secrets
echo "  PSK added"

systemctl enable --now strongswan-starter.service
systemctl restart strongswan-starter.service
echo "  StrongSwan started"

# =============================================================================
echo "=== [2/3] Configuring nftables firewall ==="

cp "${NFTABLES_CONF}" "${NFTABLES_CONF}.bak" 2>/dev/null || true

cat >> "${NFTABLES_CONF}" <<'NFTCONF'
#!/usr/sbin/nft -f

table inet filter {

    chain input {
        type filter hook input priority 0; policy drop;
        log prefix "Dropped Input: " level debug

        iif lo accept
        ct state established, related accept

        tcp dport { 22, 514, 53, 80, 443, 3015, 445, 139, 88, 2026, 8080, 2049, 389, 631 } accept
        udp dport { 53, 123, 500, 4500, 88, 137, 8080, 2049, 631 } accept

        ip protocol icmp accept
        ip protocol esp accept
        ip protocol gre accept
        ip protocol ospf accept
    }

    chain forward {
        type filter hook forward priority 0; policy drop;
        log prefix "Dropped forward: " level debug

        iif lo accept
        ct state established, related accept

        tcp dport { 22, 514, 53, 80, 443, 3015, 445, 139, 88, 2026, 8080, 2049, 389, 631 } accept
        udp dport { 53, 123, 500, 4500, 88, 137, 8080, 2049, 631 } accept

        ip protocol icmp accept
        ip protocol esp accept
        ip protocol gre accept
        ip protocol ospf accept
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}
NFTCONF

nft -f "${NFTABLES_CONF}" && echo "  Firewall rules applied" \
    || echo "  ERROR applying nftables rules!"
systemctl restart nftables
systemctl enable nftables
echo "  nftables firewall configured"

# =============================================================================
echo "=== [3/3] Configuring Rsyslog client ==="

mkdir -p /etc/rsyslog.d/

cat > /etc/rsyslog.d/rsys.conf <<EOF
# Rsyslog client config — HQ-RTR
module(load="imjournal")
module(load="imuxsock")

# Forward WARNING+ to HQ-SRV via TCP
*.warn @@${HQ_SRV_IP}:514
EOF
echo "  rsys.conf: forwarding to $HQ_SRV_IP:514"

systemctl enable --now rsyslog
systemctl restart rsyslog
echo "  Rsyslog client started"

echo ""
echo "=== Verification ==="
sleep 2
ipsec status || true
echo ""
nft list ruleset | head -30
echo ""
systemctl is-active rsyslog && echo "  rsyslog: active" || echo "  rsyslog: INACTIVE"
echo ""
echo "=== HQ-RTR (Module 3) configured ==="
echo "Test rsyslog: logger -p warn 'TEST from hq-rtr'"
echo "Capture ESP traffic: tcpdump -i ens18 -n -p esp"
