configure_ufw_icmp_rules() {
    local rules_file="${1:-/etc/ufw/before.rules}"
    local temp_file

    if [[ ! -f "$rules_file" ]]; then
        error "$(t firewall_icmp_rules_file_missing)"
        return 1
    fi
    temp_file="$(mktemp "${rules_file}.XXXXXX")" || {
        error "$(t firewall_icmp_rules_update_failed)"
        return 1
    }

    if ! awk '
        $0 == "# ok icmp codes for INPUT" {
            input_count++
            if (input_count > 1) {
                invalid = 1
                exit
            }
            section = "input"
            print
            print "-A ufw-before-input -p icmp --icmp-type destination-unreachable -j DROP"
            print "-A ufw-before-input -p icmp --icmp-type time-exceeded -j DROP"
            print "-A ufw-before-input -p icmp --icmp-type parameter-problem -j DROP"
            print "-A ufw-before-input -p icmp --icmp-type echo-request -j DROP"
            print "-A ufw-before-input -p icmp --icmp-type source-quench -j DROP"
            next
        }
        $0 == "# ok icmp codes for FORWARD" || $0 == "# ok icmp code for FORWARD" {
            forward_count++
            if (forward_count > 1) {
                invalid = 1
                exit
            }
            section = "forward"
            print
            print "-A ufw-before-forward -p icmp --icmp-type destination-unreachable -j DROP"
            print "-A ufw-before-forward -p icmp --icmp-type time-exceeded -j DROP"
            print "-A ufw-before-forward -p icmp --icmp-type parameter-problem -j DROP"
            print "-A ufw-before-forward -p icmp --icmp-type echo-request -j DROP"
            next
        }
        section == "input" {
            if (/^-A ufw-before-input -p icmp --icmp-type /) {
                next
            }
            section = ""
        }
        section == "forward" {
            if (/^-A ufw-before-forward -p icmp --icmp-type /) {
                next
            }
            section = ""
        }
        { print }
        END {
            if (invalid || input_count != 1 || forward_count != 1) {
                exit 1
            }
        }
    ' "$rules_file" > "$temp_file"; then
        rm -f -- "$temp_file"
        error "$(t firewall_icmp_rules_update_failed)"
        return 1
    fi

    if ! chmod --reference="$rules_file" "$temp_file" ||
        ! chown --reference="$rules_file" "$temp_file" ||
        ! mv -f -- "$temp_file" "$rules_file"; then
        rm -f -- "$temp_file"
        error "$(t firewall_icmp_rules_update_failed)"
        return 1
    fi

    info "$(t firewall_icmp_rules_updated)"
}

setup_firewall() {
    local configured_ssh_port="${1:-}"
    local panel_prompt_mode="${2:-interactive}"
    local ssh_port=""
    local ssh_port_input=""
    local saved_panel_ip=""
    local saved_panel_port=""
    local panel_ip=""
    local panel_port=""
    local panel_port_input=""
    local panel_port_default=""
    local panel_rule_updated=0

    log "=========================================="
    log "Настройка UFW + Fail2Ban + блокировка ICMPv4"
    log "=========================================="
    echo ""
    if ! command -v ufw >/dev/null 2>&1; then
        error "$(t ufw_not_found)"
        return 1
    fi

    if [[ -n "$configured_ssh_port" ]]; then
        if ! is_valid_tcp_port "$configured_ssh_port"; then
            error "$(t ssh_port_invalid)"
            return 1
        fi
        ssh_port=$((10#$configured_ssh_port))
    else
        while true; do
            read -rp "${PROMPT_PREFIX} $(t ssh_port_prompt) " ssh_port_input || return 1
            ssh_port_input="${ssh_port_input:-33556}"
            if is_valid_tcp_port "$ssh_port_input"; then
                ssh_port=$((10#$ssh_port_input))
                break
            fi
            warning "$(t ssh_port_invalid)"
        done
    fi

    read_remnanode_panel_rule saved_panel_ip saved_panel_port
    if [[ -n "$saved_panel_ip" ]]; then
        if is_valid_ip_address "$saved_panel_ip" && is_valid_tcp_port "$saved_panel_port"; then
            panel_ip="$saved_panel_ip"
            saved_panel_port=$((10#$saved_panel_port))
            panel_port="$saved_panel_port"
        else
            warning "$(t remnanode_firewall_saved_invalid)"
            saved_panel_ip=""
            saved_panel_port=""
        fi
    fi

    if [[ -z "$panel_ip" && "$panel_prompt_mode" != "skip-panel-prompt" ]] &&
        confirm_yes_no "$(t remnanode_firewall_configure_prompt)"; then
        if ! command -v python3 >/dev/null 2>&1; then
            error "$(t remnanode_validation_tools_required)"
            return 1
        fi
        while true; do
            read -rp "${PROMPT_PREFIX} $(t remnanode_panel_ip_prompt) " panel_ip || return 1
            if is_valid_ip_address "$panel_ip"; then
                break
            fi
            warning "$(t remnanode_panel_ip_invalid)"
        done
        panel_port_default="${saved_panel_port:-$REMNANODE_NODE_PORT}"
        while true; do
            read -rp "${PROMPT_PREFIX} $(t remnanode_node_port_prompt) [$panel_port_default]: " panel_port_input || return 1
            panel_port_input="${panel_port_input:-$panel_port_default}"
            if is_valid_tcp_port "$panel_port_input"; then
                panel_port=$((10#$panel_port_input))
                break
            fi
            warning "$(t remnanode_node_port_invalid)"
        done
        panel_rule_updated=1
    fi

    log "Сброс и базовая настройка UFW..."
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing

    ufw limit "${ssh_port}/tcp" comment 'SSH'
    ufw allow 80/tcp comment 'HTTP (ACME/fallback)'
    ufw allow 443/tcp comment 'HTTPS / VLESS fallback'

    if [[ -n "$panel_ip" ]]; then
        if ! ufw allow from "$panel_ip" to any port "$panel_port" proto tcp comment 'remnanode: только панель'; then
            warning "$(t remnanode_firewall_restore_failed)"
            if (( panel_rule_updated )) && [[ -n "$saved_panel_ip" ]]; then
                ufw allow from "$saved_panel_ip" to any port "$saved_panel_port" proto tcp comment 'remnanode: только панель' ||
                    warning "$(t remnanode_firewall_restore_failed)"
            fi
        elif (( panel_rule_updated )) || [[ -r "$REMNANODE_PANEL_IP_FILE" && ! -r "$REMNANODE_PANEL_RULE_FILE" ]]; then
            write_remnanode_panel_rule "$panel_ip" "$panel_port" || warning "$(t remnanode_panel_rule_save_failed)"
        elif [[ -n "$saved_panel_ip" ]]; then
            info "$(t remnanode_firewall_rule_restored)"
        fi
    fi
    # UFW reset restores the package defaults, so apply these rules after reset.
    if ! configure_ufw_icmp_rules; then
        ufw --force enable || true
        return 1
    fi
    info "$(t firewall_icmp_warning)"

    if ! ufw --force disable || ! ufw --force enable; then
        error "$(t firewall_restart_failed)"
        return 1
    fi
    check_success "UFW включён и базовые порты открыты"

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
allowipv6 = no

# Progressive ban policy
bantime = 2h
bantime.increment = true
bantime.factor = 2
bantime.formula = bantime * (1<<(ban.Count if ban.Count<10 else 10))
bantime.maxtime = 1w
bantime.rndtime = 10m

# Detection window
findtime = 5m
maxretry = 3

# Whitelist trusted ranges here if needed
ignoreip = 127.0.0.1/8

[sshd]
enabled = true
port = ${ssh_port}
mode = aggressive
maxretry = 3
filter = sshd
backend = systemd
journalmatch = _SYSTEMD_UNIT=ssh.service + _COMM=sshd
action = %(action_mwl)s
logpath = /var/log/auth.log
findtime = 5m
bantime = 1d

[sshd-ddos]
enabled = true
port = ${ssh_port}
filter = sshd[mode=ddos]
backend = systemd
journalmatch = _SYSTEMD_UNIT=ssh.service + _COMM=sshd
action = %(action_)s
findtime = 5m
maxretry = 4
bantime = 72h

[nginx-http-auth]
enabled = false

[recidive]
enabled = true
logpath = /var/log/fail2ban.log
backend = auto
banaction = ufw
findtime = 1d
bantime = 2w
maxretry = 3
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

    fail2ban-client status sshd-ddos >/dev/null 2>&1 || {
        error "Jail sshd-ddos не активирован"
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
