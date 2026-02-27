#!/bin/bash
###############################################################################
# m2_04_hq-srv_raid-nfs.sh — RAID0 + NFS-сервер (HQ-SRV, ALT Linux)
# Задание 2: Файловое хранилище (RAID0)
# Задание 3: NFS-сервер
###############################################################################
set -e

# ======================== ПЕРЕМЕННЫЕ =========================================
# Диски для RAID (проверьте через lsblk!)
DISK1="/dev/sdb"
DISK2="/dev/sdc"
PART1="${DISK1}1"
PART2="${DISK2}1"

# RAID
RAID_DEV="/dev/md0"
RAID_LEVEL=0    # RAID 0 (stripe)
RAID_MOUNT="/raid"

# NFS
NFS_SHARE="$RAID_MOUNT/nfs"
NFS_NETWORK="192.168.0.0/23"
NFS_OPTIONS="rw,sync,subtree_check"

# =============================================================================
echo "=== [1/7] Проверка дисков ==="

echo "Текущие блочные устройства:"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS
echo ""

for disk in "$DISK1" "$DISK2"; do
    if [ ! -b "$disk" ]; then
        echo "  ОШИБКА: Диск $disk не найден!"
        echo "  Проверьте lsblk и измените переменные DISK1/DISK2 в скрипте"
        exit 1
    fi
done
echo "  Диски $DISK1 и $DISK2 найдены"

# =============================================================================
echo "=== [2/7] Создание разделов (GPT) ==="

create_partition() {
    local disk="$1"
    echo "  Разметка $disk..."

    # Автоматическая разметка через sfdisk (неинтерактивно)
    # Создаём GPT таблицу с одним разделом на весь диск
    echo 'label: gpt' | sfdisk "$disk" --force 2>/dev/null
    echo ',,L' | sfdisk "$disk" --force 2>/dev/null

    partprobe "$disk" 2>/dev/null || true
    sleep 1
}

# Проверяем, нет ли уже активного RAID
if [ -b "$RAID_DEV" ]; then
    echo "  RAID $RAID_DEV уже существует. Пропускаем создание разделов."
else
    create_partition "$DISK1"
    create_partition "$DISK2"

    # Ждём появления разделов
    sleep 2
    partprobe 2>/dev/null || true

    # Проверяем разделы
    for part in "$PART1" "$PART2"; do
        if [ ! -b "$part" ]; then
            echo "  ОШИБКА: Раздел $part не создан!"
            echo "  Попробуйте создать разделы вручную через fdisk"
            exit 1
        fi
    done
    echo "  Разделы $PART1 и $PART2 созданы"
fi

# =============================================================================
echo "=== [3/7] Создание RAID0 ==="

if [ -b "$RAID_DEV" ]; then
    echo "  $RAID_DEV уже существует, пропускаем"
else
    # Создаём RAID массив (--run убирает подтверждение)
    mdadm --create --verbose "$RAID_DEV" \
        --level="$RAID_LEVEL" \
        --raid-devices=2 \
        "$PART1" "$PART2" \
        --run

    sleep 2
    echo "  RAID0 создан: $RAID_DEV"
fi

# Сохраняем конфигурацию
mdadm --detail --scan > /etc/mdadm.conf 2>/dev/null || true
# Дописываем если файл пуст
if [ ! -s /etc/mdadm.conf ]; then
    mdadm --detail --scan >> /etc/mdadm.conf
fi

echo "  Конфигурация сохранена в /etc/mdadm.conf"

# =============================================================================
echo "=== [4/7] Форматирование и монтирование ==="

# Проверяем есть ли уже файловая система
if ! blkid "$RAID_DEV" | grep -q "ext4"; then
    mkfs.ext4 -F "$RAID_DEV"
    echo "  $RAID_DEV отформатирован в ext4"
else
    echo "  $RAID_DEV уже содержит ext4"
fi

# Создаём точку монтирования
mkdir -p "$RAID_MOUNT"
chmod 777 "$RAID_MOUNT"

# Монтируем
if ! mountpoint -q "$RAID_MOUNT"; then
    mount -t ext4 "$RAID_DEV" "$RAID_MOUNT"
    echo "  $RAID_DEV смонтирован в $RAID_MOUNT"
else
    echo "  $RAID_MOUNT уже смонтирован"
fi

# =============================================================================
echo "=== [5/7] Добавление в fstab ==="

FSTAB_LINE="$RAID_DEV $RAID_MOUNT ext4 defaults 0 0"

if ! grep -qF "$RAID_DEV" /etc/fstab; then
    echo "$FSTAB_LINE" >> /etc/fstab
    echo "  Запись добавлена в fstab"
else
    echo "  Запись в fstab уже существует"
fi

# Проверяем монтирование
mount -av 2>&1 | grep -v "already mounted" || true

# =============================================================================
echo "=== [6/7] Создание NFS-шары ==="

mkdir -p "$NFS_SHARE"
chmod 777 "$NFS_SHARE"

# Настройка exports
EXPORT_LINE="$NFS_SHARE $NFS_NETWORK($NFS_OPTIONS)"

if ! grep -qF "$NFS_SHARE" /etc/exports 2>/dev/null; then
    echo "$EXPORT_LINE" >> /etc/exports
    echo "  Экспорт добавлен: $EXPORT_LINE"
else
    echo "  Экспорт уже настроен"
fi

# =============================================================================
echo "=== [7/7] Запуск NFS-сервера ==="

systemctl enable --now nfs
sleep 1
exportfs -a

echo ""
echo "=== Проверка ==="
echo "--- RAID ---"
cat /proc/mdstat
echo ""
echo "--- Монтирование ---"
df -h "$RAID_MOUNT"
echo ""
echo "--- NFS экспорт ---"
exportfs -v
echo ""
echo "=== RAID0 + NFS настроены ==="
echo ""
echo "На HQ-CLI выполните m2_05_hq-cli_nfs-client.sh для монтирования"
