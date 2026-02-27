#!/bin/bash
###############################################################################
# m3_br-srv.sh — BR-SRV configuration (Module 3, ALT Linux)
# Tasks: Import AD users from CSV · Rsyslog client · node_exporter · Ansible playbook
###############################################################################
set -e

# ======================== VARIABLES ==========================================
HQ_SRV_IP="192.168.0.1"
ISO_DEVICE="/dev/sr0"
ISO_MOUNT="/mnt"

# =============================================================================
echo "=== [0/4] Installing required software ==="
apt-get update -y
apt-get install -y rsyslog prometheus-node_exporter ansible
echo "  Software installed"

# =============================================================================
echo "=== [1/4] Importing users from CSV into Samba AD ==="

echo "  Mounting ISO..."
mount "$ISO_DEVICE" "$ISO_MOUNT/" 2>/dev/null || echo "  [INFO] Disk already mounted or not found"
cp "$ISO_MOUNT/Users.csv" /opt/ \
    && echo "  Users.csv copied to /opt/" \
    || { echo "  ERROR: Users.csv not found on ISO"; exit 1; }

cat > /var/import.sh <<'IMPORT_SCRIPT'
#!/bin/bash
CSV_FILE="/opt/Users.csv"
DOMAIN="AU-TEAM.IRPO"

echo "[*] Starting user import..."

while IFS=';' read -r fname lname role phone ou street zip city country password; do
    [[ "$fname" == "First Name" ]] && continue

    username=$(echo "${fname:0:1}${lname}" | tr '[:upper:]' '[:lower:]')

    samba-tool ou create "OU=${ou},DC=AU-TEAM,DC=IRPO" \
        --description="${ou} department" 2>/dev/null || true

    echo "[+] Adding user: $username (OU=$ou)"
    samba-tool user add "$username" "$password" \
        --given-name="$fname" \
        --surname="$lname" \
        --job-title="$role" \
        --telephone-number="$phone" \
        --userou="OU=${ou}" 2>/dev/null \
        && echo "    [OK] $username added" \
        || echo "    [SKIP] $username already exists"

done < "${CSV_FILE}"

echo "[*] Import complete!"
IMPORT_SCRIPT

chmod +x /var/import.sh
/var/import.sh

echo ""
echo "--- AD users ---"
samba-tool user list
echo ""
echo "--- OUs ---"
samba-tool ou list

# =============================================================================
echo "=== [2/4] Configuring Rsyslog client ==="

mkdir -p /etc/rsyslog.d/

cat > /etc/rsyslog.d/rsys.conf <<EOF
# Rsyslog client config — BR-SRV
module(load="imjournal")
module(load="imuxsock")

# Forward WARNING+ to HQ-SRV via TCP
*.warn @@${HQ_SRV_IP}:514
EOF
echo "  rsys.conf: forwarding to $HQ_SRV_IP:514"

systemctl enable --now rsyslog
systemctl restart rsyslog
echo "  Rsyslog client started"

# =============================================================================
echo "=== [3/4] Starting node_exporter (monitoring) ==="

systemctl enable --now prometheus-node_exporter
systemctl restart prometheus-node_exporter
STATUS=$(systemctl is-active prometheus-node_exporter)
echo "  prometheus-node_exporter: $STATUS"
echo "  Metrics: http://$(hostname -I | awk '{print $1}'):9100/metrics"

# =============================================================================
echo "=== [4/4] Running Ansible inventory playbook ==="

mkdir -p /etc/ansible/PC-INFO

cat > /etc/ansible/get_hostname_address.yml <<'PLAYBOOK'
---
- name: Host inventory
  hosts: hq-srv, hq-cli
  tasks:
    - name: Get host info
      copy:
        dest: /etc/ansible/PC-INFO/{{ ansible_hostname }}.yml
        content: |
          Hostname: {{ ansible_hostname }}
          IP_Address: {{ ansible_default_ipv4.address }}
      delegate_to: localhost
PLAYBOOK

chmod 777 /etc/ansible/get_hostname_address.yml
echo "  Playbook created: /etc/ansible/get_hostname_address.yml"

cp /etc/ansible/hosts /etc/ansible/hosts.bak 2>/dev/null || true
cp /etc/ansible/inv   /etc/ansible/hosts     2>/dev/null || true

cat > /etc/ansible/hosts <<'INVENTORY'
[hq]
172.16.1.1 ansible_user=net_admin

[hq-srv]
192.168.0.1 ansible_user=sshuser ansible_port=2026

[hq-cli]
192.168.0.2 ansible_user=kmw

[br]
172.16.2.1 ansible_user=net_admin
INVENTORY
echo "  Inventory configured"

echo "  Running playbook..."
ansible-playbook /etc/ansible/get_hostname_address.yml -v

echo ""
echo "=== Verification ==="
systemctl is-active rsyslog                 && echo "  rsyslog: active"         || echo "  rsyslog: INACTIVE"
systemctl is-active prometheus-node_exporter && echo "  node_exporter: active"  || echo "  node_exporter: INACTIVE"
echo ""
echo "--- PC-INFO files ---"
ls /etc/ansible/PC-INFO/ 2>/dev/null || echo "  (none yet)"
for f in /etc/ansible/PC-INFO/*.yml; do
    [ -f "$f" ] && { echo "--- $f ---"; cat "$f"; echo ""; }
done
echo ""
echo "=== BR-SRV (Module 3) configured ==="
echo "Check logs on HQ-SRV: cat /opt/br-srv/br-srv.log"
