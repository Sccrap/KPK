#!/bin/bash
# ============================================================
# MODULE 1 — ISP
# Базовая настройка: hostname, IP, NAT (nftables)
# ============================================================
set -e

echo "[*] === ISP: Начало настройки ==="

# --- Hostname ---
echo "[*] Устанавливаем hostname..."
hostnamectl set-hostname isp
exec bash 2>/dev/null || true

# --- IP Forwarding ---
echo "[*] Включаем ip_forward..."
sed -i 's/net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/' /etc/net/sysctl.conf || \
  echo 'net.ipv4.ip_forward = 1' >> /etc/net/sysctl.conf

# --- IP-адреса интерфейсов ---
echo "[*] Настраиваем IP-адреса..."
echo '172.16.1.14/28' > /etc/net/ifaces/ens20/ipv4address
echo '172.16.2.14/28' > /etc/net/ifaces/ens21/ipv4address
systemctl restart network

# --- Установка пакетов ---
echo "[*] Устанавливаем пакеты..."
apt-get update -y
apt-get install -y nano nftables

# --- NAT через nftables ---
echo "[*] Настраиваем NAT (nftables)..."
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
systemctl status nftables --no-pager

echo "[+] === ISP: Настройка завершена ==="
