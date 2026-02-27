#!/bin/bash
###############################################################################
# m2_11_hq-rtr_port-forward.sh — DNAT на HQ-RTR (ALT Linux, nftables)
# Задание 8: Статическая трансляция портов
###############################################################################
set -e

# ======================== ПЕРЕМЕННЫЕ =========================================
WAN_IP="172.16.1.1"
HQ_SRV_IP="192.168.0.1"
IF_WAN="ens19"

# Правила проброса: внешний_порт -> внутренний_IP:внутренний_порт
# HTTP (web) и SSH
DNAT_RULES=(
    "80:$HQ_SRV_IP:80"
    "2024:$HQ_SRV_IP:2024"
)

NFTABLES_CONF="/etc/nftables/nftables.nft"

# =============================================================================
echo "=== [1/2] Обновление nftables конфигурации ==="

# Проверяем есть ли уже prerouting chain
if grep -q "chain prerouting" "$NFTABLES_CONF" 2>/dev/null; then
    echo "  chain prerouting уже существует — обновляем"
    # Удаляем старый prerouting блок
    sed -i '/chain prerouting/,/^[[:space:]]*}/d' "$NFTABLES_CONF"
fi

# Генерируем DNAT правила
DNAT_BLOCK="    chain prerouting {\n"
DNAT_BLOCK+="        type nat hook prerouting priority filter;\n"

for rule in "${DNAT_RULES[@]}"; do
    IFS=':' read -r ext_port dst_ip dst_port <<< "$rule"
    DNAT_BLOCK+="        ip daddr $WAN_IP tcp dport $ext_port dnat ip to $dst_ip:$dst_port\n"
    echo "  $WAN_IP:$ext_port -> $dst_ip:$dst_port"
done

DNAT_BLOCK+="    }"

# Вставляем prerouting перед закрывающей скобкой таблицы nat
# Ищем последнюю } в блоке table inet nat и вставляем перед ней
if grep -q "table inet nat" "$NFTABLES_CONF"; then
    # Вставляем перед последней закрывающей скобкой таблицы nat
    # Используем Python для корректной вставки (sed не справится с многострочной вставкой)
    python3 <<PYEOF
import re

with open("$NFTABLES_CONF", "r") as f:
    content = f.read()

# Найдём блок table inet nat { ... } и вставим prerouting перед последней }
dnat_block = """    chain prerouting {
        type nat hook prerouting priority filter;
$(for rule in "${DNAT_RULES[@]}"; do
    IFS=':' read -r ext_port dst_ip dst_port <<< "$rule"
    echo "        ip daddr $WAN_IP tcp dport $ext_port dnat ip to $dst_ip:$dst_port"
done)
    }"""

# Ищем table inet nat и вставляем перед последней закрывающей скобкой
pattern = r'(table inet nat \{.*?)(^\})'
replacement = r'\1' + dnat_block + '\n}'

content_new = re.sub(pattern, replacement, content, flags=re.DOTALL | re.MULTILINE)

with open("$NFTABLES_CONF", "w") as f:
    f.write(content_new)
PYEOF
else
    echo "  ОШИБКА: table inet nat не найдена в $NFTABLES_CONF"
    echo "  Добавьте таблицу NAT через скрипт модуля 1 (02_hq-rtr.sh)"
    exit 1
fi

echo ""
echo "  Итоговая конфигурация:"
cat "$NFTABLES_CONF"

# =============================================================================
echo "=== [2/2] Перезапуск nftables ==="

systemctl restart nftables
nft list ruleset | grep -A5 "prerouting" || echo "  Правила prerouting не обнаружены"

echo ""
echo "=== Port forwarding на HQ-RTR настроен ==="
