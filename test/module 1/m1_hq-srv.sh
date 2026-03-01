#!/bin/bash
# ============================================================
# MODULE 1 — HQ-SRV
# Tasks: hostname, ip_forward, IP, remote_user (uid=2042),
#        SSH (port 2042), BIND DNS server
#
# INTERFACE AUTO-DETECTION:
#   HQ-SRV typically has 1 NIC (or pick the first active one).
#   The single interface gets 192.168.1.2/27, GW=192.168.1.1
#
#   Detection:
#     Primary = iface that already has an IP in 192.168.1.0/27 range
#     Fallback = first physical NIC (alphabetically sorted)
#
# PDF ref: Первый.pdf pages 4, 7, 11-12 (HQ-SRV sections)
# ============================================================
set -e

echo "[*] ========================================"
echo "[*]  MODULE 1 — HQ-SRV — Initial Setup"
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

# Prefer iface already in 192.168.1.x range
PRIMARY_IFACE=""
for IFACE in "${ALL_IFACES[@]}"; do
  CURRENT_IP=$(ip -4 addr show "$IFACE" 2>/dev/null \
    | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)
  if [[ "$CURRENT_IP" =~ ^192\.168\.1\. ]]; then
    PRIMARY_IFACE="$IFACE"
    echo "[+] Interface with 192.168.1.x found: $IFACE ($CURRENT_IP)"
    break
  fi
done

# Fallback: first physical NIC
if [ -z "$PRIMARY_IFACE" ]; then
  PRIMARY_IFACE="${ALL_IFACES[0]}"
  echo "[!] No 192.168.1.x address found — using first NIC: $PRIMARY_IFACE"
fi

echo ""
echo "[*] ============ INTERFACE ASSIGNMENT ============"
echo "    Primary NIC : $PRIMARY_IFACE  -> 192.168.1.2/27"
echo "    Gateway     : 192.168.1.1 (HQ-RTR vlan10)"
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
echo "[*] Setting hostname to 'hq-srv'..."
hostnamectl set-hostname hq-srv
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
  sed -i 's/^TYPE=.*/TYPE=eth/'            "$OPT"
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
# DNS resolver (temporary — will point to itself after BIND starts)
# ============================================================
if ! grep -q '8.8.8.8' /etc/resolv.conf; then
  echo 'nameserver 8.8.8.8' >> /etc/resolv.conf
fi

# ============================================================
# IP ADDRESS
# ============================================================
echo "[*] Assigning IP address..."
echo '192.168.1.2/27'          > /etc/net/ifaces/${PRIMARY_IFACE}/ipv4address
echo 'default via 192.168.1.1' > /etc/net/ifaces/${PRIMARY_IFACE}/ipv4route
echo "[+] $PRIMARY_IFACE = 192.168.1.2/27  route -> 192.168.1.1 (HQ-RTR)"

echo "[*] Restarting network..."
systemctl restart network
echo "[+] Network restarted"

echo "[*] Checking internet connectivity..."
ping -c 2 -W 3 8.8.8.8 &>/dev/null \
  && echo "[+] Internet: OK" \
  || echo "[!] Internet unreachable — check HQ-RTR"

# ============================================================
# PACKAGES
# ============================================================
echo "[*] Installing packages: nano, bind..."
apt-get update -y -q
apt-get install -y nano bind
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
  Authorized access only — HQ-SRV
============================================
EOF

systemctl enable --now sshd
systemctl restart sshd
echo "[+] SSH: port=2042  AllowUsers=remote_user  MaxAuthTries=2"

# ============================================================
# BIND DNS
# ============================================================
echo "[*] Configuring BIND DNS server..."

cat > /etc/bind/options.conf << 'EOF'
options {
  listen-on port 53 { 127.0.0.1; 192.168.1.2; };
  listen-on-v6 { none; };
  directory "/var/cache/bind";
  forwarders { 77.88.8.7; };
  allow-query { any; };
  dnssec-validation yes;
};
EOF

if ! grep -q 'aks42.aks' /etc/bind/local.conf 2>/dev/null; then
  cat >> /etc/bind/local.conf << 'EOF'

zone "aks42.aks" {
  type master;
  file "aks42.aks";
};

zone "1.168.192.in-addr.arpa" {
  type master;
  file "1.168.192.in-addr.arpa";
};
EOF
fi

cat > /etc/bind/zone/aks42.aks << 'EOF'
$TTL    1D
@       IN  SOA  aks42.aks. root.aks42.aks. (
                  2025100300 ; serial
                  12H ; refresh
                  1H  ; retry
                  1W  ; expire
                  1H) ; ncache

        IN  NS   aks42.aks.
        IN  A    192.168.1.1

hq-rtr  IN  A    192.168.1.1
hq-srv  IN  A    192.168.1.2
hq-cli  IN  A    192.168.2.2
br-rtr  IN  A    192.168.4.1
br-srv  IN  A    192.168.4.2
noodle  IN  CNAME br-rtr.aks42.aks.
wiki    IN  CNAME br-rtr.aks42.aks.
EOF

cat > /etc/bind/zone/1.168.192.in-addr.arpa << 'EOF'
$TTL    1D
@       IN  SOA  aks42.aks. root.aks42.aks. (
                  2025100300 ; serial
                  12H ; refresh
                  1H  ; retry
                  1W  ; expire
                  1H) ; ncache

        IN  NS   aks42.aks.
1       IN  PTR  hq-rtr.aks42.aks.
2       IN  PTR  hq-srv.aks42.aks.
EOF

chown named /etc/bind/zone/aks42.aks /etc/bind/zone/1.168.192.in-addr.arpa
chmod 600   /etc/bind/zone/aks42.aks /etc/bind/zone/1.168.192.in-addr.arpa

# Comment out rndc.conf include if present
[ -f /etc/bind/named.conf ] && \
  sed -i 's|^include.*rndc\.conf.*|//&|' /etc/bind/named.conf || true

named-checkconf -z && echo "[+] BIND config: OK" || echo "[!] BIND config error"
systemctl enable --now bind
systemctl restart bind
echo "[+] BIND DNS started"

# ============================================================
# VERIFICATION
# ============================================================
echo ""
echo "[*] --- Verification ---"
echo "    ip_forward   : $(cat /proc/sys/net/ipv4/ip_forward)"
echo "    Interface    : $(ip -br a show ${PRIMARY_IFACE} 2>/dev/null)"
echo "    SSH port     : $(ss -tlnp | grep sshd | awk '{print $4}' | head -1)"
echo "    BIND         : $(systemctl is-active bind)"
echo "    remote_user  : uid=$(id -u remote_user 2>/dev/null)"
echo ""
echo "[+] ========================================"
echo "[+]  HQ-SRV MODULE 1 — COMPLETE"
echo "     NIC=$PRIMARY_IFACE  IP=192.168.1.2/27"
echo "[!]  Test: ssh remote_user@192.168.1.2 -p 2042"
echo "[!]  Test: dig @192.168.1.2 hq-srv.aks42.aks"
echo "[+] ========================================"
