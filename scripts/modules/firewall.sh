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
    read -p "Hysteria 2 порт (UDP, например 1935): " hysteria_port
    hysteria_port=${hysteria_port:-1935}

    log "Сброс и базовая настройка UFW..."
    sudo ufw --force reset
    sudo ufw default deny incoming
    sudo ufw default allow outgoing

    # Разрешаем нужные порты
    sudo ufw allow "${ssh_port}/tcp" comment 'SSH'
    sudo ufw allow 80/tcp comment 'HTTP (ACME/fallback)'
    sudo ufw allow 443/tcp comment 'HTTPS / VLESS fallback'
    sudo ufw allow "${vless_port}/tcp" comment 'VLESS'
    sudo ufw allow "${ss_port}/tcp" comment 'Shadowsocks TCP'
    sudo ufw allow "${ss_port}/udp" comment 'Shadowsocks UDP'
    sudo ufw allow "${trojan_port}/tcp" comment 'TROJAN'
    sudo ufw allow "${hysteria_port}/udp" comment 'Hysteria 2 QUIC'

    sudo ufw --force enable && check_success "UFW включён и базовые порты открыты"

    # ────────────────────────────────────────────────
    # Отключаем входящий ping (ICMP echo-request) на уровне ядра
    # ────────────────────────────────────────────────
    log "Отключаем входящий ICMP echo-request (ping к серверу)..."

    local sysctl_file="/etc/sysctl.d/99-disable-ping.conf"
    sudo tee "$sysctl_file" > /dev/null << 'EOF'
# Ignore all incoming ICMP echo requests (ping to this server)
net.ipv4.icmp_echo_ignore_all = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Для IPv6, если используется
net.ipv6.icmp.echo_ignore_all = 1
EOF

    sudo sysctl --system 2>/dev/null || sudo sysctl -p "$sysctl_file"

    # Проверка применения (критично!)
    sleep 1  # даём время на применение
    if [ "$(cat /proc/sys/net/ipv4/icmp_echo_ignore_all)" = "1" ]; then
        check_success "Входящий ping заблокирован на уровне ядра (сервер не отвечает)"
    else
        warning "sysctl net.ipv4.icmp_echo_ignore_all НЕ применился!"
        log "Проверьте вручную:"
        log "  cat /proc/sys/net/ipv4/icmp_echo_ignore_all"
        log "  grep icmp /etc/ufw/sysctl.conf   # если там =0 — удалите или закомментируйте"
    fi

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

[nginx-http-auth]
enabled = true
EOF

    sudo systemctl restart fail2ban
    sudo systemctl enable fail2ban && check_success "Fail2Ban настроен и добавлен в автозагрузку"

    log "✅ Файрвол, защита от пинга и Fail2Ban готовы"
    log "Проверьте после перезагрузки:"
    log "  cat /proc/sys/net/ipv4/icmp_echo_ignore_all          # → 1"
    log "  ping 8.8.8.8                                         # с сервера — работает"
    log "  ping ${YOUR_SERVER_IP}                               # с другого хоста — НЕ должен отвечать"
}
