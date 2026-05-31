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

    # Установка Oh-My-Zsh
    log "$(t omz_installing)"
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        retry_command 'RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"' && check_success "Oh-My-Zsh установлен"
    else
        info "$(t omz_already)"
    fi

    # Установка плагинов ZSH
    log "$(t zsh_plugins_installing)"

    # zsh-syntax-highlighting
    if [ ! -d "$HOME/.zsh-syntax-highlighting" ]; then
        retry_command "git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $HOME/.zsh-syntax-highlighting --depth 1" && check_success "zsh-syntax-highlighting установлен"
    else
        info "$(t zsh_syntax_already)"
    fi

    # zsh-autosuggestions
    if [ ! -d "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" ]; then
        retry_command "git clone https://github.com/zsh-users/zsh-autosuggestions $HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" && check_success "zsh-autosuggestions установлен"
    else
        info "$(t zsh_auto_already)"
    fi

    # Установка Starship
    log "$(t starship_installing)"
    if ! command -v starship &> /dev/null; then
        retry_command "curl -sS https://starship.rs/install.sh | sh -s -- -y" && check_success "Starship установлен"
    else
        info "$(t starship_already)"
    fi

    # Создание .zshrc
    log "$(t zshrc_creating)"
    cat > ~/.zshrc << 'ZSHRC_EOF'
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

    check_success ".zshrc создан"

    # Изменение shell на zsh
    log "$(t shell_switching)"
    if [ "$SHELL" != "$(which zsh)" ]; then
        chsh -s "$(which zsh)" "${SUDO_USER:-$USER}" && check_success "Оболочка изменена на zsh"
    else
        info "$(t shell_already_zsh)"
    fi

    log "$(t zsh_done)"
}
