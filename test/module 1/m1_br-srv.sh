#!/bin/bash
# ============================================================
# MODULE 1 — BR-SRV
# Tasks: hostname, ip_forward, IP, remote_user (uid=2042), SSH
# PDF ref: Первый.pdf page 4 (BR-SRV section)
# ============================================================
set -e

echo "[*] ========================================"
echo "[*]  MODULE 1 — BR-SRV — Initial Setup"
echo "[*] ========================================"

# --- Hostname ---
echo "[*] Setting hostname to 'br-srv'..."
hostnamectl set-hostname br-srv
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
echo "[*] Setting TYPE=eth in interface options file..."
IFACE=ens19
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

# --- DNS resolver ---
echo "[*] Setting nameserver to 8.8.8.8..."
if ! grep -q '8.8.8.8' /etc/resolv.conf; then
  echo 'nameserver 8.8.8.8' >> /etc/resolv.conf
fi
echo "[+] /etc/resolv.conf updated"

# --- IP address ---
# PDF shows BR-SRV as 192.168.4.2/27 in network diagram
# but /28 subnet is used for BR-SRV per IP table
echo "[*] Assigning IP address..."
echo '192.168.4.2/27'          > /etc/net/ifaces/ens19/ipv4address
echo 'default via 192.168.4.1' > /etc/net/ifaces/ens19/ipv4route
echo "[+] ens19 = 192.168.4.2/27  route -> 192.168.4.1 (BR-RTR)"

echo "[*] Restarting network..."
systemctl restart network
echo "[+] Network restarted"

echo "[*] Checking internet connectivity..."
if ping -c 2 -W 3 8.8.8.8 &>/dev/null; then
  echo "[+] Internet: OK"
else
  echo "[!] Internet unreachable — check BR-RTR"
fi

# --- Install packages ---
echo "[*] Installing required packages: nano..."
apt-get update -y -q
apt-get install -y nano
echo "[+] Packages installed"

# --- User: remote_user (uid=2042) ---
echo "[*] Creating user 'remote_user' with uid=2042..."
if ! id remote_user &>/dev/null; then
  adduser --disabled-password --gecos "" --uid 2042 remote_user
  echo "[+] User remote_user created (uid=2042)"
else
  echo "[!] User remote_user already exists"
fi
echo 'remote_user:Pa$$word' | chpasswd
usermod -aG wheel remote_user
if ! grep -q '^remote_user' /etc/sudoers; then
  echo 'remote_user ALL=(ALL:ALL) NOPASSWD: ALL' >> /etc/sudoers
fi
echo "[+] remote_user: password=Pa\$\$word, uid=$(id -u remote_user), sudo=NOPASSWD"

# --- SSH configuration (port 2042) ---
echo "[*] Configuring SSH daemon (port 2042)..."
SSHD_CFG=/etc/openssh/sshd_config

sed -i 's/^#\?Port .*/Port 2042/' "$SSHD_CFG"
sed -i 's/^#\?MaxAuthTries .*/MaxAuthTries 2/' "$SSHD_CFG"
sed -i 's|^#\?Banner .*|Banner /var/sshbanner|' "$SSHD_CFG"
if grep -q '^AllowUsers' "$SSHD_CFG"; then
  sed -i 's/^AllowUsers .*/AllowUsers remote_user/' "$SSHD_CFG"
else
  echo 'AllowUsers remote_user' >> "$SSHD_CFG"
fi

cat > /var/sshbanner << 'EOF'
============================================
  Authorized access only — BR-SRV
============================================
EOF

systemctl enable --now sshd
systemctl restart sshd
echo "[+] SSH configured: port=2042, MaxAuthTries=2, AllowUsers=remote_user"

# --- Final verification ---
echo ""
echo "[*] --- Verification ---"
echo "    ip_forward: $(cat /proc/sys/net/ipv4/ip_forward)"
echo "    Interface: $(ip -br a show ens19 2>/dev/null)"
echo "    SSH port: $(ss -tlnp | grep sshd | awk '{print $4}' | head -1)"
echo "    remote_user uid: $(id -u remote_user 2>/dev/null)"
echo ""
echo "[+] ========================================"
echo "[+]  BR-SRV MODULE 1 — COMPLETE"
echo "[!]  Test SSH: ssh remote_user@192.168.4.2 -p 2042"
echo "[+] ========================================"
