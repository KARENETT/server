#!/bin/bash
# Строгий режим выполнения
set -euo pipefail
IFS=$'\n\t'

# Получение директории скриптов
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_VERSION="1.0.0"
LANGUAGE="${LANGUAGE:-}"
INSTALL_DIR="/opt/karenet-setup"
SHORTCUT_PATH="/usr/local/bin/karenet-setup"

# Доступ только для суперпользователя
if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] Требуются права суперпользователя. Запустите: sudo bash setup.sh"
    exit 1
fi

ensure_global_install() {
    local source_dir target_dir
    mkdir -p "$INSTALL_DIR"
    source_dir="$(realpath "$SCRIPT_DIR")"
    target_dir="$(realpath "$INSTALL_DIR")"

    if [[ "$source_dir" != "$target_dir" ]]; then
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
source "$SCRIPT_DIR/translation/en.sh"

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
source "$MODULES_DIR/network_tweaks.sh"
source "$MODULES_DIR/trafficguard.sh"
source "$MODULES_DIR/warp_native.sh"

# Функция установки всего
install_all() {
    log "=========================================="
    log "$(t install_all_title)"
    log "=========================================="

    check_internet || return 1

    update_system
    setup_xanmod
    setup_swap
    setup_ulimits
    install_packages
    setup_ssh
    setup_firewall
    setup_trafficguard
    setup_zsh
    setup_nodejs
    setup_uv
    setup_docker
    setup_sysctl_hardening
    setup_tcp_fastopen
    setup_mss_clamp

    mkdir -p ~/projects ~/scripts ~/downloads ~/backup && check_success "$(t install_dirs_created)"

    log "=========================================="
    log "$(t install_all_done)"
    log "=========================================="
    echo ""
    info "$(t post_steps_title)"
    echo "1. $(t post_step_shell)"
    echo "2. $(t post_step_docker)"
    echo ""
    if confirm_yes_no "$(t reboot_confirm)"; then
        log "$(t rebooting)"
        reboot
    else
        log "$(t reboot_cancelled)"
        info "$(t apply_changes_hint)"
    fi
}

selective_install() {
    local selected raw item
    local -A seen=()

    clear
    print_logo
    echo -e "${GRAY}────────────────────────────────────────────────────────────────────────────────${NC}"
    echo ""
    echo -e "${YELLOW}$(t selective_title)${NC}"
    echo -e " ${GREEN}3.${NC} $(t opt_3)"
    echo -e " ${GREEN}4.${NC} $(t opt_4)"
    echo -e " ${GREEN}5.${NC} $(t opt_5)"
    echo -e " ${GREEN}6.${NC} $(menu_option_text 6)"
    echo -e " ${GREEN}7.${NC} $(menu_option_text 7)"
    echo -e " ${GREEN}8.${NC} $(t opt_8)"
    echo -e " ${GREEN}9.${NC} $(menu_option_text 9)"
    echo -e " ${GREEN}10.${NC} $(menu_option_text 10)"
    echo -e " ${GREEN}11.${NC} $(t opt_11)"
    echo -e " ${GREEN}12.${NC} $(t opt_12)"
    echo -e " ${GREEN}13.${NC} $(t opt_13)"
    echo -e " ${GREEN}14.${NC} $(t opt_14)"
    echo -e " ${GREEN}15.${NC} $(t opt_15)"
    echo -e " ${GREEN}16.${NC} $(menu_option_text 16)"
    echo -e " ${GREEN}17.${NC} $(menu_option_text 17)"
    echo -e " ${GREEN}18.${NC} $(menu_option_text 18)"
    echo -e " ${GREEN}21.${NC} $(menu_option_text 21)"
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
            3) add_user ;;
            4) update_system ;;
            5) install_packages ;;
            6) toggle_swap ;;
            7) toggle_ulimits ;;
            8) setup_ssh ;;
            9) toggle_firewall ;;
            10) setup_trafficguard ;;
            11) setup_zsh ;;
            12) setup_nodejs ;;
            13) setup_uv ;;
            14) setup_docker ;;
            15) setup_xanmod ;;
            16) toggle_sysctl_hardening ;;
            17) toggle_tcp_fastopen ;;
            18) toggle_mss_clamp ;;
            21) setup_warp_native ;;
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
is_sysctl_hardening_enabled() { [[ -f /etc/sysctl.d/99-server-opt.conf ]]; }
is_tfo_enabled() { [[ -f /etc/sysctl.d/98-karenet-tfo.conf ]] || [[ "$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null || echo 0)" == "3" ]]; }
is_mss_clamp_enabled() { systemctl is-enabled --quiet karenet-mss-clamp.service 2>/dev/null || [[ -f /etc/systemd/system/karenet-mss-clamp.service ]]; }
is_trafficguard_enabled() { is_trafficguard_installed; }
is_warp_native_enabled() { is_warp_native_installed; }

toggle_swap() { if is_swap_enabled; then disable_swap; else setup_swap; fi; }
toggle_ulimits() { if is_ulimits_enabled; then disable_ulimits; else setup_ulimits; fi; }
toggle_firewall() { if is_firewall_enabled; then disable_firewall; else setup_firewall; fi; }
toggle_sysctl_hardening() { if is_sysctl_hardening_enabled; then disable_sysctl_hardening; else setup_sysctl_hardening; fi; }
toggle_tcp_fastopen() { if is_tfo_enabled; then disable_tcp_fastopen; else setup_tcp_fastopen; fi; }
toggle_mss_clamp() { if is_mss_clamp_enabled; then disable_mss_clamp; else setup_mss_clamp; fi; }

menu_option_text() {
    local option="$1"
    case "$option" in
        6) if is_swap_enabled; then t opt_6_disable; else t opt_6; fi ;;
        7) if is_ulimits_enabled; then t opt_7_disable; else t opt_7; fi ;;
        9) if is_firewall_enabled; then t opt_9_disable; else t opt_9; fi ;;
        10) if is_trafficguard_enabled; then t opt_10_installed; else t opt_10; fi ;;
        16) if is_sysctl_hardening_enabled; then t opt_16_disable; else t opt_16; fi ;;
        17) if is_tfo_enabled; then t opt_17_disable; else t opt_17; fi ;;
        18) if is_mss_clamp_enabled; then t opt_18_disable; else t opt_18; fi ;;
        21) if is_warp_native_enabled; then t opt_21_installed; else t opt_21; fi ;;
        *) t "opt_${option}" ;;
    esac
}

check_script_updates() {
    if ! command -v git >/dev/null 2>&1; then
        error "$(t git_not_found)"
        return 1
    fi

    if ! git -C "$INSTALL_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        warning "$(t updates_no_repo)"
        return 0
    fi

    local branch local_sha remote_sha
    branch="$(git -C "$INSTALL_DIR" rev-parse --abbrev-ref HEAD)"

    git -C "$INSTALL_DIR" fetch origin "$branch" >/dev/null 2>&1 || {
        error "$(t updates_fetch_failed)"
        return 1
    }

    local_sha="$(git -C "$INSTALL_DIR" rev-parse HEAD)"
    remote_sha="$(git -C "$INSTALL_DIR" rev-parse "origin/$branch")"

    if [[ "$local_sha" == "$remote_sha" ]]; then
        info "$(t updates_ok)"
    else
        warning "$(t updates_available)"
        info "$(t updates_hint)"
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
    if ! command -v git >/dev/null 2>&1; then
        error "$(t git_not_found)"
        return 1
    fi

    if ! git -C "$INSTALL_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        warning "$(t updates_no_repo)"
        return 0
    fi

    local branch
    branch="$(git -C "$INSTALL_DIR" rev-parse --abbrev-ref HEAD)"
    log "$(t updates_run)"

    git -C "$INSTALL_DIR" fetch origin "$branch" && git -C "$INSTALL_DIR" pull --ff-only origin "$branch" || {
        error "$(t updates_fetch_failed)"
        return 1
    }

    exec "$INSTALL_DIR/setup.sh"
}

set_language() {
    if [[ -n "$LANGUAGE" ]]; then
        return
    fi

    if [[ "${LANG:-}" == ru* || "${LC_ALL:-}" == ru* ]]; then
        LANGUAGE="ru"
    else
        LANGUAGE="en"
    fi

    clear
    echo "🌐 Select language / Выберите язык:"
    echo " 1) 🇷🇺 Русский"
    echo " 2) 🇬🇧 English"
    read -rp "${PROMPT_PREFIX} Choice [1/2, default ${LANGUAGE^^}]: " lang_choice

    case "$lang_choice" in
        1) LANGUAGE="ru" ;;
        2) LANGUAGE="en" ;;
    esac
}

t() {
    local key="$1"
    if [[ "$LANGUAGE" == "ru" ]]; then
        translate_ru "$key"
    else
        translate_en "$key"
    fi
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
KARENET SERVER SETUP
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

show_menu() {
    local divider="────────────────────────────────────────────────────────────────────────────────"

    clear
    print_logo
    echo -e "${GRAY}${divider}${NC}"
    echo ""
    echo -e "${MAGENTA}$(t category_quick)${NC}"
    echo -e " ${GREEN}1.${NC} $(t opt_1)"
    echo -e " ${GREEN}2.${NC} $(t opt_2)"
    echo ""
    echo -e "${MAGENTA}$(t category_system)${NC}"
    echo -e " ${GREEN}3.${NC} $(t opt_3)"
    echo -e " ${GREEN}4.${NC} $(t opt_4)"
    echo -e " ${GREEN}5.${NC} $(t opt_5)"
    echo -e " ${GREEN}6.${NC} $(menu_option_text 6)"
    echo -e " ${GREEN}7.${NC} $(menu_option_text 7)"
    echo ""
    echo -e "${MAGENTA}$(t category_security)${NC}"
    echo -e " ${GREEN}8.${NC} $(t opt_8)"
    echo -e " ${GREEN}9.${NC} $(menu_option_text 9)"
    echo -e " ${GREEN}10.${NC} $(menu_option_text 10)"
    echo ""
    echo -e "${MAGENTA}$(t category_dev)${NC}"
    echo -e " ${GREEN}11.${NC} $(t opt_11)"
    echo -e " ${GREEN}12.${NC} $(t opt_12)"
    echo -e " ${GREEN}13.${NC} $(t opt_13)"
    echo -e " ${GREEN}14.${NC} $(t opt_14)"
    echo ""
    echo -e "${MAGENTA}$(t category_performance)${NC}"
    echo -e " ${GREEN}15.${NC} $(t opt_15)"
    echo -e " ${GREEN}16.${NC} $(menu_option_text 16)"
    echo -e " ${GREEN}17.${NC} $(menu_option_text 17)"
    echo -e " ${GREEN}18.${NC} $(menu_option_text 18)"
    echo ""
    echo -e "${MAGENTA}$(t category_misc)${NC}"
    echo -e " ${GREEN}19.${NC} $(t opt_19)"
    echo -e " ${GREEN}20.${NC} $(t opt_20)"
    echo -e " ${GREEN}21.${NC} $(menu_option_text 21)"
    echo -e " ${GREEN}22.${NC} $(t opt_22)"
    echo ""
    echo -e "${GRAY}${divider}${NC}"
    echo -e " ${RED}0.${NC} $(t opt_0)"
    echo -e " - $(t quick_launch): ${RED}${BOLD}karenet-setup${NC}"
    echo ""
}

# Основной цикл программы (без изменений)
main() {
    set_language
    log "=========================================="
    log "$(t startup_title)"
    log "=========================================="
    while true; do
        show_menu
        read -rp "${PROMPT_PREFIX} $(t choose_item) " choice
        echo ""
        case $choice in
            1) install_all ;;
            2) selective_install ;;
            3) add_user ;;
            4) update_system ;;
            5) install_packages ;;
            6) toggle_swap ;;
            7) toggle_ulimits ;;
            8) setup_ssh ;;
            9) toggle_firewall ;;
            10) setup_trafficguard ;;
            11) setup_zsh ;;
            12) setup_nodejs ;;
            13) setup_uv ;;
            14) setup_docker ;;
            15) setup_xanmod ;;
            16) toggle_sysctl_hardening ;;
            17) toggle_tcp_fastopen ;;
            18) toggle_mss_clamp ;;
            19) check_script_updates ;;
            20) uninstall_script ;;
            21) setup_warp_native ;;
            22) self_update_script ;;
            0) log "$(t exit_log)"; exit 0 ;;
            *) error "$(t invalid_choice)" ;;
        esac
        echo ""
        read -rp "${PROMPT_PREFIX} $(t press_enter)"
    done
}

# Запуск основной функции
main
