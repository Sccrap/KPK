#!/bin/bash
# ============================================================
# MODULE 1 — HQ-RTR
# Tasks: hostname, ip_forward, IPs, NAT, net_admin user,
#        OpenVSwitch VLANs (10/20/99), DHCP server
#
# INTERFACE AUTO-DETECTION:
#   HQ-RTR has 4 NICs:
#     WAN      — uplink to ISP (172.16.1.1/28), has/gets default route
#     LAN-SRV  — toward HQ-SRV  (VLAN10 / 192.168.1.0/27)
#     LAN-CLI  — toward HQ-CLI  (VLAN20 / 192.168.2.0/28)
#     LAN-MGMT — management net (VLAN99 / 192.168.3.0/29)
#
#   Detection:
#     WAN  = iface with default route (or first sorted NIC)
#     LAN interfaces = remaining 3 NICs in sorted alphabetical order
#
# PDF ref: Первый.pdf pages 2-6 (HQ-RTR sections)
# ============================================================
set -e

echo "[*] ========================================"
echo "[*]  MODULE 1 — HQ-RTR — Initial Setup"
echo "[*] ========================================"

# ============================================================
# INTERFACE AUTO-DETECTION
# ============================================================
echo "[*] Detecting physical network interfaces..."

ALL_IFACES=( $(ip -o link show \
  | awk -F': ' '{print $2}' \
  | grep -Ev '^(lo|sit|tun|tap|veth|br-|docker|ovs|virbr|bond|dummy|vlan|hq-sw)' \
  | sort) )

echo "[*] Physical interfaces found: ${ALL_IFACES[*]}"
IFACE_COUNT=${#ALL_IFACES[@]}

if [ "$IFACE_COUNT" -lt 4 ]; then
  echo "[!] WARNING: Expected 4 interfaces for HQ-RTR, found $IFACE_COUNT: ${ALL_IFACES[*]}"
fi

# --- WAN: interface with existing default route ---
WAN_IFACE=""
DEFAULT_ROUTE_IFACE=$(ip route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -1)
if [ -n "$DEFAULT_ROUTE_IFACE" ] && [[ " ${ALL_IFACES[*]} " =~ " ${DEFAULT_ROUTE_IFACE} " ]]; then
  WAN_IFACE="$DEFAULT_ROUTE_IFACE"
  echo "[+] WAN detected via default route: $WAN_IFACE"
else
  WAN_IFACE="${ALL_IFACES[0]}"
  echo "[!] No default route found — assuming first NIC is WAN: $WAN_IFACE"
fi

# --- LAN interfaces: remaining NICs sorted ---
LAN_IFACES=()
for IFACE in "${ALL_IFACES[@]}"; do
  [ "$IFACE" != "$WAN_IFACE" ] && LAN_IFACES+=("$IFACE")
done

LAN_SRV="${LAN_IFACES[0]:-}"   # VLAN10 -> HQ-SRV (192.168.1.0/27)
LAN_CLI="${LAN_IFACES[1]:-}"   # VLAN20 -> HQ-CLI (192.168.2.0/28)
LAN_MGT="${LAN_IFACES[2]:-}"   # VLAN99 -> Management (192.168.3.0/29)

echo ""
echo "[*] ============ INTERFACE ASSIGNMENT ============"
echo "    WAN (uplink to ISP)  : $WAN_IFACE  -> 172.16.1.1/28"
echo "    LAN-SRV  (VLAN10)    : $LAN_SRV   -> 192.168.1.1/27"
echo "    LAN-CLI  (VLAN20)    : $LAN_CLI   -> 192.168.2.1/28"
echo "    LAN-MGMT (VLAN99)    : $LAN_MGT   -> 192.168.3.1/29"
echo "[*] ================================================"
echo ""
read -t 10 -p "[?] Confirm interface assignment? [Y/n]: " CONFIRM || true
CONFIRM=${CONFIRM:-Y}
if [[ "$CONFIRM" =~ ^[Nn] ]]; then
  echo ""
  echo "[*] Manual override — enter interface names:"
  read -p "    WAN interface (uplink to ISP 172.16.1.x): " WAN_IFACE
  read -p "    LAN-SRV (VLAN10, toward HQ-SRV):          " LAN_SRV
  read -p "    LAN-CLI (VLAN20, toward HQ-CLI):           " LAN_CLI
  read -p "    LAN-MGMT (VLAN99, management):             " LAN_MGT
fi

# Validate mandatory interfaces
for VAR_NAME in WAN_IFACE LAN_SRV LAN_CLI LAN_MGT; do
  VAL="${!VAR_NAME}"
  if [ -z "$VAL" ]; then
    echo "[!] ERROR: $VAR_NAME is empty. Check interface count."
    exit 1
  fi
done

echo "[+] Final assignment: WAN=$WAN_IFACE  LAN_SRV=$LAN_SRV  LAN_CLI=$LAN_CLI  LAN_MGT=$LAN_MGT"

# ============================================================
# HOSTNAME
# ============================================================
echo "[*] Setting hostname to 'hq-rtr'..."
hostnamectl set-hostname hq-rtr
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
# HELPER: set interface options (TYPE=eth)
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
set_iface_options "$LAN_SRV"   "static"
set_iface_options "$LAN_CLI"   "static"
set_iface_options "$LAN_MGT"   "static"

# ============================================================
# DNS resolver
# ============================================================
echo "[*] Setting nameserver to 8.8.8.8..."
if ! grep -q '8.8.8.8' /etc/resolv.conf; then
  echo 'nameserver 8.8.8.8' >> /etc/resolv.conf
fi
echo "[+] /etc/resolv.conf updated"

# ============================================================
# IP ADDRESSES
# ============================================================
echo "[*] Assigning IP addresses..."
echo '172.16.1.1/28'          > /etc/net/ifaces/${WAN_IFACE}/ipv4address
echo 'default via 172.16.1.14' > /etc/net/ifaces/${WAN_IFACE}/ipv4route
echo "[+] $WAN_IFACE = 172.16.1.1/28  default route -> 172.16.1.14 (ISP)"

# LAN ports get temporary IPs (removed after OVS bridge setup below)
echo '192.168.1.1/27' > /etc/net/ifaces/${LAN_SRV}/ipv4address
echo '192.168.2.1/28' > /etc/net/ifaces/${LAN_CLI}/ipv4address
echo '192.168.3.1/29' > /etc/net/ifaces/${LAN_MGT}/ipv4address
echo "[+] $LAN_SRV = 192.168.1.1/27  (temporary, will be moved to vlan10)"
echo "[+] $LAN_CLI = 192.168.2.1/28  (temporary, will be moved to vlan20)"
echo "[+] $LAN_MGT = 192.168.3.1/29  (temporary, will be moved to vlan99)"

echo "[*] Restarting network..."
systemctl restart network
echo "[+] Network restarted"

echo "[*] Checking internet connectivity..."
if ping -c 2 -W 3 8.8.8.8 &>/dev/null; then
  echo "[+] Internet: OK"
else
  echo "[!] Internet unreachable — check ISP"
fi

# ============================================================
# PACKAGES
# ============================================================
echo "[*] Installing packages..."
apt-get update -y -q
apt-get install -y nano nftables sudo dhcp-server NetworkManager-ovs frr
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
# OPENVSWITCH VLANs
# ============================================================
echo "[*] Configuring OpenVSwitch bridge 'hq-sw'..."
systemctl enable --now openvswitch
systemctl start openvswitch

# Create bridge (idempotent)
if ! ovs-vsctl br-exists hq-sw 2>/dev/null; then
  ovs-vsctl add-br hq-sw
  echo "[+] OVS bridge hq-sw created"
else
  echo "[!] OVS bridge hq-sw already exists"
fi

# Attach physical ports with VLAN tags
ovs-vsctl add-port hq-sw "${LAN_SRV}" tag=10 2>/dev/null || echo "[!] $LAN_SRV already in bridge"
ovs-vsctl add-port hq-sw "${LAN_CLI}" tag=20 2>/dev/null || echo "[!] $LAN_CLI already in bridge"
ovs-vsctl add-port hq-sw "${LAN_MGT}" tag=99 2>/dev/null || echo "[!] $LAN_MGT already in bridge"

# Create internal VLAN interfaces (these get the IPs)
ovs-vsctl add-port hq-sw vlan10 tag=10 -- set interface vlan10 type=internal 2>/dev/null || true
ovs-vsctl add-port hq-sw vlan20 tag=20 -- set interface vlan20 type=internal 2>/dev/null || true
ovs-vsctl add-port hq-sw vlan99 tag=99 -- set interface vlan99 type=internal 2>/dev/null || true

echo "[+] OVS: $LAN_SRV(tag=10)  $LAN_CLI(tag=20)  $LAN_MGT(tag=99)"
echo "[+] OVS internal interfaces: vlan10 vlan20 vlan99"

ovs-vsctl list-br
ovs-vsctl list-ports hq-sw
systemctl restart openvswitch

# Remove static IPs from physical LAN ports (IPs go on vlan10/20/99 now)
rm -f /etc/net/ifaces/${LAN_SRV}/ipv4address
rm -f /etc/net/ifaces/${LAN_CLI}/ipv4address
rm -f /etc/net/ifaces/${LAN_MGT}/ipv4address
echo "[+] Cleared static IPs from $LAN_SRV / $LAN_CLI / $LAN_MGT"

ip link set hq-sw up

# ============================================================
# vlan.sh — assigns IPs to VLAN interfaces on every boot
# ============================================================
echo "[*] Creating /root/vlan.sh..."
cat > /root/vlan.sh << 'VLANEOF'
#!/bin/bash
# Assign IPs to OVS VLAN internal interfaces after boot
ip a add 192.168.1.1/27 dev vlan10 2>/dev/null || true
ip a add 192.168.2.1/28 dev vlan20 2>/dev/null || true
ip a add 192.168.3.1/29 dev vlan99 2>/dev/null || true
systemctl restart dhcpd 2>/dev/null || true
VLANEOF
chmod +x /root/vlan.sh
echo "[+] /root/vlan.sh created"

if ! grep -q 'vlan.sh' /root/.bashrc; then
  echo 'bash /root/vlan.sh' >> /root/.bashrc
  echo "[+] vlan.sh registered in /root/.bashrc (runs on login)"
fi

# Apply immediately
bash /root/vlan.sh
echo "[+] VLAN IPs applied"

# ============================================================
# DHCP SERVER (serves HQ-CLI via vlan20)
# ============================================================
echo "[*] Configuring DHCP server for vlan20..."
cp /etc/dhcp/dhcpd.conf.example /etc/dhcp/dhcpd.conf

cat > /etc/dhcp/dhcpd.conf << 'EOF'
# HQ-RTR DHCP — serves HQ-CLI (vlan20: 192.168.2.0/28)
subnet 192.168.2.0 netmask 255.255.255.240 {
  range 192.168.2.2 192.168.2.14;
  option routers 192.168.2.1;
  option domain-name-servers 192.168.1.2;
  option domain-name "aks42.aks";
  default-lease-time 600;
  max-lease-time 7200;
}
EOF

echo 'DHCPDARGS=vlan20' > /etc/sysconfig/dhcpd
systemctl enable --now dhcpd
echo "[+] DHCP server configured on vlan20"
systemctl status dhcpd --no-pager | head -4 || true

# ============================================================
# SAVE DETECTED IFACE NAMES for Module 2 scripts
# ============================================================
cat > /root/iface_vars.sh << EOF
# Auto-detected interface names (generated by m1_hq-rtr.sh)
HQ_RTR_WAN="${WAN_IFACE}"
HQ_RTR_LAN_SRV="${LAN_SRV}"
HQ_RTR_LAN_CLI="${LAN_CLI}"
HQ_RTR_LAN_MGT="${LAN_MGT}"
EOF
echo "[+] Interface names saved to /root/iface_vars.sh (used by Module 2)"

# ============================================================
# VERIFICATION
# ============================================================
echo ""
echo "[*] --- Verification ---"
echo "    ip_forward : $(cat /proc/sys/net/ipv4/ip_forward)"
echo "    nftables   : $(systemctl is-active nftables)"
echo "    DHCP       : $(systemctl is-active dhcpd)"
echo "    Interfaces :"
ip -br a | grep -E "${WAN_IFACE}|vlan10|vlan20|vlan99|hq-sw" || true
echo "    OVS ports  : $(ovs-vsctl list-ports hq-sw 2>/dev/null | tr '\n' ' ')"
echo ""
echo "[+] ========================================"
echo "[+]  HQ-RTR MODULE 1 — COMPLETE"
echo "     WAN=$WAN_IFACE  SRV=$LAN_SRV(vlan10)  CLI=$LAN_CLI(vlan20)  MGT=$LAN_MGT(vlan99)"
echo "[!]  REBOOT REQUIRED: run 'reboot' now"
echo "[+] ========================================"
