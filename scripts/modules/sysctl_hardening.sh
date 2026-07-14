#!/bin/bash

log_ok()    { echo -e "${GREEN}[✅ OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[⚠️ WARN]${NC} $1"; }

setup_sysctl_hardening() {
    log_ok "=========================================="
    log_ok "Sysctl hardening + оптимизация под VLESS / TROJAN / HYSTERIA2"
    log_ok "=========================================="

    local SYSCTL_FILE="/etc/sysctl.d/99-server-opt.conf"
    local BACKUP_FILE="/etc/sysctl.d/99-server-opt.conf.karenet.bak"

    if [[ -f "$SYSCTL_FILE" && ! -f "$BACKUP_FILE" ]]; then
        cp -f "$SYSCTL_FILE" "$BACKUP_FILE"
    fi

    if modprobe tcp_bbr 2>/dev/null || grep -q "bbr" /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
        local TCP_CONGESTION="bbr"
        local QDISC="fq"
        log_ok "Включаем BBR + fq"
    else
        local TCP_CONGESTION="cubic"
        local QDISC="fq_codel"
        log_warn "BBR недоступен, используем CUBIC + fq_codel"
    fi

    cat <<EOF > "$SYSCTL_FILE"
### Безопасность IPv6 — отключаем, если не используется
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1

net.ipv6.conf.all.forwarding = 0
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0
net.ipv6.conf.all.autoconf = 0
net.ipv6.conf.default.autoconf = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
net.ipv6.conf.all.use_tempaddr = 2
net.ipv6.conf.default.use_tempaddr = 2

### IPv4 — маршрутизация и защита
net.ipv4.ip_forward = 0

# Защита от спуфинга и редиректов
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Логирование подозрительных пакетов
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

### ICMP — безопасность и ограничение флуда
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_echo_ignore_all = 1
net.ipv4.icmp_ratelimit = 100
net.ipv4.icmp_ratemask = 88089
net.ipv4.icmp_ignore_bogus_error_responses = 1

### TCP — защита и оптимизация
# SYN flood защита
net.ipv4.tcp_syncookies = 1

# Улучшенные параметры TCP
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_syn_backlog = 16384

# Главное исправление: TIME_WAIT
net.ipv4.tcp_max_tw_buckets = 262144

# Расширенные TCP возможности
net.ipv4.tcp_fack = 1
net.ipv4.tcp_ecn = 1
net.ipv4.tcp_sack = 1

# Keepalive — стабильность длинных соединений
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_mtu_probing = 1

# Размеры TCP буферов
net.ipv4.tcp_rmem = 4096 131072 33554432
net.ipv4.tcp_wmem = 4096 131072 33554432

# Очереди и буферы ядра
net.core.somaxconn = 16384
net.core.netdev_max_backlog = 16384
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432

# UDP буферы важны для VPN-трафика
net.ipv4.udp_rmem_min = 65536
net.ipv4.udp_wmem_min = 65536

# Современный алгоритм управления перегрузкой
net.core.default_qdisc = $QDISC
net.ipv4.tcp_congestion_control = $TCP_CONGESTION

### Безопасность ядра
kernel.yama.ptrace_scope = 1
kernel.randomize_va_space = 2

# Защита от дампов suid-программ
fs.suid_dumpable = 0

### Файловая система и память
# Максимум открытых файлов
fs.file-max = 2097152

# Не использовать swap без необходимости
vm.swappiness = 0
EOF

    if [ $? -eq 0 ]; then
        sysctl --system >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            log_ok "Настройки sysctl применены."
        else
            log_warn "sysctl --system завершился с ошибкой"
        fi
    else
        log_warn "Не удалось записать файл $SYSCTL_FILE"
    fi
}

disable_sysctl_hardening() {
    local SYSCTL_FILE="/etc/sysctl.d/99-server-opt.conf"
    local BACKUP_FILE="/etc/sysctl.d/99-server-opt.conf.karenet.bak"

    log_ok "Отключение sysctl hardening..."
    if [[ -f "$BACKUP_FILE" ]]; then
        mv -f "$BACKUP_FILE" "$SYSCTL_FILE"
    else
        rm -f "$SYSCTL_FILE"
    fi

    if sysctl --system >/dev/null 2>&1; then
        log_ok "sysctl hardening отключен"
    else
        log_warn "Не удалось полностью применить откат sysctl"
    fi
}
