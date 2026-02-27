#!/bin/bash
###############################################################################
# 07_br-srv.sh — BR-SRV configuration (ALT Linux)
# Module 1: IP, users, SSH, timezone
###############################################################################
set -e

# ======================== VARIABLES ==========================================
HOSTNAME="br-srv.au-team.irpo"
DOMAIN="au-team.irpo"

# Network interface
IF_LAN="ens19"
IP_LAN="192.168.1.1/27"
GW_LAN="192.168.1.30"

# DNS (HQ-SRV)
DNS_SERVER="192.168.0.1"

# SSH
SSH_USER="sshuser"
SSH_USER_UID="2026"
SSH_USER_PASS="P@ssw0rd"
SSH_PORT="2024"

# =============================================================================
echo "=== [0/5] Installing required software ==="
apt-get update -y
apt-get install -y openssh-server
echo "  Software installed"

# =============================================================================
echo "=== [1/5] Setting hostname ==="
hostnamectl set-hostname "$HOSTNAME"

# =============================================================================
echo "=== [2/5] Configuring IP address ==="

IF_DIR="/etc/net/ifaces/$IF_LAN"
mkdir -p "$IF_DIR"

cat > "$IF_DIR/options" <<EOF
BOOTPROTO=static
TYPE=eth
CONFIG_WIRELESS=no
SYSTEMD_BOOTPROTO=static
CONFIG_IPV4=yes
DISABLED=no
NM_CONTROLLED=no
ONBOOT=yes
EOF

echo "$IP_LAN" > "$IF_DIR/ipv4address"
echo "default via $GW_LAN" > "$IF_DIR/ipv4route"

# DNS — point to HQ-SRV
cat > /etc/resolv.conf <<EOF
search $DOMAIN
nameserver $DNS_SERVER
EOF

systemctl restart network
sleep 2
echo "  $IF_LAN -> $IP_LAN, gw $GW_LAN"

# =============================================================================
echo "=== [3/5] Creating user $SSH_USER ==="

if ! id "$SSH_USER" &>/dev/null; then
    adduser "$SSH_USER" -u "$SSH_USER_UID"
    echo "$SSH_USER:$SSH_USER_PASS" | chpasswd
    usermod -aG wheel "$SSH_USER"
    echo "$SSH_USER ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
    echo "  User $SSH_USER (uid=$SSH_USER_UID) created"
else
    echo "  User $SSH_USER already exists"
fi

# =============================================================================
echo "=== [4/5] Configuring SSH ==="

SSHD_CONFIG="/etc/openssh/sshd_config"

sed -i "s/^#\?Port .*/Port $SSH_PORT/" "$SSHD_CONFIG"

if ! grep -q "^AllowUsers" "$SSHD_CONFIG"; then
    echo "AllowUsers $SSH_USER" >> "$SSHD_CONFIG"
else
    sed -i "s/^AllowUsers .*/AllowUsers $SSH_USER/" "$SSHD_CONFIG"
fi

sed -i 's/^#\?MaxAuthTries .*/MaxAuthTries 2/' "$SSHD_CONFIG"
sed -i 's|^#\?Banner .*|Banner /var/banner|' "$SSHD_CONFIG"

cat > /var/banner <<EOF
Authorized access only
EOF

systemctl enable --now sshd
systemctl restart sshd
echo "  SSH: port $SSH_PORT, user $SSH_USER"

# =============================================================================
echo "=== [5/5] Timezone ==="
timedatectl set-timezone Europe/Moscow

echo ""
echo "=== Verification ==="
ip -c -br a
echo ""
echo "=== BR-SRV configured ==="
