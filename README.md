# Matrix Auto Installer

<div align="center">

```
  ███╗   ███╗ █████╗ ████████╗██████╗ ██╗██╗  ██╗
  ████╗ ████║██╔══██╗╚══██╔══╝██╔══██╗██║╚██╗██╔╝
  ██╔████╔██║███████║   ██║   ██████╔╝██║ ╚███╔╝
  ██║╚██╔╝██║██╔══██║   ██║   ██╔══██╗██║ ██╔██╗
  ██║ ╚═╝ ██║██║  ██║   ██║   ██║  ██║██║██╔╝ ██╗
  ╚═╝     ╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝╚═╝╚═╝  ╚═╝
```

**Synapse + Element Web + Admin UI · One-command installer**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04%20%2F%2024.04-orange)](https://ubuntu.com)
[![Debian](https://img.shields.io/badge/Debian-11%20%2F%2012-red)](https://debian.org)

*Powered by [Infoteq Web Studio](https://yournewsite.ru) — Enterprise IT solutions*

</div>

---

Автоматическая установка полного стека Matrix-сервера в одну команду:

- **[Matrix Synapse](https://github.com/element-hq/synapse)** — homeserver протокола Matrix
- **[Element Web](https://github.com/element-hq/element-web)** — веб-клиент для общения
- **[Synapse Admin UI](https://github.com/Awesome-Technologies/synapse-admin)** — панель управления пользователями и комнатами
- **PostgreSQL** — база данных
- **Redis** — кэш и очереди
- **Nginx** — reverse proxy с SSL
- **Let's Encrypt** — бесплатные TLS-сертификаты с автопродлением

---

## Требования

### Сервер

| Параметр | Минимум | Рекомендуется |
|---|---|---|
| ОС | Ubuntu 22.04 / Debian 11 | Ubuntu 24.04 / Debian 12 |
| CPU | 1 vCPU | 2 vCPU |
| RAM | 2 GB | 4 GB |
| Диск | 20 GB SSD | 40+ GB SSD |
| Доступ | root или sudo | root |

> **Важно:** сервер должен иметь **публичный статический IP-адрес**.  
> Порты **80**, **443** и **8448** должны быть открыты в firewall.

### Программное обеспечение

На сервере должны быть доступны:

- `bash` 4.0+
- `curl` или `wget`
- `git`

Всё остальное скрипт устанавливает автоматически.

---

## Шаг 1 — Подготовка DNS

До запуска скрипта необходимо создать **три A-записи** в DNS вашего домена.

Предположим, ваш основной домен — `example.com`, а IP сервера — `1.2.3.4`:

| Тип | Имя | Значение | TTL |
|---|---|---|---|
| `A` | `matrix.example.com` | `1.2.3.4` | 300 |
| `A` | `element.example.com` | `1.2.3.4` | 300 |
| `A` | `admin.example.com` | `1.2.3.4` | 300 |

Дополнительно — SRV-запись для федерации с другими Matrix-серверами:

| Тип | Имя | Значение |
|---|---|---|
| `SRV` | `_matrix._tcp.example.com` | `10 5 443 matrix.example.com` |

> ⏱ **Дождитесь распространения DNS** перед запуском скрипта.  
> Проверить можно командой: `dig +short matrix.example.com` — должен вернуть IP вашего сервера.  
> Или через сервис [dnschecker.org](https://dnschecker.org).

---

## Шаг 2 — Подготовьте данные для установки

Скрипт задаст четыре вопроса. Подготовьте ответы заранее:

**1. Основной домен Matrix-сервера**
```
matrix.example.com
```
На этом домене будет работать Synapse API. Element и Admin UI получат субдомены автоматически (`element.example.com`, `admin.example.com`).

**2. Email для Let's Encrypt**
```
admin@example.com
```
На этот адрес будут приходить уведомления об истечении сертификата. Достаточно обычного рабочего email.

**3. Matrix server_name**
```
matrix.example.com  (или просто example.com, если хотите MXID вида @user:example.com)
```
Это идентификатор вашего сервера в сети Matrix — часть после `@` в адресах пользователей.  
Если хотите короткие адреса вида `@alice:example.com`, введите `example.com` и дополнительно настройте `.well-known` на корневом домене.  
Для простоты оставьте равным основному домену.

**4. Публичная регистрация**
```
y — разрешить (любой может создать аккаунт)
n — закрытый сервер (пользователей создаёт администратор)
```

---

## Шаг 3 — Установка

### Быстрый старт (одна команда)

```bash
curl -fsSL https://raw.githubusercontent.com/maximchayka/matrixinstaller/main/install-matrix.sh | sudo bash
```

### Рекомендуемый способ (с проверкой скрипта)

```bash
# Клонируем репозиторий
git clone https://github.com/maximchayka/matrixinstaller.git
cd matrixinstaller

# Смотрим что будет выполнено
cat install-matrix.sh

# Запускаем
sudo bash install-matrix.sh
```

> 💡 Рекомендуем второй способ — всегда полезно знать, что именно запускается с правами root.

### Ход установки

Скрипт выполняет 8 шагов автоматически (~5–10 минут):

```
━━━ Шаг 1/8 · Обновление системы и установка зависимостей ━━━
━━━ Шаг 2/8 · Настройка PostgreSQL ━━━
━━━ Шаг 3/8 · Установка Matrix Synapse ━━━
━━━ Шаг 4/8 · Получение SSL-сертификатов Let's Encrypt ━━━
━━━ Шаг 5/8 · Установка Element Web ━━━
━━━ Шаг 6/8 · Установка Synapse Admin UI ━━━
━━━ Шаг 7/8 · Настройка Nginx ━━━
━━━ Шаг 8/8 · Финальная настройка ━━━
```

По завершении скрипт выведет все URL, логины и пароли.

> ⚠️ **Сохраните вывод скрипта!** Пароли отображаются только один раз.

---

## Результат установки

После успешной установки будут доступны:

| Сервис | URL | Назначение |
|---|---|---|
| Matrix Synapse | `https://matrix.example.com` | API, Federation |
| Element Web | `https://element.example.com` | Веб-клиент для пользователей |
| Synapse Admin UI | `https://admin.example.com` | Управление сервером |

### Вход в Admin UI

1. Откройте `https://admin.example.com`
2. В поле **Homeserver URL** введите `https://matrix.example.com`
3. Введите логин `admin` и пароль из вывода скрипта

---

## Управление сервисами

```bash
# Статус
sudo systemctl status matrix-synapse

# Перезапуск
sudo systemctl restart matrix-synapse

# Логи в реальном времени
sudo journalctl -u matrix-synapse -f

# Перезапуск всего стека
sudo systemctl restart matrix-synapse redis-server nginx
```

### Создание дополнительных пользователей

```bash
# Обычный пользователь
sudo register_new_matrix_user \
  -c /etc/matrix-synapse/homeserver.yaml \
  -u username -p password

# Администратор
sudo register_new_matrix_user \
  -c /etc/matrix-synapse/homeserver.yaml \
  -u username -p password -a
```

### Продление сертификатов

Сертификаты продлеваются автоматически через `certbot.timer` (systemd) или cron.  
Проверить вручную:

```bash
sudo certbot renew --dry-run
```

---

## Структура файлов

```
/etc/matrix-synapse/
├── homeserver.yaml        # основной конфиг Synapse
├── conf.d/
│   └── server_name.yaml   # server_name и report_stats
└── log.yaml               # конфигурация логирования

/var/lib/matrix-synapse/
├── homeserver.signing.key # ключ подписи (не удалять!)
└── media_store/           # загруженные файлы и медиа

/var/www/
├── element/               # Element Web
└── synapse-admin/         # Synapse Admin UI

/etc/nginx/sites-available/
├── matrix                 # конфиг для Synapse + federation
├── element                # конфиг для Element Web
└── synapse-admin          # конфиг для Admin UI

/root/.matrix_install_secrets  # сохранённые пароли (600)
```

---

## Устранение неполадок

**Synapse не запускается**
```bash
journalctl -u matrix-synapse --no-pager -n 50
cat /etc/matrix-synapse/conf.d/server_name.yaml
```

**Ошибка подключения к PostgreSQL**
```bash
# Синхронизировать пароль из конфига с PostgreSQL
PG_PASS=$(grep 'password:' /etc/matrix-synapse/homeserver.yaml | awk '{print $2}' | tr -d '"')
sudo -u postgres psql -c "ALTER USER synapse WITH PASSWORD '${PG_PASS}';"
```

**Let's Encrypt не выдаёт сертификат**
```bash
# Проверить что DNS пробился
dig +short matrix.example.com
dig +short element.example.com
dig +short admin.example.com

# Убедиться что порт 80 открыт
curl -v http://matrix.example.com/.well-known/acme-challenge/test
```

**Nginx ошибка конфигурации**
```bash
sudo nginx -t
sudo journalctl -u nginx --no-pager -n 20
```

---

## Безопасность

После установки рекомендуется:

- [ ] Ограничить доступ к Admin UI по IP (раскомментировать `allow`/`deny` в nginx конфиге)
- [ ] Настроить `ufw` или `iptables`: открыть только порты 22, 80, 443, 8448
- [ ] Сохранить `/root/.matrix_install_secrets` в защищённом хранилище и удалить с сервера
- [ ] Сменить пароль администратора Matrix через Element Web

---

## Лицензия

MIT © [Infoteq LLC](https://yournewsite.ru)

---

<div align="center">

**Powered by [Infoteq Web Studio](https://yournewsite.ru)**  
Enterprise IT solutions · [yournewsite.ru](https://yournewsite.ru)

</div>
