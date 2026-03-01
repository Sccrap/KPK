#!/bin/bash
# ============================================================
# MODULE 3 — HQ-RTR
# Задание 3: IPsec (StrongSwan) для GRE-туннеля
# Задание 4: Межсетевой экран (nftables filter)
# Задание 6: Rsyslog (клиент -> HQ-SRV)
# ============================================================
set -e

echo "[*] === HQ-RTR: MODULE 3 ==="

# ============================================================
# ЗАДАНИЕ 3: IPSEC (StrongSwan)
# ============================================================
echo "[*] [3] Настраиваем IPsec (StrongSwan)..."
apt-get install -y strongswan

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

cat > /etc/strongswan/ipsec.secrets << 'EOF'
10.5.5.1 10.5.5.2 : PSK "P@ssw0rd"
EOF

systemctl enable --now strongswan-starter
systemctl restart strongswan-starter
echo "[+] IPsec настроен. Проверь: tcpdump -i ens19 -n -p esp"

# ============================================================
# ЗАДАНИЕ 4: МЕЖСЕТЕВОЙ ЭКРАН (nftables filter)
# ============================================================
echo "[*] [4] Настраиваем nftables firewall (filter)..."

# Добавляем таблицу filter в конфиг
cat >> /etc/nftables/nftables.nft << 'EOF'

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
EOF

systemctl restart nftables
systemctl status nftables --no-pager
echo "[+] Межсетевой экран настроен"

# ============================================================
# ЗАДАНИЕ 6: RSYSLOG (Клиент -> HQ-SRV)
# ============================================================
echo "[*] [6] Настраиваем Rsyslog (клиент)..."
apt-get install -y rsyslog

cat > /etc/rsyslog.d/rsys.conf << 'EOF'
module(load="imjournal")
module(load="imuxsock")

# Отправка логов на HQ-SRV (192.168.1.2)
*.warn @@192.168.1.2:514
EOF

systemctl enable --now rsyslog
systemctl restart rsyslog
echo "[+] Rsyslog клиент настроен (отправка на 192.168.1.2:514)"

echo "[+] === HQ-RTR MODULE 3: Завершено ==="
