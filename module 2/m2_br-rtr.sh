#!/bin/bash
###############################################################################
# m2_br-rtr.sh — BR-RTR configuration (Module 2, ALT Linux)
# Tasks: NTP client · Port forwarding (DNAT)
###############################################################################
set -e

# ======================== VARIABLES ==========================================
# NTP
NTP_SERVER="172.16.1.14"

# DNAT
WAN_IP="172.16.2.1"
BR_SRV_IP="192.168.1.1"
IF_WAN="ens19"
DNAT_RULES=(
    "8080:$BR_SRV_IP:8080"
    "2024:$BR_SRV_IP:2024"
)
NFTABLES_CONF="/etc/nftables/nftables.nft"

# =============================================================================
echo "=== [0/2] Installing required software ==="
apt-get update -y
apt-get install -y chrony
echo "  Software installed"

# =============================================================================
echo "=== [1/2] Configuring NTP client ==="

cat > /etc/chrony.conf <<EOF
# NTP client — sync with ISP
server $NTP_SERVER iburst prefer

driftfile /var/lib/chrony/drift
log tracking measurements statistics
logdir /var/log/chrony
EOF

systemctl enable --now chronyd
systemctl restart chronyd
sleep 2
echo "  NTP client: server $NTP_SERVER"

# =============================================================================
echo "=== [2/2] Configuring port forwarding (DNAT) ==="

if grep -q "chain prerouting" "$NFTABLES_CONF" 2>/dev/null; then
    echo "  chain prerouting exists — replacing"
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
    echo "  ERROR: table inet nat not found in $NFTABLES_CONF"
    echo "  Add NAT table via module 1 script (03_br-rtr.sh) first"
    exit 1
fi

systemctl restart nftables

echo ""
echo "=== Verification ==="
chronyc sources 2>/dev/null | head -5
echo ""
nft list ruleset | grep -A3 "prerouting" || echo "  No prerouting rules found"
echo ""
echo "=== BR-RTR (Module 2) configured ==="
