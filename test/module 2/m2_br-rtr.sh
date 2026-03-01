#!/bin/bash
# ============================================================
# MODULE 2 — BR-RTR
# Task 1: Chrony — NTP client -> ISP (172.16.2.14)
# Task 7: nftables DNAT (port forwarding: 8080->BR-SRV:8080, 2026->BR-SRV:2026)
# Extra:  GRE tunnel + OSPF via FRR
# PDF ref: Второй.pdf task 1, task 7; Первый.pdf pages 8-10
# ============================================================
set -e

echo "[*] ========================================"
echo "[*]  MODULE 2 — BR-RTR"
echo "[*] ========================================"

# ============================================================
# DETECT WAN INTERFACE (carry over from Module 1)
# ============================================================
WAN_IFACE=""
if [ -f /root/iface_vars.sh ]; then
  source /root/iface_vars.sh
  WAN_IFACE="${BR_RTR_WAN:-}"
  [ -n "$WAN_IFACE" ] && echo "[+] WAN loaded from /root/iface_vars.sh: $WAN_IFACE"
fi
if [ -z "$WAN_IFACE" ]; then
  WAN_IFACE=$(ip route show default 2>/dev/null \
    | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -1)
  [ -n "$WAN_IFACE" ] && echo "[+] WAN via default route: $WAN_IFACE"
fi
if [ -z "$WAN_IFACE" ]; then
  WAN_IFACE=$(ip -o link show \
    | awk -F': ' '{print $2}' \
    | grep -Ev '^(lo|sit|tun|tap|veth|br-|docker|ovs|virbr|bond|dummy|vlan)' \
    | sort | head -1)
  echo "[!] WAN fallback (first NIC): $WAN_IFACE"
fi
echo "[*] Using WAN interface: $WAN_IFACE"

# ============================================================
# TASK 1: CHRONY — NTP CLIENT
# ============================================================
echo ""
echo "[*] [Task 1] Configuring Chrony NTP client -> ISP (172.16.2.14)..."
apt-get install -y chrony

# Per PDF: BR devices use server 172.16.2.14 (ISP ens21 address)
cat > /etc/chrony.conf << 'EOF'
# BR-RTR NTP client — sync from ISP
server 172.16.2.14 iburst prefer
EOF

systemctl enable --now chronyd
systemctl restart chronyd
sleep 3
echo "[+] Chrony NTP client configured (server: 172.16.2.14)"
chronyc sources 2>/dev/null || true

# ============================================================
# TASK 7: nftables — NAT + DNAT
# ============================================================
echo ""
echo "[*] [Task 7] Configuring nftables NAT + DNAT..."

if grep -q 'chain prerouting' /etc/nftables/nftables.nft 2>/dev/null; then
  echo "[!] prerouting chain already exists — skipping"
else
  # Per PDF: BR-RTR forwards:
  #   tcp dport 8080 -> BR-SRV:8080 (Docker web app)
  #   tcp dport 2026 -> BR-SRV:2026 (SSH)
  cat >> /etc/nftables/nftables.nft << 'EOF'

table inet nat {
  chain postrouting {
    type nat hook postrouting priority srcnat;
    oifname "${WAN_IFACE}" masquerade
  }
  chain prerouting {
    type nat hook prerouting priority filter;
    ip daddr 172.16.2.1 tcp dport 8080 dnat ip to 192.168.4.2:8080
    ip daddr 172.16.2.1 tcp dport 2026 dnat ip to 192.168.4.2:2026
  }
}
EOF
  echo "[+] DNAT rules added (WAN=$WAN_IFACE)"
fi

systemctl restart nftables
echo "[+] nftables DNAT configured"
echo "    172.16.2.1:8080 -> 192.168.4.2:8080"
echo "    172.16.2.1:2026 -> 192.168.4.2:2026"
nft list table inet nat 2>/dev/null || true

# ============================================================
# GRE TUNNEL — BR side (10.5.5.2/30)
# ============================================================
echo ""
echo "[*] Configuring GRE tunnel (Variant 1)..."
mkdir -p /etc/net/ifaces/tun

cat > /etc/net/ifaces/tun/options << EOF
TYPE=iptun
TUNTYPE=gre
TUNLOCAL=172.16.2.1
TUNREMOTE=172.16.1.1
TUNOPTIONS='ttl 64'
HOST=${WAN_IFACE}
EOF

echo '10.5.5.2/30' > /etc/net/ifaces/tun/ipv4address
echo "[+] GRE tunnel config written"
echo "    Local:  172.16.2.1 (BR-RTR ens19)"
echo "    Remote: 172.16.1.1 (HQ-RTR ens19)"
echo "    Tunnel IP: 10.5.5.2/30"

systemctl restart network
sleep 2
echo "[*] Testing tunnel to HQ-RTR (10.5.5.1)..."
if ping -c 2 -W 3 10.5.5.1 &>/dev/null; then
  echo "[+] GRE tunnel: OK"
else
  echo "[!] Tunnel unreachable — ensure HQ-RTR is configured first"
fi

# ============================================================
# OSPF via FRR
# ============================================================
echo ""
echo "[*] Configuring OSPF routing (FRR)..."

if [ -f /etc/frr/daemons ]; then
  sed -i 's/^ospfd=no/ospfd=yes/' /etc/frr/daemons
else
  apt-get install -y frr
  sed -i 's/^ospfd=no/ospfd=yes/' /etc/frr/daemons
fi

systemctl enable --now frr
systemctl restart frr
sleep 2

# Per PDF: BR-RTR advertises 10.5.5.0/30 and 192.168.4.0/28
vtysh << 'VTYSH_EOF'
configure terminal
router ospf
 passive-interface default
 network 10.5.5.0/30 area 0
 network 192.168.4.0/28 area 0
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

echo "[+] OSPF configured"
echo "    Networks: 10.5.5.0/30, 192.168.4.0/28"
echo "    Area 0 auth key: P@ssw0rd"

echo ""
echo "[*] --- Verification ---"
echo "    Chrony:   $(systemctl is-active chronyd)"
echo "    nftables: $(systemctl is-active nftables)"
echo "    FRR:      $(systemctl is-active frr)"
vtysh -c 'show ip route ospf' 2>/dev/null || true
echo ""
echo "[+] ========================================"
echo "[+]  BR-RTR MODULE 2 — COMPLETE"
echo "[!]  Check OSPF: vtysh -c 'show ip route ospf'"
echo "[!]  Check tunnel: ping 10.5.5.1"
echo "[+] ========================================"
