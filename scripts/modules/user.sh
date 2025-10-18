#!/bin/bash

# Функция добавления пользователя
add_user() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}    Добавление нового пользователя${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""

    read -p "Введите имя пользователя: " username

    if [ -z "$username" ]; then
        error "Имя пользователя не может быть пустым"
        return 1
    fi

    if id "$username" &>/dev/null; then
        warning "Пользователь $username уже существует"
        return 1
    fi

    log "Создание пользователя $username..."
    sudo useradd -m -s /bin/bash -G users "$username"
    check_success "Пользователь $username создан"

    log "Установка пароля для пользователя $username..."
    sudo passwd "$username"
    check_success "Пароль установлен"

    echo ""
    read -p "Выдать пользователю права sudo? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo usermod -a -G sudo "$username"
        check_success "Права sudo выданы пользователю $username"
    else
        info "Права sudo не выданы"
    fi

    log "Пользователь $username успешно создан"
}
