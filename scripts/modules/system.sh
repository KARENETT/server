#!/bin/bash

# Функция обновления системы
update_system() {
    log "=========================================="
    log "Обновление Ubuntu Server"
    log "=========================================="

    check_internet || return 1

    log "Обновление системы..."
    retry_command "sudo apt update -y" && check_success "apt update"
    retry_command "sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y" && check_success "apt upgrade"
    sudo apt autoremove -y || true
    sudo apt autoclean || true

    log "Система успешно обновлена"
}
