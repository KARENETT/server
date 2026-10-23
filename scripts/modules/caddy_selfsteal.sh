#!/bin/bash

is_valid_selfsteal_domain() {
    local domain="$1"
    local hostname_pattern='^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$'

    (( ${#domain} <= 253 )) && [[ "$domain" =~ $hostname_pattern ]]
}

render_selfsteal_caddyfile() {
    local domain="$1"

    cat <<EOF
{
    http_port 80
    https_port 9443
    default_sni $domain
    fallback_sni $domain
    auto_https disable_redirects
    servers {
        protocols h1 h2
    }
}

http://$domain {
    redir https://{host}{uri} 301
}

$domain {
    bind 127.0.0.1
    tls {
        protocols tls1.2 tls1.3
    }
    root * /var/www/selfsteal
    file_server
    header -Server
    header Strict-Transport-Security "max-age=31536000; includeSubDomains"
}
EOF
}

setup_caddy_selfsteal() {
    local domain asset_path caddyfile_tmp caddyfile_backup="" had_caddyfile=0

    log "=========================================="
    log "$(t opt_24)"
    log "=========================================="

    if ! command -v apt >/dev/null 2>&1; then
        error "$(t caddy_apt_required)"
        return 1
    fi

    asset_path="$SCRIPTS_DIR/assets/selfsteal/index.html"
    if [[ ! -f "$asset_path" ]]; then
        error "$(t caddy_asset_missing)"
        return 1
    fi

    info "$(t caddy_dns_notice)"
    info "$(t caddy_ports_notice)"
    while true; do
        read -rp "${PROMPT_PREFIX} $(t caddy_domain_prompt) " domain
        if is_valid_selfsteal_domain "$domain"; then
            break
        fi
        warning "$(t caddy_domain_invalid)"
    done

    log "$(t caddy_installing)"
    apt install -y debian-keyring debian-archive-keyring apt-transport-https curl gnupg
    install -d -m 755 /usr/share/keyrings
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' |
        gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list
    chmod 644 /usr/share/keyrings/caddy-stable-archive-keyring.gpg /etc/apt/sources.list.d/caddy-stable.list
    apt update && apt install -y caddy

    install -d -o root -g root -m 755 /var/www/selfsteal
    install -o root -g root -m 644 "$asset_path" /var/www/selfsteal/index.html

    caddyfile_tmp="$(mktemp /etc/caddy/Caddyfile.XXXXXX)"
    render_selfsteal_caddyfile "$domain" > "$caddyfile_tmp"

    if [[ -f /etc/caddy/Caddyfile ]]; then
        had_caddyfile=1
        if ! cmp -s "$caddyfile_tmp" /etc/caddy/Caddyfile; then
            caddyfile_backup="$(mktemp /etc/caddy/Caddyfile.backup.XXXXXX)"
            cp -a /etc/caddy/Caddyfile "$caddyfile_backup"
            info "$(t caddy_config_backup) $caddyfile_backup"
        fi
    fi

    install -o root -g root -m 644 "$caddyfile_tmp" /etc/caddy/Caddyfile
    rm -f "$caddyfile_tmp"

    if caddy validate --config /etc/caddy/Caddyfile && systemctl reload caddy; then
        log "$(t caddy_done)"
    else
        if [[ -n "$caddyfile_backup" ]]; then
            cp -a "$caddyfile_backup" /etc/caddy/Caddyfile
        elif (( had_caddyfile == 0 )); then
            rm -f /etc/caddy/Caddyfile
        fi
        error "$(t caddy_config_failed)"
        return 1
    fi
}
