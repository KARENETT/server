setup_firewall() {
    log "=========================================="
    log "Настройка UFW + Fail2Ban"
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
    # Отключаем входящий/исходящий ping (ICMP echo)
    # Самый надёжный способ — через ufw user rules (не трогаем before.rules)
    # ────────────────────────────────────────────────
    log "Отключаем двухсторонний ICMP (echo-request / echo-reply)..."

    # Блокируем входящий ping (кто-то пингует сервер)
    sudo ufw insert 1 deny proto icmp from any to any icmp-type echo-request comment 'Block incoming ping'

    # Блокируем исходящий ping (сервер не может пинговать наружу)
    sudo ufw insert 2 deny proto icmp from any to any icmp-type echo-reply   comment 'Block outgoing ping reply'

    # Опционально: блокируем broadcast/multicast ICMP (защита от атак)
    sudo ufw insert 3 deny proto icmp from any to any icmp-type destination-unreachable comment 'Block some icmp types'

    sudo ufw reload && check_success "ICMP echo (ping) полностью отключён через UFW"

    # Альтернатива/дополнение: sysctl (ядерный уровень, работает даже без UFW)
    echo "net.ipv4.icmp_echo_ignore_all = 1"         | sudo tee -a /etc/sysctl.d/99-no-ping.conf
    echo "net.ipv4.icmp_echo_ignore_broadcasts = 1" | sudo tee -a /etc/sysctl.d/99-no-ping.conf
    sudo sysctl -p /etc/sysctl.d/99-no-ping.conf     2>/dev/null || true
    log "Дополнительно: sysctl icmp_echo_ignore_all = 1 применён"

    # Fail2Ban (без изменений, только мелкая правка)
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
EOF

    sudo systemctl restart fail2ban
    sudo systemctl enable fail2ban  && check_success "Fail2Ban настроен и добавлен в автозагрузку"

    log "✅ Файрвол, ICMP-защита и Fail2Ban готовы"
    log "Проверьте: sudo ufw status verbose"
}
