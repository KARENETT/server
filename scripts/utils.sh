#!/bin/bash

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

# Проверка интернет-соединения
check_internet() {
    info "Проверка интернет-соединения..."
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        error "Нет интернет-соединения"
        return 1
    fi
    log "Интернет-соединение проверено"
    return 0
}
