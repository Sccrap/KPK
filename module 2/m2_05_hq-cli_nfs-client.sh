#!/bin/bash
###############################################################################
# m2_05_hq-cli_nfs-client.sh — NFS-клиент на HQ-CLI (ALT Linux)
# Задание 3 (продолжение): Автомонтирование NFS
###############################################################################
set -e

# ======================== ПЕРЕМЕННЫЕ =========================================
NFS_SERVER="192.168.0.1"
NFS_REMOTE_PATH="/raid/nfs"
NFS_LOCAL_MOUNT="/mnt/nfs"

# =============================================================================
echo "=== [1/3] Создание точки монтирования ==="

mkdir -p "$NFS_LOCAL_MOUNT"
chmod 777 "$NFS_LOCAL_MOUNT"
echo "  $NFS_LOCAL_MOUNT создан"

# =============================================================================
echo "=== [2/3] Добавление в fstab ==="

FSTAB_LINE="$NFS_SERVER:$NFS_REMOTE_PATH $NFS_LOCAL_MOUNT nfs auto 0 0"

if ! grep -qF "$NFS_SERVER:$NFS_REMOTE_PATH" /etc/fstab; then
    echo "$FSTAB_LINE" >> /etc/fstab
    echo "  Запись добавлена в fstab"
else
    echo "  Запись уже существует в fstab"
fi

# =============================================================================
echo "=== [3/3] Монтирование ==="

mount -av 2>&1 || echo "  Ошибка монтирования — проверьте доступность NFS-сервера"

echo ""
echo "=== Проверка ==="
df -h "$NFS_LOCAL_MOUNT" 2>/dev/null || echo "  NFS не смонтирован"
echo ""
echo "Если ошибка — перезапустите NFS на HQ-SRV: systemctl restart nfs"
echo "=== NFS-клиент настроен ==="
