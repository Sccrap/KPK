#!/bin/bash
###############################################################################
# m2_hq-cli.sh — HQ-CLI configuration (Module 2, ALT Linux)
# Tasks: NTP client · Domain join · NFS client · Sudo for hq group · Yandex Browser
###############################################################################
set -e

# ======================== VARIABLES ==========================================
# NTP
NTP_SERVER="172.16.1.14"

# Domain join
DOMAIN="au-team.irpo"
REALM="AU-TEAM.IRPO"
WORKGROUP="AU-TEAM"
DC_IP="192.168.1.1"
ADMIN_PASS="P@ssw0rd"
HOSTNAME_SHORT="hq-cli"

# NFS
NFS_SERVER="192.168.0.1"
NFS_REMOTE_PATH="/raid/nfs"
NFS_LOCAL_MOUNT="/mnt/nfs"

# Sudo for domain group hq
SUDO_LINE='%au-team//hq ALL=(ALL) NOPASSWD:/bin/cat,/bin/grep,/bin/id'

# =============================================================================
echo "=== [0/5] Installing required software ==="
apt-get update -y
apt-get install -y chrony
echo "  Software installed"

# =============================================================================
echo "=== [1/5] Configuring NTP client ==="

cat > /etc/chrony.conf <<EOF
# NTP client — sync with ISP
server $NTP_SERVER iburst prefer

driftfile /var/lib/chrony/drift
log tracking measurements statistics
logdir /var/log/chrony
EOF

systemctl enable --now chronyd
systemctl restart chronyd
sleep 2
echo "  NTP client: $NTP_SERVER"

# =============================================================================
echo "=== [2/5] Joining domain $DOMAIN ==="

cat > /etc/resolv.conf <<EOF
search $DOMAIN
nameserver $DC_IP
EOF
echo "  DNS points to DC: $DC_IP"

if ! ping -c 2 -W 3 "$DC_IP" &>/dev/null; then
    echo "  WARNING: DC $DC_IP unreachable — join may fail"
fi

if host -t SRV "_ldap._tcp.$DOMAIN" "$DC_IP" &>/dev/null; then
    echo "  DC DNS: SRV records found"
else
    echo "  WARNING: SRV records not found — DC may not be ready yet"
fi

cat > /etc/krb5.conf <<EOF
[libdefaults]
    default_realm = $REALM
    dns_lookup_realm = false
    dns_lookup_kdc = true

[realms]
    $REALM = {
        default_domain = $DOMAIN
    }

[domain_realm]
    .$DOMAIN = $REALM
    $DOMAIN = $REALM
EOF
echo "  krb5.conf configured"

if command -v net &>/dev/null; then
    echo "$ADMIN_PASS" | net ads join -U Administrator --no-dns-updates 2>&1 || true
    echo "  Attempted join via net ads"
fi
if command -v system-auth &>/dev/null; then
    system-auth write ad "$DOMAIN" "$HOSTNAME_SHORT" "$WORKGROUP" "Administrator" "$ADMIN_PASS" 2>&1 || true
    echo "  Attempted join via system-auth"
fi
if command -v realm &>/dev/null; then
    echo "$ADMIN_PASS" | realm join --user=Administrator "$DOMAIN" 2>&1 || true
    echo "  Attempted join via realm"
fi
echo "  If CLI join failed: Control Center -> Authentication -> Active Directory"
echo "    Domain: $DOMAIN, Workgroup: $WORKGROUP, Host: $HOSTNAME_SHORT"

# =============================================================================
echo "=== [3/5] Configuring NFS client ==="

mkdir -p "$NFS_LOCAL_MOUNT"
chmod 777 "$NFS_LOCAL_MOUNT"

FSTAB_LINE="$NFS_SERVER:$NFS_REMOTE_PATH $NFS_LOCAL_MOUNT nfs auto 0 0"
if ! grep -qF "$NFS_SERVER:$NFS_REMOTE_PATH" /etc/fstab; then
    echo "$FSTAB_LINE" >> /etc/fstab
    echo "  fstab entry added"
fi

mount -av 2>&1 || echo "  Mount error — check NFS server availability on $NFS_SERVER"
echo "  NFS: $NFS_SERVER:$NFS_REMOTE_PATH -> $NFS_LOCAL_MOUNT"

# =============================================================================
echo "=== [4/5] Configuring sudo for domain group hq ==="

if ! grep -qF "%au-team//hq" /etc/sudoers 2>/dev/null; then
    echo "$SUDO_LINE" >> /etc/sudoers
    echo "  Sudo rights added for group hq"
else
    echo "  Sudo rights for group hq already configured"
fi

# =============================================================================
echo "=== [5/5] Installing Yandex Browser ==="

apt-get install -y yandex-browser 2>/dev/null || {
    echo "  Package yandex-browser not found, trying yandex-browser-stable..."
    apt-get install -y yandex-browser-stable 2>/dev/null || {
        echo "  ERROR: Yandex Browser not available — check: apt-cache search yandex"
    }
}

echo ""
echo "=== Verification ==="
chronyc sources 2>/dev/null | head -5
echo ""
df -h "$NFS_LOCAL_MOUNT" 2>/dev/null || echo "  NFS not mounted"
echo ""
echo "=== HQ-CLI (Module 2) configured ==="
echo "Manual checks:"
echo "  kinit Administrator  (password: $ADMIN_PASS)"
echo "  klist"
