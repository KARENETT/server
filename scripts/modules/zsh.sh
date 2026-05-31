#!/bin/bash

# Функция установки ZSH
setup_zsh() {
    log "=========================================="
    log "$(t zsh_title)"
    log "=========================================="

    check_internet || return 1

    # Установка ZSH
    log "$(t zsh_installing)"
    if ! command -v zsh &> /dev/null; then
        retry_command "apt install -y zsh" && check_success "ZSH установлен"
    else
        info "$(t zsh_already)"
    fi

    # Проверка установки ZSH
    if ! command -v zsh &> /dev/null; then
        error "$(t zsh_not_installed)"
        return 1
    fi

    setup_zsh_user() {
        local username="$1"
        local user_home="$2"

        log "Настройка ZSH для пользователя: $username"

        if [ ! -d "$user_home/.oh-my-zsh" ]; then
            runuser -u "$username" -- sh -c 'RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"' || true
        fi

        if [ ! -d "$user_home/.zsh-syntax-highlighting" ]; then
            runuser -u "$username" -- git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$user_home/.zsh-syntax-highlighting" --depth 1 || true
        fi

        if [ ! -d "$user_home/.oh-my-zsh/custom/plugins/zsh-autosuggestions" ]; then
            runuser -u "$username" -- git clone https://github.com/zsh-users/zsh-autosuggestions "$user_home/.oh-my-zsh/custom/plugins/zsh-autosuggestions" --depth 1 || true
        fi

        cat > "$user_home/.zshrc" << 'ZSHRC_EOF'
# Oh My Zsh configuration
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""

# Plugins
plugins=(
    git zsh-autosuggestions docker npm node python rust sudo command-not-found
)

# Загрузка Oh My Zsh
if [ -f "$ZSH/oh-my-zsh.sh" ]; then
    source $ZSH/oh-my-zsh.sh
fi

# Syntax highlighting
if [ -f "$HOME/.zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]; then
    source $HOME/.zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi

# Starship prompt
if command -v starship &> /dev/null; then
    eval "$(starship init zsh)"
fi

# Aliases
alias c='clear'

# Environment variables
export EDITOR=micro
export VISUAL=micro
export PATH="$HOME/.local/bin:$PATH"

# History
HISTSIZE=10000
SAVEHIST=10000
HISTFILE=~/.zsh_history
setopt SHARE_HISTORY HIST_IGNORE_ALL_DUPS HIST_FIND_NO_DUPS
ZSHRC_EOF

        chown "$username:$username" "$user_home/.zshrc" || true
        usermod -s "$(which zsh)" "$username" || true
    }

    # Установка Starship
    log "$(t starship_installing)"
    if ! command -v starship &> /dev/null; then
        retry_command "curl -sS https://starship.rs/install.sh | sh -s -- -y" && check_success "Starship установлен"
    else
        info "$(t starship_already)"
    fi

    log "$(t zsh_plugins_installing)"
    while IFS=: read -r username _ uid _ _ home shell; do
        if { [ "$uid" -ge 1000 ] || [ "$username" = "root" ]; } && [ -d "$home" ] && [[ "$shell" != *nologin ]] && [[ "$shell" != *false ]]; then
            setup_zsh_user "$username" "$home"
        fi
    done < /etc/passwd

    usermod -D -s "$(which zsh)" || true
    check_success "ZSH настроен для всех пользователей; shell по умолчанию обновлен"

    log "$(t zsh_done)"
}
