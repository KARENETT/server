#!/bin/bash

is_valid_selfsteal_domain() {
    local domain="${1:-}"
    local hostname_pattern='^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$'

    (( ${#domain} <= 253 )) && [[ "$domain" =~ $hostname_pattern ]]
}

render_selfsteal_caddyfile() {
    local raw_domain="$1"
    local xhttp_domain="$2"

    cat <<EOF
{
    http_port 80
    https_port 9443

    auto_https disable_redirects

    servers {
        protocols h1 h2
    }
}

http://$raw_domain, http://$xhttp_domain {
    redir https://{host}{uri} 301
}

$raw_domain, $xhttp_domain {
    bind 127.0.0.1

    tls {
        protocols tls1.2 tls1.3

        issuer acme {
            disable_tlsalpn_challenge
        }
    }

    root * /srv
    file_server

    header -Server
    header Strict-Transport-Security "max-age=31536000"
}
EOF
}

render_selfsteal_nginx_conf() {
    local raw_domain="$1"
    local xhttp_domain="$2"

    cat <<EOF
worker_processes auto;
pid /var/run/nginx.pid;

events {
    worker_connections 4096;
}

stream {
    map \$ssl_preread_server_name \$backend {
        $raw_domain   127.0.0.1:10443;
        $xhttp_domain 127.0.0.1:10444;
        default       127.0.0.1:10443;
    }

    log_format tcp '\$remote_addr:\$remote_port -> \$upstream_addr '
                   'sni="\$ssl_preread_server_name" '
                   'sent=\$bytes_sent recv=\$bytes_received time=\$session_time';

    access_log /dev/stdout tcp;
    error_log /dev/stderr warn;

    server {
        listen 0.0.0.0:443;

        ssl_preread on;
        proxy_pass \$backend;
        proxy_protocol on;

        proxy_connect_timeout 5s;
        proxy_timeout 1h;
    }
}
EOF
}

render_selfsteal_compose() {
    cat <<'EOF'
services:
  caddy:
    image: caddy:2-alpine
    container_name: caddy
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./caddy:/etc/caddy:ro
      - ./site:/srv:ro
      - caddy_data:/data
      - caddy_config:/config
    logging:
      options:
        max-size: "10m"
        max-file: "3"

  nginx:
    image: nginx:stable-alpine
    container_name: nginx
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    logging:
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  caddy_data:
  caddy_config:
EOF
}

selfsteal_restore_previous_services() {
    local compose_file="$1"
    local web_dir="$2"
    local system_caddy_active="$3"
    local system_caddy_enabled="$4"
    shift 4
    local container

    docker compose -p remnanode-web --project-directory "$web_dir" -f "$compose_file" stop caddy nginx >/dev/null 2>&1 || true
    for container in "$@"; do
        docker start "$container" >/dev/null 2>&1 || warning "$(t caddy_rollback_failed)"
    done
    if (( system_caddy_enabled )); then
        systemctl enable caddy >/dev/null 2>&1 || warning "$(t caddy_rollback_failed)"
    fi
    if (( system_caddy_active )); then
        systemctl start caddy >/dev/null 2>&1 || warning "$(t caddy_rollback_failed)"
    fi
}

setup_caddy_selfsteal() {
    local raw_domain=""
    local xhttp_domain=""
    local asset_path="$SCRIPTS_DIR/assets/selfsteal/index.html"
    local web_dir="$REMNANODE_DIR/web"
    local caddy_dir="$REMNANODE_DIR/web/caddy"
    local nginx_dir="$REMNANODE_DIR/web/nginx"
    local site_dir="$REMNANODE_DIR/web/site"
    local compose_file="$REMNANODE_DIR/web/docker-compose.yml"
    local -a compose_project=()
    local container_name
    local container_ports
    local container_project
    local http_status=""
    local domain
    local system_caddy_active=0
    local system_caddy_enabled=0
    local container_running
    local caddy_listener=""
    local nginx_listener=""
    local -a conflicting_containers=()
    local -a stopped_containers=()
    local -A conflict_seen=()

    log "=========================================="
    log "$(t opt_24)"
    log "=========================================="

    if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
        error "$(t caddy_docker_required)"
        return 1
    fi
    if ! docker info >/dev/null 2>&1; then
        error "$(t caddy_docker_daemon_required)"
        return 1
    fi
    if ! command -v curl >/dev/null 2>&1; then
        error "$(t curl_not_found)"
        return 1
    fi
    if ! command -v ss >/dev/null 2>&1; then
        error "$(t caddy_validation_tools_required)"
        return 1
    fi
    if ! command -v ufw >/dev/null 2>&1; then
        error "$(t caddy_ufw_required)"
        return 1
    fi

    if [[ ! -f "$asset_path" ]]; then
        error "$(t caddy_asset_missing)"
        return 1
    fi

    info "$(t caddy_dns_notice)"
    info "$(t caddy_ports_notice)"
    while true; do
        read -rp "${PROMPT_PREFIX} $(t caddy_raw_domain_prompt) " raw_domain || return 1
        if is_valid_selfsteal_domain "$raw_domain"; then
            break
        fi
        warning "$(t caddy_domain_invalid)"
    done
    while true; do
        read -rp "${PROMPT_PREFIX} $(t caddy_xhttp_domain_prompt) " xhttp_domain || return 1
        if ! is_valid_selfsteal_domain "$xhttp_domain"; then
            warning "$(t caddy_domain_invalid)"
        elif [[ "${raw_domain,,}" == "${xhttp_domain,,}" ]]; then
            warning "$(t caddy_domains_must_differ)"
        else
            break
        fi
    done
    raw_domain="${raw_domain,,}"
    xhttp_domain="${xhttp_domain,,}"

    install -d -o root -g root -m 755 "$caddy_dir" "$nginx_dir" "$site_dir"
    if ! write_file_atomically "$caddy_dir/Caddyfile" 644 <<EOF
$(render_selfsteal_caddyfile "$raw_domain" "$xhttp_domain")
EOF
    then
        return 1
    fi
    if ! write_file_atomically "$nginx_dir/nginx.conf" 644 <<EOF
$(render_selfsteal_nginx_conf "$raw_domain" "$xhttp_domain")
EOF
    then
        return 1
    fi
    if ! write_file_atomically "$compose_file" 644 <<EOF
$(render_selfsteal_compose)
EOF
    then
        return 1
    fi
    install -o root -g root -m 644 "$asset_path" "$site_dir/index.html"

    compose_project=(docker compose -p remnanode-web --project-directory "$web_dir" -f "$compose_file")
    if ! "${compose_project[@]}" config --quiet; then
        error "$(t caddy_compose_invalid)"
        return 1
    fi
    if ! "${compose_project[@]}" run --rm --no-deps --entrypoint caddy caddy validate --config /etc/caddy/Caddyfile; then
        error "$(t caddy_caddyfile_invalid)"
        return 1
    fi
    if ! "${compose_project[@]}" run --rm --no-deps nginx nginx -t -c /etc/nginx/nginx.conf; then
        error "$(t caddy_nginx_config_invalid)"
        return 1
    fi

    while IFS='|' read -r container_name container_ports; do
        [[ -n "$container_name" ]] || continue
        container_project="$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.project" }}' "$container_name" 2>/dev/null || true)"
        if [[ "$container_project" == "remnanode-web" ]]; then
            continue
        fi
        if [[ "$container_name" == "caddy" || "$container_name" == "nginx" ]]; then
            error "$(t caddy_container_name_conflict) $container_name"
            return 1
        fi
        if [[ "$container_ports" == *":80->"* || "$container_ports" == *":443->"* ]]; then
            conflict_seen["$container_name"]=1
        fi
    done < <(docker ps -a --format '{{.Names}}|{{.Ports}}')
    if (( ${#conflict_seen[@]} > 0 )); then
        for container_name in "${!conflict_seen[@]}"; do
            conflicting_containers+=("$container_name")
        done
        info "$(t caddy_container_conflicts) ${conflicting_containers[*]}"
        if ! confirm_yes_no "$(t caddy_container_conflict_prompt)"; then
            return 0
        fi
    fi
    if ! ufw allow 80/tcp comment 'self-steal: HTTP/ACME' ||
        ! ufw allow 443/tcp comment 'self-steal: NGINX' ||
        ! ufw allow 9443/tcp comment 'self-steal: Caddy'; then
        error "$(t caddy_ufw_rules_failed)"
        return 1
    fi
    info "$(t caddy_ufw_rules_added)"

    if command -v systemctl >/dev/null 2>&1; then
        systemctl is-active --quiet caddy && system_caddy_active=1 || true
        systemctl is-enabled --quiet caddy && system_caddy_enabled=1 || true
        if (( system_caddy_active || system_caddy_enabled )); then
            if ! confirm_yes_no "$(t caddy_system_service_prompt)"; then
                return 0
            fi
            if (( system_caddy_active )) && ! systemctl stop caddy; then
                systemctl start caddy >/dev/null 2>&1 || true
                error "$(t caddy_service_stop_failed)"
                return 1
            fi
            if (( system_caddy_enabled )) && ! systemctl disable caddy; then
                if (( system_caddy_active )); then
                    systemctl start caddy >/dev/null 2>&1 || true
                fi
                error "$(t caddy_service_stop_failed)"
                return 1
            fi
        fi
    fi

    for container_name in "${conflicting_containers[@]}"; do
        container_running="$(docker inspect --format '{{.State.Running}}' "$container_name" 2>/dev/null || true)"
        [[ "$container_running" == "true" ]] || continue
        if ! docker stop "$container_name" >/dev/null; then
            selfsteal_restore_previous_services "$compose_file" "$web_dir" "$system_caddy_active" "$system_caddy_enabled" "${stopped_containers[@]}"
            error "$(t caddy_conflict_stop_failed)"
            return 1
        fi
        stopped_containers+=("$container_name")
    done

    if ! "${compose_project[@]}" up -d; then
        selfsteal_restore_previous_services "$compose_file" "$web_dir" "$system_caddy_active" "$system_caddy_enabled" "${stopped_containers[@]}"
        error "$(t caddy_compose_start_failed)"
        return 1
    fi

    for container_name in caddy nginx; do
        container_running="$(docker inspect --format '{{.State.Running}}' "$container_name" 2>/dev/null || true)"
        if [[ "$container_running" != "true" ]]; then
            selfsteal_restore_previous_services "$compose_file" "$web_dir" "$system_caddy_active" "$system_caddy_enabled" "${stopped_containers[@]}"
            error "$(t caddy_compose_start_failed)"
            return 1
        fi
    done
    caddy_listener="$(ss -lntH 'sport = :9443' 2>/dev/null || true)"
    nginx_listener="$(ss -lntH 'sport = :443' 2>/dev/null || true)"
    if [[ -z "$caddy_listener" || -z "$nginx_listener" ]]; then
        selfsteal_restore_previous_services "$compose_file" "$web_dir" "$system_caddy_active" "$system_caddy_enabled" "${stopped_containers[@]}"
        error "$(t caddy_listener_check_failed)"
        return 1
    fi

    for domain in "$raw_domain" "$xhttp_domain"; do
        http_status="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 5 -H "Host: $domain" http://127.0.0.1/ 2>/dev/null || true)"
        if [[ "$http_status" != "301" ]]; then
            selfsteal_restore_previous_services "$compose_file" "$web_dir" "$system_caddy_active" "$system_caddy_enabled" "${stopped_containers[@]}"
            error "$(t caddy_http_smoke_failed)"
            return 1
        fi
    done

    log "$(t caddy_started)"
}
