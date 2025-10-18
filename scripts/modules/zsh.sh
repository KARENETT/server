#!/bin/bash

# Функция установки ZSH
setup_zsh() {
    log "=========================================="
    log "Установка и настройка ZSH + Oh My Zsh"
    log "=========================================="

    check_internet || return 1

    # Установка ZSH
    log "Установка ZSH..."
    if ! command -v zsh &> /dev/null; then
        retry_command "sudo apt install -y zsh" && check_success "ZSH установлен"
    else
        info "ZSH уже установлен"
    fi

    # Проверка установки ZSH
    if ! command -v zsh &> /dev/null; then
        error "ZSH не установлен, прерывание"
        return 1
    fi

    # Установка Oh-My-Zsh
    log "Установка Oh-My-Zsh..."
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        retry_command 'RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"' && check_success "Oh-My-Zsh установлен"
    else
        info "Oh-My-Zsh уже установлен"
    fi

    # Установка плагинов ZSH
    log "Установка плагинов ZSH..."

    # zsh-syntax-highlighting
    if [ ! -d "$HOME/.zsh-syntax-highlighting" ]; then
        retry_command "git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $HOME/.zsh-syntax-highlighting --depth 1" && check_success "zsh-syntax-highlighting установлен"
    else
        info "zsh-syntax-highlighting уже установлен"
    fi

    # zsh-autosuggestions
    if [ ! -d "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" ]; then
        retry_command "git clone https://github.com/zsh-users/zsh-autosuggestions $HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" && check_success "zsh-autosuggestions установлен"
    else
        info "zsh-autosuggestions уже установлен"
    fi

    # Установка Starship
    log "Установка Starship..."
    if ! command -v starship &> /dev/null; then
        retry_command "curl -sS https://starship.rs/install.sh | sh -s -- -y" && check_success "Starship установлен"
    else
        info "Starship уже установлен"
    fi

    # Создание .zshrc
    log "Создание конфигурации .zshrc..."
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
    log "Изменение оболочки по умолчанию на zsh..."
    if [ "$SHELL" != "$(which zsh)" ]; then
        sudo chsh -s $(which zsh) $USER && check_success "Оболочка изменена на zsh"
    else
        info "Оболочка уже установлена на zsh"
    fi

    log "ZSH и Oh My Zsh успешно настроены"
}
