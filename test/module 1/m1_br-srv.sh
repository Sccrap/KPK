#!/bin/bash
# ============================================================
# MODULE 1 — BR-SRV
# Tasks: hostname, ip_forward, IP, remote_user (uid=2042), SSH
#
# INTERFACE AUTO-DETECTION:
#   BR-SRV typically has 1 NIC.
#   The single interface gets 192.168.4.2/27, GW=192.168.4.1
#
#   Detection:
#     Primary = iface already in 192.168.4.x range
#     Fallback = first physical NIC (alphabetically sorted)
#
# PDF ref: Первый.pdf page 4 (BR-SRV section)
# ============================================================
set -e

echo "[*] ========================================"
echo "[*]  MODULE 1 — BR-SRV — Initial Setup"
echo "[*] ========================================"

# ============================================================
# INTERFACE AUTO-DETECTION
# ============================================================
echo "[*] Detecting primary network interface..."

ALL_IFACES=( $(ip -o link show \
  | awk -F': ' '{print $2}' \
  | grep -Ev '^(lo|sit|tun|tap|veth|br-|docker|ovs|virbr|bond|dummy|vlan)' \
  | sort) )

echo "[*] Physical interfaces found: ${ALL_IFACES[*]}"

# Prefer iface already in 192.168.4.x range
PRIMARY_IFACE=""
for IFACE in "${ALL_IFACES[@]}"; do
  CURRENT_IP=$(ip -4 addr show "$IFACE" 2>/dev/null \
    | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)
  if [[ "$CURRENT_IP" =~ ^192\.168\.4\. ]]; then
    PRIMARY_IFACE="$IFACE"
    echo "[+] Interface with 192.168.4.x found: $IFACE ($CURRENT_IP)"
    break
  fi
done

# Fallback: first physical NIC
if [ -z "$PRIMARY_IFACE" ]; then
  PRIMARY_IFACE="${ALL_IFACES[0]}"
  echo "[!] No 192.168.4.x address found — using first NIC: $PRIMARY_IFACE"
fi

echo ""
echo "[*] ============ INTERFACE ASSIGNMENT ============"
echo "    Primary NIC : $PRIMARY_IFACE  -> 192.168.4.2/27"
echo "    Gateway     : 192.168.4.1 (BR-RTR LAN)"
echo "[*] ================================================"
echo ""
read -t 10 -p "[?] Confirm? [Y/n]: " CONFIRM || true
CONFIRM=${CONFIRM:-Y}
if [[ "$CONFIRM" =~ ^[Nn] ]]; then
  read -p "    Enter interface name: " PRIMARY_IFACE
  echo "[+] Manual: PRIMARY=$PRIMARY_IFACE"
fi

# ============================================================
# HOSTNAME
# ============================================================
echo "[*] Setting hostname to 'br-srv'..."
hostnamectl set-hostname br-srv
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
echo "[*] Setting TYPE=eth in /etc/net/ifaces/${PRIMARY_IFACE}/options..."
mkdir -p /etc/net/ifaces/${PRIMARY_IFACE}
OPT=/etc/net/ifaces/${PRIMARY_IFACE}/options
if [ -f "$OPT" ]; then
  sed -i 's/^TYPE=.*/TYPE=eth/'              "$OPT"
  sed -i 's/^BOOTPROTO=.*/BOOTPROTO=static/' "$OPT"
else
  cat > "$OPT" << OPTS
BOOTPROTO=static
TYPE=eth
DISABLED=no
NM_CONTROLLED=no
OPTS
fi
echo "[+] /etc/net/ifaces/${PRIMARY_IFACE}/options -> TYPE=eth"

# ============================================================
# DNS resolver
# ============================================================
if ! grep -q '8.8.8.8' /etc/resolv.conf; then
  echo 'nameserver 8.8.8.8' >> /etc/resolv.conf
fi

# ============================================================
# IP ADDRESS
# ============================================================
echo "[*] Assigning IP address..."
echo '192.168.4.2/27'          > /etc/net/ifaces/${PRIMARY_IFACE}/ipv4address
echo 'default via 192.168.4.1' > /etc/net/ifaces/${PRIMARY_IFACE}/ipv4route
echo "[+] $PRIMARY_IFACE = 192.168.4.2/27  route -> 192.168.4.1 (BR-RTR)"

echo "[*] Restarting network..."
systemctl restart network
echo "[+] Network restarted"

echo "[*] Checking internet connectivity..."
ping -c 2 -W 3 8.8.8.8 &>/dev/null \
  && echo "[+] Internet: OK" \
  || echo "[!] Internet unreachable — check BR-RTR"

# ============================================================
# PACKAGES
# ============================================================
echo "[*] Installing packages: nano..."
apt-get update -y -q
apt-get install -y nano
echo "[+] Packages installed"

# ============================================================
# USER: remote_user (uid=2042)
# ============================================================
echo "[*] Creating user 'remote_user' (uid=2042)..."
if ! id remote_user &>/dev/null; then
  adduser --disabled-password --gecos "" --uid 2042 remote_user
  echo "[+] User remote_user created (uid=2042)"
else
  echo "[!] remote_user already exists"
fi
echo 'remote_user:Pa$$word' | chpasswd
usermod -aG wheel remote_user
if ! grep -q '^remote_user' /etc/sudoers; then
  echo 'remote_user ALL=(ALL:ALL) NOPASSWD: ALL' >> /etc/sudoers
fi
echo "[+] remote_user: password=Pa\$\$word  uid=$(id -u remote_user)  sudo=NOPASSWD"

# ============================================================
# SSH (port 2042)
# ============================================================
echo "[*] Configuring SSH (port 2042, MaxAuthTries 2)..."
SSHD=/etc/openssh/sshd_config
sed -i 's/^#\?Port .*/Port 2042/'            "$SSHD"
sed -i 's/^#\?MaxAuthTries .*/MaxAuthTries 2/' "$SSHD"
sed -i 's|^#\?Banner .*|Banner /var/sshbanner|' "$SSHD"
grep -q '^AllowUsers' "$SSHD" \
  && sed -i 's/^AllowUsers .*/AllowUsers remote_user/' "$SSHD" \
  || echo 'AllowUsers remote_user' >> "$SSHD"

cat > /var/sshbanner << 'EOF'
============================================
  Authorized access only — BR-SRV
============================================
EOF

systemctl enable --now sshd
systemctl restart sshd
echo "[+] SSH: port=2042  AllowUsers=remote_user  MaxAuthTries=2"

# ============================================================
# VERIFICATION
# ============================================================
echo ""
echo "[*] --- Verification ---"
echo "    ip_forward  : $(cat /proc/sys/net/ipv4/ip_forward)"
echo "    Interface   : $(ip -br a show ${PRIMARY_IFACE} 2>/dev/null)"
echo "    SSH port    : $(ss -tlnp | grep sshd | awk '{print $4}' | head -1)"
echo "    remote_user : uid=$(id -u remote_user 2>/dev/null)"
echo ""
echo "[+] ========================================"
echo "[+]  BR-SRV MODULE 1 — COMPLETE"
echo "     NIC=$PRIMARY_IFACE  IP=192.168.4.2/27"
echo "[!]  Test: ssh remote_user@192.168.4.2 -p 2042"
echo "[+] ========================================"
