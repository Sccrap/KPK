#!/bin/bash
# ============================================================
# MODULE 1 — HQ-CLI
# Tasks: hostname, timezone (Europe/Moscow), DHCP verification,
#        DNS verification, SSH connectivity test
# PDF ref: Первый.pdf pages 4-5, 7 (HQ-CLI section)
# ============================================================
set -e

echo "[*] ========================================"
echo "[*]  MODULE 1 — HQ-CLI — Initial Setup"
echo "[*] ========================================"

# --- Run as root check ---
if [ "$(id -u)" != "0" ]; then
  echo "[!] This script must be run as root (su -)"
  exit 1
fi

# --- IP Forwarding (good practice even on client) ---
echo "[*] Enabling IPv4 forwarding..."
if grep -q 'net.ipv4.ip_forward' /etc/net/sysctl.conf 2>/dev/null; then
  sed -i 's/.*net.ipv4.ip_forward.*/net.ipv4.ip_forward = 1/' /etc/net/sysctl.conf
else
  echo 'net.ipv4.ip_forward = 1' >> /etc/net/sysctl.conf
fi
sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
echo "[+] ip_forward = 1"

# --- Interface options: TYPE=eth ---
# HQ-CLI receives IP via DHCP on ens19
echo "[*] Setting TYPE=eth in interface options file..."
IFACE=ens19
mkdir -p /etc/net/ifaces/${IFACE}
OPTIONS_FILE=/etc/net/ifaces/${IFACE}/options
if [ -f "$OPTIONS_FILE" ]; then
  sed -i 's/^TYPE=.*/TYPE=eth/' "$OPTIONS_FILE"
  # For DHCP client, also set BOOTPROTO
  sed -i 's/^BOOTPROTO=.*/BOOTPROTO=dhcp/' "$OPTIONS_FILE"
else
  cat > "$OPTIONS_FILE" << OPTS
BOOTPROTO=dhcp
TYPE=eth
DISABLED=no
NM_CONTROLLED=no
OPTS
fi
echo "[+] /etc/net/ifaces/${IFACE}/options -> TYPE=eth, BOOTPROTO=dhcp"

# --- Hostname ---
# PDF specifies full FQDN format for client
echo "[*] Setting hostname to 'hq-cli.aks42.aks'..."
hostnamectl set-hostname hq-cli.aks42.aks
echo "[+] Hostname: $(hostname)"

# --- Timezone ---
echo "[*] Setting timezone to Europe/Moscow..."
timedatectl set-timezone Europe/Moscow
echo "[+] Timezone: $(timedatectl | grep 'Time zone' | awk '{print $3}')"
timedatectl

# --- DNS resolver ---
# Point to HQ-SRV DNS after domain join
# Uncomment 'search' if commented, add nameserver
echo "[*] Configuring /etc/resolv.conf..."
cat > /etc/resolv.conf << 'EOF'
search aks42.aks
nameserver 192.168.1.2
EOF
echo "[+] /etc/resolv.conf -> nameserver 192.168.1.2, search aks42.aks"

# --- Restart network to get DHCP lease ---
echo "[*] Restarting network to get DHCP lease..."
systemctl restart network 2>/dev/null || true
sleep 3

# --- Verify DHCP lease ---
echo ""
echo "[*] --- Current IP addresses (DHCP should assign 192.168.2.x) ---"
ip -c -br a
echo ""

echo "[*] Checking connectivity to HQ-RTR (gateway)..."
if ping -c 2 -W 3 192.168.2.1 &>/dev/null; then
  echo "[+] Gateway 192.168.2.1: reachable"
else
  echo "[!] Gateway 192.168.2.1: NOT reachable — check HQ-RTR DHCP/VLAN"
fi

echo "[*] Checking connectivity to HQ-SRV..."
if ping -c 2 -W 3 192.168.1.2 &>/dev/null; then
  echo "[+] HQ-SRV 192.168.1.2: reachable"
else
  echo "[!] HQ-SRV 192.168.1.2: NOT reachable"
fi

echo "[*] Checking internet..."
if ping -c 2 -W 3 8.8.8.8 &>/dev/null; then
  echo "[+] Internet: OK"
else
  echo "[!] Internet: NOT reachable"
fi

# --- DNS check ---
echo "[*] Checking DNS resolution..."
if ping -c 1 -W 3 hq-srv.aks42.aks &>/dev/null; then
  echo "[+] DNS: hq-srv.aks42.aks resolved OK"
else
  echo "[!] DNS: hq-srv.aks42.aks NOT resolved — check BIND on HQ-SRV"
fi
if ping -c 1 -W 3 br-srv.aks42.aks &>/dev/null; then
  echo "[+] DNS: br-srv.aks42.aks resolved OK"
else
  echo "[!] DNS: br-srv.aks42.aks NOT resolved"
fi

echo ""
echo "[*] --- SSH Connectivity Tests ---"
echo "    Run manually after HQ-SRV and BR-SRV are configured:"
echo "    ssh remote_user@192.168.1.2 -p 2042"
echo "    ssh remote_user@192.168.4.2 -p 2042"
echo ""
echo "[+] ========================================"
echo "[+]  HQ-CLI MODULE 1 — COMPLETE"
echo "[!]  All client setup for Module 1 done"
echo "[+] ========================================"
