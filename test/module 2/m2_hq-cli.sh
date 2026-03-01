#!/bin/bash
# ============================================================
# MODULE 2 — HQ-CLI
# Задание 2: Подключение к домену Samba (Active Directory)
# Задание 5: Yandex Browser
# ============================================================
set -e

echo "[*] === HQ-CLI: MODULE 2 ==="

# ============================================================
# ЗАДАНИЕ 2: SAMBA — Подключение к домену
# ============================================================
echo "[*] [2] Подключаемся к домену AU-TEAM.IRPO..."

# Указываем DNS на BR-SRV (контроллер домена)
cat > /etc/resolv.conf << 'EOF'
nameserver 192.168.4.2
EOF

echo "[*] Устанавливаем пакеты для домена..."
apt-get install -y samba-common krb5-workstation

echo "[!] РУЧНОЙ ШАГ: Подключение к домену"
echo "    Зайди в Центр Управления Системой -> Аутентификация"
echo "    -> Домен Active Directory:"
echo "       Домен:          au-team-irpo"
echo "       Рабочая группа: au-team"
echo "       Имя компьютера: hq-cli"
echo "       Нажми Применить -> введи пароль: P@ssw0rd"
echo ""
echo "[*] После ручного подключения выполни kinit..."

# kinit для проверки
kinit Administrator@AU-TEAM.IRPO << 'EOF'
P@ssw0rd
EOF

# Права sudo для группы домена
echo '%au-team\\hq ALL=(ALL) NOPASSWD:/bin/cat,/bin/grep,/bin/id' >> /etc/sudoers

echo "[+] Домен настроен"

# ============================================================
# ЗАДАНИЕ 5: YANDEX BROWSER
# ============================================================
echo "[*] [5] Устанавливаем Yandex Browser..."
apt-get install -y yandex-browser-y 2>/dev/null || \
  echo "[!] Yandex Browser недоступен через apt — установи вручную"

echo "[!] После установки:"
echo "    Меню -> Все программы -> Интернет -> Yandex Browser"
echo "    Правой кнопкой -> Добавить на рабочий стол"

echo "[+] === HQ-CLI MODULE 2: Завершено ==="
