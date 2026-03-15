#!/bin/bash

setup_ulimits() {
    local limits_file="/etc/security/limits.d/99-server-opt.conf"

    log "=========================================="
    log "Настройка ulimits"
    log "=========================================="

    sudo tee "$limits_file" > /dev/null << 'EOF'
* soft nofile 1000000
* hard nofile 1000000
root soft nofile 1000000
root hard nofile 1000000
EOF
    check_success "Лимиты nofile записаны в $limits_file" || return 1

    ulimit -n 1000000 2>/dev/null || true

    warning "Новые лимиты полностью применятся после нового входа в систему"
    log "Лимиты открытых файлов увеличены до 1000000"
}
