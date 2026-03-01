#!/bin/bash
# ============================================================
# MODULE 1 — HQ-CLI
# Tasks: hostname, timezone, DHCP client, DNS verification,
#        SSH connectivity test
#
# INTERFACE AUTO-DETECTION:
#   HQ-CLI is a DHCP client (receives IP from HQ-RTR vlan20).
#   Detection:
#     Primary = iface that already has a 192.168.2.x DHCP lease
#     Fallback = first physical NIC — set to BOOTPROTO=dhcp
#
# PDF ref: Первый.pdf pages 4-5, 7 (HQ-CLI section)
# ============================================================
set -e

echo "[*] ========================================"
echo "[*]  MODULE 1 — HQ-CLI — Initial Setup"
echo "[*] ========================================"

if [ "$(id -u)" != "0" ]; then
  echo "[!] Must run as root (su -)"
  exit 1
fi

# ============================================================
# INTERFACE AUTO-DETECTION
# ============================================================
echo "[*] Detecting primary network interface..."

ALL_IFACES=( $(ip -o link show \
  | awk -F': ' '{print $2}' \
  | grep -Ev '^(lo|sit|tun|tap|veth|br-|docker|ovs|virbr|bond|dummy|vlan)' \
  | sort) )

echo "[*] Physical interfaces found: ${ALL_IFACES[*]}"

# Prefer iface with existing 192.168.2.x DHCP lease
PRIMARY_IFACE=""
for IFACE in "${ALL_IFACES[@]}"; do
  CURRENT_IP=$(ip -4 addr show "$IFACE" 2>/dev/null \
    | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)
  if [[ "$CURRENT_IP" =~ ^192\.168\.2\. ]]; then
    PRIMARY_IFACE="$IFACE"
    echo "[+] DHCP lease on 192.168.2.x found: $IFACE ($CURRENT_IP)"
    break
  fi
done

# Fallback: first physical NIC
if [ -z "$PRIMARY_IFACE" ]; then
  PRIMARY_IFACE="${ALL_IFACES[0]}"
  echo "[!] No 192.168.2.x lease — using first NIC: $PRIMARY_IFACE"
fi

echo ""
echo "[*] ============ INTERFACE ASSIGNMENT ============"
echo "    Primary NIC : $PRIMARY_IFACE  (DHCP, expects 192.168.2.x)"
echo "[*] ================================================"
echo ""
read -t 10 -p "[?] Confirm? [Y/n]: " CONFIRM || true
CONFIRM=${CONFIRM:-Y}
if [[ "$CONFIRM" =~ ^[Nn] ]]; then
  read -p "    Enter interface name: " PRIMARY_IFACE
  echo "[+] Manual: PRIMARY=$PRIMARY_IFACE"
fi

# ============================================================
# IP FORWARDING
# ============================================================
echo "[*] Enabling IPv4 forwarding..."
if grep -q 'net.ipv4.ip_forward' /etc/net/sysctl.conf 2>/dev/null; then
  sed -i 's/.*net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/' /etc/net/sysctl.conf
else
  echo 'net.ipv4.ip_forward = 1' >> /etc/net/sysctl.conf
fi
sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
echo "[+] ip_forward = 1"

# ============================================================
# INTERFACE OPTIONS: TYPE=eth + BOOTPROTO=dhcp
# ============================================================
echo "[*] Setting TYPE=eth BOOTPROTO=dhcp for $PRIMARY_IFACE..."
mkdir -p /etc/net/ifaces/${PRIMARY_IFACE}
OPT=/etc/net/ifaces/${PRIMARY_IFACE}/options
if [ -f "$OPT" ]; then
  sed -i 's/^TYPE=.*/TYPE=eth/'             "$OPT"
  sed -i 's/^BOOTPROTO=.*/BOOTPROTO=dhcp/'  "$OPT"
else
  cat > "$OPT" << OPTS
BOOTPROTO=dhcp
TYPE=eth
DISABLED=no
NM_CONTROLLED=no
OPTS
fi
echo "[+] /etc/net/ifaces/${PRIMARY_IFACE}/options -> TYPE=eth BOOTPROTO=dhcp"

# ============================================================
# HOSTNAME
# ============================================================
echo "[*] Setting hostname to 'hq-cli.aks42.aks'..."
hostnamectl set-hostname hq-cli.aks42.aks
echo "[+] Hostname: $(hostname)"

# ============================================================
# TIMEZONE
# ============================================================
echo "[*] Setting timezone to Europe/Moscow..."
timedatectl set-timezone Europe/Moscow
echo "[+] Timezone: $(timedatectl | grep 'Time zone' | awk '{print $3}')"

# ============================================================
# DNS — point to HQ-SRV
# ============================================================
echo "[*] Configuring DNS resolver -> HQ-SRV (192.168.1.2)..."
cat > /etc/resolv.conf << 'EOF'
search aks42.aks
nameserver 192.168.1.2
EOF
echo "[+] /etc/resolv.conf -> nameserver 192.168.1.2"

# ============================================================
# RESTART NETWORK (get DHCP lease)
# ============================================================
echo "[*] Restarting network to get DHCP lease..."
systemctl restart network 2>/dev/null || true
sleep 3

# ============================================================
# VERIFICATION
# ============================================================
echo ""
echo "[*] --- IP addresses (should have 192.168.2.x) ---"
ip -c -br a | grep -v '^lo'
echo ""

echo "[*] Connectivity checks:"
ping -c 2 -W 3 192.168.2.1 &>/dev/null \
  && echo "[+] Gateway 192.168.2.1 (HQ-RTR vlan20) : reachable" \
  || echo "[!] Gateway 192.168.2.1                  : NOT reachable"

ping -c 2 -W 3 192.168.1.2 &>/dev/null \
  && echo "[+] HQ-SRV  192.168.1.2                  : reachable" \
  || echo "[!] HQ-SRV  192.168.1.2                  : NOT reachable"

ping -c 2 -W 3 8.8.8.8 &>/dev/null \
  && echo "[+] Internet (8.8.8.8)                   : reachable" \
  || echo "[!] Internet (8.8.8.8)                   : NOT reachable"

echo ""
echo "[*] DNS checks:"
ping -c 1 -W 3 hq-srv.aks42.aks &>/dev/null \
  && echo "[+] DNS hq-srv.aks42.aks : resolved OK" \
  || echo "[!] DNS hq-srv.aks42.aks : NOT resolved — check BIND on HQ-SRV"

ping -c 1 -W 3 br-srv.aks42.aks &>/dev/null \
  && echo "[+] DNS br-srv.aks42.aks : resolved OK" \
  || echo "[!] DNS br-srv.aks42.aks : NOT resolved"

echo ""
echo "[*] SSH tests (run manually after servers are up):"
echo "    ssh remote_user@192.168.1.2 -p 2042  (HQ-SRV)"
echo "    ssh remote_user@192.168.4.2 -p 2042  (BR-SRV)"
echo ""
echo "[+] ========================================"
echo "[+]  HQ-CLI MODULE 1 — COMPLETE"
echo "     NIC=$PRIMARY_IFACE  DHCP=192.168.2.x  DNS=192.168.1.2"
echo "[+] ========================================"
