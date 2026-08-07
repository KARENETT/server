#!/bin/bash

log_ok()    { echo -e "${GREEN}[✅ OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[⚠️ WARN]${NC} $1"; }

setup_sysctl_hardening() {
    log_ok "=========================================="
    log_ok "Sysctl: BBR + fq"
    log_ok "=========================================="

    cat >>/etc/sysctl.conf <<'CFG'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
CFG

    if sysctl -p >/dev/null 2>&1; then
        log_ok "Настройки sysctl применены."
    else
        log_warn "Не удалось применить настройки sysctl"
        return 1
    fi
}

disable_sysctl_hardening() {
    local SYSCTL_FILE="/etc/sysctl.conf"

    log_ok "Отключение sysctl BBR + fq..."
    if [[ -f "$SYSCTL_FILE" ]]; then
        sed -i \
            -e '/^net\.core\.default_qdisc=fq$/d' \
            -e '/^net\.ipv4\.tcp_congestion_control=bbr$/d' \
            "$SYSCTL_FILE"
    fi

    if sysctl -p >/dev/null 2>&1; then
        log_ok "sysctl настройки отключены"
    else
        log_warn "Не удалось полностью применить откат sysctl"
    fi
}
