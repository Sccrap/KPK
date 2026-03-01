#!/bin/bash
# ============================================================
# MODULE 2 — BR-SRV
# Задание 1: Chrony (клиент)
# Задание 2: Samba AD DC
# Задание 3: Ansible (настройка и inventory)
# Задание 8: Docker (MariaDB + site) — ВЫПОЛНЯТЬ ПОСЛЕДНИМ!
# ============================================================
set -e

echo "[*] === BR-SRV: MODULE 2 ==="

# ============================================================
# ЗАДАНИЕ 1: CHRONY — NTP-клиент
# ============================================================
echo "[*] [1] Настраиваем Chrony (клиент -> BR ISP)..."
apt-get install -y chrony

cat > /etc/chrony.conf << 'EOF'
server 172.16.2.14 iburst prefer
EOF

systemctl enable --now chronyd
systemctl restart chronyd
sleep 2
chronyc sources
echo "[+] Chrony настроен"

# ============================================================
# ЗАДАНИЕ 2: SAMBA AD DC
# ============================================================
echo "[*] [2] Настраиваем Samba AD DC..."
apt-get install -y samba samba-dc krb5-workstation

# Очищаем если была предыдущая конфигурация
rm -f /etc/samba/smb.conf

echo "[*] Запуск samba-tool domain provision (неинтерактивный)..."
samba-tool domain provision \
  --use-rfc2307 \
  --realm=AU-TEAM.IRPO \
  --domain=AU-TEAM \
  --server-role=dc \
  --dns-backend=SAMBA_INTERNAL \
  --adminpass='P@ssw0rd'

# Копируем krb5.conf
cp /var/lib/samba/private/krb5.conf /etc/krb5.conf

systemctl enable --now samba
systemctl restart samba

echo "[+] Samba AD DC запущена"

# --- Создание пользователей ---
echo "[*] Создаём пользователей Samba..."
for i in 1 2 3; do
  samba-tool user create "user${i}.hq" 'P@ssw0rd' \
    --home-directory="/home/AU-TEAM/user${i}.hq" \
    --uid="user${i}.hq" 2>/dev/null || echo "[!] user${i}.hq уже существует"
done

samba-tool group add hq 2>/dev/null || true
for i in 1 2 3; do
  samba-tool group addmembers hq "user${i}.hq" 2>/dev/null || true
done
samba-tool group addmembers "Account Operators" hq 2>/dev/null || true
samba-tool group addmembers "Allowed RODC Password Replication Group" hq 2>/dev/null || true

echo "[+] Пользователи и группы Samba созданы"

# ============================================================
# ЗАДАНИЕ 3: ANSIBLE
# ============================================================
echo "[*] [3] Настраиваем Ansible..."
apt-get install -y ansible sshpass

# Генерируем SSH ключ если нет
if [ ! -f /root/.ssh/id_rsa ]; then
  ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa
fi

echo "[*] Копируем SSH ключи на хосты..."
echo "[!] Нужно вручную ввести пароли при запросе:"

# Копируем ключи
ssh-copy-id -p 2026 -o StrictHostKeyChecking=no sshuser@192.168.1.2 2>/dev/null || true
ssh-copy-id -o StrictHostKeyChecking=no kmw@192.168.2.2 2>/dev/null || true
ssh-copy-id -o StrictHostKeyChecking=no net_admin@172.16.1.1 2>/dev/null || true
ssh-copy-id -o StrictHostKeyChecking=no net_admin@172.16.2.1 2>/dev/null || true

# Inventory файл
cat > /etc/ansible/inv << 'EOF'
[hq]
	192.168.1.2 ansible_port=2026 ansible_user=sshuser
	192.168.2.2 ansible_user=kmw
	172.16.1.1  ansible_user=net_admin

[br]
	172.16.2.1 ansible_user=net_admin
EOF

# ansible.cfg
cat > /etc/ansible/ansible.cfg << 'EOF'
[defaults]
interpreter_python=auto_silent
host_key_checking=False
EOF

# Тест
echo "[*] Тест Ansible ping..."
ansible all -i /etc/ansible/inv -m ping || echo "[!] Проверь SSH доступ к хостам"

echo "[+] Ansible настроен"

# ============================================================
# ЗАДАНИЕ 8: DOCKER — ВНИМАНИЕ: ЛОМАЕТ SAMBA! ДЕЛАТЬ В КОНЦЕ!
# ============================================================
echo ""
echo "========================================================"
echo "[!] DOCKER: Задание 8 — выполнять ТОЛЬКО если уже"
echo "    завершены все задания с Samba (задание 2)!"
echo "    Запусти отдельно: bash /root/m2_docker.sh"
echo "========================================================"

# Создаём отдельный скрипт для Docker
cat > /root/m2_docker.sh << 'DOCKER_EOF'
#!/bin/bash
# MODULE 2 — Задание 8: Docker (запускать после Samba)
set -e

echo "[*] [8] Настраиваем Docker..."
systemctl enable --now docker

usermod -aG docker sshuser
usermod -aG docker root

# Монтируем CD
mount /dev/sr0 /mnt/ 2>/dev/null || echo "[!] CD уже смонтирован"

# Загружаем образы
docker load < /mnt/docker/mariadb_latest.tar
docker load < /mnt/docker/site_latest.tar

# docker-compose файл
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

docker compose -f /root/web.yaml up -d

echo "[+] Docker запущен. Клиент: открой http://192.168.4.2:8080"
DOCKER_EOF
chmod +x /root/m2_docker.sh

echo "[+] === BR-SRV MODULE 2: Завершено (без Docker) ==="
echo "[!] Для Docker: bash /root/m2_docker.sh"
