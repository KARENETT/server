#!/bin/bash
# =============================================================================
# SERVER OPTIMIZER (KERNEL + BBR + NO PING)
# =============================================================================
# Скрипт для "разгона" сервера.
# 1. Ставит ядро XanMod (если можно).
# 2. Включает BBR + FQ.
# 3. БЛОКИРУЕТ входящие пинги (Server becomes stealth).
# 4. Поднимает лимиты файлов.
# =============================================================================

set -e  # Выход при ошибке

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[✅ OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[⚠️ WARN]${NC} $1"; }
log_error() { echo -e "${RED}[❌ ERROR]${NC} $1"; }
log_skip()  { echo -e "${YELLOW}[SKIP]${NC} $1"; }

# =============================================================================
# 0. ПРЕДВАРИТЕЛЬНЫЕ ПРОВЕРКИ
# =============================================================================
preflight_checks() {
    log_info "═══════════════════════════════════════════════════════════════"
    log_info " PREFLIGHT CHECKS"
    log_info "═══════════════════════════════════════════════════════════════"
    
    # Проверка root
    if [ "$EUID" -ne 0 ]; then
        log_error "Скрипт должен запускаться от root!"
        exit 1
    fi
    
    # Проверка наличия curl (нужен для проверки сети)
    if ! command -v curl &> /dev/null; then
        apt-get update -qq && apt-get install -y -qq curl
    fi
    
    # Проверка ОС
    if [ ! -f /etc/os-release ]; then
        log_error "Не удалось определить ОС!"
        exit 1
    fi
    
    . /etc/os-release
    
    # Поддерживаемые ОС
    case "$ID" in
        ubuntu|debian)
            log_ok "OS: $PRETTY_NAME ($ID)"
            ;;
        *)
            log_warn "OS: $ID. XanMod может не встать, но тюнинг sysctl применится."
            ;;
    esac
    
    # Проверка интернета (Curl вместо Ping, т.к. ICMP часто блокируют)
    log_info "Проверка соединения..."
    if curl -s --connect-timeout 5 https://www.google.com >/dev/null; then
         log_ok "Интернет доступен (через HTTP/HTTPS)"
    elif ping -c 1 8.8.8.8 &> /dev/null; then
         log_ok "Интернет доступен (через ICMP)"
    else
        log_error "Нет интернета! Проверьте сеть."
        exit 1
    fi
}

# =============================================================================
# 1. АУДИТ ЖЕЛЕЗА
# =============================================================================
audit_hardware() {
    log_info "═══════════════════════════════════════════════════════════════"
    log_info " HARDWARE AUDIT"
    log_info "═══════════════════════════════════════════════════════════════"
    
    CPU_CORES=$(nproc)
    TOTAL_MEM_MB=$(free -m | awk '/^Mem:/{print $2}')
    CURRENT_KERNEL=$(uname -r)
    
    log_info "CPU Cores: $CPU_CORES"
    log_info "RAM: ${TOTAL_MEM_MB} MB"
    log_info "Current Kernel: $CURRENT_KERNEL"
}

# =============================================================================
# 2. УСТАНОВКА XANMOD KERNEL (BBRv3)
# =============================================================================
install_xanmod() {
    log_info "═══════════════════════════════════════════════════════════════"
    log_info " XANMOD KERNEL INSTALLATION"
    log_info "═══════════════════════════════════════════════════════════════"
    
    # Проверка: уже установлен?
    if uname -r | grep -q "xanmod"; then
        log_ok "XanMod kernel уже установлен: $(uname -r)"
        return 0
    fi
    
    # Проверка: контейнер?
    if grep -q "container=lxc" /proc/1/environ 2>/dev/null || [ -f /.dockerenv ]; then
        log_warn "Запущено внутри контейнера (LXC/Docker). Смена ядра невозможна."
        log_skip "XanMod kernel"
        return 0
    fi
    
    # Проверка: архитектура x86_64
    if [ "$(uname -m)" != "x86_64" ]; then
        log_warn "XanMod требует архитектуру x86_64."
        log_skip "XanMod kernel"
        return 0
    fi

    # Определение версии XanMod по флагам CPU
    CPU_FLAGS=$(cat /proc/cpuinfo | grep flags | head -1)
    if echo "$CPU_FLAGS" | grep -q "avx2"; then
        XANMOD_VARIANT="linux-xanmod-x64v3"
        log_info "CPU supports AVX2 → выбираем x64v3"
    elif echo "$CPU_FLAGS" | grep -q "sse4_2"; then
        XANMOD_VARIANT="linux-xanmod-x64v2"
        log_info "CPU supports SSE4.2 → выбираем x64v2"
    else
        XANMOD_VARIANT="linux-xanmod-x64v1"
        log_info "Basic CPU → выбираем x64v1"
    fi
    
    log_info "Добавление репозитория XanMod..."
    
    apt-get update -qq
    apt-get install -y -qq wget gnupg2 lsb-release
    
    wget -qO - https://dl.xanmod.org/archive.key | gpg --dearmor -o /usr/share/keyrings/xanmod-archive-keyring.gpg --yes
    echo 'deb [signed-by=/usr/share/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org releases main' | tee /etc/apt/sources.list.d/xanmod-kernel.list > /dev/null
    
    apt-get update -qq
    
    log_info "Установка $XANMOD_VARIANT..."
    if DEBIAN_FRONTEND=noninteractive apt-get install -y $XANMOD_VARIANT; then
        log_ok "XanMod kernel установлен! Потребуется перезагрузка."
        REBOOT_REQUIRED=true
    else
        log_error "Ошибка установки XanMod."
    fi
}

# =============================================================================
# 3. НАСТРОЙКА SWAP (Умная проверка)
# =============================================================================
setup_swap() {
    log_info "═══════════════════════════════════════════════════════════════"
    log_info " SWAP CONFIGURATION"
    log_info "═══════════════════════════════════════════════════════════════"
    
    TOTAL_MEM_MB=$(free -m | awk '/^Mem:/{print $2}')
    
    # Если памяти > 8GB, swap обычно не критичен для нод, но сделаем 2GB на всякий
    if [ "$TOTAL_MEM_MB" -ge 8192 ]; then
        log_ok "RAM >= 8GB, пропуск создания Swap."
        return 0
    fi

    CURRENT_SWAP=$(swapon --show --bytes 2>/dev/null | tail -n +2 | awk '{sum+=$3} END {print int(sum/1024/1024)}')
    CURRENT_SWAP=${CURRENT_SWAP:-0}
    
    if [ "$CURRENT_SWAP" -ge 1024 ]; then
        log_ok "Swap уже есть: ${CURRENT_SWAP}MB"
        return 0
    fi
    
    SWAP_SIZE_MB=$((4096 - TOTAL_MEM_MB))
    [ "$SWAP_SIZE_MB" -lt 1024 ] && SWAP_SIZE_MB=2048
    [ "$SWAP_SIZE_MB" -gt 4096 ] && SWAP_SIZE_MB=4096
    
    log_info "Создаю swap файл: ${SWAP_SIZE_MB}MB..."
    
    if [ -f /swapfile ]; then
        swapoff /swapfile 2>/dev/null || true
        rm -f /swapfile
    fi
    
    fallocate -l ${SWAP_SIZE_MB}M /swapfile
    chmod 600 /swapfile
    mkswap /swapfile > /dev/null
    swapon /swapfile
    
    if ! grep -q "/swapfile" /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
    
    sysctl -w vm.swappiness=10 > /dev/null
    sysctl -w vm.vfs_cache_pressure=50 > /dev/null
    
    log_ok "Swap ${SWAP_SIZE_MB}MB готов."
}

# =============================================================================
# 4. SYSCTL & BBR TUNING (BLOCK PING HERE)
# =============================================================================
tune_sysctl() {
    log_info "═══════════════════════════════════════════════════════════════"
    log_info " NETWORK TUNING & BBR (BLOCKING PINGS)"
    log_info "═══════════════════════════════════════════════════════════════"
    
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

# =============================================================================
# 5. ULIMITS
# =============================================================================
setup_ulimits() {
    log_info "═══════════════════════════════════════════════════════════════"
    log_info " ULIMITS CONFIGURATION"
    log_info "═══════════════════════════════════════════════════════════════"
    
    LIMITS_FILE="/etc/security/limits.d/99-server-opt.conf"
    
    cat > "$LIMITS_FILE" <<EOF
* soft nofile 1000000
* hard nofile 1000000
root soft nofile 1000000
root hard nofile 1000000
EOF
    
    ulimit -n 1000000 2>/dev/null || true
    
    log_ok "Лимиты открытых файлов (nofile) увеличены до 1,000,000"
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    REBOOT_REQUIRED=false
    
    echo ""
    log_info "╔═════════════════════════════════════════════════════════════╗"
    log_info "║   SERVER OPTIMIZER (KERNEL/BBR/NO-PING)                     ║"
    log_info "╚═════════════════════════════════════════════════════════════╝"
    echo ""
    
    preflight_checks
    audit_hardware
    
    # 1. Ядро (самое важное)
    install_xanmod
    
    # 2. Swap (стабильность)
    setup_swap
    
    # 3. Сеть и лимиты
    tune_sysctl
    setup_ulimits
    
    echo ""
    log_info "═══════════════════════════════════════════════════════════════"
    log_ok " ОПТИМИЗАЦИЯ ЗАВЕРШЕНА!"
    log_info "═══════════════════════════════════════════════════════════════"
    
    if [ "$REBOOT_REQUIRED" = true ]; then
        log_warn "⚠️ ТРЕБУЕТСЯ ПЕРЕЗАГРУЗКА для активации ядра XanMod!"
        echo -e "${YELLOW}Перезагрузить сейчас? (y/n):${NC} \c"
        read -r response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            reboot
        else
            log_info "Не забудьте перезагрузить сервер вручную командой: reboot"
        fi
    fi
}

# Запуск
main "$@"