#!/bin/bash
# ============================================================
# ЗАДАНИЕ 9: Fail2ban — защита SSH
# Выполняется на: HQ-SRV
# ============================================================

echo "=== ЗАДАНИЕ 9: Fail2ban (HQ-SRV) ==="

echo "[1/4] Установка зависимостей..."
apt-get install -y python3-module-systemd fail2ban
echo "[OK] Пакеты установлены"

echo "[2/4] Убеждаемся что auth.log существует..."
# Rsyslog должен писать auth.log (из задания 6)
touch /var/log/auth.log
# Включаем authpriv logging если нет
grep -q "authpriv" /etc/rsyslog.d/rsys.conf 2>/dev/null \
    || echo 'authpriv.* /var/log/auth.log' >> /etc/rsyslog.d/rsys.conf
systemctl restart rsyslog 2>/dev/null || true
echo "[OK] /var/log/auth.log готов"

echo "[3/4] Настройка /etc/fail2ban/jail.conf..."
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.conf.bak 2>/dev/null || true

# Используем jail.local (приоритетнее чем jail.conf)
cat > /etc/fail2ban/jail.local << 'JAIL'
[DEFAULT]
bantime  = 1m
findtime = 5m
maxretry = 2

[sshd]
enabled  = true
filter   = sshd
logpath  = /var/log/auth.log
backend  = systemd
action   = nftables[name=ssh, port=2026, protocol=tcp]
maxretry = 2
bantime  = 1m
JAIL

echo "[OK] jail.local создан"

echo "[4/4] Запуск fail2ban..."
systemctl enable --now fail2ban
systemctl restart fail2ban
sleep 2

echo ""
echo "=== ПРОВЕРКА ==="
systemctl status fail2ban --no-pager | head -8
echo ""
fail2ban-client status sshd 2>/dev/null || echo "[!] sshd jail ещё не активен, подождите 5-10 сек"

echo ""
echo "=== ТЕСТ БАНА ==="
echo "С другого хоста: ssh -p 2026 wronguser@<HQ-SRV_IP>"
echo "(введите неверный пароль 2 раза)"
echo ""
echo "Затем на HQ-SRV проверьте:"
echo "  fail2ban-client status sshd"
echo "  nft list ruleset | grep f2b"
echo ""
echo "Разблокировать IP: fail2ban-client set sshd unbanip <IP>"
