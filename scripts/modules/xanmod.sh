#!/bin/bash

detect_xanmod_package() {
    local cpu_flags

    if [[ "$(dpkg --print-architecture)" != "amd64" ]]; then
        error "$(t xanmod_amd64_only)"
        return 1
    fi

    cpu_flags="$(grep -m1 '^flags' /proc/cpuinfo || true)"
    if [[ -z "$cpu_flags" ]]; then
        error "$(t xanmod_cpu_flags_error)"
        return 1
    fi

    if [[ "$cpu_flags" == *" avx2 "* && "$cpu_flags" == *" bmi1 "* && "$cpu_flags" == *" bmi2 "* && "$cpu_flags" == *" fma "* && "$cpu_flags" == *" movbe "* ]]; then
        echo "linux-xanmod-x64v3"
    else
        echo "linux-xanmod-x64v2"
    fi
}

setup_xanmod() {
    local xanmod_package
    local distro_codename
    local key_url="https://dl.xanmod.org/archive.key"
    local key_tmp
    local keyring_path="/etc/apt/keyrings/xanmod-archive-keyring.gpg"

    xanmod_skip() {
        warning "$1"
        return 0
    }

    log "=========================================="
    log "$(t xanmod_title)"
    log "=========================================="

    check_internet || return 1

    if ! command -v apt-get &> /dev/null; then
        error "$(t xanmod_apt_only)"
        return 1
    fi

    if [[ "$(uname -r)" == *"xanmod"* ]]; then
        info "XanMod уже используется ($(uname -r))"
        return 0
    fi

    xanmod_package="$(detect_xanmod_package)" || return 1
    if command -v lsb_release &> /dev/null; then
        distro_codename="$(lsb_release -sc)"
    elif [[ -r /etc/os-release ]]; then
        distro_codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"
    fi

    if [[ -z "${distro_codename:-}" ]]; then
        error "$(t xanmod_codename_error)"
        return 1
    fi

    if dpkg -l | grep -q "^ii  ${xanmod_package} "; then
        info "Пакет $xanmod_package уже установлен"
        warning "$(t xanmod_grub_hint)"
        return 0
    fi

    info "Будет установлен пакет: $xanmod_package"
    info "Codename системы: $distro_codename"
    warning "$(t xanmod_reboot_required)"
    echo ""
    read -rp "${PROMPT_PREFIX} $(t xanmod_confirm) " -n 1
    echo ""
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        warning "$(t xanmod_cancelled)"
        return 0
    fi

    mkdir -p /etc/apt/keyrings
    key_tmp="$(mktemp /tmp/xanmod-key.XXXXXX)"
    if command -v wget >/dev/null 2>&1; then
        if ! wget -qO "$key_tmp" "$key_url"; then
            rm -f "$key_tmp"
            xanmod_skip "Не удалось загрузить ключ XanMod, пропускаем установку XanMod"
            return 0
        fi
    else
        if ! curl -fsSLA "Mozilla/5.0" "$key_url" -o "$key_tmp"; then
            rm -f "$key_tmp"
            xanmod_skip "Не удалось загрузить ключ XanMod, пропускаем установку XanMod"
            return 0
        fi
    fi

    if [[ -s "$key_tmp" ]] && gpg --batch --yes --dearmor -o "$keyring_path" "$key_tmp"; then
        chmod 0644 "$keyring_path"
        check_success "Ключ XanMod добавлен"
    else
        rm -f "$key_tmp" "$keyring_path"
        xanmod_skip "Не удалось загрузить или обработать ключ XanMod, пропускаем установку XanMod"
        return 0
    fi
    rm -f "$key_tmp"
    echo "deb [signed-by=$keyring_path] http://deb.xanmod.org $distro_codename main" > /etc/apt/sources.list.d/xanmod-release.list
    if ! check_success "Репозиторий XanMod добавлен"; then
        xanmod_skip "Не удалось добавить репозиторий XanMod, пропускаем установку XanMod"
        return 0
    fi

    if ! retry_command "apt update"; then
        xanmod_skip "Не удалось обновить список пакетов, пропускаем установку XanMod"
        return 0
    fi

    if ! retry_command "DEBIAN_FRONTEND=noninteractive apt install -y $xanmod_package"; then
        xanmod_skip "Не удалось установить XanMod, пропускаем без ошибки"
        return 0
    fi

    check_success "XanMod kernel установлен"

    info "$(t xanmod_grub_check)"
    log "$(t xanmod_done)"
}
