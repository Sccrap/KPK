#!/bin/bash
# ============================================================
# ЗАДАНИЕ 2: Центр сертификации (GOST TLS)
# Выполняется на: HQ-SRV (генерация), ISP (nginx), Клиент (trust)
# ============================================================

# --- ЦВЕТА ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[ERR]${NC} $1"; }

ROLE="${1:-hq-srv}"  # Передать роль: hq-srv | isp | client

case "$ROLE" in

# =============================================
# РОЛЬ: HQ-SRV — генерация всех сертификатов
# =============================================
hq-srv)
    echo "=== ЗАДАНИЕ 2: Центр сертификации (HQ-SRV) ==="

    echo "[1/7] Установка openssl-gost-engine..."
    apt-get update -q
    apt-get install -y openssl-gost-engine
    control openssl-gost enabled
    info "openssl-gost включён"

    echo "[2/7] Создание структуры PKI..."
    mkdir -p /etc/pki/CA/{private,certs,newcerts,crl}
    touch /etc/pki/CA/index.txt
    echo 1000 > /etc/pki/CA/serial
    chmod 700 /etc/pki/CA/private
    info "Структура /etc/pki/CA создана"

    echo "[3/7] Генерация ключа CA (GOST 2012-256)..."
    openssl genkey \
        -algorithm gost2012_256 \
        -pkeyopt paramset:TCB \
        -out /etc/pki/CA/private/ca.key
    info "Ключ CA создан"

    echo "[4/7] Самоподписанный сертификат CA..."
    openssl req -x509 -new \
        -md_gost12_256 \
        -key /etc/pki/CA/private/ca.key \
        -out /etc/pki/CA/certs/ca.crt \
        -days 3650 \
        -subj "/C=RU/ST=Moscow/L=Moscow/O=AU-TEAM/OU=WEB/CN=AU-TEAM Root CA"
    info "Сертификат CA создан"

    echo "[5/7] Генерация ключей для web и docker..."
    openssl genpkey \
        -algorithm gost2012_256 \
        -pkeyopt paramset:A \
        -out /etc/pki/CA/private/web.au-team.irpo.key

    openssl genpkey \
        -algorithm gost2012_256 \
        -pkeyopt paramset:A \
        -out /etc/pki/CA/private/docker.au-team.irpo.key
    info "Ключи web и docker созданы"

    echo "[6/7] Создание CSR и подпись сертификатов..."
    # Web CSR
    openssl req -new \
        -md_gost12_256 \
        -key /etc/pki/CA/private/web.au-team.irpo.key \
        -out /etc/pki/CA/newcerts/web.au-team.irpo.csr \
        -subj "/CN=web.au-team.irpo"

    # Docker CSR
    openssl req -new \
        -md_gost12_256 \
        -key /etc/pki/CA/private/docker.au-team.irpo.key \
        -out /etc/pki/CA/newcerts/docker.au-team.irpo.csr \
        -subj "/CN=docker.au-team.irpo"

    # Подпись web
    openssl x509 -req \
        -in /etc/pki/CA/newcerts/web.au-team.irpo.csr \
        -CA /etc/pki/CA/certs/ca.crt \
        -CAkey /etc/pki/CA/private/ca.key \
        -CAcreateserial \
        -out /etc/pki/CA/certs/web.au-team.irpo.crt \
        -days 30

    # Подпись docker
    openssl x509 -req \
        -in /etc/pki/CA/newcerts/docker.au-team.irpo.csr \
        -CA /etc/pki/CA/certs/ca.crt \
        -CAkey /etc/pki/CA/private/ca.key \
        -CAcreateserial \
        -out /etc/pki/CA/certs/docker.au-team.irpo.crt \
        -days 30
    info "Сертификаты web и docker подписаны"

    echo "[7/7] Копирование в NFS (/raid/nfs/)..."
    mkdir -p /raid/nfs/
    cp /etc/pki/CA/certs/ca.crt              /raid/nfs/
    cp /etc/pki/CA/certs/web.au-team.irpo.crt    /raid/nfs/
    cp /etc/pki/CA/certs/docker.au-team.irpo.crt /raid/nfs/
    cp /etc/pki/CA/private/web.au-team.irpo.key  /raid/nfs/
    cp /etc/pki/CA/private/docker.au-team.irpo.key /raid/nfs/
    info "Файлы скопированы в /raid/nfs/"

    echo ""
    echo "=== ГОТОВО (HQ-SRV) ==="
    echo "Следующий шаг: запустить скрипт с параметром 'isp' на ISP"
    echo "и с параметром 'client' на клиенте"
    ;;

# =============================================
# РОЛЬ: ISP — настройка nginx с TLS
# =============================================
isp)
    echo "=== ЗАДАНИЕ 2: Настройка nginx TLS (ISP) ==="

    echo "[1/3] Установка openssl-gost и копирование сертификатов с HQ-SRV..."
    apt-get update -q
    apt-get install -y openssl-gost-engine nginx

    mkdir -p /etc/nginx/ssl/private

    # Копируем файлы с HQ-SRV через scp (порт 2026, пользователь sshuser)
    HQ_SRV_IP="172.16.1.1"
    scp -P 2026 sshuser@${HQ_SRV_IP}:/raid/nfs/web.au-team.irpo.crt    /etc/nginx/ssl/
    scp -P 2026 sshuser@${HQ_SRV_IP}:/raid/nfs/web.au-team.irpo.key    /etc/nginx/ssl/private/
    scp -P 2026 sshuser@${HQ_SRV_IP}:/raid/nfs/docker.au-team.irpo.crt /etc/nginx/ssl/
    scp -P 2026 sshuser@${HQ_SRV_IP}:/raid/nfs/docker.au-team.irpo.key /etc/nginx/ssl/private/
    info "Сертификаты скопированы"

    echo "[2/3] Настройка nginx (добавление SSL-блоков)..."
    # Создаём конфиг (добавляем к существующему revers.conf)
    cat >> /etc/nginx/sites-enabled.d/revers.conf << 'NGINX_CONF'

# --- WEB SSL ---
server {
    listen 443 ssl;
    server_name web.au-team.irpo;

    ssl_certificate     /etc/nginx/ssl/web.au-team.irpo.crt;
    ssl_certificate_key /etc/nginx/ssl/private/web.au-team.irpo.key;
    ssl_protocols       TLSv1.2;
    ssl_ciphers         GOST2012-KUZNYECHIK-KUZNYECHIKOMAC;
    ssl_prefer_server_ciphers on;

    location / {
        proxy_pass http://192.168.0.1;  # Замените на нужный upstream
    }
}

# --- DOCKER SSL ---
server {
    listen 443 ssl;
    server_name docker.au-team.irpo;

    ssl_certificate     /etc/nginx/ssl/docker.au-team.irpo.crt;
    ssl_certificate_key /etc/nginx/ssl/private/docker.au-team.irpo.key;
    ssl_protocols       TLSv1.2;
    ssl_ciphers         GOST2012-KUZNYECHIK-KUZNYECHIKOMAC;
    ssl_prefer_server_ciphers on;

    location / {
        proxy_pass http://192.168.0.1;  # Замените на нужный upstream
    }
}
NGINX_CONF

    echo "[3/3] Проверка и перезапуск nginx..."
    nginx -t && systemctl restart nginx && info "nginx перезапущен успешно" \
        || error "Ошибка в конфиге nginx! Проверьте /etc/nginx/sites-enabled.d/revers.conf"
    ;;

# =============================================
# РОЛЬ: CLIENT — добавление CA в доверенные
# =============================================
client)
    echo "=== ЗАДАНИЕ 2: Добавление CA в хранилище (Клиент) ==="
    cp /mnt/nfs/ca.crt /etc/pki/ca-trust/source/anchors/
    update-ca-trust
    info "CA сертификат добавлен в доверенные"
    mkdir -p /etc/nginx/ssl/private
    info "Директории nginx/ssl созданы"
    ;;

*)
    echo "Использование: $0 [hq-srv|isp|client]"
    exit 1
    ;;
esac
