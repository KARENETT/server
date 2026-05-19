#!/bin/bash

# Функция установки Node.js, Bun, PM2
setup_nodejs() {
    log "=========================================="
    log "$(t node_title)"
    log "=========================================="

    check_internet || return 1

    # Установка Node.js
    log "$(t node_installing)"
    if ! command -v node &> /dev/null; then
        retry_command "curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -" && \
        retry_command "apt-get install -y nodejs" && check_success "Node.js установлен"
    else
        info "Node.js уже установлен ($(node --version))"
    fi

    # Установка глобальных npm пакетов
    if command -v npm &> /dev/null; then
    log "$(t node_pm2_yarn)"
        retry_command "npm install -g pm2 yarn" && check_success "PM2 и Yarn установлены"
    fi

    # Установка Bun
    log "$(t bun_installing)"
    if ! command -v bun &> /dev/null; then
        retry_command "curl -fsSL https://bun.sh/install | bash" && check_success "Bun установлен"
        export BUN_INSTALL="$HOME/.bun"
        export PATH="$BUN_INSTALL/bin:$PATH"
    else
        info "Bun уже установлен ($(bun --version))"
    fi

    log "$(t node_done)"
}
