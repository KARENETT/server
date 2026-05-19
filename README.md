# KARENET Server Setup

Минималистичный интерактивный скрипт для первичной настройки Ubuntu-сервера.

## Установка через терминал

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/KARENETT/server/main/setup.sh)
```

Или сразу с `sudo`:

```bash
curl -fsSL https://raw.githubusercontent.com/KARENETT/server/main/setup.sh | sudo bash
```

## Что умеет

- Быстрый старт и выборочная установка модулей
- Безопасность: SSH, UFW, Fail2Ban, TrafficGuard
- Производительность: XanMod, sysctl hardening (BBR), TFO, MSS clamp
- Dev-окружение: ZSH, Docker, Node.js/Bun/PM2, uv
- Дополнительно: WARP NATIVE by distillium

## Запуск после установки

```bash
sudo karenet-setup
```

## Репозиторий

https://github.com/KARENETT/server
