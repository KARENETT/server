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
    retry_command "wget -qO - https://dl.xanmod.org/archive.key | gpg --dearmor -o /etc/apt/keyrings/xanmod-archive-keyring.gpg" && check_success "Ключ XanMod добавлен" || return 1
    echo "deb [signed-by=/etc/apt/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org $distro_codename main" > /etc/apt/sources.list.d/xanmod-release.list
    check_success "Репозиторий XanMod добавлен" || return 1

    retry_command "apt update" && check_success "Список пакетов обновлён" || return 1
    retry_command "DEBIAN_FRONTEND=noninteractive apt install -y $xanmod_package" && check_success "XanMod kernel установлен" || return 1

    info "$(t xanmod_grub_check)"
    log "$(t xanmod_done)"
}
