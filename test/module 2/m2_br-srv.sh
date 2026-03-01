#!/bin/bash
# ============================================================
# MODULE 2 — BR-SRV
# Task 1: Chrony — NTP client -> ISP
# Task 2: Samba AD DC (domain: AU-TEAM.IRPO)
# Task 3: Ansible (inventory + SSH keys + ping test)
# Task 8: Docker (MariaDB + site) — WARNING: BREAKS SAMBA!
#         Docker setup is placed in /root/m2_docker.sh
#         Run it LAST after all Samba tasks are complete.
# PDF ref: Второй.pdf tasks 1, 2, 3, 8
# ============================================================
set -e

echo "[*] ========================================"
echo "[*]  MODULE 2 — BR-SRV"
echo "[*] ========================================"

# ============================================================
# TASK 1: CHRONY — NTP CLIENT
# ============================================================
echo ""
echo "[*] [Task 1] Configuring Chrony NTP client -> ISP (172.16.2.14)..."
apt-get install -y chrony

cat > /etc/chrony.conf << 'EOF'
# BR-SRV NTP client — sync from ISP
server 172.16.2.14 iburst prefer
EOF

systemctl enable --now chronyd
systemctl restart chronyd
sleep 3
echo "[+] Chrony NTP client configured"
chronyc sources 2>/dev/null || true

# ============================================================
# TASK 2: SAMBA AD DC
# ============================================================
echo ""
echo "[*] [Task 2] Configuring Samba Active Directory Domain Controller..."
apt-get install -y samba samba-dc krb5-workstation

# Clean up any previous failed provision
echo "[*] Removing old Samba config if present..."
rm -f /etc/samba/smb.conf

# Per PDF: provision non-interactively
# Realm: AU-TEAM.IRPO, Domain: AU-TEAM, DC mode, password: P@ssw0rd
echo "[*] Provisioning Samba domain AU-TEAM.IRPO..."
samba-tool domain provision \
  --use-rfc2307 \
  --realm=AU-TEAM.IRPO \
  --domain=AU-TEAM \
  --server-role=dc \
  --dns-backend=SAMBA_INTERNAL \
  --adminpass='P@ssw0rd' \
  --option="dns forwarder = 8.8.8.8"

# Copy Kerberos config
cp /var/lib/samba/private/krb5.conf /etc/krb5.conf
echo "[+] krb5.conf installed"

# Enable and start Samba
systemctl enable --now samba
systemctl restart samba
sleep 3
echo "[+] Samba AD DC started"
samba-tool domain info AU-TEAM.IRPO 2>/dev/null | head -5 || true

# --- Create Samba users ---
echo "[*] Creating Samba users (user1.hq, user2.hq, user3.hq)..."
for i in 1 2 3; do
  USERNAME="user${i}.hq"
  if ! samba-tool user show "$USERNAME" &>/dev/null; then
    samba-tool user create "$USERNAME" 'P@ssw0rd' \
      --given-name="User${i}" \
      --surname="HQ" \
      --home-directory="/home/AU-TEAM/${USERNAME}" \
      --uid="${USERNAME}"
    echo "[+] User $USERNAME created"
  else
    echo "[!] User $USERNAME already exists"
  fi
done

# Create group 'hq' and add users
echo "[*] Creating group 'hq' and adding members..."
samba-tool group add hq 2>/dev/null || echo "[!] Group hq already exists"
for i in 1 2 3; do
  samba-tool group addmembers hq "user${i}.hq" 2>/dev/null || true
done
samba-tool group addmembers "Account Operators" hq 2>/dev/null || true
samba-tool group addmembers "Allowed RODC Password Replication Group" hq 2>/dev/null || true
echo "[+] Group hq configured with users and permissions"

# --- Verify Samba ---
echo "[*] Samba group list:"
samba-tool group list 2>/dev/null | head -10 || true

# ============================================================
# TASK 3: ANSIBLE
# ============================================================
echo ""
echo "[*] [Task 3] Configuring Ansible..."
apt-get install -y ansible sshpass openssh-clients

# Generate SSH keypair if not present
if [ ! -f /root/.ssh/id_rsa ]; then
  ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa
  echo "[+] SSH keypair generated: /root/.ssh/id_rsa"
fi

# Per PDF inventory:
# [hq]: HQ-SRV sshuser@192.168.1.2:2026, HQ-CLI kmw@192.168.2.2:22, HQ-RTR net_admin@172.16.1.1:22
# [br]: BR-RTR net_admin@172.16.2.1:22
echo "[*] Distributing SSH public key to all hosts..."
echo "[!] You will be prompted for passwords for each host:"

# Remove stale known_hosts to avoid fingerprint errors
rm -f /root/.ssh/known_hosts

ssh-copy-id -p 2026 -o StrictHostKeyChecking=no sshuser@192.168.1.2   2>/dev/null || \
  echo "[!] Could not copy key to HQ-SRV (sshuser@192.168.1.2:2026) — do it manually"

ssh-copy-id -o StrictHostKeyChecking=no kmw@192.168.2.2              2>/dev/null || \
  echo "[!] Could not copy key to HQ-CLI (kmw@192.168.2.2) — do it manually"

ssh-copy-id -o StrictHostKeyChecking=no net_admin@172.16.1.1          2>/dev/null || \
  echo "[!] Could not copy key to HQ-RTR (net_admin@172.16.1.1) — do it manually"

ssh-copy-id -o StrictHostKeyChecking=no net_admin@172.16.2.1          2>/dev/null || \
  echo "[!] Could not copy key to BR-RTR (net_admin@172.16.2.1) — do it manually"

# Create inventory file
cat > /etc/ansible/inv << 'EOF'
[hq]
	192.168.1.2 ansible_port=2026 ansible_user=sshuser
	192.168.2.2 ansible_user=kmw
	172.16.1.1  ansible_user=net_admin

[br]
	172.16.2.1 ansible_user=net_admin
EOF
echo "[+] Inventory written to /etc/ansible/inv"

# ansible.cfg
cat > /etc/ansible/ansible.cfg << 'EOF'
[defaults]
interpreter_python=auto_silent
host_key_checking=False
EOF
echo "[+] ansible.cfg written"

# Test connectivity
echo "[*] Testing Ansible ping to all hosts..."
ansible all -i /etc/ansible/inv -m ping 2>/dev/null || \
  echo "[!] Ping failed for some hosts — ensure SSH keys are distributed"

# ============================================================
# TASK 8: DOCKER — separate script (DO NOT RUN NOW!)
# ============================================================
echo ""
echo "[*] [Task 8] Creating Docker setup script (run AFTER Samba is working)..."

cat > /root/m2_docker.sh << 'DOCKER_EOF'
#!/bin/bash
# ============================================================
# MODULE 2 Task 8 — Docker: MariaDB + site
# WARNING: Run this LAST — Docker packages conflict with Samba!
# PDF ref: Второй.pdf task 8
# ============================================================
set -e

echo "[*] ========================================"
echo "[*]  MODULE 2 Task 8 — Docker Setup"
echo "[!]  This will affect Samba — run LAST"
echo "[*] ========================================"

# Enable Docker daemon
systemctl enable --now docker
echo "[+] Docker daemon started"

# Add users to docker group
usermod -aG docker sshuser 2>/dev/null || true
usermod -aG docker root
echo "[+] sshuser and root added to docker group"

# Mount CD and load images
if ! mountpoint -q /mnt; then
  mount /dev/sr0 /mnt/
fi

echo "[*] Loading Docker images from CD..."
docker load < /mnt/docker/mariadb_latest.tar && echo "[+] mariadb image loaded"
docker load < /mnt/docker/site_latest.tar    && echo "[+] site image loaded"

# Create docker-compose file
# Per PDF: copy from /mnt/docker/readmetxt content into web.yaml
# Here we create web.yaml directly with the exact config shown in PDF
cat > /root/web.yaml << 'EOF'
services:
  database:
    container_name: 'db'
    image: mariadb:10.11
    restart: always
    environment:
      MARIADB_DATABASE: 'testdb'
      MARIADB_USER: 'test'
      MARIADB_PASSWORD: 'Passw0rd'
      MARIADB_ROOT_PASSWORD: 'Passw0rd'
    volumes:
      - mariadb:/var/lib/mysql

  app:
    container_name: 'testapp'
    image: site
    restart: always
    ports:
      - "8080:8080"
    environment:
      DB_TYPE: 'maria'
      DB_HOST: "db"
      DB_NAME: 'testdb'
      DB_PORT: "3306"
      DB_USER: 'test'
      DB_PASS: 'Passw0rd'

volumes:
  mariadb:
EOF

echo "[+] /root/web.yaml created"

# Start containers
docker compose -f /root/web.yaml up -d
echo "[+] Docker containers started"

# Verify
sleep 5
docker ps
echo ""
echo "[+] Docker setup complete"
echo "[!] Client test: http://192.168.4.2:8080"
DOCKER_EOF

chmod +x /root/m2_docker.sh
echo "[+] Docker script saved to /root/m2_docker.sh"

# --- Final verification ---
echo ""
echo "[*] --- Verification ---"
echo "    Chrony:  $(systemctl is-active chronyd)"
echo "    Samba:   $(systemctl is-active samba)"
echo "    Ansible: $(ansible --version 2>/dev/null | head -1)"
echo ""
echo "[+] ========================================"
echo "[+]  BR-SRV MODULE 2 — COMPLETE (no Docker)"
echo "[!]  Run Docker LAST: bash /root/m2_docker.sh"
echo "[+] ========================================"
