#!/bin/bash
# ============================================================
# MODULE 2 — HQ-RTR
# Task 1: Chrony — NTP client -> ISP (172.16.1.14)
# Task 7: nftables DNAT (port forwarding: 8080->HQ-SRV:80, 2026->HQ-SRV:2026)
# Extra:  GRE tunnel + OSPF via FRR (inter-site routing)
# PDF ref: Второй.pdf task 1, task 7; Первый.pdf pages 8-10 (tunnel/OSPF)
# ============================================================
set -e

echo "[*] ========================================"
echo "[*]  MODULE 2 — HQ-RTR"
echo "[*] ========================================"

# ============================================================
# DETECT WAN INTERFACE (carry over from Module 1)
# ============================================================
WAN_IFACE=""
# Load saved vars if Module 1 was run on this host
if [ -f /root/iface_vars.sh ]; then
  source /root/iface_vars.sh
  WAN_IFACE="${HQ_RTR_WAN:-}"
  [ -n "$WAN_IFACE" ] && echo "[+] WAN loaded from /root/iface_vars.sh: $WAN_IFACE"
fi
# Fallback: read from active default route
if [ -z "$WAN_IFACE" ]; then
  WAN_IFACE=$(ip route show default 2>/dev/null \
    | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -1)
  [ -n "$WAN_IFACE" ] && echo "[+] WAN via default route: $WAN_IFACE"
fi
# Final fallback: first physical NIC
if [ -z "$WAN_IFACE" ]; then
  WAN_IFACE=$(ip -o link show \
    | awk -F': ' '{print $2}' \
    | grep -Ev '^(lo|sit|tun|tap|veth|br-|docker|ovs|virbr|bond|dummy|vlan|hq-sw)' \
    | sort | head -1)
  echo "[!] WAN fallback (first NIC): $WAN_IFACE"
fi
echo "[*] Using WAN interface: $WAN_IFACE"

# ============================================================
# TASK 1: CHRONY — NTP CLIENT
# ============================================================
echo ""
echo "[*] [Task 1] Configuring Chrony NTP client -> ISP (172.16.1.14)..."
apt-get install -y chrony

# Per PDF: HQ devices use server 172.16.1.14 (ISP ens20 address)
cat > /etc/chrony.conf << 'EOF'
# HQ-RTR NTP client — sync from ISP
server 172.16.1.14 iburst prefer
EOF

systemctl enable --now chronyd
systemctl restart chronyd
sleep 3
echo "[+] Chrony NTP client configured (server: 172.16.1.14)"
chronyc sources 2>/dev/null || true

# ============================================================
# TASK 7: nftables — NAT + DNAT (port forwarding)
# ============================================================
echo ""
echo "[*] [Task 7] Configuring nftables NAT + DNAT..."

# Remove duplicate nat table if already added (idempotent)
if grep -q 'chain prerouting' /etc/nftables/nftables.nft 2>/dev/null; then
  echo "[!] prerouting chain already exists in nftables.nft — skipping"
else
  # Append DNAT rules to existing nat table or create new one
  # Per PDF: HQ-RTR forwards:
  #   tcp dport 8080 -> HQ-SRV:80   (Apache web)
  #   tcp dport 2026 -> HQ-SRV:2026 (SSH with different external port)
  cat >> /etc/nftables/nftables.nft << 'EOF'

table inet nat {
  chain postrouting {
    type nat hook postrouting priority srcnat;
    oifname "${WAN_IFACE}" masquerade
  }
  chain prerouting {
    type nat hook prerouting priority filter;
    ip daddr 172.16.1.1 tcp dport 8080 dnat ip to 192.168.1.2:80
    ip daddr 172.16.1.1 tcp dport 2026 dnat ip to 192.168.1.2:2026
  }
}
EOF
  echo "[+] DNAT rules added (WAN=$WAN_IFACE)"
fi

systemctl restart nftables
echo "[+] nftables DNAT configured"
echo "    172.16.1.1:8080 -> 192.168.1.2:80"
echo "    172.16.1.1:2026 -> 192.168.1.2:2026"
nft list table inet nat 2>/dev/null || true

# ============================================================
# GRE TUNNEL — HQ side (10.5.5.1/30)
# ============================================================
echo ""
echo "[*] Configuring GRE tunnel (Variant 1 — /etc/net/ifaces/tun)..."

# Per PDF Variant 1: create iface dir with options file
mkdir -p /etc/net/ifaces/tun

cat > /etc/net/ifaces/tun/options << EOF
TYPE=iptun
TUNTYPE=gre
TUNLOCAL=172.16.1.1
TUNREMOTE=172.16.2.1
TUNOPTIONS='ttl 64'
HOST=${WAN_IFACE}
EOF

echo '10.5.5.1/30' > /etc/net/ifaces/tun/ipv4address
echo "[+] GRE tunnel config written"
echo "    Local:  172.16.1.1 (HQ-RTR ens19)"
echo "    Remote: 172.16.2.1 (BR-RTR ens19)"
echo "    Tunnel IP: 10.5.5.1/30"

systemctl restart network
sleep 2
echo "[*] Testing tunnel to BR-RTR (10.5.5.2)..."
if ping -c 2 -W 3 10.5.5.2 &>/dev/null; then
  echo "[+] GRE tunnel: OK"
else
  echo "[!] Tunnel unreachable — ensure BR-RTR is configured first"
fi

# ============================================================
# OSPF via FRR
# ============================================================
echo ""
echo "[*] Configuring OSPF routing (FRR)..."

# Enable ospfd daemon
if [ -f /etc/frr/daemons ]; then
  sed -i 's/^ospfd=no/ospfd=yes/' /etc/frr/daemons
  echo "[+] ospfd enabled in /etc/frr/daemons"
else
  echo "[!] /etc/frr/daemons not found — install frr first"
  apt-get install -y frr
  sed -i 's/^ospfd=no/ospfd=yes/' /etc/frr/daemons
fi

systemctl enable --now frr
systemctl restart frr
sleep 2

# Configure OSPF via vtysh
# Per PDF: 
#   - passive-interface default (all interfaces passive by default)
#   - advertise HQ subnets + tunnel network in area 0
#   - area 0 authentication
#   - tun interface: disable broadcast mode, enable OSPF, set auth key
vtysh << 'VTYSH_EOF'
configure terminal
router ospf
 passive-interface default
 network 10.5.5.0/30 area 0
 network 192.168.1.0/27 area 0
 network 192.168.2.0/28 area 0
 network 192.168.3.0/29 area 0
 area 0 authentication
exit
interface tun
 no ospf network broadcast
 no ip ospf passive
 ip ospf authentication
 ip ospf authentication-key P@ssw0rd
exit
exit
write memory
VTYSH_EOF

echo "[+] OSPF configured via vtysh"
echo "    Networks: 10.5.5.0/30, 192.168.1.0/27, 192.168.2.0/28, 192.168.3.0/29"
echo "    Area 0 authentication key: P@ssw0rd"

echo ""
echo "[*] --- Verification ---"
echo "    Chrony:   $(systemctl is-active chronyd)"
echo "    nftables: $(systemctl is-active nftables)"
echo "    FRR:      $(systemctl is-active frr)"
echo "    OSPF routes (after BR-RTR connects):"
vtysh -c 'show ip route ospf' 2>/dev/null || true
echo ""
echo "[+] ========================================"
echo "[+]  HQ-RTR MODULE 2 — COMPLETE"
echo "[!]  Check OSPF: vtysh -c 'show ip route ospf'"
echo "[+] ========================================"
