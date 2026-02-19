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

    read -p "TROJAN порт (TCP, например 8443): " trojan_port
    trojan_port=${trojan_port:-8443}

    read -p "Hysteria 2 порт (UDP, например 8444): " hysteria_port
    hysteria_port=${hysteria_port:-8444}

    log "Сброс и базовая настройка UFW..."
    sudo ufw --force reset
    sudo ufw default deny incoming
    sudo ufw default allow outgoing

    # Разрешаем нужные порты
    sudo ufw allow "${ssh_port}/tcp" comment 'SSH'
    sudo ufw allow 80/tcp   comment 'HTTP (ACME/fallback)'
    sudo ufw allow 443/tcp  comment 'HTTPS / VLESS fallback'
    sudo ufw allow "${vless_port}/tcp" comment 'VLESS'
    sudo ufw allow "${ss_port}/tcp"    comment 'Shadowsocks TCP'
    sudo ufw allow "${ss_port}/udp"    comment 'Shadowsocks UDP'
    sudo ufw allow "${trojan_port}/tcp" comment 'TROJAN'
    sudo ufw allow "${hysteria_port}/udp" comment 'Hysteria 2'

    sudo ufw --force enable && check_success "UFW включён и базовые порты открыты"

    # ────────────────────────────────────────────────
    # Отключаем входящий и исходящий ping (ICMP echo)
    # ────────────────────────────────────────────────
    log "Отключаем двухсторонний ICMP (ping)..."

    # Способ 1 — самый надёжный: sysctl (ядерный уровень)
    local sysctl_file="/etc/sysctl.d/99-disable-ping.conf"
    sudo tee "$sysctl_file" > /dev/null << 'EOF'
net.ipv4.icmp_echo_ignore_all = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv6.icmp.echo_ignore_all = 1
EOF

    sudo sysctl --system 2>/dev/null || sudo sysctl -p "$sysctl_file"
    check_success "ICMP echo-request заблокирован на уровне ядра (сервер не отвечает на пинг)"

    # Способ 2 — дополнительно через UFW before.rules (если sysctl по какой-то причине не подходит)
    # Добавляем правила в конец секции *filter перед COMMIT — безопасно
    local RULES_FILE="/etc/ufw/before.rules"
    sudo cp "$RULES_FILE" "${RULES_FILE}.bak.$(date +%F_%H%M%S)"

    sudo sed -i '/^\*filter/a \
# Block incoming ICMP echo-request (ping to server)\
-A ufw-before-input -p icmp --icmp-type 8 -j DROP\
# Block outgoing ICMP echo-reply (if server tries to respond)\
-A ufw-before-output -p icmp --icmp-type 0 -j DROP' "$RULES_FILE"

    # Проверяем, что синтаксис валиден
    if sudo iptables-restore -t filter -n < "$RULES_FILE" 2>/dev/null; then
        sudo ufw reload && check_success "Дополнительно заблокирован ICMP echo в before.rules"
    else
        log "Ошибка в синтаксисе before.rules — откатываем изменения"
        sudo cp "${RULES_FILE}.bak.$(date +%F_%H%M%S)" "$RULES_FILE" 2>/dev/null
        sudo ufw reload
        warning "ICMP заблокирован только через sysctl"
    fi

    # Fail2Ban
    log "Настройка Fail2Ban..."
    if ! command -v fail2ban-client &> /dev/null; then
        retry_command "sudo apt install -y fail2ban" && check_success "Fail2Ban установлен"
    fi

    sudo tee /etc/fail2ban/jail.local > /dev/null << EOF
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled  = true
port     = ${ssh_port}
maxretry = 3

[nginx-http-auth]
enabled  = true
EOF

    sudo systemctl restart fail2ban
    sudo systemctl enable fail2ban && check_success "Fail2Ban настроен и добавлен в автозагрузку"

    log "✅ Файрвол, защита от пинга и Fail2Ban готовы"
    log "Проверьте:"
    log "  sudo ufw status verbose"
    log "  cat /proc/sys/net/ipv4/icmp_echo_ignore_all   # должно быть 1"
    log "  ping 8.8.8.8   # с сервера — должно работать (исходящий)"
    log "  ping ваш_IP_сервера   # с другого хоста — не должен отвечать"
}
