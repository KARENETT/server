#!/bin/bash

is_valid_remnanode_secret() {
    local secret_key="${1:-}"

    [[ "$secret_key" =~ ^[A-Za-z0-9+/]+={0,2}$ ]] || return 1
    printf '%s' "$secret_key" | base64 --decode >/dev/null 2>&1
}

render_remnanode_compose() {
    cat <<'EOF'
services:
  remnanode:
    container_name: remnanode
    hostname: remnanode
    image: remnawave/node:latest
    network_mode: host
    restart: always
    cap_add:
      - NET_ADMIN
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    environment:
      NODE_PORT: "${NODE_PORT:-30100}"
      SECRET_KEY: "${SECRET_KEY:?Set SECRET_KEY in /opt/remnanode/.env}"
      CUSTOM_CORE_URL: "https://github.com/MakostaDev/UwuRay/releases/latest/download/Xray-linux-64"
    volumes:
      - /var/log/remnanode:/var/log/remnanode
      - /dev/shm:/dev/shm
EOF
}

setup_remnanode_logrotate() {
    local config_file="/etc/logrotate.d/remnanode"

    if ! command -v logrotate >/dev/null 2>&1; then
        if ! command -v apt-get >/dev/null 2>&1; then
            error "$(t remnanode_logrotate_apt_required)"
            return 1
        fi

        info "$(t remnanode_logrotate_installing)"
        if ! apt-get update || ! DEBIAN_FRONTEND=noninteractive apt-get install -y logrotate; then
            error "$(t remnanode_logrotate_install_failed)"
            return 1
        fi
    fi

    if ! install -d -o root -g root -m 755 /etc/logrotate.d; then
        error "$(t remnanode_logrotate_config_write_failed)"
        return 1
    fi
    if ! write_file_atomically "$config_file" 644 <<'EOF'
/var/log/remnanode/*.log {
    size 50M
    rotate 5
    compress
    missingok
    notifempty
    copytruncate
}
EOF
    then
        error "$(t remnanode_logrotate_config_write_failed)"
        return 1
    fi
    if ! logrotate -vf "$config_file"; then
        error "$(t remnanode_logrotate_test_failed)"
        return 1
    fi

    info "$(t remnanode_logrotate_ready)"
}

remnanode_rollback_panel_rule() {
    local old_panel_ip="$1"
    local old_panel_port="$2"
    local new_panel_ip="$3"
    local new_panel_port="$4"

    if [[ "$new_panel_ip" != "$old_panel_ip" || "$new_panel_port" != "$old_panel_port" ]]; then
        remove_remnanode_panel_ufw_rule "$new_panel_ip" "$new_panel_port"
    fi
    if [[ -n "$old_panel_ip" && -n "$old_panel_port" ]]; then
        write_remnanode_panel_rule "$old_panel_ip" "$old_panel_port" || warning "$(t remnanode_panel_rule_save_failed)"
    else
        rm -f -- "$REMNANODE_PANEL_RULE_FILE" "$REMNANODE_PANEL_IP_FILE"
    fi
}

remnanode_restore_container() {
    local previous_container="$1"
    local compose_file="$2"
    local env_file="$3"

    [[ -n "$previous_container" ]] || return 0
    docker compose -p remnanode --project-directory "$REMNANODE_DIR" --env-file "$env_file" -f "$compose_file" rm -sf remnanode >/dev/null 2>&1 || true
    docker rename "$previous_container" remnanode || return 1
    docker start remnanode >/dev/null || return 1
}

remnanode_restore_setup_files() {
    local stage_dir="$1"
    local compose_file="$2"
    local env_file="$3"

    if ! managed_files_restore "$stage_dir/backup" "$compose_file" "$env_file"; then
        warning "$(t remnanode_rollback_failed)"
        info "$(t remnanode_backup_preserved) $stage_dir/backup"
        return 1
    fi
    rm -rf -- "$stage_dir"
}

setup_remnanode() {
    local panel_ip=""
    local node_port=""
    local node_port_input=""
    local node_port_default=""
    local secret_key=""
    local old_panel_ip=""
    local old_panel_port=""
    local existing_project=""
    local previous_container=""
    local replace_existing=0
    local compose_file="$REMNANODE_DIR/docker-compose.yml"
    local env_file="$REMNANODE_DIR/.env"
    local stage_dir=""
    local compose_candidate=""
    local existing_secret=""
    local preserve_secret=0
    local attempt
    local node_listener=""


    log "=========================================="
    log "$(t remnanode_title)"
    log "=========================================="

    if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
        error "$(t remnanode_docker_required)"
        return 1
    fi
    if ! docker info >/dev/null 2>&1; then
        error "$(t remnanode_docker_daemon_required)"
        return 1
    fi
    if ! command -v ufw >/dev/null 2>&1; then
        error "$(t ufw_not_found)"
        return 1
    fi
    if ! command -v python3 >/dev/null 2>&1 || ! command -v base64 >/dev/null 2>&1 || ! command -v ss >/dev/null 2>&1; then
        error "$(t remnanode_validation_tools_required)"
        return 1
    fi

    read_remnanode_panel_rule old_panel_ip old_panel_port
    if [[ -n "$old_panel_ip" ]] && ! is_valid_ip_address "$old_panel_ip"; then
        old_panel_ip=""
        old_panel_port=""
    fi
    if ! is_valid_tcp_port "$old_panel_port"; then
        old_panel_port="$REMNANODE_NODE_PORT"
    fi
    old_panel_port=$((10#$old_panel_port))

    if docker container inspect remnanode >/dev/null 2>&1; then
        existing_project="$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.project" }}' remnanode 2>/dev/null || true)"
        if [[ "$existing_project" != "remnanode" ]]; then
            warning "$(t remnanode_existing_container_warning)"
            if ! confirm_yes_no "$(t remnanode_replace_prompt)"; then
                info "$(t remnanode_cancelled)"
                return 0
            fi
            replace_existing=1
        fi
    fi

    while true; do
        read -rp "${PROMPT_PREFIX} $(t remnanode_panel_ip_prompt) " panel_ip || return 1
        if is_valid_ip_address "$panel_ip"; then
            break
        fi
        warning "$(t remnanode_panel_ip_invalid)"
    done

    node_port_default="$REMNANODE_NODE_PORT"
    if [[ -n "$old_panel_ip" ]]; then
        node_port_default="$old_panel_port"
    fi
    while true; do
        read -rp "${PROMPT_PREFIX} $(t remnanode_node_port_prompt) [$node_port_default]: " node_port_input || return 1
        node_port_input="${node_port_input:-$node_port_default}"
        if is_valid_tcp_port "$node_port_input"; then
            node_port=$((10#$node_port_input))
            break
        fi
        warning "$(t remnanode_node_port_invalid)"
    done
    if ! install -d -o root -g root -m 755 "$REMNANODE_DIR" /var/log/remnanode; then
        error "$(t remnanode_log_directory_failed)"
        return 1
    fi
    if ! setup_remnanode_logrotate; then
        return 1
    fi

    remnanode_read_env_value existing_secret SECRET_KEY "$env_file"
    if is_valid_remnanode_secret "$existing_secret"; then
        secret_key="$existing_secret"
        preserve_secret=1
        info "$(t remnanode_secret_preserved)"
    else
        read -r -s -p "${PROMPT_PREFIX} $(t remnanode_secret_prompt) " secret_key || {
            printf '\n'
            return 1
        }
        printf '\n'
        if ! is_valid_remnanode_secret "$secret_key"; then
            unset secret_key existing_secret
            error "$(t remnanode_secret_invalid)"
            return 1
        fi
    fi


    stage_dir="$(mktemp -d "$REMNANODE_DIR/.setup.XXXXXX")" || {
        unset secret_key existing_secret
        error "$(t remnanode_stage_failed)"
        return 1
    }
    compose_candidate="$stage_dir/docker-compose.yml"
    if ! render_remnanode_compose > "$compose_candidate"; then
        rm -rf -- "$stage_dir"
        unset secret_key existing_secret
        error "$(t remnanode_stage_failed)"
        return 1
    fi
    if ! managed_file_is_safe "$compose_file" "$compose_candidate"; then
        managed_file_save_candidate "$compose_file" "$compose_candidate" 644 || true
        rm -rf -- "$stage_dir"
        unset secret_key existing_secret
        error "$(t managed_config_manual_abort)"
        return 1
    fi
    if ! managed_files_snapshot "$stage_dir/backup" "$compose_file" "$env_file"; then
        rm -rf -- "$stage_dir"
        unset secret_key existing_secret
        error "$(t remnanode_backup_failed)"
        return 1
    fi
    if ! managed_file_commit "$compose_file" 644 "$compose_candidate" ||
        ! write_remnanode_env "$env_file" "$node_port" "$secret_key" "$preserve_secret"; then
        remnanode_restore_setup_files "$stage_dir" "$compose_file" "$env_file" || true
        unset secret_key existing_secret
        return 1
    fi
    unset secret_key existing_secret


    if ! docker compose -p remnanode --project-directory "$REMNANODE_DIR" --env-file "$env_file" -f "$compose_file" config --quiet; then
        remnanode_restore_setup_files "$stage_dir" "$compose_file" "$env_file" || true
        error "$(t remnanode_compose_invalid)"
        return 1
    fi
    if ! docker compose -p remnanode --project-directory "$REMNANODE_DIR" --env-file "$env_file" -f "$compose_file" pull remnanode; then
        remnanode_restore_setup_files "$stage_dir" "$compose_file" "$env_file" || true
        error "$(t remnanode_image_pull_failed)"
        return 1
    fi


    if ! ufw allow from "$panel_ip" to any port "$node_port" proto tcp comment 'remnanode: только панель'; then
        remnanode_restore_setup_files "$stage_dir" "$compose_file" "$env_file" || true
        error "$(t remnanode_firewall_rule_failed)"
        return 1
    fi
    if ! write_remnanode_panel_rule "$panel_ip" "$node_port"; then
        remnanode_rollback_panel_rule "$old_panel_ip" "$old_panel_port" "$panel_ip" "$node_port"
        remnanode_restore_setup_files "$stage_dir" "$compose_file" "$env_file" || true
        error "$(t remnanode_panel_rule_save_failed)"
        return 1
    fi


    if (( replace_existing )); then
        previous_container="remnanode-previous-$(date +%Y%m%d%H%M%S)-$$"
        if ! docker stop remnanode >/dev/null || ! docker rename remnanode "$previous_container"; then
            docker start remnanode >/dev/null 2>&1 || true
            remnanode_rollback_panel_rule "$old_panel_ip" "$old_panel_port" "$panel_ip" "$node_port"
            remnanode_restore_setup_files "$stage_dir" "$compose_file" "$env_file" || true
            error "$(t remnanode_existing_container_failed)"
            return 1
        fi
    fi



    if ! docker compose -p remnanode --project-directory "$REMNANODE_DIR" --env-file "$env_file" -f "$compose_file" up -d remnanode; then
        remnanode_restore_container "$previous_container" "$compose_file" "$env_file" || warning "$(t remnanode_rollback_failed)"
        remnanode_rollback_panel_rule "$old_panel_ip" "$old_panel_port" "$panel_ip" "$node_port"
        remnanode_restore_setup_files "$stage_dir" "$compose_file" "$env_file" || true
        error "$(t remnanode_start_failed)"
        return 1
    fi


    for ((attempt = 0; attempt < 10; attempt++)); do
        if [[ "$(docker inspect --format '{{.State.Running}}' remnanode 2>/dev/null || true)" == "true" ]]; then
            node_listener="$(ss -lntH "sport = :$node_port" 2>/dev/null || true)"
            if [[ -n "$node_listener" ]]; then
                break
            fi
        fi
        sleep 1
    done
    if [[ "$(docker inspect --format '{{.State.Running}}' remnanode 2>/dev/null || true)" != "true" || -z "$node_listener" ]]; then
        remnanode_restore_container "$previous_container" "$compose_file" "$env_file" || warning "$(t remnanode_rollback_failed)"
        remnanode_rollback_panel_rule "$old_panel_ip" "$old_panel_port" "$panel_ip" "$node_port"
        remnanode_restore_setup_files "$stage_dir" "$compose_file" "$env_file" || true
        error "$(t remnanode_start_failed)"
        return 1
    fi



    if [[ -n "$previous_container" ]]; then
        docker rm "$previous_container" >/dev/null || warning "$(t remnanode_previous_container_cleanup_failed)"
    fi
    if [[ -n "$old_panel_ip" && ( "$old_panel_ip" != "$panel_ip" || "$old_panel_port" != "$node_port" ) ]]; then
        remove_remnanode_panel_ufw_rule "$old_panel_ip" "$old_panel_port" || warning "$(t remnanode_old_firewall_rule_cleanup_failed)"
    fi

    log "$(t remnanode_done)"
    rm -rf -- "$stage_dir"
}
remnanode_compose() {
    docker compose -p remnanode \
        --project-directory "$REMNANODE_DIR" \
        --env-file "$REMNANODE_DIR/.env" \
        -f "$REMNANODE_DIR/docker-compose.yml" "$@"
}

remnanode_service_state() {
    local status

    if [[ ! -f "$REMNANODE_DIR/docker-compose.yml" || ! -f "$REMNANODE_DIR/.env" ]]; then
        printf 'missing'
        return 0
    fi
    if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
        printf 'unavailable'
        return 0
    fi
    if ! docker container inspect remnanode >/dev/null 2>&1; then
        printf 'stopped'
        return 0
    fi

    status="$(docker inspect --format '{{.State.Status}}' remnanode 2>/dev/null || true)"
    case "$status" in
        running) printf 'running' ;;
        restarting) printf 'restarting' ;;
        *) printf 'stopped' ;;
    esac
}

remnanode_read_env_value() {
    local output_variable="$1"
    local key="$2"
    local env_file="${3:-$REMNANODE_DIR/.env}"
    local line value=""
    local first last

    if [[ -r "$env_file" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" == "$key="* ]]; then
                value="${line#*=}"
                break
            fi
        done < "$env_file"
    fi

    if ((${#value} >= 2)); then
        first="${value:0:1}"
        last="${value: -1}"
        if [[ ( "$first" == "'" && "$last" == "'" ) || ( "$first" == '"' && "$last" == '"' ) ]]; then
            value="${value:1:${#value}-2}"
        fi
    fi
    printf -v "$output_variable" '%s' "$value"
}

write_remnanode_env() {
    local env_file="$1"
    local node_port="$2"
    local secret_key="$3"
    local preserve_secret="$4"
    local temporary_file line found_port=0 found_secret=0

    temporary_file="$(mktemp "${env_file}.XXXXXX")" || return 1
    if [[ -r "$env_file" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            case "$line" in
                NODE_PORT=*)
                    if (( ! found_port )); then
                        printf 'NODE_PORT=%s\n' "$node_port" >> "$temporary_file"
                        found_port=1
                    fi
                    ;;
                SECRET_KEY=*)
                    if (( ! found_secret )); then
                        if (( preserve_secret )); then
                            printf '%s\n' "$line" >> "$temporary_file"
                        else
                            printf "SECRET_KEY='%s'\n" "$secret_key" >> "$temporary_file"
                        fi
                        found_secret=1
                    fi
                    ;;
                *) printf '%s\n' "$line" >> "$temporary_file" ;;
            esac
        done < "$env_file"
    fi

    if (( ! found_port )); then
        printf 'NODE_PORT=%s\n' "$node_port" >> "$temporary_file"
    fi
    if (( ! found_secret )); then
        printf "SECRET_KEY='%s'\n" "$secret_key" >> "$temporary_file"
    fi

    if ! write_file_atomically "$env_file" 600 < "$temporary_file"; then
        rm -f -- "$temporary_file"
        return 1
    fi
    rm -f -- "$temporary_file"
}

remnanode_read_component_version() {
    docker exec remnanode node -e '
        const fs = require("fs");
        const valid = value => typeof value === "string" &&
            /^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$/.test(value);
        let version;
        try {
            version = JSON.parse(fs.readFileSync("package.json", "utf8")).version;
        } catch {}
        if (!valid(version)) {
            try {
                const bundle = fs.readFileSync("dist/main.js", "utf8");
                const match = bundle.match(/Remnawave Node v(?:["\x27`]\s*(?:\.concat\(\s*|\+\s*)["\x27`])?([0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?)/);
                version = match && match[1];
            } catch {}
        }
        if (!valid(version)) process.exit(1);
        process.stdout.write(version);
    ' 2>/dev/null
}

remnanode_read_xray_version() {
    local output=""

    output="$(docker exec remnanode xray version 2>/dev/null | head -n 1 || true)"
    if [[ -z "$output" ]]; then
        output="$(docker exec remnanode /usr/local/bin/xray version 2>/dev/null | head -n 1 || true)"
    fi
    [[ -n "$output" ]] || return 1
    printf '%s\n' "$output" | awk '{print $2}'
}

remnanode_print_status() {
    local state port image node_version xray_version

    state="$(remnanode_service_state)"
    printf '  %s %s\n' "$(t remnanode_state_label)" "$(t "status_${state}")"
    [[ "$state" != "missing" && "$state" != "unavailable" ]] || return 0

    remnanode_read_env_value port NODE_PORT
    if ! is_valid_tcp_port "$port"; then
        port="$REMNANODE_NODE_PORT"
    fi
    printf '  %s %s/tcp\n' "$(t remnanode_port_label)" "$port"

    image="$(docker inspect --format '{{.Config.Image}}' remnanode 2>/dev/null || true)"
    if [[ -z "$image" ]]; then
        image="$(awk '$1 == "image:" { print $2; exit }' "$REMNANODE_DIR/docker-compose.yml" 2>/dev/null || true)"
    fi
    printf '  %s %s\n' "$(t remnanode_image_label)" "${image:-unknown}"

    if [[ "$state" == "running" ]]; then
        node_version="$(remnanode_read_component_version 2>/dev/null || true)"
        xray_version="$(remnanode_read_xray_version 2>/dev/null || true)"
    else
        node_version=""
        xray_version=""
    fi
    printf '  %s %s\n' "$(t remnanode_version_label)" "${node_version:-$(t status_unknown)}"
    printf '  %s %s\n' "$(t remnanode_xray_version_label)" "${xray_version:-$(t status_unknown)}"
}

remnanode_validate_compose() {
    if ! remnanode_compose config --quiet; then
        error "$(t remnanode_compose_invalid)"
        return 1
    fi
}

remnanode_start() {
    local state
    state="$(remnanode_service_state)"
    if [[ "$state" == "missing" ]]; then
        error "$(t remnanode_not_installed)"
        return 1
    fi
    if [[ "$state" == "unavailable" ]]; then
        error "$(t remnanode_docker_daemon_required)"
        return 1
    fi
    if [[ "$state" == "running" ]]; then
        info "$(t remnanode_already_running)"
        return 0
    fi
    remnanode_validate_compose || return 1
    remnanode_compose up -d remnanode || {
        error "$(t remnanode_start_failed)"
        return 1
    }
    if [[ "$(remnanode_service_state)" != "running" ]]; then
        error "$(t remnanode_start_failed)"
        return 1
    fi
    log "$(t remnanode_started)"
}

remnanode_stop() {
    local state
    state="$(remnanode_service_state)"
    if [[ "$state" == "missing" ]]; then
        error "$(t remnanode_not_installed)"
        return 1
    fi
    if [[ "$state" == "unavailable" ]]; then
        error "$(t remnanode_docker_daemon_required)"
        return 1
    fi
    if [[ "$state" == "stopped" ]]; then
        info "$(t remnanode_already_stopped)"
        return 0
    fi
    remnanode_compose stop remnanode || return 1
    log "$(t remnanode_stopped)"
}

remnanode_restart() {
    local state
    state="$(remnanode_service_state)"
    if [[ "$state" == "missing" ]]; then
        error "$(t remnanode_not_installed)"
        return 1
    fi
    if [[ "$state" == "unavailable" ]]; then
        error "$(t remnanode_docker_daemon_required)"
        return 1
    fi
    remnanode_validate_compose || return 1
    remnanode_compose up -d --force-recreate remnanode || {
        error "$(t remnanode_start_failed)"
        return 1
    }
    if [[ "$(remnanode_service_state)" != "running" ]]; then
        error "$(t remnanode_start_failed)"
        return 1
    fi
    log "$(t remnanode_restarted)"
}

remnanode_logs() {
    if [[ ! -f "$REMNANODE_DIR/docker-compose.yml" ]]; then
        error "$(t remnanode_not_installed)"
        return 1
    fi
    remnanode_compose logs --tail 100 remnanode
}

remnanode_update() {
    if [[ "$(remnanode_service_state)" == "missing" ]]; then
        error "$(t remnanode_not_installed)"
        return 1
    fi
    if [[ "$(remnanode_service_state)" == "unavailable" ]]; then
        error "$(t remnanode_docker_daemon_required)"
        return 1
    fi
    remnanode_validate_compose || return 1
    remnanode_compose pull remnanode || {
        error "$(t remnanode_image_pull_failed)"
        return 1
    }
    remnanode_compose up -d remnanode || {
        error "$(t remnanode_start_failed)"
        return 1
    }
    if [[ "$(remnanode_service_state)" != "running" ]]; then
        error "$(t remnanode_start_failed)"
        return 1
    fi
    log "$(t remnanode_updated)"
}
