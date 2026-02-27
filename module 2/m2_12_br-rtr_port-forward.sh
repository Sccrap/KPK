#!/bin/bash
###############################################################################
# m2_12_br-rtr_port-forward.sh — DNAT на BR-RTR (ALT Linux, nftables)
# Задание 8: Статическая трансляция портов
###############################################################################
set -e

# ======================== ПЕРЕМЕННЫЕ =========================================
WAN_IP="172.16.2.1"
BR_SRV_IP="192.168.1.1"
IF_WAN="ens19"

# Правила проброса
DNAT_RULES=(
    "8080:$BR_SRV_IP:8080"
    "2024:$BR_SRV_IP:2024"
)

NFTABLES_CONF="/etc/nftables/nftables.nft"

# =============================================================================
echo "=== [1/2] Обновление nftables конфигурации ==="

if grep -q "chain prerouting" "$NFTABLES_CONF" 2>/dev/null; then
    echo "  chain prerouting уже существует — обновляем"
    sed -i '/chain prerouting/,/^[[:space:]]*}/d' "$NFTABLES_CONF"
fi

for rule in "${DNAT_RULES[@]}"; do
    IFS=':' read -r ext_port dst_ip dst_port <<< "$rule"
    echo "  $WAN_IP:$ext_port -> $dst_ip:$dst_port"
done

if grep -q "table inet nat" "$NFTABLES_CONF"; then
    python3 <<PYEOF
import re

with open("$NFTABLES_CONF", "r") as f:
    content = f.read()

dnat_block = """    chain prerouting {
        type nat hook prerouting priority filter;
$(for rule in "${DNAT_RULES[@]}"; do
    IFS=':' read -r ext_port dst_ip dst_port <<< "$rule"
    echo "        ip daddr $WAN_IP tcp dport $ext_port dnat ip to $dst_ip:$dst_port"
done)
    }"""

pattern = r'(table inet nat \{.*?)(^\})'
replacement = r'\1' + dnat_block + '\n}'
content_new = re.sub(pattern, replacement, content, flags=re.DOTALL | re.MULTILINE)

with open("$NFTABLES_CONF", "w") as f:
    f.write(content_new)
PYEOF
else
    echo "  ОШИБКА: table inet nat не найдена"
    exit 1
fi

echo ""
cat "$NFTABLES_CONF"

# =============================================================================
echo "=== [2/2] Перезапуск nftables ==="

systemctl restart nftables
nft list ruleset | grep -A5 "prerouting" || echo "  Правила не обнаружены"

echo ""
echo "=== Port forwarding на BR-RTR настроен ==="
