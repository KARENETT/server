#!/bin/bash

add_users_to_docker_group() {
    local username _ passwd uid gid gecos home shell

    if ! getent group docker >/dev/null; then
        return 0
    fi

    while IFS=: read -r username passwd uid gid gecos home shell; do
        [[ "$uid" -ge 1000 ]] || continue
        [[ "$shell" == *nologin || "$shell" == *false ]] && continue

        if id -nG "$username" | tr ' ' '\n' | grep -qx docker; then
            continue
        fi

        usermod -aG docker "$username" && check_success "Пользователь $username добавлен в группу docker"
    done < <(getent passwd)
}

# Функция установки Docker
setup_docker() {
    log "=========================================="
    log "$(t docker_title)"
    log "=========================================="

    check_internet || return 1

    log "$(t docker_installing)"
    if ! command -v docker &> /dev/null; then
        apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
        retry_command "apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release"

        mkdir -p /etc/apt/keyrings
        retry_command "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg"

        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

        apt-get update
        retry_command "apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin" && check_success "Docker установлен"

        usermod -aG docker "${SUDO_USER:-$USER}" && check_success "Пользователь добавлен в группу docker"
        systemctl start docker
        systemctl enable docker && check_success "Docker запущен и добавлен в автозагрузку"

        info "$(t docker_newgrp)"
    else
        info "Docker уже установлен ($(docker --version))"
    fi

    add_users_to_docker_group

    log "$(t docker_done)"
}
