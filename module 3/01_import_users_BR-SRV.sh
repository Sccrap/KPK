#!/bin/bash
# ============================================================
# ЗАДАНИЕ 1: Импорт пользователей в Samba AD
# Выполняется на: BR-SRV
# ============================================================
set -e

CSV_FILE="/opt/Users.csv"
DOMAIN="AU-TEAM.IRPO"

echo "=== [1/3] Монтирование диска и копирование CSV ==="
mount /dev/sr0 /mnt/ 2>/dev/null || echo "[INFO] Диск уже смонтирован или не найден"
cp /mnt/Users.csv /opt/ && echo "[OK] Users.csv скопирован в /opt/"

echo "=== [2/3] Создание скрипта импорта ==="
cat > /var/import.sh << 'IMPORT_SCRIPT'
#!/bin/bash
CSV_FILE="/opt/Users.csv"
DOMAIN="AU-TEAM.IRPO"
ADMIN_USER="Administrator"
ADMIN_PASS="P@ssw0rd"

echo "[*] Начало импорта пользователей..."

while IFS=';' read -r fname lname role phone ou street zip city country password; do
    # Пропускаем заголовок
    if [[ "$fname" == "First Name" ]]; then
        continue
    fi

    # Формируем username: первая буква имени + фамилия, всё в нижнем регистре
    username=$(echo "${fname:0:1}${lname}" | tr '[:upper:]' '[:lower:]')

    # Создаём OU (игнорируем ошибку если уже существует)
    samba-tool ou create "OU=${ou},DC=AU-TEAM,DC=IRPO" \
        --description="${ou} department" 2>/dev/null || true

    echo "[+] Добавляю пользователя: $username (OU=$ou)"
    samba-tool user add "$username" "$password" \
        --given-name="$fname" \
        --surname="$lname" \
        --job-title="$role" \
        --telephone-number="$phone" \
        --userou="OU=${ou}" 2>/dev/null \
        && echo "    [OK] $username добавлен" \
        || echo "    [SKIP] $username уже существует"

done < "${CSV_FILE}"

echo "[*] Импорт завершён!"
IMPORT_SCRIPT

chmod +x /var/import.sh
echo "[OK] Скрипт /var/import.sh создан"

echo "=== [3/3] Запуск импорта ==="
/var/import.sh

echo ""
echo "=== ПРОВЕРКА: Список пользователей ==="
samba-tool user list

echo ""
echo "=== ПРОВЕРКА: Список OU ==="
samba-tool ou list

echo ""
echo "=== ГОТОВО ==="
echo "Зайдите в ADMC на клиенте и проверьте OU и пользователей"
echo "Если не входит в ADMC: samba-tool user setpassword Administrator"
