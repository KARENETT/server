#!/bin/bash

# Функции логирования
log() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    echo -e "${GREEN}${message}${NC}"
}

error() {
    local message="[ERROR] $1"
    echo -e "${RED}${message}${NC}"
    return 1
}

warning() {
    local message="[WARNING] $1"
    echo -e "${YELLOW}${message}${NC}"
}

info() {
    local message="[INFO] $1"
    echo -e "${BLUE}${message}${NC}"
}

# Функция проверки успешности выполнения команды
check_success() {
    if [ $? -eq 0 ]; then
        log "✓ $1"
        return 0
    else
        error "✗ $1"
        return 1
    fi
}

# Функция для выполнения команд с повторами
retry_command() {
    local max_attempts=3
    local attempt=1
    local delay=5
    local command="$@"

    while [ $attempt -le $max_attempts ]; do
        if eval "$command"; then
            return 0
        else
            if [ $attempt -lt $max_attempts ]; then
                warning "Попытка $attempt из $max_attempts не удалась. Повтор через $delay секунд..."
                sleep $delay
                ((attempt++))
            else
                error "Команда не выполнена после $max_attempts попыток: $command"
                return 1
            fi
        fi
    done
}

# Проверка интернет-соединения
check_internet() {
    info "Проверка интернет-соединения..."
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        error "Нет интернет-соединения"
        return 1
    fi
    log "Интернет-соединение проверено"
    return 0
}

is_yes() {
    local answer="${1:-}"
    [[ "$answer" =~ ^([Yy]|[Дд][Аа]?|[Yy][Ee][Ss])$ ]]
}

confirm_yes_no() {
    local prompt="$1"
    local answer
    read -rp "${PROMPT_PREFIX} ${prompt} " answer
    is_yes "$answer"
}

is_valid_ip_address() {
    local address="${1:-}"

    command -v python3 >/dev/null 2>&1 || return 1
    python3 -c 'import ipaddress, sys; ipaddress.ip_address(sys.argv[1])' "$address" >/dev/null 2>&1
}

is_valid_tcp_port() {
    local port="${1:-}"

    [[ "$port" =~ ^[0-9]{1,5}$ ]] || return 1
    (( 10#$port >= 1 && 10#$port <= 65535 ))
}

read_remnanode_panel_rule() {
    local ip_variable="$1"
    local port_variable="$2"
    local panel_ip=""
    local panel_port=""

    if [[ -r "$REMNANODE_PANEL_RULE_FILE" ]]; then
        IFS='|' read -r panel_ip panel_port < "$REMNANODE_PANEL_RULE_FILE" || true
    elif [[ -r "$REMNANODE_PANEL_IP_FILE" ]]; then
        IFS= read -r panel_ip < "$REMNANODE_PANEL_IP_FILE" || panel_ip=""
        panel_port="$REMNANODE_NODE_PORT"
    fi

    printf -v "$ip_variable" '%s' "$panel_ip"
    printf -v "$port_variable" '%s' "$panel_port"
}

write_remnanode_panel_rule() {
    local panel_ip="$1"
    local panel_port="$2"

    install -d -o root -g root -m 755 "$REMNANODE_DIR" || return 1
    if ! write_file_atomically "$REMNANODE_PANEL_RULE_FILE" 600 <<EOF
$panel_ip|$panel_port
EOF
    then
        return 1
    fi
    rm -f -- "$REMNANODE_PANEL_IP_FILE"
}

remove_remnanode_panel_ufw_rule() {
    local panel_ip="$1"
    local panel_port="$2"

    ufw --force delete allow from "$panel_ip" to any port "$panel_port" proto tcp comment 'remnanode: только панель' >/dev/null 2>&1 ||
        ufw --force delete allow from "$panel_ip" to any port "$panel_port" proto tcp >/dev/null 2>&1 || true
}

write_file_atomically() {
    local target="$1"
    local mode="${2:-644}"
    local temp_file

    temp_file="$(mktemp "${target}.XXXXXX")" || return 1
    if ! cat > "$temp_file"; then
        rm -f -- "$temp_file"
        error "Failed to write temporary file for $target"
        return 1
    fi

    if ! chmod "$mode" "$temp_file" || ! mv -f -- "$temp_file" "$target"; then
        rm -f -- "$temp_file"
        error "Failed to install file $target"
        return 1
    fi
}
