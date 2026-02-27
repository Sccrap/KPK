#!/bin/bash
###############################################################################
# 07_br-srv.sh — BR-SRV configuration (ALT Linux)
# Module 1: hostname · user · SSH (port 2024) · timezone
#
# PRE-REQUISITE (manual, before running this script):
#   ens19 = 192.168.1.1/27, gateway 192.168.1.30  (towards BR-RTR LAN)
#   resolv.conf pointing to HQ-SRV:
#     echo -e "search au-team.irpo\nnameserver 192.168.0.1" > /etc/resolv.conf
#   See: module 1/README.md → "Step 0 — Manual IP Configuration"
###############################################################################
set -e

# ======================== VARIABLES ==========================================
HOSTNAME="br-srv.au-team.irpo"

SSH_USER="sshuser"
SSH_USER_UID="2026"
SSH_USER_PASS="P@ssw0rd"
SSH_PORT="2024"

# =============================================================================
echo "=== [0/4] Installing required software ==="
apt-get update -y
apt-get install -y openssh-server
echo "  Software installed"

# =============================================================================
echo "=== [1/4] Setting hostname ==="
hostnamectl set-hostname "$HOSTNAME"

# =============================================================================
echo "=== [2/4] Creating user $SSH_USER ==="

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
echo "=== [3/4] Configuring SSH ==="

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
echo "=== [4/4] Timezone ==="
timedatectl set-timezone Europe/Moscow

echo ""
echo "=== Verification ==="
ip -c -br a
echo ""
echo "=== BR-SRV configured ==="
