#!/bin/bash
###############################################################################
# m2_10_hq-srv_web.sh — Web-сервер на HQ-SRV (ALT Linux)
# Задание 7: MariaDB + Apache (httpd2) + PHP
###############################################################################
set -e

# ======================== ПЕРЕМЕННЫЕ =========================================
ISO_MOUNT="/mnt"
ISO_DEVICE="/dev/sr0"

# MariaDB
DB_NAME="webdb"
DB_USER="webc"
DB_PASS="P@ssw0rd"
DB_ROOT_PASS="P@ssw0rd"

# Пути
WEB_ROOT="/var/www/html"
DUMP_FILE="$ISO_MOUNT/web/dump.sql"

# =============================================================================
echo "=== [1/7] Запуск MariaDB ==="

systemctl enable --now mariadb
sleep 2

echo "  MariaDB запущена"

# =============================================================================
echo "=== [2/7] Безопасная настройка MariaDB ==="

# Автоматизация mysql_secure_installation
# Устанавливаем root пароль и выполняем hardening
mariadb -u root <<SQLEOF
-- Устанавливаем пароль root
ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_ROOT_PASS';
-- Удаляем анонимных пользователей
DELETE FROM mysql.user WHERE User='';
-- Запрещаем удалённый root
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
-- Удаляем тестовую БД
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
-- Применяем
FLUSH PRIVILEGES;
SQLEOF
echo "  MariaDB hardening выполнен" 2>/dev/null || echo "  MariaDB возможно уже настроена (пароль root уже задан)"

# =============================================================================
echo "=== [3/7] Монтирование Additional.iso ==="

mkdir -p "$ISO_MOUNT"
if ! mountpoint -q "$ISO_MOUNT"; then
    mount "$ISO_DEVICE" "$ISO_MOUNT" 2>/dev/null || {
        echo "  ПРЕДУПРЕЖДЕНИЕ: ISO не смонтирован. Файлы web нужно скопировать вручную."
    }
fi

# =============================================================================
echo "=== [4/7] Копирование файлов веб-приложения ==="

if [ -d "$ISO_MOUNT/web" ]; then
    cp -f "$ISO_MOUNT/web/index.php" "$WEB_ROOT/" 2>/dev/null && echo "  index.php скопирован" || echo "  index.php не найден"
    cp -f "$ISO_MOUNT/web/logo.png" "$WEB_ROOT/" 2>/dev/null && echo "  logo.png скопирован" || echo "  logo.png не найден"
else
    echo "  ПРЕДУПРЕЖДЕНИЕ: Каталог $ISO_MOUNT/web не найден"
    echo "  Скопируйте файлы вручную в $WEB_ROOT/"
fi

# Удаляем стандартную страницу Apache
rm -f "$WEB_ROOT/index.html"

# =============================================================================
echo "=== [5/7] Настройка подключения к БД в index.php ==="

if [ -f "$WEB_ROOT/index.php" ]; then
    # Обновляем параметры подключения к БД
    # Типичные переменные в index.php: $db_host, $db_name, $db_user, $db_pass
    sed -i "s/\$db_host\s*=.*/\$db_host = 'localhost';/" "$WEB_ROOT/index.php" 2>/dev/null || true
    sed -i "s/\$db_name\s*=.*/\$db_name = '$DB_NAME';/" "$WEB_ROOT/index.php" 2>/dev/null || true
    sed -i "s/\$db_user\s*=.*/\$db_user = '$DB_USER';/" "$WEB_ROOT/index.php" 2>/dev/null || true
    sed -i "s/\$db_pass\s*=.*/\$db_pass = '$DB_PASS';/" "$WEB_ROOT/index.php" 2>/dev/null || true

    echo "  Параметры БД обновлены в index.php"
    echo "  ПРОВЕРЬТЕ вручную: vim $WEB_ROOT/index.php"
else
    echo "  index.php не найден — настройте вручную"
fi

# =============================================================================
echo "=== [6/7] Создание БД и импорт дампа ==="

mariadb -u root -p"$DB_ROOT_PASS" <<SQLEOF 2>/dev/null || true
CREATE DATABASE IF NOT EXISTS $DB_NAME;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQLEOF

echo "  БД $DB_NAME создана, пользователь $DB_USER"

# Импорт дампа
if [ -f "$DUMP_FILE" ]; then
    mariadb -u root -p"$DB_ROOT_PASS" "$DB_NAME" < "$DUMP_FILE" 2>/dev/null
    echo "  Дамп импортирован из $DUMP_FILE"
elif [ -f "$ISO_MOUNT/web/dump.sql" ]; then
    mariadb -u root -p"$DB_ROOT_PASS" "$DB_NAME" < "$ISO_MOUNT/web/dump.sql" 2>/dev/null
    echo "  Дамп импортирован"
else
    echo "  ПРЕДУПРЕЖДЕНИЕ: dump.sql не найден"
    echo "  Импортируйте вручную: mariadb -u root -p $DB_NAME < dump.sql"
fi

# =============================================================================
echo "=== [7/7] Запуск Apache (httpd) ==="

systemctl enable --now httpd2 2>/dev/null || systemctl enable --now httpd 2>/dev/null
systemctl restart httpd2 2>/dev/null || systemctl restart httpd 2>/dev/null

echo ""
echo "=== Проверка ==="
echo "Откройте в браузере: http://192.168.0.1"
echo ""
echo "Если страница не работает:"
echo "  1. Проверьте index.php: vim $WEB_ROOT/index.php"
echo "  2. Проверьте БД: mariadb -u $DB_USER -p$DB_PASS $DB_NAME -e 'SHOW TABLES;'"
echo "  3. Проверьте логи: journalctl -u httpd2 --no-pager -n 20"
echo ""
echo "=== Web-сервер настроен ==="
