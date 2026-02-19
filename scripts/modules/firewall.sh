#!/bin/bash

setup_firewall() {
    log "=========================================="
    log "Настройка UFW + Fail2Ban + отключение ICMP"
    log "=========================================="

    echo ""
    read -p "SSH порт (по умолчанию 33556): " ssh_port
    ssh_port=${ssh_port:-33556}

    echo ""
    read -p "VLESS/Reality порт (TCP, обычно 9443): " vless_port
    vless_port=${vless_port:-9443}

    read -p "Shadowsocks порт (TCP+UDP, например 52465): " ss_port
    ss_port=${ss_port:-52465}

    read -p "TROJAN порт (TCP, например 8443): " hysteria_port
    trojan_port=${trojan_port:-8443}

    read -p "Hysteria 2 порт (UDP, например 8444): " hysteria_port
    hysteria_port=${hysteria_port:-8444}

    log "Сброс и базовая настройка UFW..."
    sudo ufw --force reset
    sudo ufw default deny incoming
    sudo ufw default allow outgoing

    # Разрешаем нужные порты
    sudo ufw allow "${ssh_port}/tcp" comment 'SSH'
    sudo ufw allow 80/tcp comment 'HTTP (ACME/fallback)'
    sudo ufw allow 443/tcp comment 'HTTPS (часто VLESS)'
    sudo ufw allow "${vless_port}/tcp" comment 'VLESS'
    sudo ufw allow "${ss_port}/tcp" comment 'Shadowsocks TCP'
    sudo ufw allow "${ss_port}/udp" comment 'Shadowsocks UDP'
    sudo ufw allow "${trojan_port}/tcp" comment 'TROJAN'
    sudo ufw allow "${hysteria_port}/udp" comment 'Hysteria 2'

    sudo ufw --force enable && check_success "UFW включён"

    # === ПОЛНОЕ ОТКЛЮЧЕНИЕ ДВУХСТОРОННЕГО ПИНГА ===
    local RULES_FILE="/etc/ufw/before.rules"
    sudo cp "$RULES_FILE" "${RULES_FILE}.bak.$(date +%F_%T)"

    sudo sed -i \
        -e 's|-A ufw-before-input -p icmp .* -j ACCEPT|-A ufw-before-input -p icmp -j DROP|g' \
        -e 's|-A ufw-before-output -p icmp .* -j ACCEPT|-A ufw-before-output -p icmp -j DROP|g' \
        "$RULES_FILE"

    # Дополнительно блокируем echo-request в output (сервер не сможет пинговать наружу)
    sudo sed -i '/ufw-before-output/a -A ufw-before-output -p icmp --icmp-type echo-request -j DROP' "$RULES_FILE"

    sudo ufw reload && check_success "Двухсторонний ICMP полностью отключён"

    # Fail2Ban (усиленный под SSH + возможный брутфорс портов)
    log "Настройка Fail2Ban..."
    if ! command -v fail2ban-client &> /dev/null; then
        retry_command "sudo apt install -y fail2ban"
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

[nginx-http-auth]   # если используешь веб-панель
enabled = true
EOF

    sudo systemctl restart fail2ban && check_success "Fail2Ban настроен"
    log "✅ Файрвол и защита готовы под VLESS + SS + TROJAN + Hysteria 2"
}
