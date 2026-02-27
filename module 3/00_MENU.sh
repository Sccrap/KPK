#!/bin/bash
# ============================================================
# МАСТЕР-СКРИПТ: Демо-экзамен — запуск по заданиям
# Выполняйте на нужном хосте с нужным параметром
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║         ДЕМО-ЭКЗАМЕН — АВТОМАТИЗАЦИЯ ЗАДАНИЙ        ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_menu() {
    echo -e "${BOLD}Выберите задание:${NC}"
    echo ""
    echo -e "  ${GREEN}1${NC}) Импорт пользователей AD      [BR-SRV]"
    echo -e "  ${GREEN}2${NC}) Центр сертификации GOST       [HQ-SRV | ISP | Клиент]"
    echo -e "  ${GREEN}3${NC}) IPSec/GRE туннель             [HQ-RTR | BR-RTR]"
    echo -e "  ${GREEN}4${NC}) Межсетевой экран nftables     [HQ-RTR | BR-RTR]"
    echo -e "  ${GREEN}5${NC}) Принт-сервер CUPS             [HQ-SRV]"
    echo -e "  ${GREEN}6${NC}) Логирование Rsyslog           [HQ-SRV | RTR | SRV]"
    echo -e "  ${GREEN}7${NC}) Мониторинг Prometheus+Grafana [HQ-SRV | BR-SRV]"
    echo -e "  ${GREEN}8${NC}) Ansible инвентаризация        [BR-SRV]"
    echo -e "  ${GREEN}9${NC}) Fail2ban SSH защита           [HQ-SRV]"
    echo ""
    echo -e "  ${YELLOW}0${NC}) Выход"
    echo ""
}

run_task() {
    local task="$1"
    local role="$2"
    local script="${SCRIPT_DIR}/0${task}_*.sh"

    # Найти нужный скрипт
    local found=$(ls ${SCRIPT_DIR}/0${task}_*.sh 2>/dev/null | head -1)

    if [[ -z "$found" ]]; then
        echo -e "${RED}[ERR] Скрипт для задания $task не найден!${NC}"
        return
    fi

    chmod +x "$found"
    echo -e "${CYAN}[*] Запуск: $found ${role}${NC}"
    echo ""

    if [[ -n "$role" ]]; then
        bash "$found" "$role"
    else
        bash "$found"
    fi
}

print_banner

# Если переданы аргументы — запустить сразу
if [[ -n "$1" ]]; then
    run_task "$1" "$2"
    exit 0
fi

# Интерактивное меню
while true; do
    print_menu
    read -rp "Введите номер задания: " choice

    case "$choice" in
        1) run_task 1 "" ;;
        2)
            echo "Роли: hq-srv | isp | client"
            read -rp "Введите роль: " role
            run_task 2 "$role"
            ;;
        3)
            echo "Роли: hq-rtr | br-rtr"
            read -rp "Введите роль: " role
            run_task 3 "$role"
            ;;
        4) run_task 4 "" ;;
        5) run_task 5 "" ;;
        6)
            echo "Роли: hq-srv | hq-rtr | br-rtr | br-srv"
            read -rp "Введите роль: " role
            run_task 6 "$role"
            ;;
        7)
            echo "Роли: hq-srv | br-srv"
            read -rp "Введите роль: " role
            run_task 7 "$role"
            ;;
        8) run_task 8 "" ;;
        9) run_task 9 "" ;;
        0) echo "Выход."; exit 0 ;;
        *) echo -e "${RED}Неверный выбор${NC}" ;;
    esac

    echo ""
    read -rp "Нажмите Enter для продолжения..."
    clear
    print_banner
done
