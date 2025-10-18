#!/bin/bash

# Функция настройки SSH
setup_ssh() {
    log "=========================================="
    log "Настройка SSH"
    log "=========================================="

    # Создание директории для SSH, если её нет
    sudo mkdir -p /run/sshd

    echo ""
    read -p "Введите порт для SSH (по умолчанию 33556): " ssh_port
    ssh_port=${ssh_port:-33556}

    if ! [[ "$ssh_port" =~ ^[0-9]+$ ]] || [ "$ssh_port" -lt 1 ] || [ "$ssh_port" -gt 65535 ]; then
        error "Неверный номер порта. Используется порт по умолчанию 33556"
        ssh_port=33556
    fi

    info "SSH будет настроен на порт: $ssh_port"

    if [ -f /etc/ssh/sshd_config ]; then
        sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)

        # Безопасное изменение конфигурации SSH
        sudo sed -i "s/^#*Port .*/Port $ssh_port/" /etc/ssh/sshd_config
        sudo sed -i 's/^#*PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
        sudo sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config

        # Проверка конфигурации перед перезапуском
        if sudo sshd -t; then
            sudo systemctl enable ssh
            sudo systemctl restart ssh && check_success "SSH настроен и перезапущен на порту $ssh_port"

            warning "ВАЖНО: SSH теперь работает на порту $ssh_port"
            warning "Протестируйте подключение в новом терминале: ssh -p $ssh_port $(whoami)@<server_ip>"
        else
            error "Ошибка в конфигурации SSH, откат изменений"
            sudo cp /etc/ssh/sshd_config.backup.* /etc/ssh/sshd_config
            return 1
        fi
    else
        warning "Файл конфигурации SSH не найден"
        return 1
    fi
}
