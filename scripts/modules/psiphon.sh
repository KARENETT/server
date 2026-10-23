#!/bin/bash

setup_psiphon() {
    local installer status

    if ! command -v curl >/dev/null 2>&1; then
        error "$(t curl_not_found)"
        return 1
    fi

    if ! installer="$(mktemp)"; then
        error "$(t psiphon_temp_failed)"
        return 1
    fi

    log "$(t psiphon_installing)"
    if ! curl -fsSL 'https://raw.githubusercontent.com/Chara-Freedom/vps-psiphon/main/psiphon_install.sh' -o "$installer"; then
        rm -f -- "$installer"
        error "$(t psiphon_download_failed)"
        return 1
    fi

    if bash "$installer" --region DE; then
        rm -f -- "$installer"
        log "$(t psiphon_done)"
    else
        status=$?
        rm -f -- "$installer"
        error "$(t psiphon_failed)"
        return "$status"
    fi
}
