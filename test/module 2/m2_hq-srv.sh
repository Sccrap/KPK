#!/bin/bash
# ============================================================
# MODULE 2 — HQ-SRV
# Задание 1: Chrony (клиент)
# Задание 6: Файловая система RAID + NFS
# Задание 9: Apache + MariaDB
# ============================================================
set -e

echo "[*] === HQ-SRV: MODULE 2 ==="

# ============================================================
# ЗАДАНИЕ 1: CHRONY — NTP-клиент
# ============================================================
echo "[*] [1] Настраиваем Chrony (клиент -> HQ ISP)..."
apt-get install -y chrony

cat > /etc/chrony.conf << 'EOF'
server 172.16.1.14 iburst prefer
EOF

systemctl enable --now chronyd
systemctl restart chronyd
sleep 2
chronyc sources
echo "[+] Chrony настроен"

# ============================================================
# ЗАДАНИЕ 6: RAID + NFS
# ============================================================
echo "[*] [6] Настраиваем RAID0 + NFS..."
apt-get install -y mdadm nfs-server

echo "[!] Текущие диски:"
lsblk

# Создание разделов на sdb и sdc (GPT, один раздел на весь диск)
for DISK in sdb sdc; do
  echo "[*] Разметка /dev/${DISK}..."
  (
    echo g    # GPT
    echo n    # новый раздел
    echo      # номер по умолчанию
    echo      # начало по умолчанию
    echo      # конец по умолчанию
    echo w    # запись
  ) | fdisk /dev/${DISK} || true
done

sleep 1

# Создание RAID0
echo "[*] Создаём RAID0 из /dev/sdb1 и /dev/sdc1..."
mdadm --create --verbose /dev/md0 -l 0 -n 2 /dev/sdb1 /dev/sdc1 --force

# Сохраняем конфиг
mdadm --detail --scan >> /etc/mdadm.conf

# Форматируем
mkfs.ext4 /dev/md0

# Монтируем
mkdir -p /raid
chmod 777 /raid
mount -t ext4 /dev/md0 /raid

# fstab запись
grep -q '/dev/md0' /etc/fstab || \
  echo '/dev/md0	/raid	ext4	defaults	0	0' >> /etc/fstab

mount -av

# NFS папка
mkdir -p /raid/nfs
chmod 777 /raid/nfs
touch /raid/nfs/test.txt

# NFS экспорт
echo '/raid/nfs 192.168.0.0/21(rw,sync,subtree_check)' >> /etc/exports

systemctl enable --now nfs-server
exportfs -a
systemctl restart nfs-server

echo "[+] RAID + NFS настроены"

# ============================================================
# ЗАДАНИЕ 9: APACHE + MariaDB
# ============================================================
echo "[*] [9] Настраиваем Apache + MariaDB..."
apt-get install -y httpd2 mariadb-server php

# Запускаем MariaDB
systemctl enable --now mariadb

# Безопасная установка (автоматически)
mysql -u root << 'SQL_EOF'
ALTER USER 'root'@'localhost' IDENTIFIED BY 'P@ssw0rd';
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
FLUSH PRIVILEGES;
SQL_EOF

# Монтируем CD (если есть)
mount /dev/sr0 /mnt/ 2>/dev/null || echo "[!] CD не смонтирован — пропускаем копирование файлов"

# Копируем веб-файлы
if [ -f /mnt/web/index.php ]; then
  cp /mnt/web/index.php /var/www/html/
  cp /mnt/web/logo.png  /var/www/html/ 2>/dev/null || true

  # Редактируем index.php — устанавливаем параметры подключения к БД
  sed -i 's/\$servername.*/\$servername = "localhost";/' /var/www/html/index.php
  sed -i 's/\$username.*/\$username = "webc";/'          /var/www/html/index.php
  sed -i 's/\$password.*/\$password = "P@ssw0rd";/'      /var/www/html/index.php
  sed -i 's/\$dbname.*/\$dbname = "webdb";/'             /var/www/html/index.php
fi

rm -f /var/www/html/index.html

# Создаём БД и пользователя
mysql -u root -pP@ssw0rd << 'SQL_EOF'
CREATE DATABASE IF NOT EXISTS webdb;
CREATE USER IF NOT EXISTS 'webc'@'localhost' IDENTIFIED BY 'P@ssw0rd';
GRANT ALL PRIVILEGES ON webdb.* TO 'webc'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL_EOF

# Импортируем дамп (если есть)
if [ -f /mnt/web/dump.sql ]; then
  mariadb -u webc -pP@ssw0rd -D webdb < /mnt/web/dump.sql
  echo "[+] Дамп БД импортирован"
fi

systemctl enable --now httpd2
systemctl status httpd2 --no-pager

echo "[+] === HQ-SRV MODULE 2: Завершено ==="
echo "[!] Клиент: открой http://192.168.1.2"
