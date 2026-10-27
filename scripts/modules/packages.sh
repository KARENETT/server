#!/bin/bash

# Функция установки пакетов
install_packages() {
    log "=========================================="
    log "$(t packages_title)"
    log "=========================================="

    check_internet || return 1

    local -a BASIC_PACKAGES=(
        curl wget git ufw micro gpg ca-certificates
        lsb-release apt-transport-https software-properties-common
        build-essential unzip gnupg gnupg-agent tree htop btop
        fastfetch vim nano jq rsync tmux screen bat
        fd-find ripgrep fzf python3-pip
    )
    local package_args

    echo ""
    info "$(t packages_list)"
    printf '%s\n' "${BASIC_PACKAGES[@]}" | pr -t -3
    echo ""
    if ! confirm_yes_no "$(t packages_confirm)" yes; then
        warning "$(t packages_cancelled)"
        return 0
    fi

    log "$(t packages_installing)"
    printf -v package_args '%q ' "${BASIC_PACKAGES[@]}"
    if ! retry_command "DEBIAN_FRONTEND=noninteractive apt-get install -y $package_args"; then
        return 1
    fi

    # Создание символической ссылки для bat
    mkdir -p ~/.local/bin
    if [ ! -L ~/.local/bin/bat ]; then
        ln -s /usr/bin/batcat ~/.local/bin/bat && check_success "Символическая ссылка для bat создана"
    fi

    # Установка eza
    log "$(t eza_installing)"
    if ! command -v eza &> /dev/null; then
        {
            mkdir -p /etc/apt/keyrings
            wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
            echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" > /etc/apt/sources.list.d/gierens.list
            chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
            apt update
            apt install -y eza
            check_success "eza установлен"
        } || {
            warning "$(t eza_install_failed)"
        }
    else
        info "$(t eza_already_installed)"
    fi

    log "$(t packages_done)"
}
