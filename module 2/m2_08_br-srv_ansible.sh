#!/bin/bash
###############################################################################
# m2_08_br-srv_ansible.sh — Ansible на BR-SRV (ALT Linux)
# Задание 5: Сконфигурируйте ansible
###############################################################################
set -e

# ======================== ПЕРЕМЕННЫЕ =========================================
SSH_USER="sshuser"
SSH_PASS="P@ssw0rd"
SSH_PORT_SRV="2024"     # Порт SSH на серверах (HQ-SRV, BR-SRV)
SSH_PORT_DEFAULT="22"   # Порт SSH на остальных

NET_ADMIN_USER="net_admin"
NET_ADMIN_PASS='P@$$word'

# Хосты (группа:хост:IP:порт:пользователь)
# Формат инвентаря
INVENTORY_FILE="/etc/ansible/inv"
ANSIBLE_CFG="/etc/ansible/ansible.cfg"

# IP-адреса устройств
HQ_SRV_IP="192.168.0.1"
HQ_CLI_IP="192.168.0.65"
HQ_RTR_IP="192.168.0.62"
BR_RTR_IP="192.168.1.30"

# =============================================================================
echo "=== [1/5] Генерация SSH-ключей (root) ==="

if [ ! -f /root/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa -q
    echo "  SSH-ключ root создан"
else
    echo "  SSH-ключ root уже существует"
fi

# =============================================================================
echo "=== [2/5] Генерация SSH-ключей ($SSH_USER) ==="

SSH_USER_HOME=$(eval echo "~$SSH_USER")

if [ ! -f "$SSH_USER_HOME/.ssh/id_rsa" ]; then
    su - "$SSH_USER" -c 'ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa -q'
    echo "  SSH-ключ $SSH_USER создан"
else
    echo "  SSH-ключ $SSH_USER уже существует"
fi

# =============================================================================
echo "=== [3/5] Копирование SSH-ключей на удалённые хосты ==="

echo ""
echo "  Для автоматического копирования ключей нужен sshpass."
echo "  Если sshpass не установлен, копируйте ключи вручную:"
echo ""

copy_key() {
    local user="$1"
    local host="$2"
    local port="$3"
    local pass="$4"
    local from_user="$5"

    echo "  Копирование ключа: $from_user -> $user@$host:$port"

    if command -v sshpass &>/dev/null; then
        if [ "$from_user" = "root" ]; then
            sshpass -p "$pass" ssh-copy-id \
                -o StrictHostKeyChecking=no \
                -p "$port" \
                "$user@$host" 2>/dev/null && echo "    OK" || echo "    ОШИБКА (хост недоступен?)"
        else
            su - "$from_user" -c "sshpass -p '$pass' ssh-copy-id \
                -o StrictHostKeyChecking=no \
                -p $port \
                $user@$host" 2>/dev/null && echo "    OK" || echo "    ОШИБКА (хост недоступен?)"
        fi
    else
        echo "    sshpass не установлен — выполните вручную:"
        if [ "$from_user" = "root" ]; then
            echo "    ssh-copy-id -p $port $user@$host"
        else
            echo "    su - $from_user -c 'ssh-copy-id -p $port $user@$host'"
        fi
    fi
}

# root -> хосты
copy_key "$SSH_USER"     "$HQ_SRV_IP" "$SSH_PORT_SRV"     "$SSH_PASS"       "root"
copy_key "user"          "$HQ_CLI_IP" "$SSH_PORT_DEFAULT"  "$SSH_PASS"       "root"
copy_key "$NET_ADMIN_USER" "$HQ_RTR_IP" "$SSH_PORT_DEFAULT" "$NET_ADMIN_PASS" "root"
copy_key "$NET_ADMIN_USER" "$BR_RTR_IP" "$SSH_PORT_DEFAULT" "$NET_ADMIN_PASS" "root"

# sshuser -> хосты
copy_key "$SSH_USER"     "$HQ_SRV_IP" "$SSH_PORT_SRV"     "$SSH_PASS"       "$SSH_USER"
copy_key "user"          "$HQ_CLI_IP" "$SSH_PORT_DEFAULT"  "$SSH_PASS"       "$SSH_USER"
copy_key "$NET_ADMIN_USER" "$HQ_RTR_IP" "$SSH_PORT_DEFAULT" "$NET_ADMIN_PASS" "$SSH_USER"
copy_key "$NET_ADMIN_USER" "$BR_RTR_IP" "$SSH_PORT_DEFAULT" "$NET_ADMIN_PASS" "$SSH_USER"

# =============================================================================
echo "=== [4/5] Создание инвентаря ==="

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

echo "  Инвентарь создан: $INVENTORY_FILE"
cat "$INVENTORY_FILE"

# =============================================================================
echo "=== [5/5] Настройка ansible.cfg ==="

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

echo "  ansible.cfg настроен"

echo ""
echo "=== Проверка ==="
echo "Выполните для проверки подключения:"
echo "  ansible all -i $INVENTORY_FILE -m ping"
echo ""
echo "=== Ansible настроен ==="
