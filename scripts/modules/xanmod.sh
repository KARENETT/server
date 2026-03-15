#!/bin/bash

detect_xanmod_package() {
    local cpu_flags

    if [[ "$(dpkg --print-architecture)" != "amd64" ]]; then
        error "XanMod поддерживается этим скриптом только на amd64"
        return 1
    fi

    cpu_flags="$(grep -m1 '^flags' /proc/cpuinfo || true)"
    if [[ -z "$cpu_flags" ]]; then
        error "Не удалось определить CPU flags"
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
    log "Установка XanMod Kernel"
    log "=========================================="

    check_internet || return 1

    if ! command -v apt-get &> /dev/null; then
        error "Установка XanMod через этот модуль поддерживается только для apt-based систем"
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
        error "Не удалось определить codename дистрибутива"
        return 1
    fi

    if dpkg -l | grep -q "^ii  ${xanmod_package} "; then
        info "Пакет $xanmod_package уже установлен"
        warning "Для активации ядра может потребоваться выбрать его в GRUB и перезагрузить систему"
        return 0
    fi

    info "Будет установлен пакет: $xanmod_package"
    info "Codename системы: $distro_codename"
    warning "После установки ядра потребуется перезагрузка"
    echo ""
    read -p "Продолжить установку XanMod? (Y/n): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        warning "Установка XanMod отменена"
        return 0
    fi

    sudo mkdir -p /etc/apt/keyrings
    retry_command "wget -qO - https://dl.xanmod.org/archive.key | sudo gpg --dearmor -o /etc/apt/keyrings/xanmod-archive-keyring.gpg" && check_success "Ключ XanMod добавлен" || return 1
    echo "deb [signed-by=/etc/apt/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org $distro_codename main" | sudo tee /etc/apt/sources.list.d/xanmod-release.list > /dev/null
    check_success "Репозиторий XanMod добавлен" || return 1

    retry_command "sudo apt update" && check_success "Список пакетов обновлён" || return 1
    retry_command "sudo DEBIAN_FRONTEND=noninteractive apt install -y $xanmod_package" && check_success "XanMod kernel установлен" || return 1

    info "Проверьте новый пункт в GRUB после перезагрузки"
    log "Установка XanMod завершена"
}
