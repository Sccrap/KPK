#!/bin/bash
# ============================================================
# MODULE 3 — HQ-SRV
# Задание 2: Центр сертификации (CA, GOST TLS)
# Задание 5: Принт-сервер CUPS
# Задание 6: Централизованное логирование (Rsyslog + logrotate)
# Задание 7: Мониторинг (Prometheus + Grafana)
# Задание 9: Fail2ban
# ============================================================
set -e

echo "[*] === HQ-SRV: MODULE 3 ==="

# ============================================================
# ЗАДАНИЕ 2: ЦЕНТР СЕРТИФИКАЦИИ (CA)
# ============================================================
echo "[*] [2] Настраиваем центр сертификации (GOST2012)..."

apt-get install -y openssl openssl-gost-engine

# Создаём структуру PKI
mkdir -p /etc/pki/CA/private
mkdir -p /etc/pki/CA/certs
mkdir -p /etc/pki/CA/newcerts
mkdir -p /etc/pki/CA/crl
touch /etc/pki/CA/index.txt
echo 1000 > /etc/pki/CA/serial
chmod 700 /etc/pki/CA/private

# Включаем GOST
control openssl-gost enabled 2>/dev/null || true

# Генерируем ключ CA
echo "[*] Генерируем ключ CA (GOST2012)..."
openssl genkey \
  -algorithm gost2012_256 \
  -pkeyopt paramset:TCB \
  -out /etc/pki/CA/private/ca.key

# Самоподписанный сертификат CA
echo "[*] Создаём сертификат CA..."
openssl req -x509 -new \
  -md_gost12_256 \
  -key /etc/pki/CA/private/ca.key \
  -out /etc/pki/CA/certs/ca.crt \
  -days 3650 \
  -subj "/C=RU/ST=Moscow/L=Moscow/O=AU-TEAM/OU=WEB/CN=AU-TEAM Root CA"

# Ключи для сайтов
for SITE in web.au-team.irpo docker.au-team.irpo; do
  echo "[*] Генерируем ключ для $SITE..."
  openssl genpkey \
    -algorithm gost2012_256 \
    -pkeyopt paramset:A \
    -out /etc/pki/CA/private/${SITE}.key

  # CSR
  openssl req -new \
    -md_gost12_256 \
    -key /etc/pki/CA/private/${SITE}.key \
    -out /etc/pki/CA/newcerts/${SITE}.csr \
    -subj "/CN=${SITE}"

  # Подпись сертификата
  openssl x509 -req \
    -in /etc/pki/CA/newcerts/${SITE}.csr \
    -CA /etc/pki/CA/certs/ca.crt \
    -CAkey /etc/pki/CA/private/ca.key \
    -CAcreateserial \
    -out /etc/pki/CA/certs/${SITE}.crt \
    -days 30
done

# Копируем сертификаты в NFS (если смонтирован)
if [ -d /raid/nfs ]; then
  cp /etc/pki/CA/certs/ca.crt              /raid/nfs/
  cp /etc/pki/CA/certs/web.au-team.irpo.crt /raid/nfs/
  cp /etc/pki/CA/certs/docker.au-team.irpo.crt /raid/nfs/
  cp /etc/pki/CA/private/web.au-team.irpo.key /raid/nfs/
  cp /etc/pki/CA/private/docker.au-team.irpo.key /raid/nfs/
  echo "[+] Сертификаты скопированы в /raid/nfs/"
else
  echo "[!] /raid/nfs не смонтирован — скопируй сертификаты вручную"
fi

echo "[+] CA настроен"

# ============================================================
# ЗАДАНИЕ 5: ПРИНТ-СЕРВЕР CUPS
# ============================================================
echo "[*] [5] Настраиваем CUPS..."
apt-get install -y cups cups-pdf

# Изменяем конфигурацию
CUPS_CFG=/etc/cups/cupsd.conf
sed -i 's/^Listen localhost.*/Listen hq-srv.au-team.irpo:631/' "$CUPS_CFG" || \
  sed -i 's/^Listen .*/Listen hq-srv.au-team.irpo:631/' "$CUPS_CFG"

# Комментируем Order allow,deny и добавляем allow any в 3 местах
# Location /
sed -i '/<Location \/>/,/<\/Location>/ s/Order allow,deny/#Order allow,deny/' "$CUPS_CFG"
sed -i '/<Location \/>/,/<\/Location>/ { /#Order allow,deny/a\  Allow any }' "$CUPS_CFG" 2>/dev/null || true

# Упрощённый патч через Python
python3 << 'PYEOF'
with open('/etc/cups/cupsd.conf', 'r') as f:
    content = f.read()

content = content.replace('Order allow,deny', '#Order allow,deny\n  Allow any')
content = content.replace('Order Deny,Allow', '#Order Deny,Allow\n  Allow any')

with open('/etc/cups/cupsd.conf', 'w') as f:
    f.write(content)
print("[+] cupsd.conf обновлён")
PYEOF

systemctl enable --now cups
systemctl restart cups
echo "[+] CUPS настроен: https://hq-srv.au-team.irpo:631 (root/toor)"
echo "[!] Добавь принтер вручную в браузере: CUPS-PDF"

# ============================================================
# ЗАДАНИЕ 6: RSYSLOG (Сервер)
# ============================================================
echo "[*] [6] Настраиваем Rsyslog (сервер)..."

# Основной конфиг
cat > /etc/rsyslog.d/rsys.conf << 'EOF'
# Загружаем модули
module(load="imjournal")
module(load="imuxsock")
module(load="imklog")
module(load="immark")
module(load="imtcp")
input(type="imtcp" port="514")

# Локальный auth лог
authpriv.* /var/log/auth.log

# Логи от удалённых хостов
if $fromhost-ip contains '192.168.0.62' then {
  *.warn /opt/hq-rtr/hq-rtr.log
}
if $fromhost-ip contains '10.5.5.2' then {
  *.warn /opt/br-rtr/br-rtr.log
}
if $fromhost-ip contains '192.168.1.1' then {
  *.warn /opt/br-srv/br-srv.log
}
EOF

# Создаём директории и файлы логов
mkdir -p /opt/hq-rtr /opt/br-rtr /opt/br-srv
touch /opt/hq-rtr/hq-rtr.log
touch /opt/br-rtr/br-rtr.log
touch /opt/br-srv/br-srv.log

systemctl enable --now rsyslog
systemctl restart rsyslog

# --- Logrotate ---
cat >> /etc/logrotate.conf << 'EOF'

/opt/hq-rtr/*.log
/opt/br-rtr/*.log
/opt/br-srv/*.log
{
  minsize 10M
  compress
}
EOF

systemctl enable --now logrotate 2>/dev/null || true
logrotate -d /etc/logrotate.conf
echo "[+] Rsyslog + logrotate настроены"

# ============================================================
# ЗАДАНИЕ 7: МОНИТОРИНГ — Prometheus + Grafana
# ============================================================
echo "[*] [7] Настраиваем Prometheus + Grafana..."

apt-get install -y prometheus grafana prometheus-node_exporter 2>/dev/null || \
  echo "[!] Некоторые пакеты недоступны — проверь репозиторий"

# Prometheus конфиг
cat > /etc/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    monitor: 'example'

alerting:
  alertmanagers:
    - static_configs:
      - targets: ['localhost:9093']

scrape_configs:
  - job_name: 'prometheus'
    scrape_interval: 5s
    scrape_timeout: 5s
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node'
    static_configs:
      - targets: ['hq-srv:9100', 'br-srv:9100']
EOF

systemctl enable --now grafana-server
systemctl enable --now prometheus
systemctl enable --now prometheus-node_exporter

echo "[+] Мониторинг запущен"
echo "[!] Клиент: http://hq-srv:3000  admin/admin -> сменить на P@ssw0rd"
echo "[!] Grafana: Подключения -> Prometheus -> http://localhost:9090"
echo "[!] Dashboard: Импорт -> ID 11074"

# ============================================================
# ЗАДАНИЕ 9: FAIL2BAN
# ============================================================
echo "[*] [9] Настраиваем Fail2ban..."

apt-get install -y fail2ban python3-module-systemd 2>/dev/null || \
  apt-get install -y fail2ban

cat > /etc/fail2ban/jail.local << 'EOF'
[sshd]
enabled = true
logpath = /var/log/auth.log
backend = systemd
filter = sshd
action = nftables[name=ssh, port=2026, protocol=tcp]
maxretry = 2
bantime = 1m
EOF

systemctl enable --now fail2ban
systemctl status fail2ban --no-pager

echo "[+] Fail2ban настроен"
echo "[!] Тест: попробуй 3 раза войти по SSH с неверным паролем"
echo "[!] Проверка: fail2ban-client status sshd"

echo "[+] === HQ-SRV MODULE 3: Завершено ==="
