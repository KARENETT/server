#!/bin/bash

setup_ssh() {
    log "=========================================="
    log "Настройка SSH (root + пароли запрещены)"
    log "=========================================="

    sudo mkdir -p /run/sshd

    echo ""
    read -p "Введите порт SSH (по умолчанию 33556): " ssh_port
    ssh_port=${ssh_port:-33556}

    if ! [[ "$ssh_port" =~ ^[0-9]+$ ]] || [ "$ssh_port" -lt 1024 ] || [ "$ssh_port" -gt 65535 ]; then
        error "Неверный порт. Используется 33556"
        ssh_port=33556
    fi

    if [ -f /etc/ssh/sshd_config ]; then
        sudo cp /etc/ssh/sshd_config "/etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)"

        sudo sed -i "s/^#*Port .*/Port $ssh_port/" /etc/ssh/sshd_config
        sudo sed -i 's/^#*PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
        sudo sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
        sudo sed -i 's/^#*PubkeyAuthentication .*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
        sudo sed -i 's/^#*PermitEmptyPasswords .*/PermitEmptyPasswords no/' /etc/ssh/sshd_config
        sudo sed -i 's/^#*ChallengeResponseAuthentication .*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
        sudo sed -i 's/^#*PermitUserEnvironment .*/PermitUserEnvironment no/' /etc/ssh/sshd_config
        sudo sed -i 's/^#*MaxAuthTries .*/MaxAuthTries 3/' /etc/ssh/sshd_config
        sudo sed -i 's/^#*LoginGraceTime .*/LoginGraceTime 20/' /etc/ssh/sshd_config

        if sudo sshd -t; then
            sudo systemctl enable ssh
            sudo systemctl restart ssh && check_success "SSH перезапущен на порту $ssh_port (только ключи!)"

            warning "ВАЖНО: Теперь только ключевой доступ!"
            warning "ssh -p $ssh_port user@IP"
        else
            error "Ошибка конфигурации SSH — откат"
            sudo cp /etc/ssh/sshd_config.backup.* /etc/ssh/sshd_config 2>/dev/null || true
            return 1
        fi
    else
        error "sshd_config не найден"
        return 1
    fi
}
