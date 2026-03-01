#!/bin/bash
# ============================================================
# MODULE 2 — BR-RTR
# Задание 1: Chrony (клиент)
# Задание 7: nftables DNAT
# Туннель GRE + OSPF (FRR)
# ============================================================
set -e

echo "[*] === BR-RTR: MODULE 2 ==="

# ============================================================
# ЗАДАНИЕ 1: CHRONY — NTP-клиент
# ============================================================
echo "[*] [1] Настраиваем Chrony (клиент NTP -> ISP)..."
apt-get install -y chrony

cat > /etc/chrony.conf << 'EOF'
server 172.16.2.14 iburst prefer
EOF

systemctl enable --now chronyd
systemctl restart chronyd
sleep 2
chronyc sources
echo "[+] Chrony клиент настроен"

# ============================================================
# ЗАДАНИЕ 7: NAT + DNAT
# ============================================================
echo "[*] [7] Настраиваем nftables (NAT + DNAT)..."

cat >> /etc/nftables/nftables.nft << 'EOF'

table inet nat {
  chain postrouting {
    type nat hook postrouting priority srcnat;
    oifname "ens19" masquerade
  }
  chain prerouting {
    type nat hook prerouting priority filter;
    ip daddr 172.16.2.1 tcp dport 8080 dnat ip to 192.168.4.2:8080
    ip daddr 172.16.2.1 tcp dport 2026 dnat ip to 192.168.4.2:2026
  }
}
EOF

systemctl restart nftables
systemctl status nftables --no-pager

# ============================================================
# ТУННЕЛЬ GRE
# ============================================================
echo "[*] Настраиваем GRE-туннель..."
mkdir -p /etc/net/ifaces/tun
cat > /etc/net/ifaces/tun/options << 'EOF'
TYPE=iptun
TUNTYPE=gre
TUNLOCAL=172.16.2.1
TUNREMOTE=172.16.1.1
TUNOPTIONS='ttl 64'
HOST=ens19
EOF

echo '10.5.5.2/30' > /etc/net/ifaces/tun/ipv4address
systemctl restart network

echo "[*] Проверяем туннель..."
ping -c 2 10.5.5.1 || echo "[!] Туннель ещё не поднят — проверь HQ-RTR"

# ============================================================
# OSPF через FRR
# ============================================================
echo "[*] Настраиваем OSPF (FRR)..."
sed -i 's/ospfd=no/ospfd=yes/' /etc/frr/daemons
systemctl enable --now frr
systemctl restart frr

vtysh << 'VTYSH_EOF'
conf t
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
wr
VTYSH_EOF

echo "[+] OSPF настроен. Проверь: vtysh -c 'show ip route ospf'"
echo "[+] === BR-RTR MODULE 2: Завершено ==="
