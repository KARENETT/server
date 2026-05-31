#!/bin/bash

is_trafficguard_installed() {
    systemctl is-enabled --quiet trafficguard 2>/dev/null || command -v trafficguard >/dev/null 2>&1
}

setup_trafficguard() {
    if ! command -v curl >/dev/null 2>&1; then
        error "$(t curl_not_found)"
        return 1
    fi

    if ! confirm_yes_no "$(t remote_install_confirm) TrafficGuard? (y/N):"; then
        warning "$(t remote_install_cancelled)"
        return 0
    fi

    info "URL: https://raw.githubusercontent.com/DonMatteoVPN/TrafficGuard-auto/refs/heads/main/install-trafficguard.sh"
    log "Установка защиты от сканеров (TrafficGuard)..."
    if curl -fsSL "https://raw.githubusercontent.com/DonMatteoVPN/TrafficGuard-auto/refs/heads/main/install-trafficguard.sh" | bash; then
        check_success "TrafficGuard установлен"
    else
        error "Не удалось установить TrafficGuard"
        return 1
    fi
}
