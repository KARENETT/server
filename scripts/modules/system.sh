#!/bin/bash

# Функция обновления системы
update_system() {
    log "=========================================="
    log "$(t system_update_title)"
    log "=========================================="

    check_internet || return 1

    log "$(t system_updating)"
    retry_command "apt update -y" && check_success "apt update"
    retry_command "DEBIAN_FRONTEND=noninteractive apt upgrade -y" && check_success "apt upgrade"
    apt autoremove -y || true
    apt autoclean || true

    log "$(t system_updated)"
}
