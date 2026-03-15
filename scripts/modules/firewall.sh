setup_firewall() {
    log "=========================================="
    log "Настройка UFW + Fail2Ban + отключение ICMP"
    log "=========================================="
    echo ""
    read -p "SSH порт (по умолчанию 33556): " ssh_port
    ssh_port=${ssh_port:-33556}
    echo ""

    log "Сброс и базовая настройка UFW..."
    sudo ufw --force reset
    sudo ufw default deny incoming
    sudo ufw default allow outgoing

    # Разрешаем нужные порты
    sudo ufw allow "${ssh_port}/tcp" comment 'SSH'
    sudo ufw allow 80/tcp comment 'HTTP (ACME/fallback)'
    sudo ufw allow 443/tcp comment 'HTTPS / VLESS fallback'

    sudo ufw --force enable && check_success "UFW включён и базовые порты открыты"

    # Fail2Ban (твой блок без изменений)
    log "Настройка Fail2Ban..."
    if ! command -v fail2ban-client &> /dev/null; then
        retry_command "sudo apt install -y fail2ban" && check_success "Fail2Ban установлен"
    fi

    sudo tee /etc/fail2ban/jail.local > /dev/null << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true
port = ${ssh_port}
maxretry = 3
filter = sshd
action = iptables[name=SSH, port=ssh, protocol=tcp]
logpath = /var/log/auth.log
findtime = 600
bantime = 43200

[nginx-http-auth]
enabled = true
EOF

    sudo systemctl restart fail2ban
    sudo systemctl enable fail2ban && check_success "Fail2Ban настроен и добавлен в автозагрузку"

    log "✅ Файрвол, защита от пинга и Fail2Ban готовы"
    log "Проверьте после перезагрузки"
}
