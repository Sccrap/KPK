#!/bin/bash
# ============================================================
# ЗАДАНИЕ 5: Принт-сервер CUPS
# Выполняется на: HQ-SRV
# ============================================================

echo "=== ЗАДАНИЕ 5: Настройка CUPS ==="

CUPS_CONF="/etc/cups/cupsd.conf"
HOSTNAME="hq-srv.au-team.irpo"

echo "[1/3] Бэкап и редактирование cupsd.conf..."
cp "${CUPS_CONF}" "${CUPS_CONF}.bak"

# Меняем Listen localhost -> Listen hostname:631
sed -i "s|Listen localhost:631|Listen ${HOSTNAME}:631|g" "${CUPS_CONF}"
sed -i "s|Listen localhost|Listen ${HOSTNAME}:631|g" "${CUPS_CONF}"

# В трёх Location-блоках: комментируем "Order allow,deny" и добавляем "Allow any"
python3 - << 'PYEOF'
import re

with open("/etc/cups/cupsd.conf", "r") as f:
    content = f.read()

# Обрабатываем каждый Location-блок
def patch_location(block):
    # Комментируем Order allow,deny
    block = re.sub(r'(\s*)(Order allow,deny)', r'\1#Order allow,deny', block)
    # Добавляем Allow any если нет
    if "Allow any" not in block:
        block = re.sub(r'(#Order allow,deny)', r'\1\n  Allow any', block)
    return block

content = re.sub(
    r'(<Location.*?>.*?</Location>)',
    lambda m: patch_location(m.group(0)),
    content,
    flags=re.DOTALL
)

with open("/etc/cups/cupsd.conf", "w") as f:
    f.write(content)

print("[OK] cupsd.conf обновлён")
PYEOF

echo "[2/3] Перезапуск CUPS..."
systemctl restart cups
systemctl enable cups
echo "[OK] CUPS запущен"

echo "[3/3] Проверка статуса..."
systemctl status cups --no-pager | head -10

echo ""
echo "=== ИНСТРУКЦИЯ ДЛЯ КЛИЕНТА ==="
echo "1. Откройте браузер: https://${HOSTNAME}:631"
echo "2. Войдите: root / toor"
echo "3. Администрирование > Добавить принтер"
echo "4. Выберите CUPS-PDF > Продолжить"
echo "5. Включите 'Разрешить совместный доступ' > Продолжить"
echo "6. Generic > Generic CUPS-PDF > Добавить принтер"
echo ""
echo "На клиентской машине:"
echo "  Пуск > Принтеры > Разблокировать (root/toor)"
echo "  Добавить принтер > Поиск: hq-srv > Virtual_PDF_Printer"
