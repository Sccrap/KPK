#!/bin/bash
# ============================================================
# MODULE 1 — HQ-RTR
# Tasks: hostname, ip_forward, IPs, NAT, net_admin user,
#        OpenVSwitch VLANs (10/20/99), DHCP server
# PDF ref: Первый.pdf pages 2-6 (HQ-RTR sections)
# ============================================================
set -e

echo "[*] ========================================"
echo "[*]  MODULE 1 — HQ-RTR — Initial Setup"
echo "[*] ========================================"

# --- Hostname ---
echo "[*] Setting hostname to 'hq-rtr'..."
hostnamectl set-hostname hq-rtr
echo "[+] Hostname: $(hostname)"

# --- IP Forwarding ---
echo "[*] Enabling IPv4 forwarding..."
if grep -q 'net.ipv4.ip_forward' /etc/net/sysctl.conf 2>/dev/null; then
  sed -i 's/.*net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/' /etc/net/sysctl.conf
else
  echo 'net.ipv4.ip_forward = 1' >> /etc/net/sysctl.conf
fi
sysctl -w net.ipv4.ip_forward=1 >/dev/null
echo "[+] ip_forward = 1"

# --- Interface options: TYPE=eth ---
echo "[*] Setting TYPE=eth in interface options files..."
for IFACE in ens19 ens20 ens21 ens22; do
  mkdir -p /etc/net/ifaces/${IFACE}
  OPTIONS_FILE=/etc/net/ifaces/${IFACE}/options
  if [ -f "$OPTIONS_FILE" ]; then
    sed -i 's/^TYPE=.*/TYPE=eth/' "$OPTIONS_FILE"
  else
    cat > "$OPTIONS_FILE" << OPTS
BOOTPROTO=static
TYPE=eth
DISABLED=no
NM_CONTROLLED=no
OPTS
  fi
  echo "[+] /etc/net/ifaces/${IFACE}/options -> TYPE=eth"
done

# --- DNS resolver ---
echo "[*] Setting nameserver to 8.8.8.8..."
if ! grep -q '8.8.8.8' /etc/resolv.conf; then
  echo 'nameserver 8.8.8.8' >> /etc/resolv.conf
fi
echo "[+] /etc/resolv.conf updated"

# --- IP addresses ---
# NOTE: ens20/ens21/ens22 will be removed later after OVS bridge setup
# ens19 = uplink to ISP
echo "[*] Assigning IP addresses..."
echo '172.16.1.1/28'  > /etc/net/ifaces/ens19/ipv4address
echo '192.168.1.1/27' > /etc/net/ifaces/ens20/ipv4address
echo '192.168.2.1/28' > /etc/net/ifaces/ens21/ipv4address
echo '192.168.3.1/29' > /etc/net/ifaces/ens22/ipv4address
echo 'default via 172.16.1.14' > /etc/net/ifaces/ens19/ipv4route
echo "[+] ens19 = 172.16.1.1/28  route -> 172.16.1.14"
echo "[+] ens20 = 192.168.1.1/27"
echo "[+] ens21 = 192.168.2.1/28"
echo "[+] ens22 = 192.168.3.1/29"

echo "[*] Restarting network..."
systemctl restart network
echo "[+] Network restarted"

echo "[*] Checking internet connectivity..."
if ping -c 2 -W 3 8.8.8.8 &>/dev/null; then
  echo "[+] Internet: OK"
else
  echo "[!] Internet unreachable — check ISP setup before continuing"
fi

# --- Install packages ---
echo "[*] Installing required packages..."
apt-get update -y -q
apt-get install -y nano nftables sudo dhcp-server NetworkManager-ovs frr
echo "[+] Packages installed"

# --- NAT (nftables) ---
echo "[*] Configuring NAT masquerade (ens19)..."
if grep -q 'table inet nat' /etc/nftables/nftables.nft 2>/dev/null; then
  echo "[!] NAT table already present — skipping"
else
  cat >> /etc/nftables/nftables.nft << 'EOF'

table inet nat {
  chain postrouting {
    type nat hook postrouting priority srcnat;
    oifname "ens19" masquerade
  }
}
EOF
fi
systemctl enable --now nftables
systemctl restart nftables
echo "[+] NAT configured"

# --- User: net_admin ---
echo "[*] Creating user 'net_admin'..."
if ! id net_admin &>/dev/null; then
  adduser --disabled-password --gecos "" net_admin
  echo "[+] User net_admin created"
else
  echo "[!] User net_admin already exists — updating password"
fi
echo "net_admin:P@ssw0rd" | chpasswd
usermod -aG wheel net_admin
# Add to sudoers only once
if ! grep -q '^net_admin' /etc/sudoers; then
  echo 'net_admin ALL=(ALL:ALL) NOPASSWD: ALL' >> /etc/sudoers
fi
echo "[+] net_admin: password=P@ssw0rd, sudo=NOPASSWD"

# --- OpenVSwitch VLANs ---
echo "[*] Configuring OpenVSwitch bridge and VLANs..."
systemctl enable --now openvswitch
systemctl start openvswitch

# Create bridge (idempotent)
if ! ovs-vsctl br-exists hq-sw 2>/dev/null; then
  ovs-vsctl add-br hq-sw
  echo "[+] OVS bridge hq-sw created"
else
  echo "[!] OVS bridge hq-sw already exists"
fi

# Add physical ports with VLAN tags (errors are ok if already added)
ovs-vsctl add-port hq-sw ens20 tag=10 2>/dev/null || echo "[!] ens20 already in bridge"
ovs-vsctl add-port hq-sw ens21 tag=20 2>/dev/null || echo "[!] ens21 already in bridge"
ovs-vsctl add-port hq-sw ens22 tag=99 2>/dev/null || echo "[!] ens22 already in bridge"

# Add internal VLAN interfaces
ovs-vsctl add-port hq-sw vlan10 tag=10 -- set interface vlan10 type=internal 2>/dev/null || true
ovs-vsctl add-port hq-sw vlan20 tag=20 -- set interface vlan20 type=internal 2>/dev/null || true
ovs-vsctl add-port hq-sw vlan99 tag=99 -- set interface vlan99 type=internal 2>/dev/null || true

echo "[+] OVS ports: ens20(tag=10) ens21(tag=20) ens22(tag=99)"
echo "[+] OVS internal: vlan10 vlan20 vlan99"

# Verify
ovs-vsctl list-br
ovs-vsctl list-ports hq-sw

systemctl restart openvswitch

# Remove static IPs from physical ports (now handled by OVS VLANs)
rm -f /etc/net/ifaces/ens20/ipv4address
rm -f /etc/net/ifaces/ens21/ipv4address
rm -f /etc/net/ifaces/ens22/ipv4address
echo "[+] Removed static IPs from ens20/ens21/ens22"

ip link set hq-sw up

# --- vlan.sh startup script ---
echo "[*] Creating /root/vlan.sh for VLAN IP assignment..."
cat > /root/vlan.sh << 'VLANEOF'
#!/bin/bash
# Assign IPs to OVS VLAN internal interfaces
ip a add 192.168.1.1/27 dev vlan10 2>/dev/null || true
ip a add 192.168.2.1/28 dev vlan20 2>/dev/null || true
ip a add 192.168.3.1/29 dev vlan99 2>/dev/null || true
# Restart DHCP after IPs are up
systemctl restart dhcpd 2>/dev/null || true
VLANEOF
chmod +x /root/vlan.sh
echo "[+] /root/vlan.sh created"

# Add to ~/.bashrc so it runs on login (persists across reboots)
if ! grep -q 'vlan.sh' /root/.bashrc; then
  echo 'bash /root/vlan.sh' >> /root/.bashrc
  echo "[+] vlan.sh added to /root/.bashrc"
fi

# Apply now
bash /root/vlan.sh
echo "[+] VLAN IPs applied"

# --- DHCP server ---
echo "[*] Configuring DHCP server for vlan20 (192.168.2.0/28)..."
cp /etc/dhcp/dhcpd.conf.example /etc/dhcp/dhcpd.conf

cat > /etc/dhcp/dhcpd.conf << 'EOF'
# HQ-RTR DHCP — serves HQ-CLI via vlan20
# Topology: 192.168.2.0/28, gateway=192.168.2.1, DNS=192.168.1.2
subnet 192.168.2.0 netmask 255.255.255.240 {
  range 192.168.2.2 192.168.2.14;
  option routers 192.168.2.1;
  option domain-name-servers 192.168.1.2;
  option domain-name "aks42.aks";
  default-lease-time 600;
  max-lease-time 7200;
}
EOF

# DHCP listens on vlan20 interface
echo 'DHCPDARGS=vlan20' > /etc/sysconfig/dhcpd
systemctl enable --now dhcpd
echo "[+] DHCP server configured on vlan20"
systemctl status dhcpd --no-pager || true

# --- Final verification ---
echo ""
echo "[*] --- Verification ---"
echo "    ip_forward: $(cat /proc/sys/net/ipv4/ip_forward)"
echo "    Interfaces:"
ip -br a 2>/dev/null | grep -E 'ens19|vlan10|vlan20|vlan99|hq-sw' || true
echo "    OVS bridge: $(ovs-vsctl show 2>/dev/null | head -20)"
echo "    nftables: $(systemctl is-active nftables)"
echo "    DHCP: $(systemctl is-active dhcpd)"
echo ""
echo "[+] ========================================"
echo "[+]  HQ-RTR MODULE 1 — COMPLETE"
echo "[!]  REBOOT REQUIRED: run 'reboot' now"
echo "[+] ========================================"
