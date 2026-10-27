#!/bin/bash

# Функции логирования
log() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    echo -e "${GREEN}${message}${NC}"
}

error() {
    local message="[ОШИБКА] $1"
    echo -e "${RED}${message}${NC}"
    return 1
}

warning() {
    local message="[ПРЕДУПРЕЖДЕНИЕ] $1"
    echo -e "${YELLOW}${message}${NC}"
}

info() {
    local message="[ИНФОРМАЦИЯ] $1"
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
    if [[ "${BULK_INSTALL:-0}" == "1" && "${INTERNET_CHECK_PASSED:-0}" == "1" ]]; then
        return 0
    fi

    info "Проверка интернет-соединения..."
    if ! ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
        error "Нет доступа к интернету"
        return 1
    fi
    if [[ "${BULK_INSTALL:-0}" == "1" ]]; then
        INTERNET_CHECK_PASSED=1
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
    local default="${2:-no}"
    local answer

    [[ "${BULK_INSTALL:-0}" == "1" ]] && return 0
    read -rp "${PROMPT_PREFIX} ${prompt} " answer || return 1
    [[ "$default" == "yes" && -z "$answer" ]] && return 0
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
        error "Не удалось записать временный файл для $target"
        return 1
    fi

    if ! chmod "$mode" "$temp_file" || ! mv -f -- "$temp_file" "$target"; then
        error "Не удалось установить файл $target"
        return 1
    fi
}
managed_file_sidecar() {
    printf '%s.karenet.sha256' "$1"
}

managed_file_sha256() {
    sha256sum -- "$1" | awk '{print $1}'
}

managed_file_is_safe() {
    local target="$1"
    local candidate="$2"
    local sidecar expected actual

    [[ -f "$target" ]] || return 0
    [[ -f "$candidate" ]] || return 1
    cmp -s -- "$target" "$candidate" && return 0

    sidecar="$(managed_file_sidecar "$target")"
    [[ -r "$sidecar" ]] || return 1
    IFS= read -r expected < "$sidecar" || return 1
    actual="$(managed_file_sha256 "$target")" || return 1
    [[ -n "$expected" && "$expected" == "$actual" ]]
}

managed_file_save_candidate() {
    local target="$1"
    local candidate="$2"
    local mode="${3:-644}"
    local new_file="${target}.new-${SCRIPT_VERSION:-unknown}"

    if ! install -m "$mode" -- "$candidate" "$new_file"; then
        error "$(t managed_config_candidate_failed) $new_file"
        return 1
    fi

    warning "$(t managed_config_modified) $target"
    if [[ -f "$target" ]] && command -v diff >/dev/null 2>&1; then
        diff -u -- "$target" "$new_file" || true
    fi
    info "$(t managed_config_candidate_saved) $new_file"
}

managed_file_commit() {
    local target="$1"
    local mode="$2"
    local candidate="$3"
    local sidecar backup hash

    sidecar="$(managed_file_sidecar "$target")"
    if [[ -f "$target" ]] && ! cmp -s -- "$target" "$candidate"; then
        backup="${target}.bak"
        if ! cp -p -- "$target" "$backup"; then
            error "$(t managed_config_backup_failed) $target"
            return 1
        fi
    fi

    if ! write_file_atomically "$target" "$mode" < "$candidate"; then
        return 1
    fi
    hash="$(managed_file_sha256 "$target")" || return 1
    write_file_atomically "$sidecar" 644 <<< "$hash"
}

managed_files_snapshot() {
    local snapshot_dir="$1"
    shift
    local index=0 target file

    install -d -m 700 "$snapshot_dir" || return 1
    for target in "$@"; do
        for file in "$target" "$(managed_file_sidecar "$target")"; do
            index=$((index + 1))
            if [[ -e "$file" ]]; then
                cp -p -- "$file" "$snapshot_dir/$index" || return 1
                : > "$snapshot_dir/$index.present"
            else
                : > "$snapshot_dir/$index.missing"
            fi
        done
    done
}

managed_files_restore() {
    local snapshot_dir="$1"
    shift
    local index=0 target file

    for target in "$@"; do
        for file in "$target" "$(managed_file_sidecar "$target")"; do
            index=$((index + 1))
            if [[ -f "$snapshot_dir/$index.present" ]]; then
                cp -p -- "$snapshot_dir/$index" "$file" || return 1
            else
                rm -f -- "$file"
            fi
        done
    done
}
