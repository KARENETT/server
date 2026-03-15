#!/bin/bash

log_ok()    { echo -e "${GREEN}[✅ OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[⚠️ WARN]${NC} $1"; }

setup_sysctl_hardening() {
    log_ok "=========================================="
    log_ok "Sysctl hardening + оптимизация под Hysteria 2 / VLESS"
    log_ok "=========================================="

    local SYSCTL_FILE="/etc/sysctl.d/99-server-opt.conf"

    if modprobe tcp_bbr 2>/dev/null || grep -q "bbr" /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
        local TCP_CONGESTION="bbr"
        local QDISC="fq"
        log_ok "Включаем BBR + FQ"
    else
        local TCP_CONGESTION="cubic"
        local QDISC="fq_pie"
        log_warn "BBR недоступен, используем CUBIC"
    fi

    cat <<EOF | sudo tee "$SYSCTL_FILE" >/dev/null
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

    if [ $? -eq 0 ]; then
        sudo sysctl --system >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            log_ok "Настройки sysctl применены. Пинг отключен."
        else
            log_warn "sysctl --system завершился с ошибкой"
        fi
    else
        log_warn "Не удалось записать файл $SYSCTL_FILE"
    fi
}
