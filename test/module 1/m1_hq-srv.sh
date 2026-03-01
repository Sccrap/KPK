#!/bin/bash
# ============================================================
# MODULE 1 — HQ-SRV
# Hostname, IP, пользователь remote_user, SSH, DNS (bind)
# ============================================================
set -e

echo "[*] === HQ-SRV: Начало настройки ==="

# --- Hostname ---
hostnamectl set-hostname hq-srv

# --- IP Forwarding ---
sed -i 's/net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/' /etc/net/sysctl.conf || \
  echo 'net.ipv4.ip_forward = 1' >> /etc/net/sysctl.conf

# --- DNS и маршрут ---
echo 'nameserver 8.8.8.8' >> /etc/resolv.conf
echo '192.168.1.2/27' > /etc/net/ifaces/ens19/ipv4address
echo 'default via 192.168.1.1' > /etc/net/ifaces/ens19/ipv4route
systemctl restart network

echo "[*] Проверяем интернет..."
ping -c 2 8.8.8.8 || echo "[!] Интернет недоступен — проверь HQ-RTR"

# --- Установка пакетов ---
apt-get update -y
apt-get install -y nano bind

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
echo " Authorized access only. HQ-SRV            " >> /var/sshbanner
echo "============================================" >> /var/sshbanner

systemctl enable --now sshd
systemctl restart sshd

# --- DNS (BIND) ---
echo "[*] Настраиваем BIND DNS..."
cat > /etc/bind/options.conf << 'EOF'
options {
  listen-on port 53 { 127.0.0.1; 192.168.1.2; };
  listen-on-v6 { none; };
  directory "/var/cache/bind";
  forwarders { 77.88.8.7; };
  allow-query { any; };
  dnssec-validation yes;
};
EOF

cat >> /etc/bind/local.conf << 'EOF'

zone "aks42.aks" {
  type master;
  file "aks42.aks";
};

zone "1.168.192.in-addr.arpa" {
  type master;
  file "1.168.192.in-addr.arpa";
};
EOF

# Прямая зона
cp /etc/bind/zone/localdomain /etc/bind/zone/aks42.aks
cat > /etc/bind/zone/aks42.aks << 'EOF'
$TTL    1D
@       IN  SOA  aks42.aks. root.aks42.aks. (
                  2025100300 ; serial
                  12H        ; refresh
                  1H         ; retry
                  1W         ; expire
                  1H )       ; ncache

        IN  NS   aks42.aks.
        IN  A    192.168.1.1

hq-rtr  IN  A    192.168.1.1
hq-srv  IN  A    192.168.1.2
hq-cli  IN  A    192.168.2.2
br-rtr  IN  A    192.168.4.1
br-srv  IN  A    192.168.4.2
noodle  IN  CNAME br-rtr.
wiki    IN  CNAME br-rtr.
EOF

# Обратная зона
cp /etc/bind/zone/127.in-addr.arpa /etc/bind/zone/1.168.192.in-addr.arpa
cat > /etc/bind/zone/1.168.192.in-addr.arpa << 'EOF'
$TTL    1D
@       IN  SOA  aks42.aks. root.aks42.aks. (
                  2025100300 ; serial
                  12H        ; refresh
                  1H         ; retry
                  1W         ; expire
                  1H )       ; ncache

        IN  NS   aks42.aks.
2       IN  PTR  hq-srv.aks42.aks.
1       IN  PTR  hq-rtr.aks42.aks.
2_      IN  PTR  hq-cli.aks42.aks.
EOF

# Права и проверка
chown named /etc/bind/zone/aks42.aks
chmod 600   /etc/bind/zone/aks42.aks
chown named /etc/bind/zone/1.168.192.in-addr.arpa
chmod 600   /etc/bind/zone/1.168.192.in-addr.arpa

# Закомментировать rndc.conf
sed -i 's|^include.*rndc.conf.*|//&|' /etc/bind/named.conf 2>/dev/null || true

named-checkconf -z && echo "[+] BIND config OK"
systemctl enable --now bind

echo "[+] === HQ-SRV: Настройка завершена ==="
echo "[!] Проверь: ssh remote_user@192.168.1.2 -p 2042"
