#!/bin/bash

setup_swap() {
    local total_mem_mb
    local current_swap
    local swap_size_mb

    log "=========================================="
    log "$(t swap_title)"
    log "=========================================="

    total_mem_mb="$(free -m | awk '/^Mem:/{print $2}')"
    if [[ -z "${total_mem_mb:-}" ]]; then
        error "$(t swap_error_ram)"
        return 1
    fi

    if [ "$total_mem_mb" -ge 8192 ]; then
        info "$(t swap_no_need)"
        return 0
    fi

    current_swap="$(swapon --show --bytes 2>/dev/null | tail -n +2 | awk '{sum+=$3} END {print int(sum/1024/1024)}')"
    current_swap="${current_swap:-0}"

    if [ "$current_swap" -ge 1024 ]; then
        info "$(t swap_already): ${current_swap}MB"
        return 0
    fi

    swap_size_mb=$((4096 - total_mem_mb))
    [ "$swap_size_mb" -lt 1024 ] && swap_size_mb=2048
    [ "$swap_size_mb" -gt 4096 ] && swap_size_mb=4096

    info "$(t swap_will_create): ${swap_size_mb}MB"
    echo ""
    read -rp "${PROMPT_PREFIX} $(t swap_confirm) " -n 1
    echo ""
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        warning "$(t swap_cancelled)"
        return 0
    fi

    if [ -f /swapfile ]; then
        warning "$(t swap_recreate)"
        swapoff /swapfile 2>/dev/null || true
        rm -f /swapfile
    fi

    retry_command "fallocate -l ${swap_size_mb}M /swapfile" && check_success "Swap файл создан" || return 1
    retry_command "chmod 600 /swapfile" && check_success "Права на swap файл установлены" || return 1
    retry_command "mkswap /swapfile > /dev/null" && check_success "Swap файл размечен" || return 1
    retry_command "swapon /swapfile" && check_success "Swap активирован" || return 1

    if ! grep -q '^/swapfile ' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        check_success "Swap добавлен в /etc/fstab" || return 1
    else
        info "/etc/fstab уже содержит запись для /swapfile"
    fi

    retry_command "sysctl -w vm.swappiness=10 > /dev/null" && check_success "vm.swappiness настроен" || return 1
    retry_command "sysctl -w vm.vfs_cache_pressure=50 > /dev/null" && check_success "vm.vfs_cache_pressure настроен" || return 1

    log "SWAP ${swap_size_mb}MB готов"
}

disable_swap() {
    log "=========================================="
    log "Отключение SWAP"
    log "=========================================="

    swapoff -a >/dev/null 2>&1 || true
    rm -f /swapfile
    sed -i '\|^/swapfile none swap sw 0 0$|d' /etc/fstab
    sysctl -w vm.swappiness=60 >/dev/null 2>&1 || true
    check_success "SWAP отключен"
}
