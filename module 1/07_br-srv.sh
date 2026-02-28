#!/bin/bash
###############################################################################
# 07_br-srv.sh — BR-SRV configuration (ALT Linux)
# Module 1: hostname · user · SSH · timezone
#
# Интерфейс определяется АВТОМАТИЧЕСКИ:
#   LAN — интерфейс с IP 192.168.x.x, или первый физический
###############################################################################
set -e

# ======================== FIXED VARIABLES ====================================
HOSTNAME="br-srv.au-team.irpo"

IP_LAN="192.168.1.1/27"
GW_LAN="192.168.1.30"

SSH_USER="sshuser"
SSH_USER_UID="2026"
SSH_USER_PASS="P@ssw0rd"
SSH_PORT="2024"

# ======================== AUTO-DETECT INTERFACE ==============================
detect_interface() {
    echo "  Scanning network interfaces..."
    ALL_IFACES=( $(ls /sys/class/net/ | grep -vE '^(lo|vlan|tun|gre|ovs|docker|br-)' | sort) )
    echo "  Found interfaces: ${ALL_IFACES[*]}"

    # Ищем интерфейс с IP из 192.168.x.x
    IF_LAN=""
    for iface in "${ALL_IFACES[@]}"; do
        if ip addr show "$iface" 2>/dev/null | grep -qE "192\.168\."; then
            IF_LAN="$iface"
            break
        fi
    done

    if [ -z "$IF_LAN" ]; then
        echo "  WARNING: no 192.168.x.x IP found, using first interface"
        IF_LAN="${ALL_IFACES[0]}"
    fi

    echo "  LAN (to BR-RTR): $IF_LAN"
}

configure_iface_static() {
    local iface="$1"
    local ip="$2"
    local dir="/etc/net/ifaces/$iface"
    mkdir -p "$dir"
    cat > "$dir/options" <<OPTS
BOOTPROTO=static
TYPE=eth
CONFIG_WIRELESS=no
SYSTEMD_BOOTPROTO=static
CONFIG_IPV4=yes
DISABLED=no
NM_CONTROLLED=no
ONBOOT=yes
OPTS
    echo "$ip" > "$dir/ipv4address"
    echo "  $iface -> $ip"
}

# =============================================================================
echo "=== [0/4] Installing required software ==="
apt-get update -y
apt-get install -y openssh-server
echo "  Done"

# =============================================================================
echo "=== [1/4] Setting hostname ==="
hostnamectl set-hostname "$HOSTNAME"

# =============================================================================
echo "=== [1.5/4] Auto-detecting and configuring interface ==="
detect_interface

configure_iface_static "$IF_LAN" "$IP_LAN"
echo "default via $GW_LAN" > "/etc/net/ifaces/$IF_LAN/ipv4route"

echo -e "search au-team.irpo\nnameserver 192.168.0.1" > /etc/resolv.conf

systemctl restart network
sleep 2
echo "  Network restarted"

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
grep -q "^AllowUsers" "$SSHD_CONFIG" \
    && sed -i "s/^AllowUsers .*/AllowUsers $SSH_USER/" "$SSHD_CONFIG" \
    || echo "AllowUsers $SSH_USER" >> "$SSHD_CONFIG"
sed -i 's/^#\?MaxAuthTries .*/MaxAuthTries 2/' "$SSHD_CONFIG"
sed -i 's|^#\?Banner .*|Banner /var/banner|' "$SSHD_CONFIG"
echo "Authorized access only" > /var/banner
systemctl enable --now sshd
systemctl restart sshd
echo "  SSH port=$SSH_PORT user=$SSH_USER"

# =============================================================================
echo "=== [4/4] Timezone ==="
timedatectl set-timezone Europe/Moscow

echo ""
echo "=== Verification ==="
echo "  LAN=$IF_LAN"
ip -c -br a
echo "=== BR-SRV configured ==="
