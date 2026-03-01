#!/bin/bash
# ============================================================
# MODULE 1 — BR-RTR
# Hostname, IP, NAT, пользователь net_admin
# ============================================================
set -e

echo "[*] === BR-RTR: Начало настройки ==="

# --- Hostname ---
hostnamectl set-hostname br-rtr

# --- IP Forwarding ---
sed -i 's/net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/' /etc/net/sysctl.conf || \
  echo 'net.ipv4.ip_forward = 1' >> /etc/net/sysctl.conf

# --- DNS и IP-адреса ---
echo 'nameserver 8.8.8.8' >> /etc/resolv.conf
echo '172.16.2.1/28'   > /etc/net/ifaces/ens19/ipv4address
echo '192.168.4.1/28'  > /etc/net/ifaces/ens20/ipv4address
echo 'default via 172.16.2.14' > /etc/net/ifaces/ens19/ipv4route
systemctl restart network

echo "[*] Проверяем интернет..."
ping -c 2 8.8.8.8 || echo "[!] Интернет недоступен — проверь ISP"

# --- Установка пакетов ---
apt-get update -y
apt-get install -y nano nftables sudo frr

# --- NAT ---
cat >> /etc/nftables/nftables.nft << 'EOF'

table inet nat {
  chain postrouting {
    type nat hook postrouting priority srcnat;
    oifname "ens19" masquerade
  }
}
EOF
systemctl enable --now nftables
systemctl restart nftables

# --- Пользователь net_admin ---
echo "[*] Создаём пользователя net_admin..."
if ! id net_admin &>/dev/null; then
  adduser --disabled-password --gecos "" net_admin
fi
echo "net_admin:P@ssw0rd" | chpasswd
usermod -aG wheel net_admin
echo 'net_admin ALL=(ALL:ALL) NOPASSWD: ALL' >> /etc/sudoers

echo "[+] === BR-RTR: Настройка завершена ==="
