#!/bin/bash

# Функция настройки файрвола
setup_firewall() {
    log "=========================================="
    log "Настройка UFW и Fail2Ban"
    log "=========================================="

    echo ""
    read -p "Введите SSH порт для файрвола (по умолчанию 33556): " ssh_port
    ssh_port=${ssh_port:-33556}

    # Настройка UFW
    log "Настройка файрвола UFW..."
    sudo ufw --force reset
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw allow ${ssh_port}/tcp comment 'SSH'
    sudo ufw allow 80/tcp comment 'HTTP'
    sudo ufw allow 443/tcp comment 'HTTPS'
    sudo ufw --force enable && check_success "UFW настроен"

    # Установка Fail2Ban
    log "Установка и настройка Fail2Ban..."
    if ! command -v fail2ban-client &> /dev/null; then
        retry_command "sudo apt install -y fail2ban" && check_success "Fail2Ban установлен"
    else
        info "Fail2Ban уже установлен"
    fi

    # Создание конфигурации Fail2Ban
    sudo tee /etc/fail2ban/jail.local > /dev/null << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true
port = ${ssh_port}
logpath = %(sshd_log)s
backend = %(sshd_backend)s
maxretry = 3
bantime = 3600
EOF

    sudo systemctl restart fail2ban
    sudo systemctl enable fail2ban && check_success "Fail2Ban настроен"

    log "Файрвол и Fail2Ban настроены"
}
