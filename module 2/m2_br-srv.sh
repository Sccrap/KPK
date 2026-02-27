#!/bin/bash
###############################################################################
# m2_br-srv.sh — BR-SRV configuration (Module 2, ALT Linux)
# Tasks: NTP client · Samba AD DC · AD users/groups · Ansible · Docker
###############################################################################
set -e

# ======================== VARIABLES ==========================================
# NTP
NTP_SERVER="172.16.1.14"

# Samba AD
DOMAIN="au-team.irpo"
REALM="AU-TEAM.IRPO"
WORKGROUP="AU-TEAM"
ADMIN_PASS="P@ssw0rd"
DNS_FORWARDER="77.88.8.7"
SERVER_IP="192.168.1.1"

# Samba users/groups
DEFAULT_PASS="P@ssw0rd"
USERS=(
    "user1:User One"
    "user2:User Two"
    "user3:User Three"
    "admin1:Admin One"
)
GROUP_NAME="hq"
GROUP_MEMBERS=("user1" "user2" "user3" "admin1")
SUDO_COMMANDS="/bin/cat,/bin/grep,/bin/id"

# Ansible
SSH_USER="sshuser"
SSH_PASS="P@ssw0rd"
SSH_PORT_SRV="2024"
SSH_PORT_DEFAULT="22"
NET_ADMIN_USER="net_admin"
NET_ADMIN_PASS='P@$$word'
INVENTORY_FILE="/etc/ansible/inv"
ANSIBLE_CFG="/etc/ansible/ansible.cfg"
HQ_SRV_IP="192.168.0.1"
HQ_CLI_IP="192.168.0.65"
HQ_RTR_IP="192.168.0.62"
BR_RTR_IP="192.168.1.30"

# Docker
ISO_MOUNT="/mnt"
ISO_DEVICE="/dev/sr0"
DOCKER_DIR="/mnt/docker"
APP_NAME="testapp"
APP_IMAGE="site"
APP_PORT_EXT="8080"
APP_PORT_INT="8000"
DB_CONTAINER="db"
DB_IMAGE="mariadb"
DB_NAME="testdb"
DB_USER="test"
DB_PASS="P@ssw0rd"
DB_ROOT_PASS="P@ssw0rd"
DB_PORT="3306"
DB_TYPE="maria"
COMPOSE_FILE="/root/web.yaml"

# =============================================================================
echo "=== [0/5] Installing required software ==="
apt-get update -y
apt-get install -y chrony samba ansible docker
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
echo "=== [2/5] Configuring Samba AD Domain Controller ==="

systemctl stop samba 2>/dev/null || true
systemctl stop smb 2>/dev/null || true
systemctl stop winbind 2>/dev/null || true

rm -f /etc/samba/smb.conf
rm -rf /var/lib/samba/private/*.tdb /var/lib/samba/private/*.ldb
rm -rf /var/lib/samba/*.tdb /var/lib/samba/*.ldb
rm -rf /var/cache/samba/*
echo "  Old Samba config removed"

samba-tool domain provision \
    --use-rfc2307 \
    --realm="$REALM" \
    --domain="$WORKGROUP" \
    --server-role=dc \
    --dns-backend=SAMBA_INTERNAL \
    --adminpass="$ADMIN_PASS" \
    --option="dns forwarder = $DNS_FORWARDER"
echo "  Domain $REALM provisioned"

cp /var/lib/samba/private/krb5.conf /etc/krb5.conf
echo "  krb5.conf copied"

cat > /etc/resolv.conf <<EOF
search $DOMAIN
nameserver 127.0.0.1
nameserver $SERVER_IP
EOF

systemctl enable --now samba
sleep 3
echo "  Samba AD started"

# =============================================================================
echo "=== [3/5] Creating AD users and groups ==="

for entry in "${USERS[@]}"; do
    IFS=':' read -r username fullname <<< "$entry"
    if samba-tool user list 2>/dev/null | grep -qw "$username"; then
        echo "  $username — already exists"
    else
        samba-tool user create "$username" "$DEFAULT_PASS" \
            --given-name="${fullname%% *}" \
            --surname="${fullname#* }" \
            --use-username-as-cn 2>/dev/null
        echo "  $username created (password: $DEFAULT_PASS)"
    fi
done

if samba-tool group list 2>/dev/null | grep -qw "$GROUP_NAME"; then
    echo "  Group $GROUP_NAME already exists"
else
    samba-tool group add "$GROUP_NAME" 2>/dev/null
    echo "  Group $GROUP_NAME created"
fi

for username in "${GROUP_MEMBERS[@]}"; do
    if samba-tool group listmembers "$GROUP_NAME" 2>/dev/null | grep -qw "$username"; then
        echo "  $username already in $GROUP_NAME"
    else
        samba-tool group addmembers "$GROUP_NAME" "$username" 2>/dev/null
        echo "  $username added to $GROUP_NAME"
    fi
done

echo ""
echo "  Run on HQ-CLI to grant sudo for group hq:"
echo "  echo '%au-team//hq ALL=(ALL) NOPASSWD:$SUDO_COMMANDS' >> /etc/sudoers"

# =============================================================================
echo "=== [4/5] Configuring Ansible ==="

if [ ! -f /root/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa -q
    echo "  SSH key for root created"
fi

SSH_USER_HOME=$(eval echo "~$SSH_USER")
if [ ! -f "$SSH_USER_HOME/.ssh/id_rsa" ]; then
    su - "$SSH_USER" -c 'ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa -q'
    echo "  SSH key for $SSH_USER created"
fi

copy_key() {
    local user="$1" host="$2" port="$3" pass="$4" from_user="$5"
    echo "  Copying key: $from_user -> $user@$host:$port"
    if command -v sshpass &>/dev/null; then
        if [ "$from_user" = "root" ]; then
            sshpass -p "$pass" ssh-copy-id -o StrictHostKeyChecking=no -p "$port" "$user@$host" 2>/dev/null \
                && echo "    OK" || echo "    FAILED (host unreachable?)"
        else
            su - "$from_user" -c "sshpass -p '$pass' ssh-copy-id -o StrictHostKeyChecking=no -p $port $user@$host" 2>/dev/null \
                && echo "    OK" || echo "    FAILED"
        fi
    else
        echo "    sshpass not installed — run manually: ssh-copy-id -p $port $user@$host"
    fi
}

copy_key "$SSH_USER"       "$HQ_SRV_IP" "$SSH_PORT_SRV"     "$SSH_PASS"       "root"
copy_key "user"            "$HQ_CLI_IP" "$SSH_PORT_DEFAULT"  "$SSH_PASS"       "root"
copy_key "$NET_ADMIN_USER" "$HQ_RTR_IP" "$SSH_PORT_DEFAULT"  "$NET_ADMIN_PASS" "root"
copy_key "$NET_ADMIN_USER" "$BR_RTR_IP" "$SSH_PORT_DEFAULT"  "$NET_ADMIN_PASS" "root"

mkdir -p /etc/ansible

cat > "$INVENTORY_FILE" <<EOF
[servers]
hq-srv ansible_host=$HQ_SRV_IP ansible_port=$SSH_PORT_SRV ansible_user=$SSH_USER

[clients]
hq-cli ansible_host=$HQ_CLI_IP ansible_port=$SSH_PORT_DEFAULT ansible_user=user

[routers]
hq-rtr ansible_host=$HQ_RTR_IP ansible_port=$SSH_PORT_DEFAULT ansible_user=$NET_ADMIN_USER
br-rtr ansible_host=$BR_RTR_IP ansible_port=$SSH_PORT_DEFAULT ansible_user=$NET_ADMIN_USER
EOF
echo "  Inventory: $INVENTORY_FILE"

cat > "$ANSIBLE_CFG" <<EOF
[defaults]
inventory = $INVENTORY_FILE
interpreter_python = auto_silent
host_key_checking = False
timeout = 30

[privilege_escalation]
become = True
become_method = sudo
become_ask_pass = False
EOF
echo "  ansible.cfg configured"

# =============================================================================
echo "=== [5/5] Deploying Docker containers ==="

systemctl enable --now docker
sleep 2

mkdir -p "$ISO_MOUNT"
if ! mountpoint -q "$ISO_MOUNT"; then
    mount "$ISO_DEVICE" "$ISO_MOUNT" 2>/dev/null || {
        echo "  ERROR: Could not mount $ISO_DEVICE — check: lsblk"
        exit 1
    }
fi
echo "  Contents of $DOCKER_DIR:"
ls -la "$DOCKER_DIR/" 2>/dev/null || echo "  Directory $DOCKER_DIR not found!"

for tarfile in "$DOCKER_DIR"/*.tar; do
    [ -f "$tarfile" ] && docker load < "$tarfile" && echo "  Loaded: $(basename "$tarfile")"
done
echo ""
docker images --format "  {{.Repository}}:{{.Tag}} ({{.Size}})"

cat > "$COMPOSE_FILE" <<EOF
services:
  app:
    container_name: $APP_NAME
    image: $APP_IMAGE
    restart: always
    ports:
      - "$APP_PORT_EXT:$APP_PORT_INT"
    environment:
      DB_TYPE: $DB_TYPE
      DB_HOST: "$DB_CONTAINER"
      DB_NAME: $DB_NAME
      DB_PORT: "$DB_PORT"
      DB_USER: $DB_USER
      DB_PASS: $DB_PASS
    depends_on:
      - database

  database:
    container_name: $DB_CONTAINER
    image: $DB_IMAGE
    restart: always
    environment:
      MARIADB_DATABASE: $DB_NAME
      MARIADB_USER: $DB_USER
      MARIADB_PASSWORD: $DB_PASS
      MARIADB_ROOT_PASSWORD: $DB_ROOT_PASS
    volumes:
      - mariadb_data:/var/lib/mysql

volumes:
  mariadb_data:
EOF

cd /root
docker compose -f "$COMPOSE_FILE" down 2>/dev/null || true
docker compose -f "$COMPOSE_FILE" up -d
sleep 5

echo ""
echo "=== Verification ==="
samba-tool domain info 127.0.0.1 2>/dev/null || echo "  (domain still initializing)"
echo ""
echo "--- AD users ---"
samba-tool user list 2>/dev/null
echo ""
echo "--- Docker ---"
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
echo ""
echo "App: http://$(hostname -I | awk '{print $1}'):$APP_PORT_EXT"
echo ""
echo "  Ansible test: ansible all -i $INVENTORY_FILE -m ping"
echo ""
echo "=== BR-SRV (Module 2) configured ==="
echo "!!! RECOMMENDED: reboot the server after Samba AD: reboot !!!"
