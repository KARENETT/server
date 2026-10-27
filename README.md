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
- развёртывание RemnaNode и self-steal Caddy/Nginx через Docker Compose;
- интерактивное меню и CLI-команды через `setup.sh` и `karenet-setup`.

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
| Network | sysctl hardening, BBR, network tuning, Caddy/Nginx self-steal, Psiphon |
| Security | SSH, firewall (в том числе ограничение порта RemnaNode IP панели), fail2ban, trafficguard, блокировка торрентов через ds-guard |
| Runtime | Docker, Node.js, uv, ZSH, XanMod, WARP Native |

## 🔐 RemnaNode и self-steal

Главное меню разделяет настройки: `1` — сервер, `2` — RemnaNode, `3` — self-steal, `4` — полная настройка сервера, `5` — выборочная установка. Путь к установке RemnaNode: `2 → 1`; self-steal: `3 → 1`. Выборочная установка (`5`) использует идентификаторы модулей: RemnaNode `26`, self-steal `24`.

Интерфейс скрипта всегда русский, независимо от локали сервера. Пункт `4` сначала запрашивает порт SSH (по умолчанию `33556`), затем автоматически выполняет настройки сервера без дополнительных подтверждений. Сервер не перезагружается автоматически. RemnaNode, self-steal и WARP Native остаются отдельными пунктами, так как требуют пользовательских данных.

- RemnaNode создаётся в `/opt/remnanode/docker-compose.yml`; скрипт запрашивает IP панели, TCP-порт ноды (по умолчанию `30100`) и скрытый `SECRET_KEY`. UFW разрешает порт ноды только с IP панели; правило сохраняется для восстановления после сброса UFW. После добавления правила установка принудительно выполняет `ufw --force enable`; если SSH-порт не разрешён во входящих правилах, соединение с сервером может оборваться. Ключ хранится в `/opt/remnanode/.env` с правами `600`. Создаётся `/var/log/remnanode`; если `logrotate` отсутствует, он устанавливается, а правила ротации записываются в `/etc/logrotate.d/remnanode` (`size 50M`, 5 архивов, gzip, `copytruncate`) и проверяются командой `logrotate -vf`. Параметр `-f` принудительно ротирует существующие непустые логи и архивирует их также при повторной установке.
- Self-steal создаёт Caddy/Nginx Compose-стек в `/opt/remnanode/web` и запрашивает домены `raw` и `xhttp`. DNS должен вести прямо на сервер; TCP/80 нужен для ACME. Nginx направляет raw на Xray `127.0.0.1:10443`, XHTTP — на `127.0.0.1:10444`, используя PROXY protocol. Caddy обслуживает оба домена на `127.0.0.1:9443` и перенаправляет HTTP для обоих. Оба Xray inbound должны слушать соответствующие порты и принимать PROXY protocol. UFW должен быть установлен: при установке добавляются правила allow для TCP/80, TCP/443 и TCP/9443. Caddy на 9443 слушает только loopback, поэтому правило не делает его доступным извне при текущей конфигурации. Запуск стека выполняется из `/opt/remnanode/web` командой `docker compose up -d`; Compose-проект сохраняет имя `remnanode-web`.
- При первой установке self-steal можно выбрать шаблон сайта VEILSTORE или SpeedtestFast.PRO. Если `/opt/remnanode/web/site/index.html` уже существует, повторная настройка сохраняет его без изменений. Шаблон SpeedtestFast.PRO загружает шрифты и библиотеки с внешних CDN, а тест скорости выполняет через инфраструктуру Яндекса; для полной работы браузеру нужен доступ к этим адресам.
- Настройка UFW в меню сервера (`1 → 7`) запрещает входящие подключения по умолчанию и разрешает выбранный TCP-порт SSH, `80/tcp` и `443/tcp`. Полная установка использует порт SSH, введённый в начале сценария, без повторного запроса и не спрашивает IP панели. RemnaNode сохраняет правило доступа с IP панели и портом ноды; настройка UFW восстанавливает его без повторного ввода. При отдельной настройке UFW необязательный ввод IP панели доступен, только если сохранённого правила ещё нет.
- В `/etc/ufw/before.rules` блокируются ICMPv4: для INPUT — `destination-unreachable`, `time-exceeded`, `parameter-problem`, `echo-request`, `source-quench`; для FORWARD — первые четыре типа. ICMPv6 не изменяется; блокировка `destination-unreachable` и `time-exceeded` может нарушить PMTU и сетевую диагностику.
- При установке self-steal скрипт попросит остановить системный Caddy и контейнеры, занимающие порты `80` или `443`.

### Статус, управление и CLI

Подменю RemnaNode и self-steal показывают состояние служб и доступные для него действия. Для RemnaNode доступны статус, запуск, остановка, перезапуск, логи и обновление образа. Для self-steal — статус Caddy/NGINX, домены, порты, краткое состояние SSL, управление службами, логи, проверка конфигурации и подробности сертификатов.
При ошибке действия в интерактивном меню скрипт возвращается в главное меню. Команды CLI сохраняют ненулевой код завершения при ошибке.


Без аргументов `karenet-setup` открывает меню. Те же функции доступны из командной строки:

```bash
sudo karenet-setup remnanode status
sudo karenet-setup remnanode logs
sudo karenet-setup remnanode restart
sudo karenet-setup remnanode update
sudo karenet-setup selfsteal status
sudo karenet-setup selfsteal restart
sudo karenet-setup selfsteal validate
sudo karenet-setup selfsteal cert
sudo karenet-setup firewall status
sudo karenet-setup check-updates
sudo karenet-setup update
sudo karenet-setup --version
```

Обновление скрипта выполняется только явно через `update`; при старте меню сеть не проверяется. Загрузчик сначала использует GitHub Raw, затем jsDelivr как запасной источник. Конфигурации Compose, Caddy и NGINX проверяются до запуска. При ошибке проверки или запуска скрипт восстанавливает предыдущую конфигурацию; ручные изменения не перезаписываются — рядом создаётся `.new-<версия>` и выводится diff. Для управляемых файлов сохраняются контрольная сумма `.karenet.sha256` и резервная копия `.bak`. `SECRET_KEY` хранится отдельно в `/opt/remnanode/.env` и сохраняется при повторной настройке.


---

## 📁 Структура репозитория

- `setup.sh` — интерактивный установщик с отдельными меню сервера, RemnaNode и self-steal
- `scripts/modules/` — независимые модули настройки
- `scripts/assets/selfsteal/index.html` — шаблон VEILSTORE для Caddy self-steal
- `scripts/assets/selfsteal/speedtest/index.html` — шаблон SpeedtestFast.PRO
- `scripts/utils.sh` — общие функции и helper-утилиты
- `translation/ru.sh` — русскоязычный интерфейс
- `skills/remnawave-xray/` и `.agents/skills/remnawave-xray/SKILL.md` — upstream-справочник Remnawave/Xray и его роутер; оба распространяются отдельно по AGPL-3.0

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

MIT для кода проекта, см. файл `LICENSE`. Вендоренный skill и его роутер (`skills/remnawave-xray/`, `.agents/skills/remnawave-xray/SKILL.md`) лицензированы отдельно по AGPL-3.0; см. `skills/remnawave-xray/LICENSE` и `UPSTREAM.txt`.
