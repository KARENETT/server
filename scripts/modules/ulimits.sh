#!/bin/bash

setup_ulimits() {
    local limits_file="/etc/security/limits.d/99-server-opt.conf"

    log "=========================================="
    log "$(t ulimits_title)"
    log "=========================================="

    tee "$limits_file" > /dev/null << 'EOF'
* soft nofile 1000000
* hard nofile 1000000
root soft nofile 1000000
root hard nofile 1000000
EOF
    check_success "Лимиты nofile записаны в $limits_file" || return 1

    ulimit -n 1000000 2>/dev/null || true

    warning "$(t ulimits_relogin)"
    log "$(t ulimits_done)"
}

disable_ulimits() {
    local limits_file="/etc/security/limits.d/99-server-opt.conf"

    log "=========================================="
    log "$(t ulimits_disable_title)"
    log "=========================================="

    rm -f "$limits_file"
    warning "$(t ulimits_disable_relogin)"
    check_success "Пользовательские ulimits отключены"
}
