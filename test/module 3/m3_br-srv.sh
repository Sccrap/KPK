#!/bin/bash
# ============================================================
# MODULE 3 — BR-SRV
# Task 1: Bulk user import from CSV into Samba AD
# Task 7: Monitoring — prometheus-node_exporter
# Task 8: Ansible 2.0 — playbook to collect hostname/IP
# PDF ref: Третий.pdf tasks 1, 7, 8
# ============================================================
set -e

echo "[*] ========================================"
echo "[*]  MODULE 3 — BR-SRV"
echo "[*] ========================================"

# ============================================================
# TASK 1: IMPORT USERS FROM CSV INTO SAMBA AD
# ============================================================
echo ""
echo "[*] [Task 1] Importing users from CSV into Samba Active Directory..."

# Mount CD
if ! mountpoint -q /mnt; then
  mount /dev/sr0 /mnt/ 2>/dev/null && echo "[+] CD mounted" || \
    echo "[!] Could not mount /dev/sr0 — copy Users.csv manually to /opt/"
fi

# Copy CSV to /opt/
if [ -f /mnt/Users.csv ]; then
  cp /mnt/Users.csv /opt/
  echo "[+] Users.csv copied to /opt/"
else
  echo "[!] /mnt/Users.csv not found — place it at /opt/Users.csv manually"
fi

# Create import script
cat > /var/import.sh << 'IMPORTEOF'
#!/bin/bash
# User import from CSV into Samba AD
# CSV format: First Name;Last Name;Role;Phone;OU;Street;ZIP;City;Country;Password
CSV_FILE="/opt/Users.csv"
DOMAIN="AU-TEAM.IRPO"
ADMIN_USER="Administrator"
ADMIN_PASS="P@ssw0rd"

if [ ! -f "$CSV_FILE" ]; then
  echo "[!] ERROR: $CSV_FILE not found"
  exit 1
fi

echo "[*] Starting user import from $CSV_FILE..."

while IFS=';' read -r fname lname role phone ou street zip city country password; do
  # Skip header row
  if [[ "$fname" == "First Name" ]]; then
    continue
  fi

  # Skip empty lines
  [[ -z "$fname" ]] && continue

  # Build username: first letter of fname + lname, lowercase
  username=$(echo "${fname:0:1}${lname}" | tr '[:upper:]' '[:lower:]')

  # Create OU (ignore error if already exists)
  echo "[*] Creating OU: $ou"
  samba-tool ou create "OU=${ou},DC=AU-TEAM,DC=IRPO" \
    --description="${ou} department" 2>/dev/null || true

  # Create user
  echo "[*] Adding user: $username (OU=$ou, role=$role)"
  samba-tool user add "$username" "$password" \
    --given-name="$fname" \
    --surname="$lname" \
    --job-title="$role" \
    --telephone-number="$phone" \
    --userou="OU=$ou" 2>/dev/null || \
    echo "[!] User $username already exists — skipping"

done < "${CSV_FILE}"

echo "[+] Import complete"
IMPORTEOF

chmod +x /var/import.sh
echo "[+] Import script created at /var/import.sh"

# Run import
echo "[*] Running import script..."
/var/import.sh

# Verify via Administrator kinit
echo ""
echo "[!] Verify on HQ-CLI:"
echo "    kinit Administrator@AU-TEAM.IRPO"
echo "    Password: P@ssw0rd"
echo "    Then open ADMC to verify OU and users"
echo ""
echo "[!] If domain login fails (expired password), run:"
echo "    samba-tool user password Administrator"

# ============================================================
# TASK 7: PROMETHEUS NODE_EXPORTER
# ============================================================
echo ""
echo "[*] [Task 7] Starting prometheus-node_exporter on BR-SRV..."
apt-get install -y prometheus-node_exporter 2>/dev/null || \
  echo "[!] prometheus-node_exporter not in repos — check package source"

systemctl enable --now prometheus-node_exporter
echo "[+] node_exporter running on port 9100"
echo "[!] Prometheus on HQ-SRV should scrape br-srv:9100"
systemctl status prometheus-node_exporter --no-pager | head -5

# ============================================================
# TASK 8: ANSIBLE 2.0 — PLAYBOOK (collect hostname/IP)
# ============================================================
echo ""
echo "[*] [Task 8] Configuring Ansible playbook for host inventory..."

if ! mountpoint -q /mnt; then
  mount /dev/sr0 /mnt/ 2>/dev/null || true
fi

# Copy playbook from CD or create manually
if [ -f /mnt/playbook/get_hostname_address.yml ]; then
  cp /mnt/playbook/get_hostname_address.yml /etc/ansible/
  chmod 777 /etc/ansible/get_hostname_address.yml
  echo "[+] Playbook copied from CD"
else
  echo "[*] Playbook not found on CD — creating from PDF specification..."
  # Per PDF: the playbook collects hostname and IP from hq-srv and hq-cli
  # and writes results to /etc/ansible/PC-INFO/<hostname>.yml on localhost
  cat > /etc/ansible/get_hostname_address.yml << 'EOF'
---
- name: Inventory collection
  hosts: hq-srv, hq-cli
  tasks:
    - name: Collect hostname and IP from host
      copy:
        dest: /etc/ansible/PC-INFO/{{ ansible_hostname }}.yml
        content: |
          Hostname: {{ ansible_hostname }}
          IP_Address: {{ ansible_default_ipv4.address }}
      delegate_to: localhost
EOF
  echo "[+] Playbook created at /etc/ansible/get_hostname_address.yml"
fi

# Create output directory
mkdir -p /etc/ansible/PC-INFO
echo "[+] /etc/ansible/PC-INFO created"

# Copy inv to hosts if needed
if [ ! -f /etc/ansible/hosts ]; then
  cp /etc/ansible/inv /etc/ansible/hosts 2>/dev/null || true
fi

# Verify inventory file exists
echo "[*] Current Ansible inventory (/etc/ansible/inv):"
cat /etc/ansible/inv 2>/dev/null || echo "[!] Inventory not found — run m2_br-srv.sh first"

# Run playbook
echo "[*] Running playbook..."
ansible-playbook /etc/ansible/get_hostname_address.yml \
  -i /etc/ansible/inv 2>/dev/null || \
  echo "[!] Playbook failed — check SSH keys and host connectivity"

# Verify output
echo ""
echo "[*] Collected host info:"
ls /etc/ansible/PC-INFO/ 2>/dev/null
echo ""
for f in /etc/ansible/PC-INFO/*.yml; do
  [ -f "$f" ] && echo "=== $f ===" && cat "$f"
done

# --- Final verification ---
echo ""
echo "[*] --- Verification ---"
echo "    Samba users: $(samba-tool user list 2>/dev/null | wc -l) users in domain"
echo "    node_exporter: $(systemctl is-active prometheus-node_exporter)"
echo "    PC-INFO files: $(ls /etc/ansible/PC-INFO/ 2>/dev/null | wc -l)"
echo ""
echo "[+] ========================================"
echo "[+]  BR-SRV MODULE 3 — COMPLETE"
echo "[+] ========================================"
