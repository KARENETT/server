#!/bin/bash

setup_sysctl_hardening() {
    log "=========================================="
    log "Sysctl hardening + оптимизация под Hysteria 2 / VLESS"
    log "=========================================="

    local conf="/etc/sysctl.d/99-proxy-hardening.conf"

    sudo tee "$conf" > /dev/null << 'EOF'
net.ipv4.ip_forward = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.conf.all.log_martians = 1

net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

net.ipv4.tcp_fastopen = 3

net.core.rmem_max = 16777216
net.core.wmem_max = 16777216

net.core.netdev_max_backlog = 250000
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF

    sudo sysctl --system
    sudo sysctl -p "$conf"

    check_success "Sysctl оптимизация применена (Hysteria 2 + BBR + защита)"
}
