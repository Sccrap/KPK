#!/bin/bash
###############################################################################
# m2_hq-srv.sh — HQ-SRV configuration (Module 2, ALT Linux)
# Tasks: NTP client · RAID0 + NFS server · Web (MariaDB + Apache + PHP)
###############################################################################
set -e

# ======================== VARIABLES ==========================================
# NTP
NTP_SERVER="172.16.1.14"

# RAID + NFS
DISK1="/dev/sdb"
DISK2="/dev/sdc"
PART1="${DISK1}1"
PART2="${DISK2}1"
RAID_DEV="/dev/md0"
RAID_LEVEL=0
RAID_MOUNT="/raid"
NFS_SHARE="$RAID_MOUNT/nfs"
NFS_NETWORK="192.168.0.0/23"
NFS_OPTIONS="rw,sync,subtree_check"

# Web / MariaDB
ISO_MOUNT="/mnt"
ISO_DEVICE="/dev/sr0"
DB_NAME="webdb"
DB_USER="webc"
DB_PASS="P@ssw0rd"
DB_ROOT_PASS="P@ssw0rd"
WEB_ROOT="/var/www/html"
DUMP_FILE="$ISO_MOUNT/web/dump.sql"

# =============================================================================
echo "=== [0/4] Installing required software ==="
apt-get update -y
apt-get install -y chrony mdadm nfs-server mariadb-server httpd2 php
echo "  Software installed"

# =============================================================================
echo "=== [1/4] Configuring NTP client ==="

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
echo "=== [2/4] Configuring RAID0 + NFS server ==="

echo "  --- Current block devices ---"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS
echo ""

for disk in "$DISK1" "$DISK2"; do
    if [ ! -b "$disk" ]; then
        echo "  ERROR: Disk $disk not found! Check lsblk and update DISK1/DISK2 in script"
        exit 1
    fi
done
echo "  Disks $DISK1 and $DISK2 found"

create_partition() {
    local disk="$1"
    echo "  Partitioning $disk..."
    echo 'label: gpt' | sfdisk "$disk" --force 2>/dev/null
    echo ',,L' | sfdisk "$disk" --force 2>/dev/null
    partprobe "$disk" 2>/dev/null || true
    sleep 1
}

if [ ! -b "$RAID_DEV" ]; then
    create_partition "$DISK1"
    create_partition "$DISK2"
    sleep 2
    partprobe 2>/dev/null || true
    for part in "$PART1" "$PART2"; do
        [ ! -b "$part" ] && { echo "  ERROR: Partition $part not created!"; exit 1; }
    done
    echo "  Partitions $PART1 and $PART2 created"

    mdadm --create --verbose "$RAID_DEV" \
        --level="$RAID_LEVEL" --raid-devices=2 "$PART1" "$PART2" --run
    sleep 2
    echo "  RAID0 created: $RAID_DEV"
else
    echo "  $RAID_DEV already exists, skipping RAID creation"
fi

mdadm --detail --scan > /etc/mdadm.conf 2>/dev/null || true
[ ! -s /etc/mdadm.conf ] && mdadm --detail --scan >> /etc/mdadm.conf

if ! blkid "$RAID_DEV" | grep -q "ext4"; then
    mkfs.ext4 -F "$RAID_DEV"
    echo "  $RAID_DEV formatted as ext4"
fi

mkdir -p "$RAID_MOUNT"
chmod 777 "$RAID_MOUNT"
if ! mountpoint -q "$RAID_MOUNT"; then
    mount -t ext4 "$RAID_DEV" "$RAID_MOUNT"
fi

if ! grep -qF "$RAID_DEV" /etc/fstab; then
    echo "$RAID_DEV $RAID_MOUNT ext4 defaults 0 0" >> /etc/fstab
fi

mkdir -p "$NFS_SHARE"
chmod 777 "$NFS_SHARE"
if ! grep -qF "$NFS_SHARE" /etc/exports 2>/dev/null; then
    echo "$NFS_SHARE $NFS_NETWORK($NFS_OPTIONS)" >> /etc/exports
fi

systemctl enable --now nfs
sleep 1
exportfs -a
echo "  RAID0 + NFS: $NFS_SHARE -> $NFS_NETWORK"

# =============================================================================
echo "=== [3/4] Configuring web server (MariaDB + Apache + PHP) ==="

systemctl enable --now mariadb
sleep 2

mariadb -u root <<SQLEOF 2>/dev/null || true
ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_ROOT_PASS';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
SQLEOF
echo "  MariaDB hardening done"

mkdir -p "$ISO_MOUNT"
if ! mountpoint -q "$ISO_MOUNT"; then
    mount "$ISO_DEVICE" "$ISO_MOUNT" 2>/dev/null \
        || echo "  WARNING: ISO not mounted — copy web files to $WEB_ROOT/ manually"
fi

if [ -d "$ISO_MOUNT/web" ]; then
    cp -f "$ISO_MOUNT/web/index.php" "$WEB_ROOT/" 2>/dev/null && echo "  index.php copied" || true
    cp -f "$ISO_MOUNT/web/logo.png"  "$WEB_ROOT/" 2>/dev/null && echo "  logo.png copied"  || true
else
    echo "  WARNING: $ISO_MOUNT/web not found — copy files to $WEB_ROOT/ manually"
fi
rm -f "$WEB_ROOT/index.html"

if [ -f "$WEB_ROOT/index.php" ]; then
    sed -i "s/\$db_host\s*=.*/\$db_host = 'localhost';/" "$WEB_ROOT/index.php" 2>/dev/null || true
    sed -i "s/\$db_name\s*=.*/\$db_name = '$DB_NAME';/"   "$WEB_ROOT/index.php" 2>/dev/null || true
    sed -i "s/\$db_user\s*=.*/\$db_user = '$DB_USER';/"   "$WEB_ROOT/index.php" 2>/dev/null || true
    sed -i "s/\$db_pass\s*=.*/\$db_pass = '$DB_PASS';/"   "$WEB_ROOT/index.php" 2>/dev/null || true
    echo "  DB params updated in index.php — verify: vim $WEB_ROOT/index.php"
fi

mariadb -u root -p"$DB_ROOT_PASS" <<SQLEOF 2>/dev/null || true
CREATE DATABASE IF NOT EXISTS $DB_NAME;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQLEOF
echo "  DB $DB_NAME created, user $DB_USER"

if [ -f "$DUMP_FILE" ]; then
    mariadb -u root -p"$DB_ROOT_PASS" "$DB_NAME" < "$DUMP_FILE" 2>/dev/null
    echo "  Dump imported from $DUMP_FILE"
else
    echo "  WARNING: dump.sql not found — import manually: mariadb -u root -p $DB_NAME < dump.sql"
fi

systemctl enable --now httpd2 2>/dev/null || systemctl enable --now httpd 2>/dev/null
systemctl restart httpd2 2>/dev/null || systemctl restart httpd 2>/dev/null
echo "  Apache started"

# =============================================================================
echo "=== [4/4] Verification ==="
echo "--- RAID ---"
cat /proc/mdstat
echo ""
echo "--- NFS exports ---"
exportfs -v
echo ""
echo "--- NTP ---"
chronyc sources 2>/dev/null | head -5
echo ""
echo "Web: http://192.168.0.1"
echo "=== HQ-SRV (Module 2) configured ==="
