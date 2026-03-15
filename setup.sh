#!/bin/bash
# Строгий режим выполнения
set -euo pipefail
IFS=$'\n\t'

# Получение директории скриптов
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Загрузка конфигурации
source "$SCRIPT_DIR/scripts/config.sh"
source "$SCRIPT_DIR/scripts/utils.sh"

# Загрузка модулей
source "$MODULES_DIR/user.sh"
source "$MODULES_DIR/system.sh"
source "$MODULES_DIR/swap.sh"
source "$MODULES_DIR/ulimits.sh"
source "$MODULES_DIR/packages.sh"
source "$MODULES_DIR/ssh.sh"
source "$MODULES_DIR/firewall.sh"
source "$MODULES_DIR/zsh.sh"
source "$MODULES_DIR/nodejs.sh"
source "$MODULES_DIR/uv.sh"
source "$MODULES_DIR/docker.sh"
source "$MODULES_DIR/xanmod.sh"
source "$MODULES_DIR/sysctl_hardening.sh"

# Проверка прав
if [[ $EUID -eq 0 ]]; then
   error "Этот скрипт НЕ должен запускаться от root"
   exit 1
fi

# Функция установки всего
install_all() {
    log "=========================================="
    log "Полная установка и настройка сервера"
    log "=========================================="

    check_internet || return 1

    update_system
    setup_xanmod
    setup_swap
    setup_ulimits
    install_packages
    setup_ssh
    setup_firewall
    setup_zsh
    setup_nodejs
    setup_uv
    setup_docker
    setup_sysctl_hardening

    mkdir -p ~/projects ~/scripts ~/downloads ~/backup && check_success "Структура каталогов создана"

    log "=========================================="
    log "Полная установка завершена успешно!"
    log "=========================================="
    echo ""
    info "Для применения всех изменений необходимо:"
    echo "1. Перелогиниться или выполнить: exec zsh"
    echo "2. Проверить Docker: newgrp docker && docker run hello-world"
    echo ""
    read -p "Хотите перезагрузить систему сейчас? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Перезагрузка системы..."
        sudo reboot
    else
        log "Перезагрузка отменена"
        info "Для применения изменений: exec zsh"
    fi
}
show_menu() {
    clear
    BANNER=$(cat << 'EOF'
                                         _
 ___ ___ _ ____ _____ _ __ ___ ___| |_ _ _ _ __
/ __|/ _ \ '__\ \ / / _ \ '__| / __|/ _ \ __| | | | '_ \
\__ \ __/ | \ V / __/ | \__ \ __/ |_| |_| | |_) |
|___/\___|_| \_/ \___|_| |___/\___|\__|\__,_| .__/
                                                  |_|
EOF
    )
    echo -e "${CYAN}$BANNER${NC}"
    echo ""
    echo -e "${YELLOW}Выберите действие:${NC}"
    echo ""
    echo -e " ${GREEN}1)${NC} Установить все настройки сразу"
    echo -e " ${GREEN}2)${NC} Добавить пользователя"
    echo -e " ${GREEN}3)${NC} Обновить Ubuntu Server"
    echo -e " ${GREEN}4)${NC} Установить базовые пакеты"
    echo -e " ${GREEN}5)${NC} Настроить SWAP"
    echo -e " ${GREEN}6)${NC} Настроить ulimits"
    echo -e " ${GREEN}7)${NC} Настроить SSH"
    echo -e " ${GREEN}8)${NC} Настроить файрвол UFW и Fail2Ban"
    echo -e " ${GREEN}9)${NC} Установить и настроить ZSH + Oh My Zsh"
    echo -e " ${GREEN}10)${NC} Установить Node.js, Bun и PM2"
    echo -e " ${GREEN}11)${NC} Установить uv"
    echo -e " ${GREEN}12)${NC} Установить Docker"
    echo -e " ${GREEN}13)${NC} Установить XanMod Kernel"
    echo -e " ${GREEN}14)${NC} Применить sysctl hardening (BBR + производительность)"
    echo -e " ${RED}0)${NC} Выход"
    echo ""
    echo -e "${BLUE}Лог сохраняется в: $LOG_FILE${NC}"
    echo ""
}

# Основной цикл программы (без изменений)
main() {
    log "=========================================="
    log "Запуск скрипта установки и настройки"
    log "=========================================="
    while true; do
        show_menu
        read -p "Ваш выбор: " choice
        echo ""
        case $choice in
            1) install_all ;;
            2) add_user ;;
            3) update_system ;;
            4) install_packages ;;
            5) setup_swap ;;
            6) setup_ulimits ;;
            7) setup_ssh ;;
            8) setup_firewall ;;
            9) setup_zsh ;;
            10) setup_nodejs ;;
            11) setup_uv ;;
            12) setup_docker ;;
            13) setup_xanmod ;;
            14) setup_sysctl_hardening ;;
            0) log "Выход из программы"; exit 0 ;;
            *) error "Неверный выбор. Попробуйте снова." ;;
        esac
        echo ""
        read -p "Нажмите Enter для продолжения..."
    done
}

# Запуск основной функции
main
