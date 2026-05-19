#!/bin/bash

# Функция добавления пользователя
add_user() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}    Добавление нового пользователя${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo ""

    read -rp "${PROMPT_PREFIX} $(t user_step_1) " username

    if [ -z "$username" ]; then
        error "$(t user_error_empty_name)"
        return 1
    fi

    if id "$username" &>/dev/null; then
        warning "Пользователь $username уже существует"
        return 1
    fi

    local password password_confirm

    read -rsp "${PROMPT_PREFIX} $(t user_step_2) " password
    echo ""
    read -rsp "${PROMPT_PREFIX} $(t user_step_3) " password_confirm
    echo ""

    if [ -z "$password" ]; then
        error "$(t user_error_empty_password)"
        return 1
    fi

    if [ "$password" != "$password_confirm" ]; then
        error "$(t user_error_password_mismatch)"
        return 1
    fi

    log "Создание пользователя $username..."
    useradd -m -s /bin/bash -G users "$username"
    check_success "Пользователь $username создан"

    log "Установка пароля для пользователя $username..."
    printf "%s:%s\n" "$username" "$password" | chpasswd
    check_success "Пароль установлен"

    echo ""
    if confirm_yes_no "$(t user_step_4)"; then
        usermod -a -G sudo "$username"
        check_success "Права sudo выданы пользователю $username"
    else
        info "Права sudo не выданы"
    fi

    log "Пользователь $username успешно создан"
}
