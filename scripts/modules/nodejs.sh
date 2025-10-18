#!/bin/bash

# Функция установки Node.js, Bun, PM2
setup_nodejs() {
    log "=========================================="
    log "Установка Node.js, Bun и PM2"
    log "=========================================="

    check_internet || return 1

    # Установка Node.js
    log "Установка Node.js..."
    if ! command -v node &> /dev/null; then
        retry_command "curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -" && \
        retry_command "sudo apt-get install -y nodejs" && check_success "Node.js установлен"
    else
        info "Node.js уже установлен ($(node --version))"
    fi

    # Установка глобальных npm пакетов
    if command -v npm &> /dev/null; then
        log "Установка PM2 и Yarn..."
        retry_command "sudo npm install -g pm2 yarn" && check_success "PM2 и Yarn установлены"
    fi

    # Установка Bun
    log "Установка Bun..."
    if ! command -v bun &> /dev/null; then
        retry_command "curl -fsSL https://bun.sh/install | bash" && check_success "Bun установлен"
        export BUN_INSTALL="$HOME/.bun"
        export PATH="$BUN_INSTALL/bin:$PATH"
    else
        info "Bun уже установлен ($(bun --version))"
    fi

    log "Node.js, Bun и PM2 установлены"
}
