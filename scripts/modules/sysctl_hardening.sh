#!/bin/bash

setup_sysctl_hardening() {
    log "=========================================="
    log "Sysctl hardening + оптимизация под Hysteria 2 / VLESS"
    log "=========================================="

    SYSCTL_FILE="/etc/sysctl.d/99-server-opt.conf"

    if modprobe tcp_bbr 2>/dev/null || grep -q "bbr" /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
        TCP_CONGESTION="bbr"
        QDISC="fq"
        log_ok "Включаем BBR + FQ"
    else
        TCP_CONGESTION="cubic"
        QDISC="fq_pie"
        log_warn "BBR недоступен, используем CUBIC"
    fi

    cat > "$SYSCTL_FILE" <<EOF
# =============================================================================
# Server Network Optimization
# =============================================================================

# --- SECURITY: BLOCK ALL PINGS (ICMP) ---
net.ipv4.icmp_echo_ignore_all = 1
# ----------------------------------------

# --- BBR & Queue Management ---
net.core.default_qdisc = $QDISC
net.ipv4.tcp_congestion_control = $TCP_CONGESTION

# --- TCP Tuning ---
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 65536 33554432

# Увеличение очереди подключений
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.core.netdev_max_backlog = 16384

# Тайм-ауты
net.ipv4.tcp_fin_timeout = 25
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15

# --- Security & Misc ---
net.ipv4.conf.all.rp_filter = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_fastopen = 3
fs.file-max = 2097152
EOF

    sysctl --system > /dev/null 2>&1
    log_ok "Настройки sysctl применены. Пинг отключен."
}
