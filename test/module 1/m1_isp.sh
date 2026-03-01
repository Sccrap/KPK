#!/bin/bash
# ============================================================
# MODULE 1 — ISP
# Tasks: hostname, ip_forward, interface IPs, NAT (nftables)
#
# INTERFACE AUTO-DETECTION:
#   ISP has 3 NICs:
#     WAN  (ens19 typically) — uplink to internet, has/gets default route
#     IFace toward HQ-RTR   — assigned 172.16.1.14/28
#     IFace toward BR-RTR   — assigned 172.16.2.14/28
#
#   Detection order:
#     1. WAN  = iface that already has a default route
#        (if none, pick first physical NIC — hypervisor usually puts WAN first)
#     2. HQ   = second physical NIC (sorted alphabetically)
#     3. BR   = third physical NIC
#
# PDF ref: Первый.pdf, page 2 (ISP section)
# ============================================================
set -e

echo "[*] ========================================"
echo "[*]  MODULE 1 — ISP — Initial Setup"
echo "[*] ========================================"

# ============================================================
# INTERFACE AUTO-DETECTION
# ============================================================
echo "[*] Detecting physical network interfaces..."

# Get all physical NICs: exclude loopback, virtual bridges, tunN, sit, vlan, ovs
ALL_IFACES=( $(ip -o link show \
  | awk -F': ' '{print $2}' \
  | grep -Ev '^(lo|sit|tun|tap|veth|br-|docker|ovs|virbr|bond|dummy|vlan)' \
  | sort) )

echo "[*] Physical interfaces found: ${ALL_IFACES[*]}"
IFACE_COUNT=${#ALL_IFACES[@]}

if [ "$IFACE_COUNT" -lt 3 ]; then
  echo "[!] WARNING: Expected at least 3 interfaces, found $IFACE_COUNT: ${ALL_IFACES[*]}"
  echo "[!] Proceeding with available interfaces..."
fi

# --- Detect WAN interface (has default route) ---
WAN_IFACE=""

# Method 1: check existing default route
DEFAULT_ROUTE_IFACE=$(ip route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -1)
if [ -n "$DEFAULT_ROUTE_IFACE" ] && [[ " ${ALL_IFACES[*]} " =~ " ${DEFAULT_ROUTE_IFACE} " ]]; then
  WAN_IFACE="$DEFAULT_ROUTE_IFACE"
  echo "[+] WAN detected via default route: $WAN_IFACE"
fi

# Method 2: fallback — first NIC in sorted list (hypervisors typically attach WAN first)
if [ -z "$WAN_IFACE" ]; then
  WAN_IFACE="${ALL_IFACES[0]}"
  echo "[!] No default route found — assuming first NIC is WAN: $WAN_IFACE"
fi

# --- Remaining NICs for HQ and BR (sorted, excluding WAN) ---
REMAINING_IFACES=()
for IFACE in "${ALL_IFACES[@]}"; do
  [ "$IFACE" != "$WAN_IFACE" ] && REMAINING_IFACES+=("$IFACE")
done

HQ_IFACE="${REMAINING_IFACES[0]:-}"
BR_IFACE="${REMAINING_IFACES[1]:-}"

if [ -z "$HQ_IFACE" ] || [ -z "$BR_IFACE" ]; then
  echo "[!] ERROR: Could not detect enough interfaces for HQ and BR assignment"
  echo "    Found: WAN=$WAN_IFACE HQ=$HQ_IFACE BR=$BR_IFACE"
  echo "    Available interfaces: ${ALL_IFACES[*]}"
  exit 1
fi

echo ""
echo "[*] ============ INTERFACE ASSIGNMENT ============"
echo "    WAN  (uplink)        : $WAN_IFACE  (NAT masquerade)"
echo "    HQ-RTR facing        : $HQ_IFACE  -> 172.16.1.14/28"
echo "    BR-RTR facing        : $BR_IFACE  -> 172.16.2.14/28"
echo "[*] ================================================"
echo ""
read -t 10 -p "[?] Confirm interface assignment? [Y/n]: " CONFIRM || true
CONFIRM=${CONFIRM:-Y}
if [[ "$CONFIRM" =~ ^[Nn] ]]; then
  echo ""
  echo "[*] Manual override — enter interface names:"
  read -p "    WAN interface  (uplink to internet): " WAN_IFACE
  read -p "    HQ-RTR interface (172.16.1.14/28):  " HQ_IFACE
  read -p "    BR-RTR interface (172.16.2.14/28):  " BR_IFACE
  echo "[+] Manual assignment: WAN=$WAN_IFACE  HQ=$HQ_IFACE  BR=$BR_IFACE"
fi

# ============================================================
# HOSTNAME
# ============================================================
echo "[*] Setting hostname to 'isp'..."
hostnamectl set-hostname isp
echo "[+] Hostname: $(hostname)"

# ============================================================
# IP FORWARDING
# ============================================================
echo "[*] Enabling IPv4 forwarding..."
if grep -q 'net.ipv4.ip_forward' /etc/net/sysctl.conf 2>/dev/null; then
  sed -i 's/.*net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/' /etc/net/sysctl.conf
else
  echo 'net.ipv4.ip_forward = 1' >> /etc/net/sysctl.conf
fi
sysctl -w net.ipv4.ip_forward=1 >/dev/null
echo "[+] ip_forward = 1"

# ============================================================
# INTERFACE OPTIONS: TYPE=eth
# ============================================================
echo "[*] Setting TYPE=eth in interface options files..."
set_iface_options() {
  local IFACE="$1"
  local BOOTPROTO="${2:-static}"
  mkdir -p /etc/net/ifaces/${IFACE}
  local OPT=/etc/net/ifaces/${IFACE}/options
  if [ -f "$OPT" ]; then
    sed -i 's/^TYPE=.*/TYPE=eth/'            "$OPT"
    sed -i "s/^BOOTPROTO=.*/BOOTPROTO=${BOOTPROTO}/" "$OPT"
  else
    cat > "$OPT" << OPTS
BOOTPROTO=${BOOTPROTO}
TYPE=eth
DISABLED=no
NM_CONTROLLED=no
OPTS
  fi
  echo "[+] /etc/net/ifaces/${IFACE}/options -> TYPE=eth BOOTPROTO=${BOOTPROTO}"
}

set_iface_options "$WAN_IFACE" "static"
set_iface_options "$HQ_IFACE"  "static"
set_iface_options "$BR_IFACE"  "static"

# ============================================================
# IP ADDRESSES
# ============================================================
echo "[*] Assigning IP addresses..."

# HQ-facing interface
echo '172.16.1.14/28' > /etc/net/ifaces/${HQ_IFACE}/ipv4address
echo "[+] $HQ_IFACE = 172.16.1.14/28  (toward HQ-RTR)"

# BR-facing interface
echo '172.16.2.14/28' > /etc/net/ifaces/${BR_IFACE}/ipv4address
echo "[+] $BR_IFACE = 172.16.2.14/28  (toward BR-RTR)"

# WAN interface — no static IP needed (DHCP from provider or already configured)
# Remove any stale static IP file so WAN uses whatever was pre-assigned
echo "[*] WAN interface $WAN_IFACE — keeping existing IP (no change)"

echo "[*] Restarting network..."
systemctl restart network
echo "[+] Network restarted"

# ============================================================
# PACKAGES
# ============================================================
echo "[*] Installing packages: nano, nftables..."
apt-get update -y -q
apt-get install -y nano nftables
echo "[+] Packages installed"

# ============================================================
# NAT via nftables (masquerade on WAN interface)
# ============================================================
echo "[*] Configuring NAT masquerade on $WAN_IFACE..."

if grep -q 'table inet nat' /etc/nftables/nftables.nft 2>/dev/null; then
  echo "[!] NAT table already exists — skipping"
else
  cat >> /etc/nftables/nftables.nft << EOF

table inet nat {
  chain postrouting {
    type nat hook postrouting priority srcnat;
    oifname "${WAN_IFACE}" masquerade
  }
}
EOF
  echo "[+] NAT table added (masquerade on $WAN_IFACE)"
fi

systemctl enable --now nftables
systemctl restart nftables
echo "[+] nftables enabled"

# ============================================================
# VERIFICATION
# ============================================================
echo ""
echo "[*] --- Verification ---"
echo "    ip_forward : $(cat /proc/sys/net/ipv4/ip_forward)"
echo "    nftables   : $(systemctl is-active nftables)"
echo "    Interfaces :"
ip -br a | grep -E "${WAN_IFACE}|${HQ_IFACE}|${BR_IFACE}" || ip -br a
echo "    NAT ruleset:"
nft list table inet nat 2>/dev/null || echo "    (check manually)"
echo ""
echo "[+] ========================================"
echo "[+]  ISP MODULE 1 — COMPLETE"
echo "     WAN=$WAN_IFACE  HQ=$HQ_IFACE (172.16.1.14/28)  BR=$BR_IFACE (172.16.2.14/28)"
echo "[+] ========================================"
