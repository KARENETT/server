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

    read -r -s -p "${PROMPT_PREFIX} $(t remnanode_secret_prompt) " secret_key || {
        printf '\n'
        return 1
    }
    printf '\n'
    if ! is_valid_remnanode_secret "$secret_key"; then
        unset secret_key
        error "$(t remnanode_secret_invalid)"
        return 1
    fi

    if ! write_file_atomically "$compose_file" 644 <<EOF
$(render_remnanode_compose)
EOF
    then
        unset secret_key
        return 1
    fi
    if ! write_file_atomically "$env_file" 600 <<EOF
NODE_PORT=$node_port
SECRET_KEY='$secret_key'
EOF
    then
        unset secret_key
        return 1
    fi
    unset secret_key

    if ! docker compose -p remnanode --project-directory "$REMNANODE_DIR" --env-file "$env_file" -f "$compose_file" config --quiet; then
        error "$(t remnanode_compose_invalid)"
        return 1
    fi
    if ! docker compose -p remnanode --project-directory "$REMNANODE_DIR" --env-file "$env_file" -f "$compose_file" pull remnanode; then
        error "$(t remnanode_image_pull_failed)"
        return 1
    fi

    if ! ufw allow from "$panel_ip" to any port "$node_port" proto tcp comment 'remnanode: только панель'; then
        error "$(t remnanode_firewall_rule_failed)"
        return 1
    fi
    if ! write_remnanode_panel_rule "$panel_ip" "$node_port"; then
        remnanode_rollback_panel_rule "$old_panel_ip" "$old_panel_port" "$panel_ip" "$node_port"
        error "$(t remnanode_panel_rule_save_failed)"
        return 1
    fi

    if (( replace_existing )); then
        previous_container="remnanode-previous-$(date +%Y%m%d%H%M%S)-$$"
        if ! docker stop remnanode >/dev/null || ! docker rename remnanode "$previous_container"; then
            docker start remnanode >/dev/null 2>&1 || true
            remnanode_rollback_panel_rule "$old_panel_ip" "$old_panel_port" "$panel_ip" "$node_port"
            error "$(t remnanode_existing_container_failed)"
            return 1
        fi
    fi

    if ! docker compose -p remnanode --project-directory "$REMNANODE_DIR" --env-file "$env_file" -f "$compose_file" up -d remnanode; then
        remnanode_restore_container "$previous_container" "$compose_file" "$env_file" || warning "$(t remnanode_rollback_failed)"
        remnanode_rollback_panel_rule "$old_panel_ip" "$old_panel_port" "$panel_ip" "$node_port"
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
}
