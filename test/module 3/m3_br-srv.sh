#!/bin/bash
# ============================================================
# MODULE 3 — BR-SRV
# Задание 1: Импорт пользователей из CSV
# Задание 7: Мониторинг (Prometheus node_exporter)
# Задание 8: Ansible 2.0 (playbook)
# ============================================================
set -e

echo "[*] === BR-SRV: MODULE 3 ==="

# ============================================================
# ЗАДАНИЕ 1: ИМПОРТ ПОЛЬЗОВАТЕЛЕЙ ИЗ CSV
# ============================================================
echo "[*] [1] Импорт пользователей из CSV..."

mount /dev/sr0 /mnt/ 2>/dev/null || echo "[!] CD уже смонтирован"
cp /mnt/Users.csv /opt/ 2>/dev/null || echo "[!] Файл Users.csv не найден на CD"

cat > /var/import.sh << 'EOF'
#!/bin/bash
CSV_FILE="/opt/Users.csv"
DOMAIN="AU-TEAM.IRPO"
ADMIN_USER="Administrator"
ADMIN_PASS="P@ssw0rd"

while IFS=';' read -r fname lname role phone ou street zip city country password; do
  # Пропускаем заголовок
  if [[ "$fname" == "First Name" ]]; then
    continue
  fi

  # Формируем username: первая буква имени + фамилия (нижний регистр)
  username=$(echo "${fname:0:1}${lname}" | tr '[:upper:]' '[:lower:]')

  # Создаём OU (подразделение)
  samba-tool ou create "OU=${ou},DC=AU-TEAM,DC=IRPO" \
    --description="${ou} department" 2>/dev/null || true

  echo "Adding user: $username in OU=$ou"

  # Создаём пользователя
  samba-tool user add "$username" "$password" \
    --given-name="$fname" \
    --surname="$lname" \
    --job-title="$role" \
    --telephone-number="$phone" \
    --userou="OU=$ou" 2>/dev/null || echo "[!] Пользователь $username уже существует"

done < "${CSV_FILE}"

echo "Complete import"
EOF

chmod +x /var/import.sh
/var/import.sh

echo "[+] Импорт завершён"
echo "[!] Клиент: kinit Administrator -> зайди в ADMC -> проверь группы и пользователей"

# ============================================================
# ЗАДАНИЕ 7: МОНИТОРИНГ — Prometheus node_exporter (BR-SRV)
# ============================================================
echo "[*] [7] Запускаем prometheus-node_exporter..."
apt-get install -y prometheus-node_exporter 2>/dev/null || \
  echo "[!] prometheus-node_exporter не найден в репозитории — проверь настройку пакетов"

systemctl enable --now prometheus-node_exporter
systemctl status prometheus-node_exporter --no-pager
echo "[+] node_exporter запущен на порту 9100"

# ============================================================
# ЗАДАНИЕ 8: ANSIBLE 2.0 — Playbook сбора информации
# ============================================================
echo "[*] [8] Настраиваем Ansible Playbook (сбор hostname/IP)..."

mount /dev/sr0 /mnt/ 2>/dev/null || true

if [ -f /mnt/playbook/get_hostname_address.yml ]; then
  cp /mnt/playbook/get_hostname_address.yml /etc/ansible/
  chmod 777 /etc/ansible/get_hostname_address.yml
  echo "[+] Playbook скопирован с CD"
else
  echo "[*] Создаём playbook вручную..."
  cat > /etc/ansible/get_hostname_address.yml << 'EOF'
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
EOF
fi

mkdir -p /etc/ansible/PC-INFO

echo "[*] Запускаем playbook..."
ansible-playbook /etc/ansible/get_hostname_address.yml \
  -i /etc/ansible/inv || echo "[!] Ошибка playbook — проверь SSH доступ к хостам"

echo "[*] Результат:"
ls /etc/ansible/PC-INFO/ 2>/dev/null && cat /etc/ansible/PC-INFO/*.yml 2>/dev/null || \
  echo "[!] Файлы не созданы — проверь inventory"

echo "[+] === BR-SRV MODULE 3: Завершено ==="
