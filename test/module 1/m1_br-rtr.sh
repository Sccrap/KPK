#!/bin/bash
# ============================================================
# MODULE 1 — BR-RTR
# Tasks: hostname, ip_forward, IPs, NAT, net_admin user
#
# INTERFACE AUTO-DETECTION:
#   BR-RTR has 2 NICs:
#     WAN — uplink to ISP (172.16.2.1/28), has default route
#     LAN — toward BR-SRV  (192.168.4.1/28)
#
#   Detection:
#     WAN = iface with existing default route
#           fallback: first sorted NIC (hypervisor puts WAN first)
#     LAN = the other NIC
#
# PDF ref: Первый.pdf page 3 (BR-RTR section)
# ============================================================
set -e

echo "[*] ========================================"
echo "[*]  MODULE 1 — BR-RTR — Initial Setup"
echo "[*] ========================================"

# ============================================================
# INTERFACE AUTO-DETECTION
# ============================================================
echo "[*] Detecting physical network interfaces..."

ALL_IFACES=( $(ip -o link show \
  | awk -F': ' '{print $2}' \
  | grep -Ev '^(lo|sit|tun|tap|veth|br-|docker|ovs|virbr|bond|dummy|vlan)' \
  | sort) )

echo "[*] Physical interfaces found: ${ALL_IFACES[*]}"

if [ "${#ALL_IFACES[@]}" -lt 2 ]; then
  echo "[!] WARNING: Expected 2 interfaces, found ${#ALL_IFACES[@]}"
fi

# WAN = iface with default route; fallback = first NIC
WAN_IFACE=""
DEFAULT_ROUTE_IFACE=$(ip route show default 2>/dev/null \
  | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -1)
if [ -n "$DEFAULT_ROUTE_IFACE" ] && \
   [[ " ${ALL_IFACES[*]} " =~ " ${DEFAULT_ROUTE_IFACE} " ]]; then
  WAN_IFACE="$DEFAULT_ROUTE_IFACE"
  echo "[+] WAN detected via default route: $WAN_IFACE"
else
  WAN_IFACE="${ALL_IFACES[0]}"
  echo "[!] No default route — assuming first NIC is WAN: $WAN_IFACE"
fi

# LAN = remaining NIC(s)
LAN_IFACES=()
for IFACE in "${ALL_IFACES[@]}"; do
  [ "$IFACE" != "$WAN_IFACE" ] && LAN_IFACES+=("$IFACE")
done
LAN_IFACE="${LAN_IFACES[0]:-}"

if [ -z "$LAN_IFACE" ]; then
  echo "[!] ERROR: Cannot detect LAN interface. Found: ${ALL_IFACES[*]}"
  exit 1
fi

echo ""
echo "[*] ============ INTERFACE ASSIGNMENT ============"
echo "    WAN (uplink to ISP)  : $WAN_IFACE  -> 172.16.2.1/28"
echo "    LAN (toward BR-SRV)  : $LAN_IFACE  -> 192.168.4.1/28"
echo "[*] ================================================"
echo ""
read -t 10 -p "[?] Confirm? [Y/n]: " CONFIRM || true
CONFIRM=${CONFIRM:-Y}
if [[ "$CONFIRM" =~ ^[Nn] ]]; then
  read -p "    WAN interface (uplink to ISP): " WAN_IFACE
  read -p "    LAN interface (toward BR-SRV): " LAN_IFACE
  echo "[+] Manual: WAN=$WAN_IFACE  LAN=$LAN_IFACE"
fi

# ============================================================
# HOSTNAME
# ============================================================
echo "[*] Setting hostname to 'br-rtr'..."
hostnamectl set-hostname br-rtr
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
# HELPER: set TYPE=eth in options file
# ============================================================
set_iface_options() {
  local IFACE="$1"
  local BOOTPROTO="${2:-static}"
  mkdir -p /etc/net/ifaces/${IFACE}
  local OPT=/etc/net/ifaces/${IFACE}/options
  if [ -f "$OPT" ]; then
    sed -i 's/^TYPE=.*/TYPE=eth/'                    "$OPT"
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

# ============================================================
# INTERFACE OPTIONS: TYPE=eth
# ============================================================
echo "[*] Setting TYPE=eth in interface options files..."
set_iface_options "$WAN_IFACE" "static"
set_iface_options "$LAN_IFACE" "static"

# ============================================================
# DNS resolver
# ============================================================
echo "[*] Setting temporary nameserver 8.8.8.8..."
if ! grep -q '8.8.8.8' /etc/resolv.conf; then
  echo 'nameserver 8.8.8.8' >> /etc/resolv.conf
fi

# ============================================================
# IP ADDRESSES
# ============================================================
echo "[*] Assigning IP addresses..."
echo '172.16.2.1/28'           > /etc/net/ifaces/${WAN_IFACE}/ipv4address
echo 'default via 172.16.2.14' > /etc/net/ifaces/${WAN_IFACE}/ipv4route
echo "[+] $WAN_IFACE = 172.16.2.1/28  route -> 172.16.2.14 (ISP)"

echo '192.168.4.1/28' > /etc/net/ifaces/${LAN_IFACE}/ipv4address
echo "[+] $LAN_IFACE = 192.168.4.1/28  (toward BR-SRV)"

echo "[*] Restarting network..."
systemctl restart network
echo "[+] Network restarted"

echo "[*] Checking internet connectivity..."
ping -c 2 -W 3 8.8.8.8 &>/dev/null \
  && echo "[+] Internet: OK" \
  || echo "[!] Internet unreachable — check ISP"

# ============================================================
# PACKAGES
# ============================================================
echo "[*] Installing packages..."
apt-get update -y -q
apt-get install -y nano nftables sudo frr
echo "[+] Packages installed"

# ============================================================
# NAT (nftables) — masquerade on WAN
# ============================================================
echo "[*] Configuring NAT masquerade on $WAN_IFACE..."
if grep -q 'table inet nat' /etc/nftables/nftables.nft 2>/dev/null; then
  echo "[!] NAT table already present — skipping"
else
  cat >> /etc/nftables/nftables.nft << EOF

table inet nat {
  chain postrouting {
    type nat hook postrouting priority srcnat;
    oifname "${WAN_IFACE}" masquerade
  }
}
EOF
fi
systemctl enable --now nftables
systemctl restart nftables
echo "[+] NAT configured on $WAN_IFACE"

# ============================================================
# USER: net_admin
# ============================================================
echo "[*] Creating user 'net_admin'..."
if ! id net_admin &>/dev/null; then
  adduser --disabled-password --gecos "" net_admin
  echo "[+] User net_admin created"
else
  echo "[!] User net_admin already exists — updating password"
fi
echo "net_admin:P@ssw0rd" | chpasswd
usermod -aG wheel net_admin
if ! grep -q '^net_admin' /etc/sudoers; then
  echo 'net_admin ALL=(ALL:ALL) NOPASSWD: ALL' >> /etc/sudoers
fi
echo "[+] net_admin: password=P@ssw0rd, sudo=NOPASSWD"

# ============================================================
# SAVE DETECTED IFACE NAMES for Module 2 scripts
# ============================================================
cat > /root/iface_vars.sh << EOF
# Auto-detected interface names (generated by m1_br-rtr.sh)
BR_RTR_WAN="${WAN_IFACE}"
BR_RTR_LAN="${LAN_IFACE}"
EOF
echo "[+] Interface names saved to /root/iface_vars.sh (used by Module 2)"

# ============================================================
# VERIFICATION
# ============================================================
echo ""
echo "[*] --- Verification ---"
echo "    ip_forward : $(cat /proc/sys/net/ipv4/ip_forward)"
echo "    nftables   : $(systemctl is-active nftables)"
echo "    Interfaces :"
ip -br a | grep -E "${WAN_IFACE}|${LAN_IFACE}" || true
echo "    NAT ruleset:"
nft list table inet nat 2>/dev/null || echo "    (check manually)"
echo ""
echo "[+] ========================================"
echo "[+]  BR-RTR MODULE 1 — COMPLETE"
echo "     WAN=$WAN_IFACE (172.16.2.1/28)  LAN=$LAN_IFACE (192.168.4.1/28)"
echo "[+] ========================================"
