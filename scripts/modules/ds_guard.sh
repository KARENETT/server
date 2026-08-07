#!/bin/bash

DS_GUARD_URL="https://doubleservers.com/6eaygszz4o2yjlwfqs7lu5iw/k3coxnqhumw4fhcyzoh334hj"
DS_GUARD_MARKER="/var/lib/karenet-setup/ds-guard.installed"

is_ds_guard_installed() {
    [[ -f "$DS_GUARD_MARKER" ]] || \
        systemctl is-enabled --quiet ds-guard 2>/dev/null || \
        systemctl is-active --quiet ds-guard 2>/dev/null || \
        command -v ds-guard >/dev/null 2>&1
}

setup_ds_guard() {
    local tmp_dir ds_guard_bin

    if ! command -v curl >/dev/null 2>&1; then
        error "$(t curl_not_found)"
        return 1
    fi

    if ! confirm_yes_no "$(t remote_install_confirm) ds-guard? (y/N):"; then
        warning "$(t remote_install_cancelled)"
        return 0
    fi

    tmp_dir="$(mktemp -d /tmp/ds-guard.XXXXXX)" || return 1
    ds_guard_bin="$tmp_dir/ds-guard"

    info "URL: $DS_GUARD_URL"
    log "$(t ds_guard_installing)"

    if curl -fsSL "$DS_GUARD_URL" -o "$ds_guard_bin" && chmod +x "$ds_guard_bin" && "$ds_guard_bin"; then
        mkdir -p "$(dirname "$DS_GUARD_MARKER")"
        touch "$DS_GUARD_MARKER"
        rm -rf "$tmp_dir"
        check_success "$(t ds_guard_done)"
    else
        rm -rf "$tmp_dir"
        error "$(t ds_guard_failed)"
        return 1
    fi
}
