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
name: remnanode-web

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

selfsteal_template_asset() {
    case "${1:-}" in
        1) printf '%s\n' "$SCRIPTS_DIR/assets/selfsteal/index.html" ;;
        2) printf '%s\n' "$SCRIPTS_DIR/assets/selfsteal/speedtest/index.html" ;;
        *) return 1 ;;
    esac
}

selfsteal_restore_previous_services() {
    local web_dir="$1"
    local system_caddy_active="$2"
    local system_caddy_enabled="$3"
    shift 3
    local container

    (cd "$web_dir" && docker compose stop caddy nginx) >/dev/null 2>&1 || true
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

selfsteal_rollback_setup_config() {
    local stage_dir="$1"
    shift

    if ! managed_files_restore "$stage_dir/backup" "$@"; then
        warning "$(t caddy_rollback_failed)"
        info "$(t caddy_backup_preserved) $stage_dir/backup"
        return 1
    fi
    rm -rf -- "$stage_dir"
}

setup_caddy_selfsteal() {
    local raw_domain=""
    local xhttp_domain=""
    local asset_path=""
    local template_choice="1"
    local web_dir="$REMNANODE_DIR/web"
    local caddy_dir="$REMNANODE_DIR/web/caddy"
    local nginx_dir="$REMNANODE_DIR/web/nginx"
    local site_dir="$REMNANODE_DIR/web/site"
    local compose_file="$REMNANODE_DIR/web/docker-compose.yml"
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
    local stage_dir=""
    local config_conflict=0
    local config_index
    local -a config_targets=()
    local -a config_candidates=()


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
    if [[ ! -f "$site_dir/index.html" ]]; then
        info "$(t caddy_template_prompt)"
        printf '  1) %s\n' "$(t caddy_template_veilstore)"
        printf '  2) %s\n' "$(t caddy_template_speedtest)"
        while true; do
            read -rp "${PROMPT_PREFIX} $(t caddy_template_choice_prompt) " template_choice || return 1
            template_choice="${template_choice:-1}"
            if asset_path="$(selfsteal_template_asset "$template_choice")"; then
                break
            fi
            warning "$(t caddy_template_invalid)"
        done
        if [[ ! -f "$asset_path" ]]; then
            error "$(t caddy_asset_missing)"
            return 1
        fi
    else
        info "$(t caddy_site_preserved)"
    fi

    install -d -o root -g root -m 755 "$caddy_dir" "$nginx_dir" "$site_dir"
    stage_dir="$(mktemp -d "$web_dir/.setup.XXXXXX")" || {
        error "$(t caddy_stage_failed)"
        return 1
    }
    config_targets=("$caddy_dir/Caddyfile" "$nginx_dir/nginx.conf" "$compose_file")
    config_candidates=("$stage_dir/Caddyfile" "$stage_dir/nginx.conf" "$stage_dir/docker-compose.yml")
    if ! render_selfsteal_caddyfile "$raw_domain" "$xhttp_domain" > "${config_candidates[0]}" ||
        ! render_selfsteal_nginx_conf "$raw_domain" "$xhttp_domain" > "${config_candidates[1]}" ||
        ! render_selfsteal_compose > "${config_candidates[2]}"; then
        rm -rf -- "$stage_dir"
        error "$(t caddy_stage_failed)"
        return 1
    fi
    for config_index in "${!config_targets[@]}"; do
        if ! managed_file_is_safe "${config_targets[$config_index]}" "${config_candidates[$config_index]}"; then
            config_conflict=1
            managed_file_save_candidate "${config_targets[$config_index]}" "${config_candidates[$config_index]}" 644 || true
        fi
    done
    if (( config_conflict )); then
        rm -rf -- "$stage_dir"
        error "$(t managed_config_manual_abort)"
        return 1
    fi
    if ! managed_files_snapshot "$stage_dir/backup" "${config_targets[@]}"; then
        rm -rf -- "$stage_dir"
        error "$(t caddy_backup_failed)"
        return 1
    fi
    for config_index in "${!config_targets[@]}"; do
        if ! managed_file_commit "${config_targets[$config_index]}" 644 "${config_candidates[$config_index]}"; then
            selfsteal_rollback_setup_config "$stage_dir" "${config_targets[@]}" || true
            error "$(t caddy_config_write_failed)"
            return 1
        fi
    done
    if [[ ! -f "$site_dir/index.html" ]] && ! install -o root -g root -m 644 "$asset_path" "$site_dir/index.html"; then
        selfsteal_rollback_setup_config "$stage_dir" "${config_targets[@]}" || true
        error "$(t caddy_asset_install_failed)"
        return 1
    fi

    if ! selfsteal_validate_config; then
        selfsteal_rollback_setup_config "$stage_dir" "${config_targets[@]}" || true
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
            selfsteal_rollback_setup_config "$stage_dir" "${config_targets[@]}" || true
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
            selfsteal_rollback_setup_config "$stage_dir" "${config_targets[@]}" || true
            return 0
        fi

    fi
    if ! ufw allow 80/tcp comment 'self-steal: HTTP/ACME' ||
        ! ufw allow 443/tcp comment 'self-steal: NGINX' ||
        ! ufw allow 9443/tcp comment 'self-steal: Caddy'; then
        selfsteal_rollback_setup_config "$stage_dir" "${config_targets[@]}" || true
        error "$(t caddy_ufw_rules_failed)"
        return 1
    fi
    info "$(t caddy_ufw_rules_added)"


    if command -v systemctl >/dev/null 2>&1; then
        systemctl is-active --quiet caddy && system_caddy_active=1 || true
        systemctl is-enabled --quiet caddy && system_caddy_enabled=1 || true
        if (( system_caddy_active || system_caddy_enabled )); then
            if ! confirm_yes_no "$(t caddy_system_service_prompt)"; then
                selfsteal_rollback_setup_config "$stage_dir" "${config_targets[@]}" || true
                return 0
            fi

            if (( system_caddy_active )) && ! systemctl stop caddy; then
                systemctl start caddy >/dev/null 2>&1 || true
                selfsteal_rollback_setup_config "$stage_dir" "${config_targets[@]}" || true
                error "$(t caddy_service_stop_failed)"
                return 1
            fi

            if (( system_caddy_enabled )) && ! systemctl disable caddy; then
                if (( system_caddy_active )); then
                    systemctl start caddy >/dev/null 2>&1 || true
                fi
                selfsteal_rollback_setup_config "$stage_dir" "${config_targets[@]}" || true
                error "$(t caddy_service_stop_failed)"
                return 1
            fi
        fi
    fi

    for container_name in "${conflicting_containers[@]}"; do
        container_running="$(docker inspect --format '{{.State.Running}}' "$container_name" 2>/dev/null || true)"
        [[ "$container_running" == "true" ]] || continue
        if ! docker stop "$container_name" >/dev/null; then
            selfsteal_restore_previous_services "$web_dir" "$system_caddy_active" "$system_caddy_enabled" "${stopped_containers[@]}"
            selfsteal_rollback_setup_config "$stage_dir" "${config_targets[@]}" || true
            error "$(t caddy_conflict_stop_failed)"
            return 1
        fi
        stopped_containers+=("$container_name")
    done

    if ! selfsteal_compose up -d; then
        selfsteal_restore_previous_services "$web_dir" "$system_caddy_active" "$system_caddy_enabled" "${stopped_containers[@]}"
        selfsteal_rollback_setup_config "$stage_dir" "${config_targets[@]}" || true
        error "$(t caddy_compose_start_failed)"
        return 1
    fi


    for container_name in caddy nginx; do
        container_running="$(docker inspect --format '{{.State.Running}}' "$container_name" 2>/dev/null || true)"
        if [[ "$container_running" != "true" ]]; then
            selfsteal_restore_previous_services "$web_dir" "$system_caddy_active" "$system_caddy_enabled" "${stopped_containers[@]}"
            selfsteal_rollback_setup_config "$stage_dir" "${config_targets[@]}" || true
            error "$(t caddy_compose_start_failed)"
            return 1
        fi
    done

    caddy_listener="$(ss -lntH 'sport = :9443' 2>/dev/null || true)"
    nginx_listener="$(ss -lntH 'sport = :443' 2>/dev/null || true)"
    if [[ -z "$caddy_listener" || -z "$nginx_listener" ]]; then
        selfsteal_restore_previous_services "$web_dir" "$system_caddy_active" "$system_caddy_enabled" "${stopped_containers[@]}"
        selfsteal_rollback_setup_config "$stage_dir" "${config_targets[@]}" || true
        error "$(t caddy_listener_check_failed)"
        return 1
    fi

    for domain in "$raw_domain" "$xhttp_domain"; do
        http_status="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 5 -H "Host: $domain" http://127.0.0.1/ 2>/dev/null || true)"
        if [[ "$http_status" != "301" ]]; then
            selfsteal_restore_previous_services "$web_dir" "$system_caddy_active" "$system_caddy_enabled" "${stopped_containers[@]}"
            selfsteal_rollback_setup_config "$stage_dir" "${config_targets[@]}" || true
            error "$(t caddy_http_smoke_failed)"
            return 1
        fi
    done


    log "$(t caddy_started)"
    rm -rf -- "$stage_dir"

}
selfsteal_compose() {
    local web_dir="$REMNANODE_DIR/web"
    (
        cd "$web_dir" || exit 1
        docker compose "$@"
    )
}

selfsteal_service_state() {
    local caddy_state nginx_state
    local web_dir="$REMNANODE_DIR/web"

    if [[ ! -f "$web_dir/docker-compose.yml" || ! -f "$web_dir/caddy/Caddyfile" || ! -f "$web_dir/nginx/nginx.conf" ]]; then
        printf 'missing'
        return 0
    fi
    if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
        printf 'unavailable'
        return 0
    fi

    caddy_state="$(docker inspect --format '{{.State.Status}}' caddy 2>/dev/null || true)"
    nginx_state="$(docker inspect --format '{{.State.Status}}' nginx 2>/dev/null || true)"
    if [[ "$caddy_state" == "running" && "$nginx_state" == "running" ]]; then
        printf 'running'
    elif [[ -z "$caddy_state" && -z "$nginx_state" ]]; then
        printf 'stopped'
    elif [[ "$caddy_state" == "running" || "$nginx_state" == "running" ||
        "$caddy_state" == "restarting" || "$nginx_state" == "restarting" ]]; then
        printf 'partial'
    else
        printf 'stopped'
    fi
}

selfsteal_read_domains() {
    local raw_variable="$1"
    local xhttp_variable="$2"
    local nginx_conf="$REMNANODE_DIR/web/nginx/nginx.conf"
    local raw_value="" xhttp_value=""

    if [[ -r "$nginx_conf" ]]; then
        IFS=' ' read -r raw_value xhttp_value < <(
            awk '
                $1 != "default" && $2 == "127.0.0.1:10443;" { raw = $1 }
                $1 != "default" && $2 == "127.0.0.1:10444;" { xhttp = $1 }
                END { print raw, xhttp }
            ' "$nginx_conf"
        )
    fi
    printf -v "$raw_variable" '%s' "$raw_value"
    printf -v "$xhttp_variable" '%s' "$xhttp_value"
}

selfsteal_read_certificate() {
    local domain="$1"

    command -v openssl >/dev/null 2>&1 || return 1
    command -v timeout >/dev/null 2>&1 || return 1
    timeout 1 openssl s_client \
        -connect 127.0.0.1:9443 \
        -servername "$domain" \
        -showcerts </dev/null 2>/dev/null |
        awk '
            /-----BEGIN CERTIFICATE-----/ { capture = 1 }
            capture { print }
            /-----END CERTIFICATE-----/ { exit }
        '
}

selfsteal_certificate_status() {
    local domain="$1"
    local pem enddate expiry_epoch now_epoch days_left

    pem="$(selfsteal_read_certificate "$domain" 2>/dev/null || true)"
    if [[ -z "$pem" ]]; then
        printf '%s' "$(t selfsteal_ssl_unavailable)"
        return 0
    fi
    enddate="$(printf '%s\n' "$pem" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)"
    expiry_epoch="$(date -d "$enddate" +%s 2>/dev/null || true)"
    if [[ -z "$expiry_epoch" ]]; then
        printf '%s' "$(t selfsteal_ssl_invalid)"
        return 0
    fi
    now_epoch="$(date +%s)"
    if (( expiry_epoch < now_epoch )); then
        days_left=$(( (now_epoch - expiry_epoch + 86399) / 86400 ))
        printf '%s %s %s' "$(t selfsteal_ssl_expired)" "$days_left" "$(t selfsteal_days)"
    else
        days_left=$(( (expiry_epoch - now_epoch) / 86400 ))
        if ! printf '%s\n' "$pem" | openssl x509 -noout -checkhost "$domain" >/dev/null 2>&1; then
            printf '%s' "$(t selfsteal_ssl_mismatch)"
        elif (( days_left <= 30 )); then
            printf '%s %s %s' "$(t selfsteal_ssl_expiring)" "$days_left" "$(t selfsteal_days)"
        else
            printf '%s %s %s' "$(t selfsteal_ssl_valid)" "$days_left" "$(t selfsteal_days)"
        fi
    fi
}

selfsteal_container_state_label() {
    case "$1" in
        running) t status_running ;;
        restarting) t status_restarting ;;
        created|exited|dead|paused) t status_stopped ;;
        "") t status_missing ;;
        *) printf '%s' "$1" ;;
    esac
}

selfsteal_print_status() {
    local state="${1:-}" raw_domain xhttp_domain caddy_state nginx_state

    [[ -n "$state" ]] || state="$(selfsteal_service_state)"
    printf '  %s %s\n' "$(t selfsteal_state_label)" "$(t "selfsteal_state_${state}")"
    [[ "$state" != "missing" && "$state" != "unavailable" ]] || return 0

    selfsteal_read_domains raw_domain xhttp_domain
    printf '  %s %s\n' "$(t selfsteal_raw_domain_label)" "${raw_domain:-$(t status_unknown)}"
    printf '  %s %s\n' "$(t selfsteal_xhttp_domain_label)" "${xhttp_domain:-$(t status_unknown)}"
    printf '  %s %s\n' "$(t selfsteal_ports_label)" "$(t selfsteal_ports_value)"

    caddy_state="$(docker inspect --format '{{.State.Status}}' caddy 2>/dev/null || true)"
    nginx_state="$(docker inspect --format '{{.State.Status}}' nginx 2>/dev/null || true)"
    if [[ "$caddy_state" == "running" ]]; then
        printf '  %s %s: %s\n' "$(t selfsteal_ssl_label)" "${raw_domain:-Caddy}" \
            "$(selfsteal_certificate_status "${raw_domain:-localhost}")"
        if [[ -n "$xhttp_domain" && "$xhttp_domain" != "$raw_domain" ]]; then
            printf '  %s %s: %s\n' "$(t selfsteal_ssl_label)" "$xhttp_domain" \
                "$(selfsteal_certificate_status "$xhttp_domain")"
        fi
    else
        printf '  %s %s\n' "$(t selfsteal_ssl_label)" "$(t selfsteal_ssl_unavailable)"
    fi
    printf '  %s %s / %s\n' "$(t selfsteal_containers_label)" \
        "$(selfsteal_container_state_label "$caddy_state")" \
        "$(selfsteal_container_state_label "$nginx_state")"
}

selfsteal_print_certificate_details() {
    local raw_domain xhttp_domain domain pem subject issuer enddate expiry_epoch now_epoch days_left

    if [[ "$(selfsteal_service_state)" == "missing" ]]; then
        error "$(t selfsteal_not_installed)"
        return 1
    fi
    selfsteal_read_domains raw_domain xhttp_domain
    for domain in "$raw_domain" "$xhttp_domain"; do
        [[ -n "$domain" ]] || continue
        printf '\n%s %s\n' "$(t selfsteal_ssl_details_title)" "$domain"
        pem="$(selfsteal_read_certificate "$domain" 2>/dev/null || true)"
        if [[ -z "$pem" ]]; then
            printf '  %s\n' "$(t selfsteal_ssl_unavailable)"
            continue
        fi
        subject="$(printf '%s\n' "$pem" | openssl x509 -noout -subject 2>/dev/null || true)"
        issuer="$(printf '%s\n' "$pem" | openssl x509 -noout -issuer 2>/dev/null || true)"
        enddate="$(printf '%s\n' "$pem" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)"
        expiry_epoch="$(date -d "$enddate" +%s 2>/dev/null || true)"
        printf '  %s %s\n' "$(t selfsteal_ssl_subject_label)" "${subject#subject=}"
        printf '  %s %s\n' "$(t selfsteal_ssl_issuer_label)" "${issuer#issuer=}"
        printf '  %s %s\n' "$(t selfsteal_ssl_expiry_label)" "$enddate"
        if [[ -n "$expiry_epoch" ]]; then
            now_epoch="$(date +%s)"
            if (( expiry_epoch < now_epoch )); then
                days_left=$(( (now_epoch - expiry_epoch + 86399) / 86400 ))
                printf '  %s %s %s\n' "$(t selfsteal_ssl_status_label)" \
                    "$(t selfsteal_ssl_expired)" "$days_left $(t selfsteal_days)"
            else
                days_left=$(( (expiry_epoch - now_epoch) / 86400 ))
                if printf '%s\n' "$pem" | openssl x509 -noout -checkhost "$domain" >/dev/null 2>&1; then
                    printf '  %s %s %s %s\n' "$(t selfsteal_ssl_status_label)" \
                        "$(t selfsteal_ssl_valid)" "$days_left" "$(t selfsteal_days)"
                else
                    printf '  %s %s\n' "$(t selfsteal_ssl_status_label)" "$(t selfsteal_ssl_mismatch)"
                fi
            fi
        fi
    done
}

selfsteal_validate_config() {
    if ! selfsteal_compose config --quiet; then
        error "$(t caddy_compose_invalid)"
        return 1
    fi
    if ! selfsteal_compose run --rm --no-deps --entrypoint caddy caddy validate --config /etc/caddy/Caddyfile; then
        error "$(t caddy_caddyfile_invalid)"
        return 1
    fi
    if ! selfsteal_compose run --rm --no-deps nginx nginx -t -c /etc/nginx/nginx.conf; then
        error "$(t caddy_nginx_config_invalid)"
        return 1
    fi
}

selfsteal_verify_running() {
    local raw_domain xhttp_domain http_status domain container_name

    for container_name in caddy nginx; do
        if [[ "$(docker inspect --format '{{.State.Running}}' "$container_name" 2>/dev/null || true)" != "true" ]]; then
            error "$(t caddy_compose_start_failed)"
            return 1
        fi
    done
    if [[ -z "$(ss -lntH 'sport = :9443' 2>/dev/null || true)" ||
        -z "$(ss -lntH 'sport = :443' 2>/dev/null || true)" ]]; then
        error "$(t caddy_listener_check_failed)"
        return 1
    fi

    selfsteal_read_domains raw_domain xhttp_domain
    for domain in "$raw_domain" "$xhttp_domain"; do
        [[ -n "$domain" ]] || continue
        http_status="$(curl -sS -o /dev/null -w '%{http_code}' \
            --connect-timeout 3 --max-time 5 -H "Host: $domain" http://127.0.0.1/ 2>/dev/null || true)"
        if [[ "$http_status" != "301" ]]; then
            error "$(t caddy_http_smoke_failed)"
            return 1
        fi
    done
}

selfsteal_start() {
    local state
    state="$(selfsteal_service_state)"
    if [[ "$state" == "missing" ]]; then
        error "$(t selfsteal_not_installed)"
        return 1
    fi
    if [[ "$state" == "unavailable" ]]; then
        error "$(t caddy_docker_daemon_required)"
        return 1
    fi
    if [[ "$state" == "running" ]]; then
        info "$(t selfsteal_already_running)"
        return 0
    fi
    selfsteal_validate_config || return 1
    selfsteal_compose up -d || {
        error "$(t caddy_compose_start_failed)"
        return 1
    }
    selfsteal_verify_running || return 1
    log "$(t selfsteal_started)"
}

selfsteal_stop() {
    local state
    state="$(selfsteal_service_state)"
    if [[ "$state" == "missing" ]]; then
        error "$(t selfsteal_not_installed)"
        return 1
    fi
    if [[ "$state" == "unavailable" ]]; then
        error "$(t caddy_docker_daemon_required)"
        return 1
    fi
    if [[ "$state" == "stopped" ]]; then
        info "$(t selfsteal_already_stopped)"
        return 0
    fi
    selfsteal_compose stop caddy nginx || return 1
    log "$(t selfsteal_stopped)"
}

selfsteal_restart() {
    local state
    state="$(selfsteal_service_state)"
    if [[ "$state" == "missing" ]]; then
        error "$(t selfsteal_not_installed)"
        return 1
    fi
    if [[ "$state" == "unavailable" ]]; then
        error "$(t caddy_docker_daemon_required)"
        return 1
    fi
    selfsteal_validate_config || return 1
    selfsteal_compose up -d --force-recreate || {
        error "$(t caddy_compose_start_failed)"
        return 1
    }
    selfsteal_verify_running || return 1
    log "$(t selfsteal_restarted)"
}

selfsteal_logs() {
    if [[ ! -f "$REMNANODE_DIR/web/docker-compose.yml" ]]; then
        error "$(t selfsteal_not_installed)"
        return 1
    fi
    selfsteal_compose logs --tail 100 caddy nginx
}
