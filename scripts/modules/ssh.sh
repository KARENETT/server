#!/bin/bash

setup_ssh() {
    local ssh_port backup_file
    SSH_CONFIGURED_PORT=""
    log "=========================================="
    log "$(t ssh_title)"
    log "=========================================="

    mkdir -p /run/sshd

    echo ""
    read -rp "${PROMPT_PREFIX} $(t ssh_port_prompt) " ssh_port
    ssh_port=${ssh_port:-33556}

    if ! [[ "$ssh_port" =~ ^[0-9]+$ ]] || [ "$ssh_port" -lt 1024 ] || [ "$ssh_port" -gt 65535 ]; then
        error "$(t ssh_invalid_port)"
        ssh_port=33556
    fi

    if [ -f /etc/ssh/sshd_config ]; then
        backup_file="/etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)"
        cp /etc/ssh/sshd_config "$backup_file"

        sed -i "s/^#*Port .*/Port $ssh_port/" /etc/ssh/sshd_config
        sed -i 's/^#*PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
        sed -i 's/^#*AllowUsers .*/AllowUsers haxgun/' /etc/ssh/sshd_config
        sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
        sed -i 's/^#*PubkeyAuthentication .*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
        sed -i 's/^#*PermitEmptyPasswords .*/PermitEmptyPasswords no/' /etc/ssh/sshd_config
        sed -i 's/^#*ChallengeResponseAuthentication .*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
        sed -i 's/^#*PermitUserEnvironment .*/PermitUserEnvironment no/' /etc/ssh/sshd_config
        sed -i 's/^#*MaxAuthTries .*/MaxAuthTries 3/' /etc/ssh/sshd_config
        sed -i 's/^#*LoginGraceTime .*/LoginGraceTime 20/' /etc/ssh/sshd_config
        sed -i 's/^#*X11Forwarding .*/X11Forwarding no/' /etc/ssh/sshd_config
        sed -i 's/^#*UseDNS .*/UseDNS no/' /etc/ssh/sshd_config

        if sshd -t; then
            if ! systemctl enable ssh || ! systemctl restart ssh; then
                cp -- "$backup_file" /etc/ssh/sshd_config || true
                systemctl restart ssh >/dev/null 2>&1 || true
                error "$(t ssh_restart_failed)"
                return 1
            fi

            SSH_CONFIGURED_PORT="$ssh_port"
            log "✓ SSH перезапущен на порту $ssh_port (только ключи!)"
            warning "$(t ssh_key_only)"
            warning "ssh -p $ssh_port user@IP"
        else
            error "$(t ssh_config_error)"
            cp -- "$backup_file" /etc/ssh/sshd_config || true
            return 1
        fi
    else
        error "$(t ssh_config_missing)"
        return 1
    fi
}
