#!/bin/bash
###############################################################################
# m2_03_br-srv_samba-users.sh — Создание пользователей и групп в Samba AD
# Задание 1 (продолжение): Пользователи, группы, права sudo
# Выполняется на BR-SRV (контроллер домена)
###############################################################################
set -e

# ======================== ПЕРЕМЕННЫЕ =========================================
DOMAIN="au-team.irpo"
REALM="AU-TEAM.IRPO"
DEFAULT_PASS="P@ssw0rd"

# Пользователи (имя:фамилия)
# Измените под свои нужды
USERS=(
    "user1:User One"
    "user2:User Two"
    "user3:User Three"
    "admin1:Admin One"
)

# Группа
GROUP_NAME="hq"

# Пользователи, которые будут в группе hq
GROUP_MEMBERS=("user1" "user2" "user3" "admin1")

# Sudo-права для группы hq (на HQ-CLI)
# Формат: %DOMAIN//group ALL=(ALL) NOPASSWD:commands
SUDO_COMMANDS="/bin/cat,/bin/grep,/bin/id"

# =============================================================================
echo "=== [1/4] Создание пользователей ==="

for entry in "${USERS[@]}"; do
    IFS=':' read -r username fullname <<< "$entry"

    # Проверяем существует ли пользователь
    if samba-tool user list 2>/dev/null | grep -qw "$username"; then
        echo "  $username — уже существует, пропускаем"
    else
        samba-tool user create "$username" "$DEFAULT_PASS" \
            --given-name="${fullname%% *}" \
            --surname="${fullname#* }" \
            --use-username-as-cn \
            2>/dev/null
        echo "  $username — создан (пароль: $DEFAULT_PASS)"
    fi
done

# =============================================================================
echo "=== [2/4] Создание группы $GROUP_NAME ==="

if samba-tool group list 2>/dev/null | grep -qw "$GROUP_NAME"; then
    echo "  Группа $GROUP_NAME уже существует"
else
    samba-tool group add "$GROUP_NAME" 2>/dev/null
    echo "  Группа $GROUP_NAME создана"
fi

# =============================================================================
echo "=== [3/4] Добавление пользователей в группу $GROUP_NAME ==="

for username in "${GROUP_MEMBERS[@]}"; do
    if samba-tool group listmembers "$GROUP_NAME" 2>/dev/null | grep -qw "$username"; then
        echo "  $username уже в группе $GROUP_NAME"
    else
        samba-tool group addmembers "$GROUP_NAME" "$username" 2>/dev/null
        echo "  $username добавлен в группу $GROUP_NAME"
    fi
done

# =============================================================================
echo "=== [4/4] Настройка sudo-прав для группы ==="

SUDO_LINE="%au-team//hq ALL=(ALL) NOPASSWD:$SUDO_COMMANDS"

echo ""
echo "  Для предоставления sudo-прав группе hq выполните на HQ-CLI:"
echo ""
echo "  echo '$SUDO_LINE' >> /etc/sudoers"
echo ""

# Если скрипт запущен на машине где нужны sudo-права (напр. HQ-CLI)
# Раскомментируйте:
# if ! grep -qF "%au-team//hq" /etc/sudoers 2>/dev/null; then
#     echo "$SUDO_LINE" >> /etc/sudoers
#     echo "  Sudo-права добавлены"
# fi

echo ""
echo "=== Проверка ==="
echo "--- Список пользователей ---"
samba-tool user list 2>/dev/null
echo ""
echo "--- Участники группы $GROUP_NAME ---"
samba-tool group listmembers "$GROUP_NAME" 2>/dev/null
echo ""
echo "=== Пользователи и группы настроены ==="
