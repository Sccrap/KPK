#!/bin/bash
# ============================================================
# MODULE 1 — BR-RTR
# Tasks: hostname, ip_forward, IPs, NAT, net_admin user
# PDF ref: Первый.pdf page 3 (BR-RTR section)
# ============================================================
set -e

echo "[*] ========================================"
echo "[*]  MODULE 1 — BR-RTR — Initial Setup"
echo "[*] ========================================"

# --- Hostname ---
echo "[*] Setting hostname to 'br-rtr'..."
hostnamectl set-hostname br-rtr
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
for IFACE in ens19 ens20; do
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
echo "[*] Assigning IP addresses..."
# ens19 = uplink to ISP (172.16.2.1/28)
echo '172.16.2.1/28'  > /etc/net/ifaces/ens19/ipv4address
echo 'default via 172.16.2.14' > /etc/net/ifaces/ens19/ipv4route
echo "[+] ens19 = 172.16.2.1/28  route -> 172.16.2.14 (ISP)"
# ens20 = LAN toward BR-SRV
echo '192.168.4.1/28' > /etc/net/ifaces/ens20/ipv4address
echo "[+] ens20 = 192.168.4.1/28  (toward BR-SRV)"

echo "[*] Restarting network..."
systemctl restart network
echo "[+] Network restarted"

echo "[*] Checking internet connectivity..."
if ping -c 2 -W 3 8.8.8.8 &>/dev/null; then
  echo "[+] Internet: OK"
else
  echo "[!] Internet unreachable — check ISP setup"
fi

# --- Install packages ---
echo "[*] Installing required packages..."
apt-get update -y -q
apt-get install -y nano nftables sudo frr
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
if ! grep -q '^net_admin' /etc/sudoers; then
  echo 'net_admin ALL=(ALL:ALL) NOPASSWD: ALL' >> /etc/sudoers
fi
echo "[+] net_admin: password=P@ssw0rd, sudo=NOPASSWD"

# --- Verify sudo works ---
echo "[*] Testing sudo access for net_admin..."
su - net_admin -c "sudo id" 2>/dev/null && echo "[+] sudo OK" || \
  echo "[!] sudo test failed — check manually"

# --- Final verification ---
echo ""
echo "[*] --- Verification ---"
echo "    ip_forward: $(cat /proc/sys/net/ipv4/ip_forward)"
echo "    Interfaces:"
ip -br a 2>/dev/null | grep -E 'ens19|ens20' || true
echo "    nftables: $(systemctl is-active nftables)"
echo "    NAT ruleset:"
nft list table inet nat 2>/dev/null || echo "    (check manually)"
echo ""
echo "[+] ========================================"
echo "[+]  BR-RTR MODULE 1 — COMPLETE"
echo "[+] ========================================"
