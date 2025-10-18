#!/bin/bash

# Функция установки Docker
setup_docker() {
    log "=========================================="
    log "Установка Docker"
    log "=========================================="

    check_internet || return 1

    log "Установка Docker..."
    if ! command -v docker &> /dev/null; then
        sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
        retry_command "sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release"

        sudo mkdir -p /etc/apt/keyrings
        retry_command "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg"

        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

        sudo apt-get update
        retry_command "sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin" && check_success "Docker установлен"

        sudo usermod -aG docker $USER && check_success "Пользователь добавлен в группу docker"
        sudo systemctl start docker
        sudo systemctl enable docker && check_success "Docker запущен и добавлен в автозагрузку"

        info "Для применения прав docker выполните: newgrp docker"
    else
        info "Docker уже установлен ($(docker --version))"
    fi

    log "Docker успешно установлен"
}
