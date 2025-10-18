#!/bin/bash

# Функция установки пакетов
install_packages() {
    log "=========================================="
    log "Установка базовых пакетов"
    log "=========================================="

    check_internet || return 1

    BASIC_PACKAGES=(
        curl wget git ufw micro gpg ca-certificates
        lsb-release apt-transport-https software-properties-common
        build-essential unzip gnupg gnupg-agent tree htop
        neofetch vim nano jq rsync tmux screen bat
        fd-find ripgrep fzf python3-pip
    )

    echo ""
    info "Будут установлены следующие пакеты:"
    printf '%s\n' "${BASIC_PACKAGES[@]}" | column -c 80
    echo ""
    read -p "Продолжить установку? (Y/n): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        warning "Установка пакетов отменена"
        return 0
    fi

    log "Установка базовых утилит..."
    for package in "${BASIC_PACKAGES[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            info "Установка $package..."
            retry_command "sudo DEBIAN_FRONTEND=noninteractive apt install -y $package" && check_success "$package установлен" || warning "$package не удалось установить"
        else
            info "$package уже установлен"
        fi
    done

    # Создание символической ссылки для bat
    mkdir -p ~/.local/bin
    if [ ! -L ~/.local/bin/bat ]; then
        ln -s /usr/bin/batcat ~/.local/bin/bat && check_success "bat symlink создан"
    fi

    # Установка eza
    log "Установка eza..."
    if ! command -v eza &> /dev/null; then
        {
            sudo mkdir -p /etc/apt/keyrings
            wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
            echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | sudo tee /etc/apt/sources.list.d/gierens.list > /dev/null
            sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
            sudo apt update
            sudo apt install -y eza
            check_success "eza установлен"
        } || {
            warning "Установка eza через apt не удалась, пропускаем..."
        }
    else
        info "eza уже установлен"
    fi

    log "Установка пакетов завершена"
}
