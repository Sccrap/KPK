#!/bin/bash
# ============================================================
# MODULE 3 — HQ-RTR
# Task 3: IPsec (StrongSwan) to protect GRE tunnel
# Task 4: Firewall — nftables filter (input/forward policy drop)
# Task 6: Rsyslog client — send logs to HQ-SRV
# PDF ref: Третий.pdf tasks 3, 4, 6
# NOTE: Task 3 per PDF "does not work on verification, no errors"
# ============================================================
set -e

echo "[*] ========================================"
echo "[*]  MODULE 3 — HQ-RTR"
echo "[*] ========================================"

# Detect WAN interface (saved by Module 1, or from routing table)
WAN_IFACE=""
[ -f /root/iface_vars.sh ] && source /root/iface_vars.sh && WAN_IFACE="${HQ_RTR_WAN:-}"
[ -z "$WAN_IFACE" ] && WAN_IFACE=$(ip route show default 2>/dev/null \
  | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -1)
[ -z "$WAN_IFACE" ] && WAN_IFACE=$(ip -o link show \
  | awk -F': ' '{print $2}' \
  | grep -Ev '^(lo|sit|tun|tap|veth|br-|docker|ovs|virbr|bond|dummy|vlan|hq-sw)' \
  | sort | head -1)
echo "[*] WAN interface: $WAN_IFACE"

# ============================================================
# TASK 3: IPSEC (StrongSwan) — tunnel encryption
# ============================================================
echo ""
echo "[*] [Task 3] Configuring IPsec (StrongSwan) for GRE tunnel..."
apt-get install -y strongswan

# Per PDF: ipsec.conf — protect GRE protocol between tunnel endpoints
# HQ side: left=10.5.5.1, right=10.5.5.2
cat > /etc/strongswan/ipsec.conf << 'EOF'
config setup

conn gre
  type=tunnel
  authby=secret
  left=10.5.5.1
  right=10.5.5.2
  leftprotoport=gre
  rightprotoport=gre
  auto=start
  pfs=no
EOF

# Pre-shared key
cat > /etc/strongswan/ipsec.secrets << 'EOF'
10.5.5.1 10.5.5.2 : PSK "P@ssw0rd"
EOF
chmod 600 /etc/strongswan/ipsec.secrets
echo "[+] IPsec config written"
echo "    Conn: gre, left=10.5.5.1, right=10.5.5.2, PSK=P@ssw0rd"

systemctl enable --now strongswan-starter
systemctl restart strongswan-starter
sleep 2
echo "[+] StrongSwan started"
echo "[!] Note: PDF states verification may fail despite no errors"
echo "[!] Verify: tcpdump -i ${WAN_IFACE} -n esp  (on BR-RTR)"

# ============================================================
# TASK 4: FIREWALL — nftables filter table
# ============================================================
echo ""
echo "[*] [Task 4] Configuring nftables firewall (filter table)..."

# Per PDF: add filter table with input/forward policy=drop
# Allow: established+related, specific TCP/UDP ports, ICMP, ESP, GRE, OSPF
# IMPORTANT: Add AFTER existing nat table — do not duplicate

if grep -q 'table inet filter' /etc/nftables/nftables.nft 2>/dev/null; then
  echo "[!] filter table already in nftables.nft — skipping"
else
  cat >> /etc/nftables/nftables.nft << 'EOF'

table inet filter {
  chain input {
    type filter hook input priority 0;
    policy drop;
    log prefix "Dropped Input: " level debug

    # Always allow loopback
    iif lo accept

    # Allow established/related connections
    ct state established, related accept

    # Allowed TCP services
    tcp dport {
      22,    # SSH (local)
      80,    # HTTP
      88,    # Kerberos
      139,   # NetBIOS
      389,   # LDAP
      443,   # HTTPS
      445,   # SMB
      514,   # Syslog
      631,   # CUPS
      2026,  # SSH external
      2049,  # NFS
      3015,  # custom
      8080   # HTTP alt / Docker
    } accept

    # Allowed UDP services
    udp dport {
      53,    # DNS
      88,    # Kerberos
      123,   # NTP
      137,   # NetBIOS
      500,   # IKE (IPsec)
      2049,  # NFS
      4500,  # IPsec NAT-T
      631,   # CUPS
      8080
    } accept

    # Allow ICMP (ping)
    ip protocol icmp accept

    # Allow ESP (IPsec encrypted traffic)
    ip protocol esp accept

    # Allow GRE (tunnel)
    ip protocol gre accept

    # Allow OSPF routing protocol
    ip protocol ospf accept
  }

  chain forward {
    type filter hook forward priority 0;
    policy drop;
    log prefix "Dropped forward: " level debug

    iif lo accept
    ct state established, related accept

    tcp dport {
      22, 80, 88, 139, 389, 443, 445, 514,
      631, 2026, 2049, 3015, 8080
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
    # Allow all outbound by default
    policy accept;
  }
}
EOF
  echo "[+] Filter table added to nftables.nft"
fi

systemctl restart nftables
echo "[+] nftables firewall applied"
nft list ruleset 2>/dev/null | grep -E 'table|chain|policy' | head -20 || true

# ============================================================
# TASK 6: RSYSLOG CLIENT — send logs to HQ-SRV
# ============================================================
echo ""
echo "[*] [Task 6] Configuring Rsyslog to forward logs to HQ-SRV..."
apt-get install -y rsyslog

# Per PDF: send *.warn to HQ-SRV (192.168.1.2) on TCP port 514
# @@ = TCP (@ = UDP)
cat > /etc/rsyslog.d/rsys.conf << 'EOF'
# Load input modules
module(load="imjournal")
module(load="imuxsock")

# Forward all warnings to central log server (HQ-SRV)
*.warn @@192.168.1.2:514
EOF

systemctl enable --now rsyslog
systemctl restart rsyslog
echo "[+] Rsyslog client configured -> 192.168.1.2:514 (TCP)"

# --- Final verification ---
echo ""
echo "[*] --- Verification ---"
echo "    StrongSwan: $(systemctl is-active strongswan-starter)"
echo "    nftables:   $(systemctl is-active nftables)"
echo "    Rsyslog:    $(systemctl is-active rsyslog)"
echo ""
echo "    nftables tables:"
nft list tables 2>/dev/null || true
echo ""
echo "[!] IPsec check: ipsec status"
echo "[!] ESP capture: tcpdump -i ${WAN_IFACE} -n esp (run on BR-RTR)"
echo ""
echo "[+] ========================================"
echo "[+]  HQ-RTR MODULE 3 — COMPLETE"
echo "[+] ========================================"
