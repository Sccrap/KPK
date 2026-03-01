#!/bin/bash
# ============================================================
# MODULE 1 — HQ-SRV
# Tasks: hostname, ip_forward, IP, remote_user (uid=2042),
#        SSH (port 2042), BIND DNS server
# PDF ref: Первый.pdf pages 4, 7, 11-12 (HQ-SRV sections)
# ============================================================
set -e

echo "[*] ========================================"
echo "[*]  MODULE 1 — HQ-SRV — Initial Setup"
echo "[*] ========================================"

# --- Hostname ---
echo "[*] Setting hostname to 'hq-srv'..."
hostnamectl set-hostname hq-srv
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

# --- IP address and default route ---
echo "[*] Assigning IP address..."
echo '192.168.1.2/27'          > /etc/net/ifaces/ens19/ipv4address
echo 'default via 192.168.1.1' > /etc/net/ifaces/ens19/ipv4route
echo "[+] ens19 = 192.168.1.2/27  route -> 192.168.1.1 (HQ-RTR)"

echo "[*] Restarting network..."
systemctl restart network
echo "[+] Network restarted"

echo "[*] Checking internet connectivity..."
if ping -c 2 -W 3 8.8.8.8 &>/dev/null; then
  echo "[+] Internet: OK"
else
  echo "[!] Internet unreachable — check HQ-RTR"
fi

# --- Install packages ---
echo "[*] Installing required packages: nano, bind..."
apt-get update -y -q
apt-get install -y nano bind
echo "[+] Packages installed"

# --- User: remote_user (uid=2042) ---
echo "[*] Creating user 'remote_user' with uid=2042..."
if ! id remote_user &>/dev/null; then
  adduser --disabled-password --gecos "" --uid 2042 remote_user
  echo "[+] User remote_user created (uid=2042)"
else
  echo "[!] User remote_user already exists"
fi
# Password: Pa$$word (literal dollar signs)
echo 'remote_user:Pa$$word' | chpasswd
usermod -aG wheel remote_user
if ! grep -q '^remote_user' /etc/sudoers; then
  echo 'remote_user ALL=(ALL:ALL) NOPASSWD: ALL' >> /etc/sudoers
fi
echo "[+] remote_user: password=Pa\$\$word, uid=$(id -u remote_user), sudo=NOPASSWD"

# --- SSH configuration (port 2042) ---
echo "[*] Configuring SSH daemon (port 2042)..."
SSHD_CFG=/etc/openssh/sshd_config

# Port
sed -i 's/^#\?Port .*/Port 2042/' "$SSHD_CFG"
# MaxAuthTries
sed -i 's/^#\?MaxAuthTries .*/MaxAuthTries 2/' "$SSHD_CFG"
# Banner
sed -i 's|^#\?Banner .*|Banner /var/sshbanner|' "$SSHD_CFG"
# AllowUsers — restrict to remote_user only
if grep -q '^AllowUsers' "$SSHD_CFG"; then
  sed -i 's/^AllowUsers .*/AllowUsers remote_user/' "$SSHD_CFG"
else
  echo 'AllowUsers remote_user' >> "$SSHD_CFG"
fi

# SSH banner file (content from task description in exam)
cat > /var/sshbanner << 'EOF'
============================================
  Authorized access only — HQ-SRV
============================================
EOF

systemctl enable --now sshd
systemctl restart sshd
echo "[+] SSH configured: port=2042, MaxAuthTries=2, AllowUsers=remote_user"

# --- DNS: BIND ---
echo "[*] Configuring BIND DNS server..."

# /etc/bind/options.conf
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
echo "[+] /etc/bind/options.conf written"

# /etc/bind/local.conf — add forward and reverse zones
# Check if zones already declared to avoid duplicate
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
  echo "[+] Zones added to /etc/bind/local.conf"
else
  echo "[!] Zones already in local.conf — skipping"
fi

# Forward zone file: aks42.aks
cat > /etc/bind/zone/aks42.aks << 'EOF'
$TTL    1D
@       IN  SOA  aks42.aks. root.aks42.aks. (
                  2025100300 ; serial
                  12H        ; refresh
                  1H         ; retry
                  1W         ; expire
                  1H )       ; ncache

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
echo "[+] Forward zone /etc/bind/zone/aks42.aks written"

# Reverse zone file: 1.168.192.in-addr.arpa
cat > /etc/bind/zone/1.168.192.in-addr.arpa << 'EOF'
$TTL    1D
@       IN  SOA  aks42.aks. root.aks42.aks. (
                  2025100300 ; serial
                  12H        ; refresh
                  1H         ; retry
                  1W         ; expire
                  1H )       ; ncache

        IN  NS   aks42.aks.
2       IN  PTR  hq-srv.aks42.aks.
1       IN  PTR  hq-rtr.aks42.aks.
EOF
echo "[+] Reverse zone /etc/bind/zone/1.168.192.in-addr.arpa written"

# Set ownership and permissions
chown named /etc/bind/zone/aks42.aks
chmod 600   /etc/bind/zone/aks42.aks
chown named /etc/bind/zone/1.168.192.in-addr.arpa
chmod 600   /etc/bind/zone/1.168.192.in-addr.arpa
echo "[+] Zone file ownership set to 'named'"

# Comment out rndc.conf include (PDF instruction)
if [ -f /etc/bind/named.conf ]; then
  sed -i 's|^include.*rndc\.conf.*|//&|' /etc/bind/named.conf
  echo "[+] rndc.conf include commented out in named.conf"
fi

# Validate config before starting
echo "[*] Validating BIND configuration..."
named-checkconf -z && echo "[+] BIND config: OK" || echo "[!] BIND config ERROR — check manually"

systemctl enable --now bind
systemctl restart bind
echo "[+] BIND DNS started"

# --- Final verification ---
echo ""
echo "[*] --- Verification ---"
echo "    ip_forward: $(cat /proc/sys/net/ipv4/ip_forward)"
echo "    Interface: $(ip -br a show ens19 2>/dev/null)"
echo "    SSH port: $(ss -tlnp | grep sshd | awk '{print $4}' | head -1)"
echo "    BIND: $(systemctl is-active bind)"
echo "    remote_user uid: $(id -u remote_user 2>/dev/null)"
echo ""
echo "[+] ========================================"
echo "[+]  HQ-SRV MODULE 1 — COMPLETE"
echo "[!]  Test SSH: ssh remote_user@192.168.1.2 -p 2042"
echo "[!]  Test DNS: dig @192.168.1.2 hq-srv.aks42.aks"
echo "[+] ========================================"
