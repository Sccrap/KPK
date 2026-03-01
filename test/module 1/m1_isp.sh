#!/bin/bash
# ============================================================
# MODULE 1 — ISP
# Tasks: hostname, ip_forward, interface IPs, NAT (nftables)
# Interfaces: ens19 (external/uplink), ens20 (->HQ), ens21 (->BR)
# PDF ref: Первый.pdf, page 2 (ISP section)
# ============================================================
set -e

echo "[*] ========================================"
echo "[*]  MODULE 1 — ISP — Initial Setup"
echo "[*] ========================================"

# --- Hostname ---
echo "[*] Setting hostname to 'isp'..."
hostnamectl set-hostname isp
echo "[+] Hostname: $(hostname)"

# --- IP Forwarding ---
echo "[*] Enabling IPv4 forwarding in /etc/net/sysctl.conf..."
if grep -q 'net.ipv4.ip_forward' /etc/net/sysctl.conf 2>/dev/null; then
  sed -i 's/.*net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/' /etc/net/sysctl.conf
else
  echo 'net.ipv4.ip_forward = 1' >> /etc/net/sysctl.conf
fi
sysctl -w net.ipv4.ip_forward=1 >/dev/null
echo "[+] ip_forward = 1"

# --- Interface options: TYPE=eth (REQUIRED for ALT Linux networking) ---
# Without TYPE=eth the interface won't initialize on systemctl restart network
echo "[*] Setting TYPE=eth in interface options files..."
for IFACE in ens19 ens20 ens21; do
  mkdir -p /etc/net/ifaces/${IFACE}
  OPTIONS_FILE=/etc/net/ifaces/${IFACE}/options
  if [ -f "$OPTIONS_FILE" ]; then
    # Replace existing TYPE line
    sed -i 's/^TYPE=.*/TYPE=eth/' "$OPTIONS_FILE"
  else
    # Create fresh options file
    cat > "$OPTIONS_FILE" << OPTS
BOOTPROTO=static
TYPE=eth
DISABLED=no
NM_CONTROLLED=no
OPTS
  fi
  echo "[+] /etc/net/ifaces/${IFACE}/options -> TYPE=eth"
done

# --- IP addresses ---
echo "[*] Assigning IP addresses..."
# ens20 -> HQ-RTR side (172.16.1.14/28)
echo '172.16.1.14/28' > /etc/net/ifaces/ens20/ipv4address
echo "[+] ens20 = 172.16.1.14/28  (toward HQ-RTR)"
# ens21 -> BR-RTR side (172.16.2.14/28)
echo '172.16.2.14/28' > /etc/net/ifaces/ens21/ipv4address
echo "[+] ens21 = 172.16.2.14/28  (toward BR-RTR)"

echo "[*] Restarting network service..."
systemctl restart network
echo "[+] Network restarted"

# --- Install packages ---
echo "[*] Updating packages and installing: nano, nftables..."
apt-get update -y -q
apt-get install -y nano nftables
echo "[+] Packages installed"

# --- NAT via nftables ---
# ISP performs masquerade on ens19 (uplink to internet)
echo "[*] Configuring NAT masquerade on ens19 (nftables)..."
if grep -q 'table inet nat' /etc/nftables/nftables.nft 2>/dev/null; then
  echo "[!] NAT table already exists in nftables.nft — skipping"
else
  cat >> /etc/nftables/nftables.nft << 'EOF'

table inet nat {
  chain postrouting {
    type nat hook postrouting priority srcnat;
    oifname "ens19" masquerade
  }
}
EOF
  echo "[+] NAT table appended to /etc/nftables/nftables.nft"
fi

systemctl enable --now nftables
systemctl restart nftables
echo "[+] nftables enabled and active"

# --- Verify ---
echo ""
echo "[*] --- Verification ---"
echo "    Interfaces:"
ip -br a 2>/dev/null | grep -E 'ens19|ens20|ens21' || ip addr show
echo "    ip_forward: $(cat /proc/sys/net/ipv4/ip_forward)"
echo "    nftables: $(systemctl is-active nftables)"
echo "    NAT ruleset:"
nft list table inet nat 2>/dev/null || echo "    (nft list failed — check manually)"
echo ""
echo "[+] ========================================"
echo "[+]  ISP MODULE 1 — COMPLETE"
echo "[+] ========================================"
