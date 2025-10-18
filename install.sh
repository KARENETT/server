#!/bin/bash

if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root"
    echo "Этот скрипт должен быть запущен с правами root"
    exit 1
fi

TEMP_DIR=$(mktemp -d)

if [ -d "/opt/serversetup" ]; then
    echo "Removing existing servers setup installation..."
    echo "Удаление существующей директории настройки сервера..."
    rm -rf /opt/serversetup
fi

if ! command -v curl &> /dev/null; then
    echo "Installing curl..."
    echo "Установка curl..."
    if command -v apt-get &> /dev/null; then
        apt update -y && apt install -y curl
    elif command -v yum &> /dev/null; then
        yum install -y curl
    elif command -v dnf &> /dev/null; then
        dnf install -y curl
    else
        echo "Failed to install curl. Please install it manually."
        echo "Не удалось установить curl. Пожалуйста, установите его вручную."
        exit 1
    fi
fi

cd "$TEMP_DIR" || exit 1

echo "Downloading server setup..."
echo "Загрузка серверной установки..."
curl -L https://github.com/haxgun/server/archive/refs/heads/main.zip -o serversetup.zip

if [ ! -f serversetup.zip ]; then
    echo "Error: Failed to download archive"
    echo "Ошибка: Не удалось загрузить архив"
    rm -rf "$TEMP_DIR"
    exit 1
fi

if ! command -v unzip &> /dev/null; then
    echo "Installing unzip..."
    echo "Установка unzip..."
    if command -v apt-get &> /dev/null; then
        echo "Updating package list..."
        echo "Обновление списка пакетов..."
        sudo apt update -y && sudo apt install -y unzip
    elif command -v yum &> /dev/null; then
        sudo yum install -y unzip
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y unzip
    else
        echo "Failed to install unzip. Please install it manually."
        echo "Не удалось установить unzip. Пожалуйста, установите его вручную."
        rm -rf "$TEMP_DIR"
        exit 1
    fi
fi

echo "Extracting files..."
echo "Распаковка файлов..."
unzip -q remnasetup.zip

if [ ! -d "RemnaSetup-main" ]; then
    echo "Error: Failed to extract archive"
    echo "Ошибка: Не удалось распаковать архив"
    rm -rf "$TEMP_DIR"
    exit 1
fi

mkdir -p /opt/serversetup

echo "Installing server setup to /opt/serversetup..."
echo "Установка настройки сервера в /opt/serversetup..."
cp -r server-main/* /opt/serversetup/

if [ ! -f "/opt/serversetup/setup.sh" ]; then
    echo "Error: Failed to copy files"
    echo "Ошибка: Не удалось скопировать файлы"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "Setting permissions..."
echo "Установка прав доступа..."
chown -R $SUDO_USER:$SUDO_USER /opt/serversetup
chmod -R 755 /opt/serversetup
chmod +x /opt/serversetup/setup.sh
chmod +x /opt/serversetup/scripts/config.sh
chmod +x /opt/serversetup/scripts/utils.sh
chmod +x /opt/serversetup/scripts/modules/*.sh

rm -rf "$TEMP_DIR"

cd /opt/serversetup || exit 1

echo "Starting server setup..."
echo "Запуск настройки сервера..."
bash /opt/serversetup/setup.sh
