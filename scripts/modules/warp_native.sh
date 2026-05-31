#!/bin/bash

is_warp_native_installed() {
    command -v warp >/dev/null 2>&1 || command -v warp-cli >/dev/null 2>&1 || systemctl list-unit-files 2>/dev/null | grep -q '^warp-'
}

setup_warp_native() {
    if ! command -v curl >/dev/null 2>&1; then
        error "$(t curl_not_found)"
        return 1
    fi

    if ! confirm_yes_no "$(t remote_install_confirm) WARP NATIVE? (y/N):"; then
        warning "$(t remote_install_cancelled)"
        return 0
    fi

    info "URL: https://raw.githubusercontent.com/distillium/warp-native/main/install.sh"
    log "Установка WARP NATIVE by distillium..."
    if bash <(curl -fsSL "https://raw.githubusercontent.com/distillium/warp-native/main/install.sh"); then
        check_success "WARP NATIVE установлен"
    else
        error "Не удалось установить WARP NATIVE"
        return 1
    fi
}
