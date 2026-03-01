#!/bin/bash
# ============================================================
# MODULE 3 — BR-RTR
# Task 3: IPsec (StrongSwan) — BR side
# Task 4: Firewall — nftables filter
# Task 6: Rsyslog client -> HQ-SRV
# PDF ref: Третий.pdf tasks 3, 4, 6
# ============================================================
set -e

echo "[*] ========================================"
echo "[*]  MODULE 3 — BR-RTR"
echo "[*] ========================================"

# ============================================================
# TASK 3: IPSEC (StrongSwan) — tunnel encryption (BR side)
# ============================================================
echo ""
echo "[*] [Task 3] Configuring IPsec (StrongSwan) for GRE tunnel..."
apt-get install -y strongswan

# Per PDF: BR side has left=10.5.5.2, right=10.5.5.1 (mirror of HQ-RTR)
cat > /etc/strongswan/ipsec.conf << 'EOF'
config setup

conn gre
  type=tunnel
  authby=secret
  left=10.5.5.2
  right=10.5.5.1
  leftprotoport=gre
  rightprotoport=gre
  auto=start
  pfs=no
EOF

cat > /etc/strongswan/ipsec.secrets << 'EOF'
10.5.5.2 10.5.5.1 : PSK "P@ssw0rd"
EOF
chmod 600 /etc/strongswan/ipsec.secrets
echo "[+] IPsec config written"
echo "    Conn: gre, left=10.5.5.2, right=10.5.5.1, PSK=P@ssw0rd"

systemctl enable --now strongswan-starter
systemctl restart strongswan-starter
sleep 2
echo "[+] StrongSwan started"

# Verify ESP packets (need tcpdump on BR side)
echo "[*] Checking for ESP packets (5 second capture)..."
timeout 5 tcpdump -i ens19 -n esp -c 3 2>/dev/null && \
  echo "[+] ESP packets detected — IPsec is working" || \
  echo "[!] No ESP packets detected — check HQ-RTR IPsec"

# ============================================================
# TASK 4: FIREWALL — nftables filter (identical to HQ-RTR)
# ============================================================
echo ""
echo "[*] [Task 4] Configuring nftables firewall (filter table)..."

if grep -q 'table inet filter' /etc/nftables/nftables.nft 2>/dev/null; then
  echo "[!] filter table already in nftables.nft — skipping"
else
  cat >> /etc/nftables/nftables.nft << 'EOF'

table inet filter {
  chain input {
    type filter hook input priority 0;
    policy drop;
    log prefix "Dropped Input: " level debug

    iif lo accept
    ct state established, related accept

    tcp dport {
      22, 80, 88, 139, 389, 443, 445,
      514, 631, 2026, 2049, 3015, 8080
    } accept

    udp dport {
      53, 88, 123, 137, 500, 2049, 4500, 631, 8080
    } accept

    ip protocol icmp accept
    ip protocol esp accept
    ip protocol gre accept
    ip protocol ospf accept
  }

  chain forward {
    type filter hook forward priority 0;
    policy drop;
    log prefix "Dropped forward: " level debug

    iif lo accept
    ct state established, related accept

    tcp dport {
      22, 80, 88, 139, 389, 443, 445,
      514, 631, 2026, 2049, 3015, 8080
    } accept

    udp dport {
      53, 88, 123, 137, 500, 2049, 4500, 631, 8080
    } accept

    ip protocol icmp accept
    ip protocol esp accept
    ip protocol gre accept
    ip protocol ospf accept
  }

  chain output {
    type filter hook output priority 0;
    policy accept;
  }
}
EOF
  echo "[+] Filter table added to nftables.nft"
fi

systemctl restart nftables
echo "[+] nftables firewall applied"
nft list tables 2>/dev/null || true

# ============================================================
# TASK 6: RSYSLOG CLIENT — send logs to HQ-SRV
# ============================================================
echo ""
echo "[*] [Task 6] Configuring Rsyslog to forward logs to HQ-SRV..."
apt-get install -y rsyslog

cat > /etc/rsyslog.d/rsys.conf << 'EOF'
# Load input modules
module(load="imjournal")
module(load="imuxsock")

# Forward all warnings to central log server (HQ-SRV via tunnel)
*.warn @@192.168.1.2:514
EOF

systemctl enable --now rsyslog
systemctl restart rsyslog
echo "[+] Rsyslog client configured -> 192.168.1.2:514 (TCP)"

# Test log forwarding
echo "[*] Sending test log message..."
logger -p user.warn "BR-RTR test message from m3_br-rtr.sh"
echo "[+] Test log sent — check /opt/br-rtr/br-rtr.log on HQ-SRV"

# --- Final verification ---
echo ""
echo "[*] --- Verification ---"
echo "    StrongSwan: $(systemctl is-active strongswan-starter)"
echo "    nftables:   $(systemctl is-active nftables)"
echo "    Rsyslog:    $(systemctl is-active rsyslog)"
echo ""
echo "[!] IPsec status: ipsec status"
echo "[!] Check HQ-SRV: tail /opt/br-rtr/br-rtr.log"
echo ""
echo "[+] ========================================"
echo "[+]  BR-RTR MODULE 3 — COMPLETE"
echo "[+] ========================================"
