#!/bin/bash

setup_tcp_fastopen() {
    local sysctl_file="/etc/sysctl.d/98-karenet-tfo.conf"

    log "Включение TCP Fast Open..."
    cat > "$sysctl_file" <<'EOF'
net.ipv4.tcp_fastopen = 3
EOF

    if sysctl -p "$sysctl_file" >/dev/null 2>&1; then
        check_success "TCP Fast Open включен"
    else
        error "Не удалось применить TCP Fast Open"
        return 1
    fi
}

disable_tcp_fastopen() {
    local sysctl_file="/etc/sysctl.d/98-karenet-tfo.conf"

    log "Отключение TCP Fast Open..."
    rm -f "$sysctl_file"
    sysctl -w net.ipv4.tcp_fastopen=0 >/dev/null 2>&1 || true
    sysctl --system >/dev/null 2>&1 || true
    check_success "TCP Fast Open отключен"
}

setup_mss_clamp() {
    local script_path="/usr/local/sbin/karenet-mss-clamp.sh"
    local service_path="/etc/systemd/system/karenet-mss-clamp.service"

    log "Настройка MSS clamp..."

    cat > "$script_path" <<'EOF'
#!/bin/bash
set -euo pipefail

iptables -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || \
iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

ip6tables -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || \
ip6tables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
EOF

    chmod +x "$script_path"

    cat > "$service_path" <<EOF
[Unit]
Description=KARENET MSS Clamp
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$script_path
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now karenet-mss-clamp.service >/dev/null 2>&1

    check_success "MSS clamp настроен"
}

disable_mss_clamp() {
    local script_path="/usr/local/sbin/karenet-mss-clamp.sh"
    local service_name="karenet-mss-clamp.service"
    local service_path="/etc/systemd/system/$service_name"

    log "Отключение MSS clamp..."
    systemctl disable --now "$service_name" >/dev/null 2>&1 || true
    rm -f "$service_path" "$script_path"

    iptables -t mangle -D FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu >/dev/null 2>&1 || true
    ip6tables -t mangle -D FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu >/dev/null 2>&1 || true

    systemctl daemon-reload
    check_success "MSS clamp отключен"
}
