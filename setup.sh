#!/bin/bash
# Строгий режим выполнения
set -euo pipefail
IFS=$'\n\t'

# Resolve installed shortcuts while preserving process-substitution launchers.
SCRIPT_SOURCE="${BASH_SOURCE[0]:-$0}"
case "$SCRIPT_SOURCE" in
    /dev/fd/*|/proc/*) ;;
    *) SCRIPT_SOURCE="$(readlink -f -- "$SCRIPT_SOURCE" 2>/dev/null || printf '%s' "$SCRIPT_SOURCE")" ;;
esac
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" 2>/dev/null && pwd || pwd)"
SCRIPT_VERSION="1.3.0"

LANGUAGE="ru"
export LANGUAGE
unset BULK_INSTALL INTERNET_CHECK_PASSED
SSH_CONFIGURED_PORT=""
INSTALL_DIR="/opt/karenet-setup"
SHORTCUT_PATH="/usr/local/bin/karenet-setup"
REPO_RAW_BASE="https://raw.githubusercontent.com/KARENETT/server/main"
REPO_MIRROR_BASE="https://cdn.jsdelivr.net/gh/KARENETT/server@main"
RUNTIME_FILES=(
    "setup.sh"
    "scripts/config.sh"
    "scripts/utils.sh"
    "scripts/modules/user.sh"
    "scripts/modules/system.sh"
    "scripts/modules/swap.sh"
    "scripts/modules/ulimits.sh"
    "scripts/modules/packages.sh"
    "scripts/modules/ssh.sh"
    "scripts/modules/firewall.sh"
    "scripts/modules/zsh.sh"
    "scripts/modules/nodejs.sh"
    "scripts/modules/uv.sh"
    "scripts/modules/docker.sh"
    "scripts/modules/xanmod.sh"
    "scripts/modules/sysctl_hardening.sh"
    "scripts/modules/trafficguard.sh"
    "scripts/modules/ds_guard.sh"
    "scripts/modules/warp_native.sh"
    "scripts/modules/caddy_selfsteal.sh"
    "scripts/modules/remnanode.sh"
    "scripts/modules/psiphon.sh"
    "scripts/assets/selfsteal/index.html"
    "scripts/assets/selfsteal/speedtest/index.html"
    "translation/ru.sh"
)

fetch_runtime_file() {
    local path="$1"
    local destination="$2"
    local base

    mkdir -p "$(dirname "$destination")" || return 1
    for base in "$REPO_RAW_BASE" "$REPO_MIRROR_BASE"; do
        rm -f -- "$destination"
        if curl -fsSL --connect-timeout 5 --max-time 45 "$base/$path" -o "$destination" &&
            [[ -s "$destination" ]]; then
            if [[ "$path" == *.sh ]] && ! bash -n "$destination" >/dev/null 2>&1; then
                continue
            fi
            return 0
        fi
    done
    rm -f -- "$destination"
    return 1
}

download_runtime_files() {
    local target_dir="$1"
    local file

    for file in "${RUNTIME_FILES[@]}"; do
        if ! fetch_runtime_file "$file" "$target_dir/$file"; then
            echo "[ОШИБКА] Не удалось скачать или проверить: $file"
            return 1
        fi
    done
}

# Доступ только для суперпользователя
if [[ $EUID -ne 0 ]]; then
    echo "[ОШИБКА] Требуются права суперпользователя. Запустите: sudo bash setup.sh"
    exit 1
fi

# При запуске через `curl ... | sudo bash` stdin занят скриптом и к моменту
# интерактивного меню оказывается на EOF. Переключаем ввод на терминал.
if [[ ! -t 0 && -r /dev/tty ]]; then
    exec < /dev/tty
fi

ensure_global_install() {
    local source_dir target_dir tmp_dir

    if [[ ! -f "$SCRIPT_DIR/scripts/config.sh" ]]; then
        tmp_dir="$(mktemp -d /tmp/karenet-setup.XXXXXX)"
        if ! download_runtime_files "$tmp_dir"; then
            rm -rf -- "$tmp_dir"
            exit 1
        fi
        mkdir -p "$INSTALL_DIR"
        cp -a "$tmp_dir/." "$INSTALL_DIR/"
        rm -rf -- "$tmp_dir"
        chmod +x "$INSTALL_DIR/setup.sh"
        ln -sfn "$INSTALL_DIR/setup.sh" "$SHORTCUT_PATH"
        exec "$INSTALL_DIR/setup.sh" "$@"
    fi

    mkdir -p "$INSTALL_DIR"
    source_dir="$(realpath "$SCRIPT_DIR")"
    target_dir="$(realpath "$INSTALL_DIR")"
    if [[ "$source_dir" != "$target_dir" && -d "$SCRIPT_DIR/scripts" ]]; then
        cp -a "$SCRIPT_DIR/." "$INSTALL_DIR/"
    fi

    chmod +x "$INSTALL_DIR/setup.sh"
    ln -sfn "$INSTALL_DIR/setup.sh" "$SHORTCUT_PATH"
    if [[ "$SCRIPT_DIR/setup.sh" != "$INSTALL_DIR/setup.sh" ]]; then
        exec "$INSTALL_DIR/setup.sh" "$@"
    fi
}

ensure_global_install "$@"

# Загрузка конфигурации
source "$SCRIPT_DIR/scripts/config.sh"
source "$SCRIPT_DIR/scripts/utils.sh"
source "$SCRIPT_DIR/translation/ru.sh"

BRIGHT_GREEN=$'\033[1;92m'
GRAY=$'\033[0;90m'
RESET_COLOR=$'\033[0m'
BOLD=$'\033[1m'
PROMPT_PREFIX="${BRIGHT_GREEN}[?]${RESET_COLOR}"

# Загрузка модулей
source "$MODULES_DIR/user.sh"
source "$MODULES_DIR/system.sh"
source "$MODULES_DIR/swap.sh"
source "$MODULES_DIR/ulimits.sh"
source "$MODULES_DIR/packages.sh"
source "$MODULES_DIR/ssh.sh"
source "$MODULES_DIR/firewall.sh"
source "$MODULES_DIR/zsh.sh"
source "$MODULES_DIR/nodejs.sh"
source "$MODULES_DIR/uv.sh"
source "$MODULES_DIR/docker.sh"
source "$MODULES_DIR/xanmod.sh"
source "$MODULES_DIR/sysctl_hardening.sh"
source "$MODULES_DIR/trafficguard.sh"
source "$MODULES_DIR/ds_guard.sh"
source "$MODULES_DIR/caddy_selfsteal.sh"
source "$MODULES_DIR/remnanode.sh"
source "$MODULES_DIR/warp_native.sh"
source "$MODULES_DIR/psiphon.sh"

# Функция установки всего
install_all() {
    local BULK_INSTALL=1
    local INTERNET_CHECK_PASSED=0
    local DEBIAN_FRONTEND=noninteractive
    export DEBIAN_FRONTEND

    log "=========================================="
    log "$(t install_all_title)"
    log "=========================================="
    prompt_ssh_port || return 1
    info "$(t install_all_scope_notice)"
    check_internet || return 1

    update_system || return 1
    setup_xanmod || return 1
    setup_swap || return 1
    setup_ulimits || return 1
    install_packages || return 1
    setup_ssh "$SSH_CONFIGURED_PORT" || return 1
    setup_firewall "$SSH_CONFIGURED_PORT" "skip-panel-prompt" || return 1
    if is_trafficguard_installed; then
        info "$(t opt_10_installed)"
    else
        setup_trafficguard || return 1
    fi
    if is_ds_guard_installed; then
        info "$(t opt_23_installed)"
    else
        setup_ds_guard || return 1
    fi
    setup_zsh || return 1
    setup_nodejs || return 1
    setup_uv || return 1
    setup_docker || return 1
    setup_sysctl_hardening || return 1
    setup_psiphon || return 1

    if ! mkdir -p ~/projects ~/scripts ~/downloads ~/backup; then
        error "$(t install_dirs_failed)"
        return 1
    fi
    check_success "$(t install_dirs_created)" || return 1

    log "=========================================="
    log "$(t install_all_done)"
    log "=========================================="
    echo ""
    info "$(t post_steps_title)"
    echo "1. $(t post_step_shell)"
    echo "2. $(t post_step_docker)"
    echo ""
    info "$(t install_all_reboot_notice)"
}

selective_install() {
    local selected raw item
    local -A seen=()

    clear_screen
    print_logo
    echo -e "${GRAY}────────────────────────────────────────────────────────────────────────────────${NC}"
    echo ""
    echo -e "${YELLOW}$(t selective_title)${NC}"
    echo -e "${MAGENTA}$(t category_system)${NC}"
    echo -e " ${GREEN}3.${NC} $(t opt_3)"
    echo -e " ${GREEN}4.${NC} $(t opt_4)"
    echo -e " ${GREEN}5.${NC} $(t opt_5)"
    echo -e " ${GREEN}6.${NC} $(menu_option_text 6)"
    echo -e " ${GREEN}7.${NC} $(menu_option_text 7)"
    echo -e "${MAGENTA}$(t category_security)${NC}"
    echo -e " ${GREEN}8.${NC} $(t opt_8)"
    echo -e " ${GREEN}9.${NC} $(menu_option_text 9)"
    echo -e " ${GREEN}10.${NC} $(menu_option_text 10)"
    echo -e " ${GREEN}23.${NC} $(menu_option_text 23)"
    echo -e "${MAGENTA}$(t category_dev)${NC}"
    echo -e " ${GREEN}11.${NC} $(t opt_11)"
    echo -e " ${GREEN}12.${NC} $(t opt_12)"
    echo -e " ${GREEN}13.${NC} $(t opt_13)"
    echo -e " ${GREEN}14.${NC} $(t opt_14)"
    echo -e "${MAGENTA}$(t category_performance)${NC}"
    echo -e " ${GREEN}15.${NC} $(t opt_15)"
    echo -e " ${GREEN}16.${NC} $(menu_option_text 16)"
    echo -e "${MAGENTA}$(t category_misc)${NC}"
    echo -e " ${GREEN}19.${NC} $(t opt_19)"
    echo -e " ${GREEN}20.${NC} $(t opt_20)"
    echo -e " ${GREEN}21.${NC} $(menu_option_text 21)"
    echo -e " ${GREEN}22.${NC} $(t opt_22)"
    echo -e " ${GREEN}25.${NC} $(t opt_25)"
    echo -e "${MAGENTA}$(t category_selfsteal)${NC}"
    echo -e " ${GREEN}24.${NC} $(t opt_24)"
    echo -e "${MAGENTA}$(t category_remnanode)${NC}"
    echo -e " ${GREEN}26.${NC} $(t opt_26)"
    echo ""
    read -rp "${PROMPT_PREFIX} $(t selective_input) " raw

    selected="$(expand_selection "$raw")"

    if [[ -z "${selected// }" ]]; then
        warning "$(t selective_empty)"
        return 0
    fi

    for item in $selected; do
        choice="${item//[^0-9]/}"
        [[ -n "${seen[$choice]:-}" ]] && continue
        seen[$choice]=1
        case "$choice" in
            3) add_user || return 1 ;;
            4) update_system || return 1 ;;
            5) install_packages || return 1 ;;
            6) toggle_swap || return 1 ;;
            7) toggle_ulimits || return 1 ;;
            8) setup_ssh || return 1 ;;
            9) toggle_firewall || return 1 ;;
            10) setup_trafficguard || return 1 ;;
            23) setup_ds_guard || return 1 ;;
            11) setup_zsh || return 1 ;;
            12) setup_nodejs || return 1 ;;
            13) setup_uv || return 1 ;;
            14) setup_docker || return 1 ;;
            15) setup_xanmod || return 1 ;;
            16) toggle_sysctl_hardening || return 1 ;;
            21) setup_warp_native || return 1 ;;
            24) setup_caddy_selfsteal || return 1 ;;
            26) setup_remnanode || return 1 ;;
            25) setup_psiphon || return 1 ;;
            *) warning "$(t selective_invalid): $item" ;;
        esac
    done
}

expand_selection() {
    local raw="$1"
    local token start end i out=""

    for token in $raw; do
        if [[ "$token" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            start="${BASH_REMATCH[1]}"
            end="${BASH_REMATCH[2]}"
            if ((start <= end)); then
                for ((i = start; i <= end; i++)); do out+="$i "; done
            else
                for ((i = start; i >= end; i--)); do out+="$i "; done
            fi
        else
            out+="$token "
        fi
    done

    echo "$out"
}

is_swap_enabled() { swapon --show 2>/dev/null | tail -n +2 | grep -q .; }
is_ulimits_enabled() { [[ -f /etc/security/limits.d/99-server-opt.conf ]]; }
is_firewall_enabled() { ufw status 2>/dev/null | grep -qi "Status: active" || systemctl is-active --quiet fail2ban; }
is_sysctl_hardening_enabled() {
    grep -qxF 'net.core.default_qdisc=fq' /etc/sysctl.conf 2>/dev/null &&
        grep -qxF 'net.ipv4.tcp_congestion_control=bbr' /etc/sysctl.conf 2>/dev/null
}
is_trafficguard_enabled() { is_trafficguard_installed; }
is_ds_guard_enabled() { is_ds_guard_installed; }
is_warp_native_enabled() { is_warp_native_installed; }

toggle_swap() { if is_swap_enabled; then disable_swap; else setup_swap; fi; }
toggle_ulimits() { if is_ulimits_enabled; then disable_ulimits; else setup_ulimits; fi; }
toggle_firewall() {
    if is_firewall_enabled; then
        disable_firewall
    elif [[ -n "$SSH_CONFIGURED_PORT" ]]; then
        setup_firewall "$SSH_CONFIGURED_PORT"
    else
        setup_firewall
    fi
}
toggle_sysctl_hardening() { if is_sysctl_hardening_enabled; then disable_sysctl_hardening; else setup_sysctl_hardening; fi; }

menu_option_text() {
    local option="$1"
    case "$option" in
        6) if is_swap_enabled; then t opt_6_disable; else t opt_6; fi ;;
        7) if is_ulimits_enabled; then t opt_7_disable; else t opt_7; fi ;;
        9) if is_firewall_enabled; then t opt_9_disable; else t opt_9; fi ;;
        10) if is_trafficguard_enabled; then t opt_10_installed; else t opt_10; fi ;;
        23) if is_ds_guard_enabled; then t opt_23_installed; else t opt_23; fi ;;
        16) if is_sysctl_hardening_enabled; then t opt_16_disable; else t opt_16; fi ;;
        21) if is_warp_native_enabled; then t opt_21_installed; else t opt_21; fi ;;
        *) t "opt_${option}" ;;
    esac
}

get_remote_script_version() {
    local temporary_file remote_version

    temporary_file="$(mktemp "${TMPDIR:-/tmp}/karenet-setup.version.XXXXXX")" || return 1
    if ! fetch_runtime_file "setup.sh" "$temporary_file"; then
        rm -f -- "$temporary_file"
        return 1
    fi
    remote_version="$(awk -F'"' '/^SCRIPT_VERSION="/ { print $2; exit }' "$temporary_file")"
    rm -f -- "$temporary_file"
    [[ "$remote_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] || return 1
    printf '%s' "$remote_version"
}

version_is_newer() {
    local current="$1"
    local candidate="$2"
    local newest

    [[ "$current" != "$candidate" ]] || return 1
    newest="$(printf '%s\n%s\n' "$current" "$candidate" | sort -V | tail -n 1)"
    [[ "$newest" == "$candidate" ]]
}
check_script_updates() {
    local remote_version

    remote_version="$(get_remote_script_version)" || {
        error "$(t updates_fetch_failed)"
        return 1
    }
    if [[ "$remote_version" == "$SCRIPT_VERSION" ]]; then
        info "$(t updates_ok) ($remote_version)"
    elif version_is_newer "$SCRIPT_VERSION" "$remote_version"; then
        warning "$(t updates_available) ($remote_version)"
        info "$(t updates_hint)"
    else
        warning "$(t updates_local_newer) ($remote_version)"
    fi
}


uninstall_script() {
    if confirm_yes_no "$(t uninstall_confirm)"; then
        read -rp "${PROMPT_PREFIX} $(t uninstall_type_delete) " confirm_delete
        if [[ "$confirm_delete" != "DELETE" ]]; then
            warning "$(t uninstall_cancelled)"
            return 0
        fi
        rm -f "$SHORTCUT_PATH"
        rm -rf "$INSTALL_DIR"
        log "$(t uninstall_done)"
        exit 0
    fi

    info "$(t uninstall_cancelled)"
}

self_update_script() {
    local restart_menu=0
    local stage_dir=""
    local backup_dir="${INSTALL_DIR}.rollback.$$"
    local remote_version=""
    local had_install=0

    if [[ "${1:-}" == "--restart-menu" ]]; then
        restart_menu=1
    fi
    log "$(t updates_run)"
    remote_version="$(get_remote_script_version)" || {
        error "$(t updates_fetch_failed)"
        return 1
    }
    if ! version_is_newer "$SCRIPT_VERSION" "$remote_version"; then
        if [[ "$remote_version" == "$SCRIPT_VERSION" ]]; then
            info "$(t updates_ok) ($remote_version)"
        else
            warning "$(t updates_local_newer) ($remote_version)"
        fi
        return 0
    fi

    stage_dir="$(mktemp -d "$(dirname "$INSTALL_DIR")/karenet-setup.stage.XXXXXX")" || {
        error "$(t updates_stage_failed)"
        return 1
    }
    if ! download_runtime_files "$stage_dir"; then
        rm -rf -- "$stage_dir"
        error "$(t updates_fetch_failed)"
        return 1
    fi

    remote_version="$(awk -F'"' '/^SCRIPT_VERSION="/ { print $2; exit }' "$stage_dir/setup.sh")"
    if [[ ! "$remote_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
        rm -rf -- "$stage_dir"
        error "$(t updates_version_invalid)"
        return 1
    fi
    if ! version_is_newer "$SCRIPT_VERSION" "$remote_version"; then
        rm -rf -- "$stage_dir"
        if [[ "$remote_version" == "$SCRIPT_VERSION" ]]; then
            info "$(t updates_ok) ($remote_version)"
        else
            warning "$(t updates_local_newer) ($remote_version)"
        fi
        return 0
    fi

    chmod +x "$stage_dir/setup.sh"
    if [[ -e "$INSTALL_DIR" ]]; then
        if ! mv -- "$INSTALL_DIR" "$backup_dir"; then
            rm -rf -- "$stage_dir"
            error "$(t updates_install_failed)"
            return 1
        fi
        had_install=1
    fi
    if ! mv -- "$stage_dir" "$INSTALL_DIR"; then
        rm -rf -- "$stage_dir"
        if (( had_install )); then
            mv -- "$backup_dir" "$INSTALL_DIR" || true
        fi
        error "$(t updates_install_failed)"
        return 1
    fi
    if ! bash -n "$INSTALL_DIR/setup.sh" ||
        ! ln -sfn "$INSTALL_DIR/setup.sh" "$SHORTCUT_PATH"; then
        rm -rf -- "$INSTALL_DIR"
        if (( had_install )); then
            mv -- "$backup_dir" "$INSTALL_DIR" || true
            ln -sfn "$INSTALL_DIR/setup.sh" "$SHORTCUT_PATH" || true
        fi
        error "$(t updates_install_failed)"
        return 1
    fi

    rm -rf -- "$backup_dir"
    log "$(t updates_installed) $remote_version"
    if (( restart_menu )); then
        export LANGUAGE
        exec "$INSTALL_DIR/setup.sh"
    fi
}





t() {
    translate_ru "$1"
}

print_logo() {
    local WHITE=$'\033[1;97m'
    local logo_lines title_lines

    mapfile -t logo_lines << 'EOF'
    .*%=     .*%=
  .+@@@@#- .+%@@@%-
   =%@@@@@#%@@@@@#:
+++=*@@@@@@@@@@@%+=++-
@@@@@@@@@@@@@@@@@@@@@*
@@@@@@@@@@@@@@@@@@@@@*
::+@@@@@@%=*@@@@@@%=:.
:#@@@@@%+.  :*@@@@@%+.
-#@@@@+.      :#@@@@*.
  -%*.          -%*:
EOF

    mapfile -t title_lines << EOF
KARENET — настройка сервера
$(t version_label) v${SCRIPT_VERSION}
https://github.com/KARENETT/server
EOF

    local max_lines=${#logo_lines[@]}
    local title_start=$(((max_lines - ${#title_lines[@]}) / 2))
    local padding="      "

    for ((i = 0; i < max_lines; i++)); do
        if ((i >= title_start && i < title_start + ${#title_lines[@]})); then
            printf "%b%s%s%s%b\n" "$WHITE" "${logo_lines[$i]}" "$padding" "${title_lines[$((i - title_start))]}" "$RESET_COLOR"
        else
            printf "%b%s%b\n" "$WHITE" "${logo_lines[$i]}" "$RESET_COLOR"
        fi
    done
}

menu_divider() {
    echo -e "${GRAY}────────────────────────────────────────────────────────────${NC}"
}

clear_screen() {
    if [[ -t 1 && -n "${TERM:-}" && "$TERM" != "dumb" ]]; then
        printf '\033[H\033[2J'
    fi
}

menu_header() {
    local title="$1"
    clear_screen
    print_logo
    menu_divider
    echo -e "${BOLD}${title}${NC}"
    echo ""
}

menu_container_state() {
    local container="$1" docker_available="${2:-0}" state

    if [[ "$docker_available" != "1" ]]; then
        printf 'unavailable'
        return 0
    fi

    if ! state="$(docker inspect --format '{{.State.Status}}' "$container" 2>/dev/null)"; then
        printf 'missing'
        return 0
    fi

    if [[ "$state" == "running" ]]; then
        printf 'running'
    else
        printf 'stopped'
    fi
}

print_service_status() {
    local label_key="$1" container="$2" docker_available="$3" state color
    state="$(menu_container_state "$container" "$docker_available")"

    case "$state" in
        running) color="$GREEN" ;;
        stopped) color="$YELLOW" ;;
        *) color="$GRAY" ;;
    esac

    printf "  %b%-16s%b %b%s%b\n" \
        "$MAGENTA" "$(t "$label_key")" "$NC" \
        "$color" "$(t "status_${state}")" "$NC"
}

show_menu() {
    local docker_available=1

    if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
        docker_available=0
    fi
    menu_header "$(t main_menu_title)"

    echo -e "${MAGENTA}$(t menu_status_title)${NC}"
    print_service_status status_remnanode_label remnanode "$docker_available"
    print_service_status status_caddy_label caddy "$docker_available"
    print_service_status status_nginx_label nginx "$docker_available"
    echo ""
    menu_divider

    echo -e "${MAGENTA}$(t category_services)${NC}"
    echo -e " ${GREEN}1.${NC} $(t opt_server_settings) ${GRAY}→${NC}"
    echo -e " ${GREEN}2.${NC} $(t opt_remnanode_settings) ${GRAY}→${NC}"
    echo -e " ${GREEN}3.${NC} $(t opt_selfsteal_settings) ${GRAY}→${NC}"
    echo ""
    echo -e "${MAGENTA}$(t category_quick)${NC}"
    echo -e " ${GREEN}4.${NC} $(t opt_1)"
    echo -e " ${GREEN}5.${NC} $(t opt_2)"
    echo ""
    menu_divider
    echo -e " ${RED}0.${NC} $(t opt_0)"
    echo -e " - $(t quick_launch): ${RED}${BOLD}karenet-setup${NC}"
    echo ""
}

show_server_settings_menu() {
    menu_header "$(t server_menu_title)"

    echo -e "${MAGENTA}$(t category_system)${NC}"
    echo -e " ${GREEN}1.${NC} $(t opt_3)"
    echo -e " ${GREEN}2.${NC} $(t opt_4)"
    echo -e " ${GREEN}3.${NC} $(t opt_5)"
    echo -e " ${GREEN}4.${NC} $(menu_option_text 6)"
    echo -e " ${GREEN}5.${NC} $(menu_option_text 7)"
    echo -e "${MAGENTA}$(t category_security)${NC}"
    echo -e " ${GREEN}6.${NC} $(t opt_8)"
    echo -e " ${GREEN}7.${NC} $(menu_option_text 9)"
    echo -e " ${GREEN}8.${NC} $(menu_option_text 10)"
    echo -e " ${GREEN}9.${NC} $(menu_option_text 23)"
    echo -e "${MAGENTA}$(t category_dev)${NC}"
    echo -e " ${GREEN}10.${NC} $(t opt_11)"
    echo -e " ${GREEN}11.${NC} $(t opt_12)"
    echo -e " ${GREEN}12.${NC} $(t opt_13)"
    echo -e " ${GREEN}13.${NC} $(t opt_14)"
    echo -e "${MAGENTA}$(t category_performance)${NC}"
    echo -e " ${GREEN}14.${NC} $(t opt_15)"
    echo -e " ${GREEN}15.${NC} $(menu_option_text 16)"
    echo -e "${MAGENTA}$(t category_misc)${NC}"
    echo -e " ${GREEN}16.${NC} $(menu_option_text 21)"
    echo -e " ${GREEN}17.${NC} $(t opt_25)"
    echo -e " ${GREEN}18.${NC} $(t opt_19)"
    echo -e " ${GREEN}19.${NC} $(t opt_22)"
    echo -e " ${GREEN}20.${NC} $(t opt_20)"
    echo ""
    menu_divider
    echo -e " ${RED}0.${NC} $(t opt_back)"
    echo ""
}

run_menu_action_and_pause() {
    "$@" || return 1
    read -rp "${PROMPT_PREFIX} $(t press_enter)" || return 1
}

server_settings_menu() {
    local choice
    while true; do
        show_server_settings_menu
        read -rp "${PROMPT_PREFIX} $(t choose_server_item) " choice || return 1
        echo ""

        case "$choice" in
            1) run_menu_action_and_pause add_user || return 1 ;;
            2) run_menu_action_and_pause update_system || return 1 ;;
            3) run_menu_action_and_pause install_packages || return 1 ;;
            4) run_menu_action_and_pause toggle_swap || return 1 ;;
            5) run_menu_action_and_pause toggle_ulimits || return 1 ;;
            6) run_menu_action_and_pause setup_ssh || return 1 ;;
            7) run_menu_action_and_pause toggle_firewall || return 1 ;;
            8) run_menu_action_and_pause setup_trafficguard || return 1 ;;
            9) run_menu_action_and_pause setup_ds_guard || return 1 ;;
            10) run_menu_action_and_pause setup_zsh || return 1 ;;
            11) run_menu_action_and_pause setup_nodejs || return 1 ;;
            12) run_menu_action_and_pause setup_uv || return 1 ;;
            13) run_menu_action_and_pause setup_docker || return 1 ;;
            14) run_menu_action_and_pause setup_xanmod || return 1 ;;
            15) run_menu_action_and_pause toggle_sysctl_hardening || return 1 ;;
            16) run_menu_action_and_pause setup_warp_native || return 1 ;;
            17) run_menu_action_and_pause setup_psiphon || return 1 ;;
            18) run_menu_action_and_pause check_script_updates || return 1 ;;
            19) run_menu_action_and_pause self_update_script --restart-menu || return 1 ;;
            20) run_menu_action_and_pause uninstall_script || return 1 ;;
            0) return 0 ;;
            *) error "$(t invalid_choice)" || true; read -rp "${PROMPT_PREFIX} $(t press_enter)" || return 1 ;;
        esac
    done
}

show_remnanode_menu() {
    local state

    menu_header "$(t remnanode_menu_title)"
    state="$(remnanode_service_state)"
    echo -e "${MAGENTA}$(t menu_status_title)${NC}"
    remnanode_print_status "$state"
    echo ""
    menu_divider

    case "$state" in
        missing)
            echo -e "${MAGENTA}$(t category_install)${NC}"
            echo -e " ${GREEN}1.${NC} $(t opt_remnanode_install)"
            ;;
        unavailable)
            echo -e "${MAGENTA}$(t category_monitor)${NC}"
            echo -e " ${GREEN}5.${NC} $(t opt_remnanode_status)"
            ;;
        running)
            echo -e "${MAGENTA}$(t category_manage)${NC}"
            echo -e " ${GREEN}3.${NC} $(t opt_remnanode_stop)"
            echo -e " ${GREEN}4.${NC} $(t opt_remnanode_restart)"
            echo -e "${MAGENTA}$(t category_monitor)${NC}"
            echo -e " ${GREEN}5.${NC} $(t opt_remnanode_status)"
            echo -e " ${GREEN}6.${NC} $(t opt_remnanode_logs)"
            echo -e "${MAGENTA}$(t category_updates)${NC}"
            echo -e " ${GREEN}7.${NC} $(t opt_remnanode_update)"
            ;;
        stopped)
            echo -e "${MAGENTA}$(t category_manage)${NC}"
            echo -e " ${GREEN}2.${NC} $(t opt_remnanode_start)"
            echo -e "${MAGENTA}$(t category_monitor)${NC}"
            echo -e " ${GREEN}5.${NC} $(t opt_remnanode_status)"
            echo -e " ${GREEN}6.${NC} $(t opt_remnanode_logs)"
            echo -e "${MAGENTA}$(t category_updates)${NC}"
            echo -e " ${GREEN}7.${NC} $(t opt_remnanode_update)"
            ;;
        restarting)
            echo -e "${MAGENTA}$(t category_manage)${NC}"
            echo -e " ${GREEN}3.${NC} $(t opt_remnanode_stop)"
            echo -e " ${GREEN}4.${NC} $(t opt_remnanode_restart)"
            echo -e "${MAGENTA}$(t category_monitor)${NC}"
            echo -e " ${GREEN}5.${NC} $(t opt_remnanode_status)"
            echo -e " ${GREEN}6.${NC} $(t opt_remnanode_logs)"
            echo -e "${MAGENTA}$(t category_updates)${NC}"
            echo -e " ${GREEN}7.${NC} $(t opt_remnanode_update)"
            ;;
    esac
    echo ""
    menu_divider
    echo -e " ${RED}0.${NC} $(t opt_back)"
    echo ""
}


remnanode_settings_menu() {
    local choice
    while true; do
        show_remnanode_menu
        read -rp "${PROMPT_PREFIX} $(t choose_remnanode_item) " choice || return 1
        echo ""
        case "$choice" in
            1) run_menu_action_and_pause setup_remnanode || return 1 ;;
            2) run_menu_action_and_pause remnanode_start || return 1 ;;
            3) run_menu_action_and_pause remnanode_stop || return 1 ;;
            4) run_menu_action_and_pause remnanode_restart || return 1 ;;
            5) run_menu_action_and_pause remnanode_print_status || return 1 ;;
            6) run_menu_action_and_pause remnanode_logs || return 1 ;;
            7) run_menu_action_and_pause remnanode_update || return 1 ;;
            0) return 0 ;;
            *) error "$(t invalid_choice)" || true; read -rp "${PROMPT_PREFIX} $(t press_enter)" || return 1 ;;
        esac
    done
}


show_selfsteal_menu() {
    local state

    menu_header "$(t selfsteal_menu_title)"
    state="$(selfsteal_service_state)"
    echo -e "${MAGENTA}$(t menu_status_title)${NC}"
    selfsteal_print_status "$state"
    echo ""
    menu_divider

    case "$state" in
        missing)
            echo -e "${MAGENTA}$(t category_install)${NC}"
            echo -e " ${GREEN}1.${NC} $(t opt_selfsteal_install)"
            ;;
        unavailable)
            echo -e "${MAGENTA}$(t category_monitor)${NC}"
            echo -e " ${GREEN}5.${NC} $(t opt_selfsteal_status)"
            ;;
        running)
            echo -e "${MAGENTA}$(t category_manage)${NC}"
            echo -e " ${GREEN}3.${NC} $(t opt_selfsteal_stop)"
            echo -e " ${GREEN}4.${NC} $(t opt_selfsteal_restart)"
            echo -e "${MAGENTA}$(t category_monitor)${NC}"
            echo -e " ${GREEN}5.${NC} $(t opt_selfsteal_status)"
            echo -e " ${GREEN}6.${NC} $(t opt_selfsteal_logs)"
            echo -e " ${GREEN}7.${NC} $(t opt_selfsteal_validate)"
            echo -e "${MAGENTA}$(t category_ssl)${NC}"
            echo -e " ${GREEN}8.${NC} $(t opt_selfsteal_cert)"
            ;;
        partial)
            echo -e "${MAGENTA}$(t category_manage)${NC}"
            echo -e " ${GREEN}2.${NC} $(t opt_selfsteal_start)"
            echo -e " ${GREEN}3.${NC} $(t opt_selfsteal_stop)"
            echo -e " ${GREEN}4.${NC} $(t opt_selfsteal_restart)"
            echo -e "${MAGENTA}$(t category_monitor)${NC}"
            echo -e " ${GREEN}5.${NC} $(t opt_selfsteal_status)"
            echo -e " ${GREEN}6.${NC} $(t opt_selfsteal_logs)"
            echo -e " ${GREEN}7.${NC} $(t opt_selfsteal_validate)"
            echo -e "${MAGENTA}$(t category_ssl)${NC}"
            echo -e " ${GREEN}8.${NC} $(t opt_selfsteal_cert)"
            ;;
        stopped)
            echo -e "${MAGENTA}$(t category_manage)${NC}"
            echo -e " ${GREEN}2.${NC} $(t opt_selfsteal_start)"
            echo -e "${MAGENTA}$(t category_monitor)${NC}"
            echo -e " ${GREEN}5.${NC} $(t opt_selfsteal_status)"
            echo -e " ${GREEN}6.${NC} $(t opt_selfsteal_logs)"
            echo -e " ${GREEN}7.${NC} $(t opt_selfsteal_validate)"
            echo -e "${MAGENTA}$(t category_ssl)${NC}"
            echo -e " ${GREEN}8.${NC} $(t opt_selfsteal_cert)"
            ;;
    esac
    echo ""
    menu_divider
    echo -e " ${RED}0.${NC} $(t opt_back)"
    echo ""
}



selfsteal_settings_menu() {
    local choice
    while true; do
        show_selfsteal_menu
        read -rp "${PROMPT_PREFIX} $(t choose_selfsteal_item) " choice || return 1
        echo ""
        case "$choice" in
            1) run_menu_action_and_pause setup_caddy_selfsteal || return 1 ;;
            2) run_menu_action_and_pause selfsteal_start || return 1 ;;
            3) run_menu_action_and_pause selfsteal_stop || return 1 ;;
            4) run_menu_action_and_pause selfsteal_restart || return 1 ;;
            5) run_menu_action_and_pause selfsteal_print_status || return 1 ;;
            6) run_menu_action_and_pause selfsteal_logs || return 1 ;;
            7) run_menu_action_and_pause selfsteal_validate_config || return 1 ;;
            8) run_menu_action_and_pause selfsteal_print_certificate_details || return 1 ;;
            0) return 0 ;;
            *) error "$(t invalid_choice)" || true; read -rp "${PROMPT_PREFIX} $(t press_enter)" || return 1 ;;
        esac
    done
}



main() {
    local choice
    log "=========================================="
    log "$(t startup_title)"
    log "=========================================="
    while true; do
        show_menu
        read -rp "${PROMPT_PREFIX} $(t choose_item) " choice || return 1
        echo ""
        case "$choice" in
            1) server_settings_menu || continue ;;
            2) remnanode_settings_menu || continue ;;
            3) selfsteal_settings_menu || continue ;;
            4)
                if install_all; then
                    read -rp "${PROMPT_PREFIX} $(t press_enter)" || return 1
                fi
                ;;
            5)
                if selective_install; then
                    read -rp "${PROMPT_PREFIX} $(t press_enter)" || return 1
                fi
                ;;
            0) log "$(t exit_log)"; exit 0 ;;
            *) error "$(t invalid_choice)" || true; read -rp "${PROMPT_PREFIX} $(t press_enter)" || return 1 ;;
        esac
    done
}



show_help() {
    echo "$(t cli_usage_title)"
    echo
    echo "  sudo karenet-setup"
    echo "  sudo karenet-setup remnanode [install|status|start|stop|restart|logs|update]"
    echo "  sudo karenet-setup selfsteal [install|status|start|stop|restart|logs|validate|cert]"
    echo "  sudo karenet-setup firewall status"
    echo "  sudo karenet-setup [check-updates|update|version]"
}

firewall_status() {
    if ! command -v ufw >/dev/null 2>&1; then
        error "$(t ufw_not_found)"
        return 1
    fi
    ufw status verbose
}

cli_remnanode() {
    local action="${1:-}"
    if (($#)); then shift; fi
    if [[ -z "$action" ]]; then
        if ! remnanode_settings_menu; then
            main
        fi
        return 0
    fi
    case "$action" in
        install|configure|setup) (($# == 0)) || { error "$(t cli_unexpected_arguments)"; return 1; }; setup_remnanode ;;
        status) (($# == 0)) || { error "$(t cli_unexpected_arguments)"; return 1; }; remnanode_print_status ;;
        start) (($# == 0)) || { error "$(t cli_unexpected_arguments)"; return 1; }; remnanode_start ;;
        stop) (($# == 0)) || { error "$(t cli_unexpected_arguments)"; return 1; }; remnanode_stop ;;
        restart) (($# == 0)) || { error "$(t cli_unexpected_arguments)"; return 1; }; remnanode_restart ;;
        logs) (($# == 0)) || { error "$(t cli_unexpected_arguments)"; return 1; }; remnanode_logs ;;
        update) (($# == 0)) || { error "$(t cli_unexpected_arguments)"; return 1; }; remnanode_update ;;
        help|-h|--help) show_help ;;
        *) error "$(t cli_unknown_command) $action" || true; show_help; return 2 ;;
    esac
}

cli_selfsteal() {
    local action="${1:-}"
    if (($#)); then shift; fi
    if [[ -z "$action" ]]; then
        if ! selfsteal_settings_menu; then
            main
        fi
        return 0
    fi
    case "$action" in
        install|configure|setup) (($# == 0)) || { error "$(t cli_unexpected_arguments)"; return 1; }; setup_caddy_selfsteal ;;
        status) (($# == 0)) || { error "$(t cli_unexpected_arguments)"; return 1; }; selfsteal_print_status ;;
        start) (($# == 0)) || { error "$(t cli_unexpected_arguments)"; return 1; }; selfsteal_start ;;
        stop) (($# == 0)) || { error "$(t cli_unexpected_arguments)"; return 1; }; selfsteal_stop ;;
        restart) (($# == 0)) || { error "$(t cli_unexpected_arguments)"; return 1; }; selfsteal_restart ;;
        logs) (($# == 0)) || { error "$(t cli_unexpected_arguments)"; return 1; }; selfsteal_logs ;;
        validate) (($# == 0)) || { error "$(t cli_unexpected_arguments)"; return 1; }; selfsteal_validate_config ;;
        cert|certificate) (($# == 0)) || { error "$(t cli_unexpected_arguments)"; return 1; }; selfsteal_print_certificate_details ;;
        help|-h|--help) show_help ;;
        *) error "$(t cli_unknown_command) $action" || true; show_help; return 2 ;;
    esac
}

cli_firewall() {
    local action="${1:-}"
    if (($#)); then shift; fi
    if [[ "$action" == "status" && $# -eq 0 ]]; then
        firewall_status
        return
    fi
    error "$(t cli_unknown_command) firewall ${action:-}" || true
    show_help
    return 2
}

dispatch_cli() {
    local command="${1:-}"
    if (($# == 0)); then
        main
        return
    fi
    if (($#)); then shift; fi

    case "$command" in
        version|--version|-v)
            printf 'KARENET — версия %s\n' "$SCRIPT_VERSION"
            ;;
        help|--help|-h)
            show_help
            ;;
        update|self-update)
            self_update_script
            ;;
        check-updates)
            check_script_updates
            ;;
        remnanode)
            cli_remnanode "$@"
            ;;
        selfsteal)
            cli_selfsteal "$@"
            ;;
        firewall)
            cli_firewall "$@"
            ;;
        *)
            error "$(t cli_unknown_command) $command" || true
            show_help
            return 2
            ;;
    esac
}

# Execute the menu when no arguments are supplied; otherwise dispatch a CLI action.
dispatch_cli "$@"

