#!/bin/bash
# ============================================================
# ЗАДАНИЕ 8: Ansible — инвентаризация хостов
# Выполняется на: BR-SRV
# ============================================================

echo "=== ЗАДАНИЕ 8: Ansible (BR-SRV) ==="

echo "[1/4] Монтирование диска и копирование playbook..."
mount /dev/sr0 /mnt/ 2>/dev/null || echo "[INFO] Диск уже смонтирован"
cp /mnt/playbook/get_hostname_address.yml /etc/ansible/ 2>/dev/null \
    && echo "[OK] playbook скопирован с диска" \
    || echo "[INFO] Создаём playbook вручную..."

echo "[2/4] Создание playbook /etc/ansible/get_hostname_address.yml..."
mkdir -p /etc/ansible/PC-INFO

cat > /etc/ansible/get_hostname_address.yml << 'PLAYBOOK'
---
- name: Инвентаризация
  hosts: hq-srv, hq-cli
  tasks:
    - name: получение данных с хоста
      copy:
        dest: /etc/ansible/PC-INFO/{{ ansible_hostname }}.yml
        content: |
          Hostname: {{ ansible_hostname }}
          IP_Address: {{ ansible_default_ipv4.address }}
      delegate_to: localhost
PLAYBOOK

chmod 777 /etc/ansible/get_hostname_address.yml
echo "[OK] playbook создан"

echo "[3/4] Настройка inventory /etc/ansible/hosts..."
# Бэкап
cp /etc/ansible/hosts /etc/ansible/hosts.bak 2>/dev/null || true
cp /etc/ansible/inv /etc/ansible/hosts 2>/dev/null || true

cat > /etc/ansible/hosts << 'INVENTORY'
[hq]
172.16.1.1 ansible_user=net_admin

[hq-srv]
192.168.0.1 ansible_user=sshuser ansible_port=2026

[hq-cli]
192.168.0.2 ansible_user=kmw

[br]
172.16.2.1 ansible_user=net_admin
INVENTORY

echo "[OK] Inventory настроен"

echo "[4/4] Запуск ansible-playbook..."
mkdir -p /etc/ansible/PC-INFO
ansible-playbook /etc/ansible/get_hostname_address.yml -v

echo ""
echo "=== ПРОВЕРКА ==="
echo "Файлы в PC-INFO:"
ls /etc/ansible/PC-INFO/
echo ""
echo "Содержимое:"
for f in /etc/ansible/PC-INFO/*.yml; do
    echo "--- $f ---"
    cat "$f"
    echo ""
done
