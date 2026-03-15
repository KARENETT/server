#!/bin/bash

setup_swap() {
    local total_mem_mb
    local current_swap
    local swap_size_mb

    log "=========================================="
    log "Настройка SWAP"
    log "=========================================="

    total_mem_mb="$(free -m | awk '/^Mem:/{print $2}')"
    if [[ -z "${total_mem_mb:-}" ]]; then
        error "Не удалось определить объём RAM"
        return 1
    fi

    if [ "$total_mem_mb" -ge 8192 ]; then
        info "RAM >= 8GB, создание SWAP не требуется"
        return 0
    fi

    current_swap="$(swapon --show --bytes 2>/dev/null | tail -n +2 | awk '{sum+=$3} END {print int(sum/1024/1024)}')"
    current_swap="${current_swap:-0}"

    if [ "$current_swap" -ge 1024 ]; then
        info "SWAP уже настроен: ${current_swap}MB"
        return 0
    fi

    swap_size_mb=$((4096 - total_mem_mb))
    [ "$swap_size_mb" -lt 1024 ] && swap_size_mb=2048
    [ "$swap_size_mb" -gt 4096 ] && swap_size_mb=4096

    info "Будет создан SWAP файл размером ${swap_size_mb}MB"
    echo ""
    read -p "Продолжить настройку SWAP? (Y/n): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        warning "Настройка SWAP отменена"
        return 0
    fi

    if [ -f /swapfile ]; then
        warning "Обнаружен существующий /swapfile, он будет пересоздан"
        sudo swapoff /swapfile 2>/dev/null || true
        sudo rm -f /swapfile
    fi

    retry_command "sudo fallocate -l ${swap_size_mb}M /swapfile" && check_success "Swap файл создан" || return 1
    retry_command "sudo chmod 600 /swapfile" && check_success "Права на swap файл установлены" || return 1
    retry_command "sudo mkswap /swapfile > /dev/null" && check_success "Swap файл размечен" || return 1
    retry_command "sudo swapon /swapfile" && check_success "Swap активирован" || return 1

    if ! grep -q '^/swapfile ' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab > /dev/null
        check_success "Swap добавлен в /etc/fstab" || return 1
    else
        info "/etc/fstab уже содержит запись для /swapfile"
    fi

    retry_command "sudo sysctl -w vm.swappiness=10 > /dev/null" && check_success "vm.swappiness настроен" || return 1
    retry_command "sudo sysctl -w vm.vfs_cache_pressure=50 > /dev/null" && check_success "vm.vfs_cache_pressure настроен" || return 1

    log "SWAP ${swap_size_mb}MB готов"
}
