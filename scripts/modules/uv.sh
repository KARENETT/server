#!/bin/bash

# Функция установки uv
setup_uv() {
    log "=========================================="
    log "$(t uv_title)"
    log "=========================================="

    check_internet || return 1

    log "$(t uv_installing)"
    if ! command -v uv &> /dev/null; then
        retry_command "curl -LsSf https://astral.sh/uv/install.sh | sh" && check_success "uv установлен"
    else
        info "uv уже установлен"
    fi

    log "$(t uv_done)"
}
