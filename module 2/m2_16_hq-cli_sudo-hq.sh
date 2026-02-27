#!/bin/bash
###############################################################################
# m2_16_hq-cli_sudo-hq.sh — Sudo-права для доменной группы hq (HQ-CLI)
# Выполняется ПОСЛЕ ввода HQ-CLI в домен и создания группы hq
###############################################################################
set -e

SUDO_LINE='%au-team//hq ALL=(ALL) NOPASSWD:/bin/cat,/bin/grep,/bin/id'

if ! grep -qF "%au-team//hq" /etc/sudoers 2>/dev/null; then
    echo "$SUDO_LINE" >> /etc/sudoers
    echo "Sudo-права для группы hq добавлены:"
    echo "  $SUDO_LINE"
else
    echo "Sudo-права для группы hq уже настроены"
fi
