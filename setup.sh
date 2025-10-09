#!/bin/bash

# Строгий режим выполнения
set -euo pipefail
IFS=$'\n\t'

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Файл логирования
LOG_FILE="$HOME/server_setup_$(date +%Y%m%d_%H%M%S).log"

# Функции логирования
log() {
    local message="[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    echo -e "${GREEN}${message}${NC}" | tee -a "$LOG_FILE"
}

error() {
    local message="[ERROR] $1"
    echo -e "${RED}${message}${NC}" | tee -a "$LOG_FILE"
    return 1
}

warning() {
    local message="[WARNING] $1"
    echo -e "${YELLOW}${message}${NC}" | tee -a "$LOG_FILE"
}

info() {
    local message="[INFO] $1"
    echo -e "${BLUE}${message}${NC}" | tee -a "$LOG_FILE"
}

# Функция проверки успешности выполнения команды
check_success() {
    if [ $? -eq 0 ]; then
        log "✓ $1"
        return 0
    else
        error "✗ $1"
        return 1
    fi
}

# Функция для выполнения команд с повторами
retry_command() {
    local max_attempts=3
    local attempt=1
    local delay=5
    local command="$@"

    while [ $attempt -le $max_attempts ]; do
        if eval "$command"; then
            return 0
        else
            if [ $attempt -lt $max_attempts ]; then
                warning "Попытка $attempt из $max_attempts не удалась. Повтор через $delay секунд..."
                sleep $delay
                ((attempt++))
            else
                error "Команда не выполнена после $max_attempts попыток: $command"
                return 1
            fi
        fi
    done
}

# Функция очистки при ошибке
cleanup_on_error() {
    error "Произошла ошибка. Выполняется откат изменений..."
    # Здесь можно добавить дополнительные действия по откату
    exit 1
}

# Установка обработчика ошибок
trap cleanup_on_error ERR

# Проверка прав
if [[ $EUID -eq 0 ]]; then
   error "Этот скрипт НЕ должен запускаться от root"
   exit 1
fi

log "=========================================="
log "Начало установки и настройки сервера"
log "Лог сохраняется в: $LOG_FILE"
log "=========================================="

# Проверка интернет-соединения
info "Проверка интернет-соединения..."
if ! ping -c 1 8.8.8.8 &> /dev/null; then
    error "Нет интернет-соединения"
    exit 1
fi
log "Интернет-соединение проверено"

# Обновление системы
log "Обновление системы..."
retry_command "sudo apt update -y" && check_success "apt update"
retry_command "sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y" && check_success "apt upgrade"
sudo apt autoremove -y || true
sudo apt autoclean || true

# Установка базовых утилит
log "Установка базовых утилит..."
BASIC_PACKAGES=(
    curl
    wget
    git
    ufw
    micro
    gpg
    ca-certificates
    lsb-release
    apt-transport-https
    software-properties-common
    build-essential
    unzip
    gnupg
    gnupg-agent
    tree
    htop
    neofetch
    vim
    nano
    jq
    rsync
    tmux
    screen
    bat
    fd-find
    ripgrep
    fzf
    python3-pip
)

for package in "${BASIC_PACKAGES[@]}"; do
    if ! dpkg -l | grep -q "^ii  $package "; then
        info "Установка $package..."
        retry_command "sudo DEBIAN_FRONTEND=noninteractive apt install -y $package" && check_success "$package установлен" || warning "$package не удалось установить"
    else
        info "$package уже установлен"
    fi
done

# Создание символической ссылки для bat
mkdir -p ~/.local/bin
if [ ! -L ~/.local/bin/bat ]; then
    ln -s /usr/bin/batcat ~/.local/bin/bat && check_success "bat symlink создан"
fi

# Установка eza
log "Установка eza..."
if ! command -v eza &> /dev/null; then
    {
        sudo mkdir -p /etc/apt/keyrings
        wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
        echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | sudo tee /etc/apt/sources.list.d/gierens.list > /dev/null
        sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
        sudo apt update
        sudo apt install -y eza
        check_success "eza установлен"
    } || {
        warning "Установка eza через apt не удалась, пробуем через cargo..."
        if ! command -v cargo &> /dev/null; then
            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
            source "$HOME/.cargo/env"
        fi
        cargo install eza && check_success "eza установлен через cargo"
    }
else
    info "eza уже установлен"
fi

# Настройка SSH
log "Настройка SSH..."
if [ -f /etc/ssh/sshd_config ]; then
    sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)

    # Безопасное изменение конфигурации SSH
    sudo sed -i 's/^#*Port .*/Port 33556/' /etc/ssh/sshd_config
    sudo sed -i 's/^#*PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
    sudo sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config

    # Проверка конфигурации перед перезапуском
    if sudo sshd -t; then
        sudo systemctl restart ssh && check_success "SSH настроен и перезапущен"
    else
        error "Ошибка в конфигурации SSH, откат изменений"
        sudo cp /etc/ssh/sshd_config.backup.* /etc/ssh/sshd_config
    fi
fi

# Настройка UFW
log "Настройка файрвола..."
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 33556/tcp comment 'SSH'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw --force enable && check_success "UFW настроен"

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
    exit 1
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
cat > ~/.zshrc << 'EOF'
# Oh My Zsh configuration
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""

# Plugins
plugins=(
    git
    zsh-autosuggestions
    docker
    npm
    node
    python
    rust
    sudo
    command-not-found
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

if command -v bun &> /dev/null; then
    alias bd='bun dev'
    alias bp='bun dev:proxy'
    alias bdd='bun dev --debug'
    alias bf='bun format'
    alias bi='bun install'
    alias bui='bun remove'
    alias bx='bunx'
    alias bl='bun lint'
    alias bul='bun update -i --latest'
fi

if command -v lazygit &> /dev/null; then
    alias lg='lazygit'
fi

if command -v lazydocker &> /dev/null; then
    alias ld='lazydocker'
fi

alias .="source"

if command -v eza &> /dev/null; then
    alias ls="eza --tree --level=1 --icons=always --no-time --no-user --no-permissions"
    alias ll='eza -l --icons'
    alias la='eza -la --icons'
    alias tree='eza --tree --icons'
fi

if command -v git &> /dev/null; then
    alias gs='git status'
    alias gp='git push'
    alias gpf='git push --force'
    alias gpft='git push --follow-tags'
    alias gpl='git pull --rebase'
    alias gcl='git clone'
    alias gst='git stash'
    alias grm='git rm'
    alias gmv='git mv'

    alias main='git checkout main'

    alias gco='git checkout'
    alias gcob='git checkout -b'

    alias gb='git branch'
    alias gbd='git branch -d'

    alias grb='git rebase'
    alias grbom='git rebase origin/master'
    alias grbc='git rebase --continue'

    alias gl='git log'
    alias glo='git log --oneline --graph'

    alias grh='git reset HEAD'
    alias grh1='git reset HEAD~1'

    alias ga='git add'
    alias gA='git add -A'

    alias gc='git commit'
    alias gcm='git commit -m'
    alias gca='git commit -a'
    alias gcam='git add -A && git commit -m'
    alias gfrb='git fetch origin && git rebase origin/master'

    alias gxn='git clean -dn'
    alias gx='git clean -df'

    alias gsha='git rev-parse HEAD | pbcopy'
fi

if command -v docker &> /dev/null; then
    alias dsa='docker stop $(docker ps -q)'
    alias dra='docker stop $(docker ps -a -q) && docker rm $(docker ps -a -q)'
    alias ds='docker stop'
    alias dp='docker ps -a'
fi

if command -v batcat &> /dev/null; then
    alias cat='batcat'
elif [ -f ~/.local/bin/bat ]; then
    alias cat='bat'
fi

# Environment variables
export EDITOR=micro
export VISUAL=micro

# Path additions
export PATH="$HOME/.local/bin:$PATH"

# Cargo
if [ -d "$HOME/.cargo/bin" ]; then
    export PATH="$HOME/.cargo/bin:$PATH"
fi

# Bun
if [ -d "$HOME/.bun/bin" ]; then
    export BUN_INSTALL="$HOME/.bun"
    export PATH="$BUN_INSTALL/bin:$PATH"
fi

# History
HISTSIZE=10000
SAVEHIST=10000
HISTFILE=~/.zsh_history
setopt SHARE_HISTORY
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_FIND_NO_DUPS
EOF

check_success ".zshrc создан"

# Установка Node.js
log "Установка Node.js..."
if ! command -v node &> /dev/null; then
    retry_command "curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -" && \
    retry_command "sudo apt-get install -y nodejs" && check_success "Node.js установлен"
else
    info "Node.js уже установлен ($(node --version))"
fi

# Установка глобальных npm пакетов
if command -v npm &> /dev/null; then
    log "Установка глобальных npm пакетов..."
    retry_command "npm install -g pm2 yarn" && check_success "npm пакеты установлены"
fi

# Установка Bun
log "Установка Bun..."
if ! command -v bun &> /dev/null; then
    retry_command "curl -fsSL https://bun.sh/install | bash" && check_success "Bun установлен"
    # Добавление bun в PATH для текущей сессии
    export BUN_INSTALL="$HOME/.bun"
    export PATH="$BUN_INSTALL/bin:$PATH"
else
    info "Bun уже установлен ($(bun --version))"
fi

# Установка uv
log "Установка uv..."
if ! command -v uv &> /dev/null; then
    retry_command "curl -LsSf https://astral.sh/uv/install.sh | sh" && check_success "uv установлен"
else
    info "uv уже установлен"
fi

# Установка Docker
log "Установка Docker..."
if ! command -v docker &> /dev/null; then
    # Удаление старых версий
    sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

    # Установка зависимостей
    retry_command "sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release"

    # Добавление GPG ключа
    sudo mkdir -p /etc/apt/keyrings
    retry_command "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg"

    # Добавление репозитория
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Установка Docker
    sudo apt-get update
    retry_command "sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin" && check_success "Docker установлен"

    # Добавление пользователя в группу docker
    sudo usermod -aG docker $USER && check_success "Пользователь добавлен в группу docker"

    # Запуск Docker
    sudo systemctl start docker
    sudo systemctl enable docker && check_success "Docker запущен и добавлен в автозагрузку"
else
    info "Docker уже установлен ($(docker --version))"
fi

# Установка Fail2Ban
log "Установка и настройка Fail2Ban..."
if ! command -v fail2ban-client &> /dev/null; then
    retry_command "sudo apt install -y fail2ban" && check_success "Fail2Ban установлен"
else
    info "Fail2Ban уже установлен"
fi

# Создание конфигурации Fail2Ban
sudo tee /etc/fail2ban/jail.local > /dev/null << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true
port = 33556
logpath = %(sshd_log)s
backend = %(sshd_backend)s
maxretry = 3
bantime = 3600
EOF

sudo systemctl restart fail2ban
sudo systemctl enable fail2ban && check_success "Fail2Ban настроен"

# Создание структуры каталогов
log "Создание структуры каталогов..."
mkdir -p ~/projects ~/scripts ~/downloads ~/backup && check_success "Структура каталогов создана"

# Изменение shell на zsh
log "Изменение оболочки по умолчанию на zsh..."
if [ "$SHELL" != "$(which zsh)" ]; then
    sudo chsh -s $(which zsh) $USER && check_success "Оболочка изменена на zsh"
else
    info "Оболочка уже установлена на zsh"
fi

# Финальная проверка
log "=========================================="
log "Проверка установленных компонентов:"
log "=========================================="

components=(
    "zsh:zsh --version"
    "git:git --version"
    "docker:docker --version"
    "node:node --version"
    "npm:npm --version"
    "bun:bun --version"
    "starship:starship --version"
    "eza:eza --version"
)

for component in "${components[@]}"; do
    name="${component%%:*}"
    cmd="${component#*:}"
    if eval "$cmd" &> /dev/null; then
        version=$(eval "$cmd" 2>&1 | head -n1)
        log "✓ $name: $version"
    else
        warning "✗ $name: не установлен"
    fi
done

# Финальные инструкции
log "=========================================="
log "Установка завершена успешно!"
log "=========================================="
echo ""
info "Для применения всех изменений необходимо:"
echo "1. Перелогиниться или выполнить: exec zsh"
echo "2. Проверить Docker: newgrp docker && docker run hello-world"
echo "3. SSH теперь работает на порту 33556"
echo ""
warning "ВАЖНО: Убедитесь, что у вас есть доступ к серверу через SSH на порту 33556 перед отключением!"
warning "Протестируйте подключение в новом терминале: ssh -p 33556 $(whoami)@<server_ip>"
echo ""
info "Лог установки сохранён в: $LOG_FILE"
echo ""

read -p "Хотите перезагрузить систему сейчас? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log "Перезагрузка системы..."
    sudo reboot
else
    log "Перезагрузка отменена. Не забудьте перезагрузиться позже."
    info "Для применения изменений прямо сейчас выполните: exec zsh"
fi
