#!/bin/bash
# ============================================================
# MODULE 1 — BR-SRV
# Hostname, IP, пользователь remote_user, SSH
# ============================================================
set -e

echo "[*] === BR-SRV: Начало настройки ==="

# --- Hostname ---
hostnamectl set-hostname br-srv

# --- IP Forwarding ---
sed -i 's/net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/' /etc/net/sysctl.conf || \
  echo 'net.ipv4.ip_forward = 1' >> /etc/net/sysctl.conf

# --- DNS и маршрут ---
echo 'nameserver 8.8.8.8' >> /etc/resolv.conf
echo '192.168.4.2/27' > /etc/net/ifaces/ens19/ipv4address
echo 'default via 192.168.4.1' > /etc/net/ifaces/ens19/ipv4route
systemctl restart network

echo "[*] Проверяем интернет..."
ping -c 2 8.8.8.8 || echo "[!] Интернет недоступен — проверь BR-RTR"

# --- Установка пакетов ---
apt-get update -y
apt-get install -y nano

# --- Пользователь remote_user (uid=2042) ---
echo "[*] Создаём пользователя remote_user..."
if ! id remote_user &>/dev/null; then
  adduser --disabled-password --gecos "" --uid 2042 remote_user
fi
echo "remote_user:Pa\$\$word" | chpasswd
usermod -aG wheel remote_user
echo 'remote_user ALL=(ALL:ALL) NOPASSWD: ALL' >> /etc/sudoers

# --- SSH настройка ---
echo "[*] Настраиваем SSH (порт 2042)..."
SSHD_CFG=/etc/openssh/sshd_config
sed -i 's/^#\?Port .*/Port 2042/' "$SSHD_CFG"
sed -i 's/^#\?MaxAuthTries .*/MaxAuthTries 2/' "$SSHD_CFG"
sed -i 's/^#\?Banner .*/Banner \/var\/sshbanner/' "$SSHD_CFG"
sed -i 's/^#\?AllowUsers .*/AllowUsers remote_user/' "$SSHD_CFG"

echo "============================================" > /var/sshbanner
echo " Authorized access only. BR-SRV            " >> /var/sshbanner
echo "============================================" >> /var/sshbanner

systemctl enable --now sshd
systemctl restart sshd

echo "[+] === BR-SRV: Настройка завершена ==="
echo "[!] Проверь: ssh remote_user@192.168.4.2 -p 2042"
