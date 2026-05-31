setup_firewall() {
    log "=========================================="
    log "Настройка UFW + Fail2Ban + отключение ICMP"
    log "=========================================="
    echo ""
    read -rp "${PROMPT_PREFIX} $(t ssh_port_prompt) " ssh_port
    ssh_port=${ssh_port:-33556}
    echo ""

    log "Сброс и базовая настройка UFW..."
    if ! command -v ufw >/dev/null 2>&1; then
        error "$(t ufw_not_found)"
        return 1
    fi

    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing

    # Разрешаем нужные порты
    ufw allow "${ssh_port}/tcp" comment 'SSH'
    ufw allow 80/tcp comment 'HTTP (ACME/fallback)'
    ufw allow 443/tcp comment 'HTTPS / VLESS fallback'

    ufw --force enable && check_success "UFW включён и базовые порты открыты"

    # Fail2Ban
    log "Настройка Fail2Ban..."
    if ! command -v fail2ban-client &> /dev/null; then
        retry_command "apt install -y fail2ban" && check_success "Fail2Ban установлен"
    fi

    tee /etc/fail2ban/jail.local > /dev/null << EOF
[DEFAULT]
banaction = ufw
banaction_allports = ufw
backend = systemd
usedns = warn
allowipv6 = auto

# Progressive ban policy
bantime = 1h
bantime.increment = true
bantime.factor = 2
bantime.formula = bantime * (1<<(ban.Count if ban.Count<10 else 10))
bantime.maxtime = 1w
bantime.rndtime = 10m

# Detection window
findtime = 10m
maxretry = 5

# Whitelist trusted ranges here if needed
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true
port = ${ssh_port}
mode = aggressive
maxretry = 4
filter = sshd
backend = systemd
journalmatch = _SYSTEMD_UNIT=ssh.service + _COMM=sshd
action = %(action_mwl)s
logpath = /var/log/auth.log
findtime = 10m
bantime = 12h

[sshd-ddos]
enabled = true
port = ${ssh_port}
filter = sshd-ddos
backend = systemd
journalmatch = _SYSTEMD_UNIT=ssh.service + _COMM=sshd
action = %(action_)s
findtime = 5m
maxretry = 6
bantime = 24h

[nginx-http-auth]
enabled = false

[recidive]
enabled = true
logpath = /var/log/fail2ban.log
backend = auto
banaction = ufw
findtime = 1d
bantime = 1w
maxretry = 5
EOF

    tee /etc/fail2ban/fail2ban.local > /dev/null << 'EOF'
[Definition]
logtarget = /var/log/fail2ban.log
loglevel = INFO
syslogsocket = auto
EOF

    systemctl restart fail2ban
    systemctl enable fail2ban && check_success "Fail2Ban настроен и добавлен в автозагрузку"

    if ! fail2ban-client ping >/dev/null 2>&1; then
        error "Fail2Ban не запустился корректно"
        return 1
    fi

    fail2ban-client status sshd >/dev/null 2>&1 || {
        error "Jail sshd не активирован"
        return 1
    }

    log "✅ Файрвол, защита от пинга и Fail2Ban готовы"
    log "Проверьте после перезагрузки"
}

disable_firewall() {
    log "=========================================="
    log "Отключение UFW и Fail2Ban"
    log "=========================================="

    systemctl disable --now fail2ban >/dev/null 2>&1 || true
    if command -v ufw >/dev/null 2>&1; then
        ufw --force disable >/dev/null 2>&1 || true
    fi
    check_success "UFW и Fail2Ban отключены"
}
