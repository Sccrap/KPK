#!/bin/bash
# ============================================================
# MODULE 1 — HQ-CLI
# Hostname, timezone, проверка DHCP и DNS
# ============================================================
set -e

echo "[*] === HQ-CLI: Начало настройки ==="

# --- IP Forwarding (на клиенте тоже включаем) ---
sed -i 's/net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/' /etc/net/sysctl.conf 2>/dev/null || \
  echo 'net.ipv4.ip_forward = 1' >> /etc/net/sysctl.conf 2>/dev/null || true

# --- Hostname ---
hostnamectl set-hostname hq-cli.aks42.aks

# --- Timezone ---
timedatectl set-timezone Europe/Moscow
echo "[*] Timezone:"
timedatectl

# --- resolv.conf ---
cat > /etc/resolv.conf << 'EOF'
# search aks42.aks
nameserver 192.168.1.2
EOF

# --- Проверка DHCP ---
echo "[*] Текущие IP-адреса:"
ip -c -br a

echo "[*] Проверяем доступность HQ-SRV..."
ping -c 2 192.168.1.2 || echo "[!] HQ-SRV недоступен"

# --- Проверка DNS ---
echo "[*] Проверяем DNS..."
ping -c 2 hq-srv.aks42.aks || echo "[!] DNS не работает"
ping -c 2 br-srv.aks42.aks || echo "[!] br-srv DNS недоступен"

# --- SSH подключение тест ---
echo ""
echo "[*] Для подключения по SSH к серверам:"
echo "    ssh remote_user@192.168.1.2 -p 2042"
echo "    ssh remote_user@192.168.4.2 -p 2042"

echo "[+] === HQ-CLI: Настройка завершена ==="
