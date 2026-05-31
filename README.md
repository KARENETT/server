<div align="center">

<img src="logo.png" alt="KARENET" width="240"  />

Интерактивный набор скриптов для быстрой, безопасной и повторяемой настройки Ubuntu/Debian сервера.

[![Shell](https://img.shields.io/badge/Shell-Bash-121011?style=for-the-badge&logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Ubuntu/Debian](https://img.shields.io/badge/OS-Ubuntu%20%7C%20Debian-E95420?style=for-the-badge&logo=ubuntu&logoColor=white)](https://ubuntu.com)
[![Docker Ready](https://img.shields.io/badge/Docker-Ready-2496ED?style=for-the-badge&logo=docker&logoColor=white)](https://www.docker.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)](LICENSE)

</div>

---

## 🚀 Что делает проект

`KARENET Server` автоматизирует первичную подготовку VPS/выделенного сервера:

- Hardening SSH и сетевой безопасности;
- базовый firewall и защитные сервисы;
- сетевые оптимизации (BBR/sysctl/TFO);
- установка dev-инструментов и runtime-компонентов;
- единый интерактивный запуск через `setup.sh`.

---

## ✨ Возможности

<table>
<tr>
<td width="50%" valign="top">

### 🔐 Security

- Настройка SSH (порт, ограничения, базовый hardening)
- UFW/Firewall профили и базовые правила доступа
- Fail2Ban и дополнительные защитные модули
- TrafficGuard и сетевые ограничения для снижения шума

</td>
<td width="50%" valign="top">

### 🛠 Infrastructure

- Настройка sysctl hardening и congestion control (BBR)
- Оптимизация сети (MSS clamp, TCP tweaks)
- Установка Docker и вспомогательных пакетов
- Модули Node.js, uv, ZSH и системные утилиты

</td>
</tr>
</table>

---

## ⚡ Быстрый старт

Запуск напрямую из GitHub:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/KARENETT/server/main/setup.sh)
```

Или сразу с `sudo`:

```bash
curl -fsSL https://raw.githubusercontent.com/KARENETT/server/main/setup.sh | sudo bash
```

Локальный запуск после установки:

```bash
sudo karenet-setup
```

---

## ⚙️ Модули установки

| Категория | Что настраивается |
|:--|:--|
| System | Базовые системные пакеты, user/system tweaks |
| Network | sysctl hardening, BBR, network tuning |
| Security | SSH, firewall, fail2ban, trafficguard |
| Runtime | Docker, Node.js, uv, ZSH, XanMod, WARP Native |

---

## 📁 Структура репозитория

- `setup.sh` - основной интерактивный установщик
- `scripts/modules/` - независимые модули настройки
- `scripts/utils.sh` - общие функции и helper-утилиты
- `translation/en.sh`, `translation/ru.sh` - локализация интерфейса

---

## 🔗 Полезные команды

```bash
# Клонировать проект
git clone git@github.com:KARENETT/server.git

# Запустить локально
cd server
sudo bash setup.sh
```

---

## 📄 Лицензия

MIT, см. файл `LICENSE`.
