#!/bin/bash
###############################################################################
# m2_09_br-srv_docker.sh — Docker: MariaDB + Web App (BR-SRV, ALT Linux)
# Задание 6: Развертывание приложений в Docker
###############################################################################
set -e

# ======================== ПЕРЕМЕННЫЕ =========================================
ISO_MOUNT="/mnt"
ISO_DEVICE="/dev/sr0"
DOCKER_DIR="/mnt/docker"

# Параметры приложения
APP_NAME="testapp"
APP_IMAGE="site"
APP_PORT_EXT="8080"
APP_PORT_INT="8000"

# Параметры БД
DB_CONTAINER="db"
DB_IMAGE="mariadb"              # Образ из tar (mariadb:latest)
DB_NAME="testdb"
DB_USER="test"
DB_PASS="P@ssw0rd"
DB_ROOT_PASS="P@ssw0rd"
DB_PORT="3306"
DB_TYPE="maria"

# Docker Compose файл
COMPOSE_FILE="/root/web.yaml"

# =============================================================================
echo "=== [1/5] Запуск Docker ==="

systemctl enable --now docker
sleep 2
echo "  Docker запущен"

# =============================================================================
echo "=== [2/5] Монтирование Additional.iso ==="

mkdir -p "$ISO_MOUNT"

if mountpoint -q "$ISO_MOUNT"; then
    echo "  $ISO_MOUNT уже смонтирован"
else
    mount "$ISO_DEVICE" "$ISO_MOUNT" 2>/dev/null || {
        echo "  ОШИБКА: Не удалось смонтировать $ISO_DEVICE"
        echo "  Проверьте наличие CD/DVD: lsblk"
        exit 1
    }
    echo "  $ISO_DEVICE смонтирован в $ISO_MOUNT"
fi

echo "  Содержимое $DOCKER_DIR:"
ls -la "$DOCKER_DIR/" 2>/dev/null || echo "  Каталог $DOCKER_DIR не найден!"

# =============================================================================
echo "=== [3/5] Импорт Docker-образов ==="

for tarfile in "$DOCKER_DIR"/*.tar; do
    if [ -f "$tarfile" ]; then
        echo "  Загружаем $(basename "$tarfile")..."
        docker load < "$tarfile"
    fi
done

echo ""
echo "  Доступные образы:"
docker images --format "  {{.Repository}}:{{.Tag}} ({{.Size}})"

# =============================================================================
echo "=== [4/5] Создание docker-compose файла ==="

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

echo "  $COMPOSE_FILE создан"

# =============================================================================
echo "=== [5/5] Запуск контейнеров ==="

cd /root

# Останавливаем если уже запущены
docker compose -f "$COMPOSE_FILE" down 2>/dev/null || true

# Запускаем
docker compose -f "$COMPOSE_FILE" up -d

sleep 5

echo ""
echo "=== Проверка ==="
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
echo ""
echo "Приложение доступно на: http://$(hostname -I | awk '{print $1}'):$APP_PORT_EXT"
echo ""
echo "=== Docker настроен ==="
