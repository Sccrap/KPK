#!/bin/bash
# ============================================================
# MODULE 2 — HQ-SRV
# Task 1: Chrony — NTP client -> ISP
# Task 6: Filesystem — RAID0 (/dev/md0) + NFS share
# Task 9: Apache (httpd2) + MariaDB web application
# PDF ref: Второй.pdf tasks 1, 6, 9
# ============================================================
set -e

echo "[*] ========================================"
echo "[*]  MODULE 2 — HQ-SRV"
echo "[*] ========================================"

# ============================================================
# TASK 1: CHRONY — NTP CLIENT
# ============================================================
echo ""
echo "[*] [Task 1] Configuring Chrony NTP client -> ISP (172.16.1.14)..."
apt-get install -y chrony

cat > /etc/chrony.conf << 'EOF'
# HQ-SRV NTP client — sync from ISP
server 172.16.1.14 iburst prefer
EOF

systemctl enable --now chronyd
systemctl restart chronyd
sleep 3
echo "[+] Chrony NTP client configured"
chronyc sources 2>/dev/null || true

# ============================================================
# TASK 6: RAID0 + NFS
# ============================================================
echo ""
echo "[*] [Task 6] Configuring RAID0 and NFS..."
apt-get install -y mdadm nfs-server

echo "[*] Current block devices:"
lsblk

# --- Partition sdb and sdc ---
for DISK in sdb sdc; do
  if lsblk /dev/${DISK} &>/dev/null; then
    echo "[*] Partitioning /dev/${DISK} (GPT, single partition)..."
    # Only partition if not already done
    if ! lsblk /dev/${DISK}1 &>/dev/null 2>&1; then
      (
        echo g    # new GPT table
        echo n    # new partition
        echo      # default partition number (1)
        echo      # default first sector
        echo      # default last sector (use all space)
        echo w    # write
      ) | fdisk /dev/${DISK}
      echo "[+] /dev/${DISK}1 created"
    else
      echo "[!] /dev/${DISK}1 already exists — skipping"
    fi
  else
    echo "[!] /dev/${DISK} not found — check lsblk output"
  fi
done

sleep 1
partprobe 2>/dev/null || true

# --- Create RAID0 array ---
echo "[*] Creating RAID0 array /dev/md0..."
if [ ! -b /dev/md0 ]; then
  mdadm --create --verbose /dev/md0 --level=0 --raid-devices=2 \
    /dev/sdb1 /dev/sdc1 --force
  echo "[+] RAID0 /dev/md0 created"
else
  echo "[!] /dev/md0 already exists — skipping creation"
fi

# Save RAID config
mdadm --detail --scan >> /etc/mdadm.conf
echo "[+] RAID config saved to /etc/mdadm.conf"

# --- Format and mount ---
if ! blkid /dev/md0 | grep -q ext4; then
  mkfs.ext4 /dev/md0
  echo "[+] /dev/md0 formatted as ext4"
fi

mkdir -p /raid
chmod 777 /raid

if ! mountpoint -q /raid; then
  mount -t ext4 /dev/md0 /raid
  echo "[+] /dev/md0 mounted at /raid"
fi

# fstab entry (idempotent)
if ! grep -q '/dev/md0' /etc/fstab; then
  echo '/dev/md0	/raid	ext4	defaults	0	0' >> /etc/fstab
  echo "[+] /dev/md0 added to /etc/fstab"
fi

mount -av 2>/dev/null | grep -E 'md0|raid' || true

# --- NFS share ---
echo "[*] Configuring NFS share /raid/nfs..."
mkdir -p /raid/nfs
chmod 777 /raid/nfs
touch /raid/nfs/test.txt
echo "[+] /raid/nfs created, test.txt placed"

# NFS export — allow access from the whole address space (192.168.0.0/21)
# Per PDF: 192.168.0.0/21 covers all subnets used in topology
if ! grep -q '/raid/nfs' /etc/exports; then
  echo '/raid/nfs 192.168.0.0/21(rw,sync,subtree_check)' >> /etc/exports
  echo "[+] /raid/nfs exported to 192.168.0.0/21"
fi

systemctl enable --now nfs-server
exportfs -a
systemctl restart nfs-server
echo "[+] NFS server started"
exportfs -v

# ============================================================
# TASK 9: APACHE + MariaDB
# ============================================================
echo ""
echo "[*] [Task 9] Configuring Apache + MariaDB..."
apt-get install -y httpd2 mariadb-server php8.2 php8.2-mysqlnd 2>/dev/null || \
  apt-get install -y httpd2 mariadb-server php php-mysqlnd

# --- MariaDB ---
echo "[*] Starting MariaDB..."
systemctl enable --now mariadb

echo "[*] Securing MariaDB and setting root password..."
# Non-interactive secure install
mysql -u root 2>/dev/null << 'SQL_EOF' || mysql -u root -pP@ssw0rd 2>/dev/null << 'SQL_EOF2'
ALTER USER 'root'@'localhost' IDENTIFIED BY 'P@ssw0rd';
DELETE FROM mysql.user WHERE User='' OR (User='root' AND Host NOT IN ('localhost','127.0.0.1','::1'));
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
SQL_EOF
echo "[+] MariaDB root password set to P@ssw0rd"
SQL_EOF2
echo "[+] MariaDB already secured"

# --- Mount CD if needed ---
if ! mountpoint -q /mnt; then
  mount /dev/sr0 /mnt/ 2>/dev/null && echo "[+] CD mounted at /mnt" || \
    echo "[!] CD not available — web files must be placed manually in /var/www/html/"
fi

# --- Copy web files ---
if [ -f /mnt/web/index.php ]; then
  cp /mnt/web/index.php /var/www/html/
  [ -f /mnt/web/logo.png ] && cp /mnt/web/logo.png /var/www/html/
  echo "[+] index.php and logo.png copied"

  # Set DB connection credentials in index.php
  sed -i 's/\$servername\s*=.*/\$servername = "localhost";/' /var/www/html/index.php
  sed -i 's/\$username\s*=.*/\$username = "webc";/'         /var/www/html/index.php
  sed -i 's/\$password\s*=.*/\$password = "P@ssw0rd";/'    /var/www/html/index.php
  sed -i 's/\$dbname\s*=.*/\$dbname = "webdb";/'           /var/www/html/index.php
  echo "[+] index.php DB credentials patched"
else
  echo "[!] /mnt/web/index.php not found — place it manually"
fi

rm -f /var/www/html/index.html

# --- Create database and user ---
echo "[*] Creating MariaDB database 'webdb' and user 'webc'..."
mysql -u root -pP@ssw0rd << 'SQL_EOF'
CREATE DATABASE IF NOT EXISTS webdb;
CREATE USER IF NOT EXISTS 'webc'@'localhost' IDENTIFIED BY 'P@ssw0rd';
GRANT ALL PRIVILEGES ON webdb.* TO 'webc'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL_EOF
echo "[+] Database webdb and user webc created"

# --- Import SQL dump ---
if [ -f /mnt/web/dump.sql ]; then
  mariadb -u webc -pP@ssw0rd -D webdb < /mnt/web/dump.sql
  echo "[+] Database dump imported from /mnt/web/dump.sql"
else
  echo "[!] /mnt/web/dump.sql not found — import manually if needed"
fi

# --- Start Apache ---
systemctl enable --now httpd2
echo "[+] Apache (httpd2) started"
systemctl status httpd2 --no-pager | head -5

# --- Final verification ---
echo ""
echo "[*] --- Verification ---"
echo "    Chrony:     $(systemctl is-active chronyd)"
echo "    RAID:       $(mdadm --detail /dev/md0 2>/dev/null | grep 'State' | head -1 || echo 'check manually')"
echo "    NFS:        $(systemctl is-active nfs-server)"
echo "    MariaDB:    $(systemctl is-active mariadb)"
echo "    Apache:     $(systemctl is-active httpd2)"
echo "    /raid/nfs:  $(ls /raid/nfs/)"
echo ""
echo "[!] Client test: open http://192.168.1.2 in browser"
echo ""
echo "[+] ========================================"
echo "[+]  HQ-SRV MODULE 2 — COMPLETE"
echo "[+] ========================================"
