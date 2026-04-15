#!/usr/bin/env bash
# ==============================================================================
#  Matrix Synapse + Element Web + Synapse Admin UI
#  Автоматический установщик с Let's Encrypt SSL
#  Поддерживаемые ОС: Ubuntu 22.04 / 24.04, Debian 11 / 12
# ==============================================================================

set -eo pipefail
# Примечание: -u (nounset) отключён намеренно — некоторые вложенные
# команды могут создавать временные unset-переменные в subshell.
# pipefail оставлен, но для tr|head используем специальный враппер.

# Безопасная генерация случайной строки (избегает SIGPIPE/pipefail)
rand_str() {
    local len=${1:-32}
    cat /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*' 2>/dev/null \
        | dd bs=1 count="$len" 2>/dev/null
    return 0
}

# Trap для диагностики неожиданных выходов
trap 'echo -e "\n${RED}[ERROR]${RESET} Скрипт прерван на строке ${LINENO}. Команда: ${BASH_COMMAND}" >&2' ERR

# ─── Цвета для вывода ─────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }
step()    { echo -e "\n${BOLD}${CYAN}━━━ $* ━━━${RESET}"; }

# ─── Проверка прав ────────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && error "Запустите скрипт с правами root: sudo $0"

# ─── Баннер ───────────────────────────────────────────────────────────────────
clear
echo -e "${BOLD}${CYAN}"
cat << 'EOF'
  ███╗   ███╗ █████╗ ████████╗██████╗ ██╗██╗  ██╗
  ████╗ ████║██╔══██╗╚══██╔══╝██╔══██╗██║╚██╗██╔╝
  ██╔████╔██║███████║   ██║   ██████╔╝██║ ╚███╔╝
  ██║╚██╔╝██║██╔══██║   ██║   ██╔══██╗██║ ██╔██╗
  ██║ ╚═╝ ██║██║  ██║   ██║   ██║  ██║██║██╔╝ ██╗
  ╚═╝     ╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝╚═╝╚═╝  ╚═╝
EOF
echo -e "${RESET}${BOLD}  Synapse + Element + Admin UI  ·  Auto Installer${RESET}"
echo
# Разделитель под логотипом
echo -e "${CYAN}  ──────────────────────────────────────────────────${RESET}"
echo -e "  ${BOLD}Powered by Infoteq Web Studio${RESET}"
echo -e "  ${YELLOW}Enterprise IT solutions · yournewsite.ru${RESET}"
echo -e "${CYAN}  ──────────────────────────────────────────────────${RESET}"
echo

# ==============================================================================
#  ВВОД ПАРАМЕТРОВ
# ==============================================================================
step "Настройка параметров установки"

# ── Домен ─────────────────────────────────────────────────────────────────────
while true; do
    read -rp "$(echo -e "${BOLD}Введите основной домен${RESET} (например: matrix.example.com): ")" MATRIX_DOMAIN
    [[ -n "$MATRIX_DOMAIN" ]] && break
    warn "Домен не может быть пустым"
done

# ── Email для Let's Encrypt ───────────────────────────────────────────────────
while true; do
    read -rp "$(echo -e "${BOLD}Email для Let's Encrypt${RESET} (уведомления об истечении сертификата): ")" LE_EMAIL
    [[ "$LE_EMAIL" =~ ^[^@]+@[^@]+\.[^@]+$ ]] && break
    warn "Введите корректный email"
done

# ── Дополнительные субдомены ──────────────────────────────────────────────────
# Element Web будет на element.<domain>, Admin UI на admin.<domain>
ELEMENT_DOMAIN="element.${MATRIX_DOMAIN}"
ADMIN_DOMAIN="admin.${MATRIX_DOMAIN}"

# ── Имя сервера Matrix (server_name) ─────────────────────────────────────────
read -rp "$(echo -e "${BOLD}Matrix server_name${RESET} [${MATRIX_DOMAIN}]: ")" MATRIX_SERVER_NAME
MATRIX_SERVER_NAME="${MATRIX_SERVER_NAME:-$MATRIX_DOMAIN}"

# ── Регистрация новых пользователей ──────────────────────────────────────────
while true; do
    read -rp "$(echo -e "${BOLD}Разрешить публичную регистрацию?${RESET} [y/N]: ")" REG_ANSWER
    REG_ANSWER="${REG_ANSWER:-N}"
    case "${REG_ANSWER^^}" in
        Y) ENABLE_REGISTRATION="true";  break ;;
        N) ENABLE_REGISTRATION="false"; break ;;
        *) warn "Введите y или n" ;;
    esac
done

# ── PostgreSQL пароль ─────────────────────────────────────────────────────────
PG_SECRETS_FILE="/root/.matrix_install_secrets"
if [[ -f "$PG_SECRETS_FILE" ]]; then
    info "Найдены сохранённые секреты от предыдущего запуска — переиспользуем..."
    # shellcheck disable=SC1090
    source "$PG_SECRETS_FILE"
else
    PG_PASSWORD=$(rand_str 24)
fi
info "Сгенерирован/загружен пароль PostgreSQL: ${BOLD}${PG_PASSWORD}${RESET}"

# ── Подтверждение ─────────────────────────────────────────────────────────────
echo
echo -e "${BOLD}Параметры установки:${RESET}"
echo -e "  Matrix (Synapse)  : https://${MATRIX_DOMAIN}"
echo -e "  Element Web       : https://${ELEMENT_DOMAIN}"
echo -e "  Admin UI          : https://${ADMIN_DOMAIN}"
echo -e "  server_name       : ${MATRIX_SERVER_NAME}"
echo -e "  Let's Encrypt     : ${LE_EMAIL}"
echo -e "  Регистрация       : ${ENABLE_REGISTRATION}"
echo
read -rp "$(echo -e "${BOLD}Начать установку? [y/N]:${RESET} ")" CONFIRM
[[ "${CONFIRM^^}" == "Y" ]] || { info "Установка отменена"; exit 0; }

# ==============================================================================
#  УТИЛИТЫ
# ==============================================================================
apt_install() { DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"; }

wait_for_apt() {
    local locks=( /var/lib/apt/lists/lock /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend /var/cache/apt/archives/lock )
    local waited=0
    while true; do
        local busy=0
        for lock in "${locks[@]}"; do
            if fuser "$lock" &>/dev/null 2>&1; then
                busy=1; break
            fi
        done
        if [[ $busy -eq 0 ]]; then return 0; fi
        if [[ $waited -eq 0 ]]; then info "Ожидание освобождения apt lock..."; fi
        waited=$((waited + 1))
        if [[ $waited -ge 120 ]]; then
            warn "apt lock держится более 2 минут — принудительно снимаем..."
            systemctl stop unattended-upgrades 2>/dev/null || true
            kill "$(fuser /var/lib/dpkg/lock-frontend 2>/dev/null)" 2>/dev/null || true
            sleep 2
            return 0
        fi
        sleep 1
    done
}

wait_for_postgres() {
    info "Ожидание готовности PostgreSQL..."
    local retries=30
    while true; do
        if su -c "psql -c '\q'" postgres &>/dev/null; then
            return 0
        fi
        retries=$((retries - 1))
        if [[ $retries -le 0 ]]; then
            error "PostgreSQL не запустился за 30 секунд"
        fi
        sleep 1
    done
}

# ==============================================================================
#  ШАГ 1 — ЗАВИСИМОСТИ
# ==============================================================================
step "Шаг 1/8 · Обновление системы и установка зависимостей"

wait_for_apt
apt-get update -qq
apt_install \
    curl wget gnupg lsb-release ca-certificates \
    software-properties-common apt-transport-https \
    nginx certbot python3-certbot-nginx \
    postgresql postgresql-client \
    python3 python3-pip python3-venv python3-dev \
    build-essential libffi-dev libssl-dev libjpeg-dev libxslt1-dev \
    libpq-dev icu-devtools libicu-dev \
    redis-server \
    unzip git jq

success "Зависимости установлены"

# ==============================================================================
#  ШАГ 2 — POSTGRESQL
# ==============================================================================
step "Шаг 2/8 · Настройка PostgreSQL"

systemctl enable --now postgresql
wait_for_postgres

PG_USER_EXISTS=$(su -c "psql -tc \"SELECT 1 FROM pg_roles WHERE rolname='synapse'\"" postgres 2>/dev/null || echo "")
if ! echo "$PG_USER_EXISTS" | grep -q 1; then
    info "Создаём пользователя synapse в PostgreSQL..."
    su -c "psql -c \"CREATE USER synapse WITH PASSWORD '${PG_PASSWORD}';\"" postgres
else
    info "Пользователь synapse уже существует — обновляем пароль..."
    su -c "psql -c \"ALTER USER synapse WITH PASSWORD '${PG_PASSWORD}';\"" postgres
fi

PG_DB_EXISTS=$(su -c "psql -tc \"SELECT 1 FROM pg_database WHERE datname='synapse'\"" postgres 2>/dev/null || echo "")
if ! echo "$PG_DB_EXISTS" | grep -q 1; then
    su -c "psql -c \"CREATE DATABASE synapse
         ENCODING 'UTF8'
         LC_COLLATE='C'
         LC_CTYPE='C'
         template=template0
         OWNER synapse;\"" postgres
fi

success "База данных synapse создана"

# ==============================================================================
#  ШАГ 3 — MATRIX SYNAPSE
# ==============================================================================
step "Шаг 3/8 · Установка Matrix Synapse"

# Добавляем официальный apt-репозиторий Matrix.org
curl -fsSL https://packages.matrix.org/debian/matrix-org-archive-keyring.gpg \
    | gpg --dearmor -o /usr/share/keyrings/matrix-org-archive-keyring.gpg

echo "deb [signed-by=/usr/share/keyrings/matrix-org-archive-keyring.gpg] \
https://packages.matrix.org/debian/ $(lsb_release -sc) main" \
    | tee /etc/apt/sources.list.d/matrix-org.list

wait_for_apt
apt-get update -qq
apt_install matrix-synapse-py3

SYNAPSE_CONFIG_DIR="/etc/matrix-synapse"
SYNAPSE_DATA_DIR="/var/lib/matrix-synapse"
SIGNING_KEY_PATH="${SYNAPSE_DATA_DIR}/homeserver.signing.key"

# Останавливаем Synapse если был запущен
systemctl stop matrix-synapse 2>/dev/null || true

# Создаём все необходимые директории с правильными правами
mkdir -p "${SYNAPSE_DATA_DIR}/media_store"
mkdir -p "${SYNAPSE_DATA_DIR}/uploads"
mkdir -p /var/log/matrix-synapse
chown -R matrix-synapse:matrix-synapse "${SYNAPSE_DATA_DIR}"
chown -R matrix-synapse:matrix-synapse /var/log/matrix-synapse
chmod 750 "${SYNAPSE_DATA_DIR}"

# Генерируем signing key через generate_signing_key (надёжнее чем --generate-keys)
if [[ ! -f "$SIGNING_KEY_PATH" ]]; then
    python3 -m synapse.util.generate_signing_key \
        > "$SIGNING_KEY_PATH" 2>/dev/null \
    || python3 -c "
import nacl.signing, base64, sys
key = nacl.signing.SigningKey.generate()
pub = base64.b64encode(key.verify_key.encode()).decode()
prv = base64.b64encode(key.encode()).decode()
print(f'ed25519 a_auto {prv}')
" > "$SIGNING_KEY_PATH" 2>/dev/null \
    || {
        # Крайний fallback — через generate-config
        python3 -m synapse.app.homeserver \
            --server-name "$MATRIX_SERVER_NAME" \
            --config-path "${SYNAPSE_CONFIG_DIR}/homeserver.yaml" \
            --generate-config \
            --report-stats=no 2>/dev/null || true
        # Берём путь к ключу из сгенерированного конфига
        if [[ -f "${SYNAPSE_CONFIG_DIR}/homeserver.yaml" ]]; then
            GEN_KEY=$(grep 'signing_key_path' "${SYNAPSE_CONFIG_DIR}/homeserver.yaml" \
                      | awk '{print $2}' | tr -d '"' || echo "")
            [[ -n "$GEN_KEY" && -f "$GEN_KEY" ]] && cp "$GEN_KEY" "$SIGNING_KEY_PATH"
        fi
    }
fi

[[ -f "$SIGNING_KEY_PATH" ]] || error "Не удалось создать signing key"
chown matrix-synapse:matrix-synapse "$SIGNING_KEY_PATH"
chmod 600 "$SIGNING_KEY_PATH"
info "Signing key: $(head -c 40 "$SIGNING_KEY_PATH")..."

# Пакет грузит конфиги в порядке:
#   1. homeserver.yaml  2. conf.d/*.yaml  (conf.d перекрывает!)
# ExecStartPre --generate-keys создаёт conf.d/server_name.yaml с 'None' при каждом старте.
# Правильное решение: заполнить conf.d нужными значениями самим —
# тогда --generate-keys увидит существующий файл и не тронет его.
mkdir -p "${SYNAPSE_CONFIG_DIR}/conf.d"

info "Записываем conf.d/server_name.yaml..."
cat > "${SYNAPSE_CONFIG_DIR}/conf.d/server_name.yaml" << CONFYAML
server_name: "${MATRIX_SERVER_NAME}"
report_stats: false
CONFYAML

info "Содержимое conf.d после записи:"
cat "${SYNAPSE_CONFIG_DIR}/conf.d/server_name.yaml"

# Убеждаемся что server_name реально задан
[[ -z "$MATRIX_SERVER_NAME" ]] && error "MATRIX_SERVER_NAME пустой!"
MACAROON_SECRET=$(rand_str 64)
REGISTRATION_SECRET=$(rand_str 64)
FORM_SECRET=$(rand_str 64)

# Сохраняем секреты для идемпотентных повторных запусков
cat > "$PG_SECRETS_FILE" << SECRETS
PG_PASSWORD="${PG_PASSWORD}"
MACAROON_SECRET="${MACAROON_SECRET}"
REGISTRATION_SECRET="${REGISTRATION_SECRET}"
FORM_SECRET="${FORM_SECRET}"
SECRETS
chmod 600 "$PG_SECRETS_FILE"

# ── Основной homeserver.yaml ──────────────────────────────────────────────────
cat > "${SYNAPSE_CONFIG_DIR}/homeserver.yaml" << SYNAPSE_YAML
# Matrix Synapse — homeserver.yaml
# Сгенерировано автоматически $(date)

server_name: "${MATRIX_SERVER_NAME}"
public_baseurl: "https://${MATRIX_DOMAIN}/"

# Порты
listeners:
  - port: 8008
    tls: false
    type: http
    bind_addresses: ['127.0.0.1']
    x_forwarded: true
    resources:
      - names: [client, federation]
        compress: false

# База данных
database:
  name: psycopg2
  args:
    user: synapse
    password: "${PG_PASSWORD}"
    database: synapse
    host: localhost
    port: 5432
    cp_min: 5
    cp_max: 10

# Логирование
log_config: "/etc/matrix-synapse/log.yaml"

# Хранилище медиафайлов
media_store_path: "${SYNAPSE_DATA_DIR}/media_store"
max_upload_size: 100M
url_preview_enabled: false

# Ключи
signing_key_path: "${SIGNING_KEY_PATH}"
macaroon_secret_key: "${MACAROON_SECRET}"
form_secret: "${FORM_SECRET}"

# Регистрация
enable_registration: ${ENABLE_REGISTRATION}
registration_requires_token: false
registration_shared_secret: "${REGISTRATION_SECRET}"

# Безопасность
bcrypt_rounds: 12
allow_guest_access: false
enable_metrics: true

# Push-уведомления
push:
  include_content: false

# Федерация
federation_domain_whitelist: ~

# Redis (для worker-режима и кэша)
redis:
  enabled: true
  host: localhost
  port: 6379

# Ограничения
rc_message:
  per_second: 0.2
  burst_count: 10
rc_registration:
  per_second: 0.17
  burst_count: 3
rc_login:
  address:
    per_second: 0.17
    burst_count: 3
  account:
    per_second: 0.17
    burst_count: 3
  failed_attempts:
    per_second: 0.17
    burst_count: 3

# Retention (автоочистка)
retention:
  enabled: true
  default_policy:
    min_lifetime: 1d
    max_lifetime: 1y
  allowed_lifetime_min: 1d
  allowed_lifetime_max: 1y
  purge_jobs:
    - longest_max_lifetime: 3d
      interval: 12h
    - interval: 1d

# Thumbnail
thumbnail_sizes:
  - width: 32
    height: 32
    method: crop
  - width: 96
    height: 96
    method: crop
  - width: 320
    height: 240
    method: scale
  - width: 640
    height: 480
    method: scale
  - width: 800
    height: 600
    method: scale

# Trusted key servers
trusted_key_servers:
  - server_name: "matrix.org"

suppress_key_server_warning: true
SYNAPSE_YAML

# ── log.yaml ─────────────────────────────────────────────────────────────────
cat > "${SYNAPSE_CONFIG_DIR}/log.yaml" << 'LOG_YAML'
version: 1
formatters:
  precise:
    format: '%(asctime)s - %(name)s - %(lineno)d - %(levelname)s - %(request)s - %(message)s'
handlers:
  file:
    class: logging.handlers.TimedRotatingFileHandler
    formatter: precise
    filename: /var/log/matrix-synapse/homeserver.log
    when: midnight
    backupCount: 3
  console:
    class: logging.StreamHandler
    formatter: precise
loggers:
  synapse.storage.SQL:
    level: WARNING
root:
  level: WARNING
  handlers: [file, console]
disable_existing_loggers: false
LOG_YAML

mkdir -p /var/log/matrix-synapse
chown matrix-synapse:matrix-synapse /var/log/matrix-synapse

# Быстрая проверка YAML-синтаксиса
info "Проверка конфигурации Synapse..."
python3 -c "
import yaml, sys
with open('${SYNAPSE_CONFIG_DIR}/homeserver.yaml') as f:
    cfg = yaml.safe_load(f)
sn = cfg.get('server_name', '')
if not sn or sn == 'None':
    print('ERROR: server_name пустой или None!', file=sys.stderr)
    sys.exit(1)
print(f'  server_name : {sn}')
print(f'  listeners   : {len(cfg.get(\"listeners\", []))}')
print(f'  database    : {cfg.get(\"database\", {}).get(\"name\",\"?\")}')
" || error "Ошибка в homeserver.yaml"

systemctl enable matrix-synapse

# Сбрасываем счётчик рестартов (сервис мог зациклиться ещё до нашей установки)
systemctl stop matrix-synapse  2>/dev/null || true
systemctl reset-failed matrix-synapse 2>/dev/null || true
sleep 2

systemctl start matrix-synapse || {
    echo -e "\n${RED}Synapse не запустился. Логи:${RESET}"
    journalctl -u matrix-synapse --no-pager -n 40
    echo -e "\n${RED}Реальный конфиг (первые 20 строк):${RESET}"
    head -20 "${SYNAPSE_CONFIG_DIR}/homeserver.yaml"
    echo -e "\n${YELLOW}Содержимое conf.d/:${RESET}"
    ls -la "${SYNAPSE_CONFIG_DIR}/conf.d/" 2>/dev/null && \
        cat "${SYNAPSE_CONFIG_DIR}/conf.d/"*.yaml 2>/dev/null || echo "(пусто)"
    echo -e "\n${YELLOW}ExecStart из systemd unit:${RESET}"
    systemctl cat matrix-synapse | grep -i exec
    error "matrix-synapse.service failed. См. логи выше"
}

# Ждём готовности HTTP
info "Ожидание готовности Synapse API..."
local_retries=20
while ! curl -sf http://127.0.0.1:8008/_matrix/client/versions &>/dev/null; do
    local_retries=$((local_retries - 1))
    if [[ $local_retries -le 0 ]]; then
        warn "API ещё не отвечает — продолжаем установку"
        break
    fi
    sleep 2
done

success "Matrix Synapse установлен и запущен"

# ==============================================================================
#  ШАГ 4 — LET'S ENCRYPT (предварительно — временный nginx)
# ==============================================================================
step "Шаг 4/8 · Получение SSL-сертификатов Let's Encrypt"

# Базовый nginx для прохождения ACME-челленджа
mkdir -p /var/www/html
cat > /etc/nginx/sites-available/acme-challenge << 'NGINX_ACME'
server {
    listen 80;
    server_name _;
    root /var/www/html;
    location /.well-known/acme-challenge/ { try_files $uri =404; }
    location / { return 301 https://$host$request_uri; }
}
NGINX_ACME

ln -sf /etc/nginx/sites-available/acme-challenge /etc/nginx/sites-enabled/acme-challenge
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx || systemctl start nginx

# Запрашиваем сертификаты для всех трёх доменов
set +e
certbot certonly \
    --nginx \
    --non-interactive \
    --agree-tos \
    --email "$LE_EMAIL" \
    --domains "${MATRIX_DOMAIN},${ELEMENT_DOMAIN},${ADMIN_DOMAIN}"
CERTBOT_RC=$?
set -e

if [[ $CERTBOT_RC -ne 0 ]]; then
    warn "Не удалось получить один сертификат для всех доменов — пробуем по одному..."
    for DOMAIN in "$MATRIX_DOMAIN" "$ELEMENT_DOMAIN" "$ADMIN_DOMAIN"; do
        set +e
        certbot certonly \
            --nginx --non-interactive --agree-tos \
            --email "$LE_EMAIL" --domain "$DOMAIN"
        [[ $? -ne 0 ]] && warn "Сертификат для ${DOMAIN} не получен (DNS не пробился?)"
        set -e
    done
fi

success "SSL-сертификаты получены"

# ==============================================================================
#  ШАГ 5 — ELEMENT WEB
# ==============================================================================
step "Шаг 5/8 · Установка Element Web"

ELEMENT_DIR="/var/www/element"
mkdir -p "$ELEMENT_DIR"

# Получаем актуальную версию
ELEMENT_VERSION=$(curl -s https://api.github.com/repos/element-hq/element-web/releases/latest \
    | jq -r '.tag_name' 2>/dev/null || echo "v1.11.85")

info "Скачиваем Element Web ${ELEMENT_VERSION}..."
ELEMENT_URL="https://github.com/element-hq/element-web/releases/download/${ELEMENT_VERSION}/element-${ELEMENT_VERSION}.tar.gz"

TMP_DIR=$(mktemp -d)
curl -fsSL "$ELEMENT_URL" -o "${TMP_DIR}/element.tar.gz"
tar -xzf "${TMP_DIR}/element.tar.gz" -C "${TMP_DIR}"
cp -r "${TMP_DIR}/element-${ELEMENT_VERSION}/." "$ELEMENT_DIR/"
rm -rf "$TMP_DIR"

# Конфиг Element
cat > "${ELEMENT_DIR}/config.json" << ELEMENT_CONFIG
{
    "default_server_config": {
        "m.homeserver": {
            "base_url": "https://${MATRIX_DOMAIN}",
            "server_name": "${MATRIX_SERVER_NAME}"
        },
        "m.identity_server": {
            "base_url": "https://vector.im"
        }
    },
    "brand": "Element",
    "integrations_ui_url": "https://scalar.vector.im/",
    "integrations_rest_url": "https://scalar.vector.im/api",
    "integrations_widgets_urls": [
        "https://scalar.vector.im/_matrix/integrations/v1",
        "https://scalar.vector.im/api",
        "https://scalar-staging.vector.im/_matrix/integrations/v1",
        "https://scalar-staging.vector.im/api",
        "https://scalar-staging.riot.im/_matrix/integrations/v1"
    ],
    "hosting_signup_link": "https://element.io/matrix-services?utm_source=element-web&utm_medium=web",
    "bug_report_endpoint_url": "https://element.io/bugreports/submit",
    "uisi_autorageshake_app": "element-auto-uisi",
    "showLabsSettings": false,
    "piwik": false,
    "roomDirectory": {
        "servers": ["${MATRIX_SERVER_NAME}"]
    },
    "enable_presence_by_hs_url": {
        "https://${MATRIX_DOMAIN}": false,
        "https://matrix.org": false
    },
    "setting_defaults": {
        "breadcrumbs": true
    },
    "jitsi": {
        "preferred_domain": "meet.element.io"
    }
}
ELEMENT_CONFIG

chown -R www-data:www-data "$ELEMENT_DIR"
success "Element Web ${ELEMENT_VERSION} установлен"

# ==============================================================================
#  ШАГ 6 — SYNAPSE ADMIN UI
# ==============================================================================
step "Шаг 6/8 · Установка Synapse Admin UI"

ADMIN_DIR="/var/www/synapse-admin"
mkdir -p "$ADMIN_DIR"

# Получаем актуальную версию
ADMIN_VERSION=$(curl -s https://api.github.com/repos/Awesome-Technologies/synapse-admin/releases/latest \
    | jq -r '.tag_name' 2>/dev/null || echo "0.10.3")

info "Скачиваем Synapse Admin ${ADMIN_VERSION}..."
ADMIN_URL="https://github.com/Awesome-Technologies/synapse-admin/releases/download/${ADMIN_VERSION}/synapse-admin-${ADMIN_VERSION}.tar.gz"

TMP_DIR=$(mktemp -d)
curl -fsSL "$ADMIN_URL" -o "${TMP_DIR}/admin.tar.gz"
tar -xzf "${TMP_DIR}/admin.tar.gz" -C "${TMP_DIR}"

# tar может создать папку с или без префикса версии
EXTRACTED=$(find "${TMP_DIR}" -maxdepth 1 -type d | grep -v "^${TMP_DIR}$" | head -1)
cp -r "${EXTRACTED}/." "$ADMIN_DIR/"
rm -rf "$TMP_DIR"

chown -R www-data:www-data "$ADMIN_DIR"
success "Synapse Admin UI ${ADMIN_VERSION} установлен"

# ==============================================================================
#  ШАГ 7 — NGINX (финальная конфигурация)
# ==============================================================================
step "Шаг 7/8 · Настройка Nginx"

# Вспомогательная функция — путь к cert/key
cert_path() { echo "/etc/letsencrypt/live/${1}/fullchain.pem"; }
key_path()  { echo "/etc/letsencrypt/live/${1}/privkey.pem"; }

# Определяем, получили ли мы один wildcard-сертификат или отдельные
SSL_CERT=$(cert_path "$MATRIX_DOMAIN")
SSL_KEY=$(key_path  "$MATRIX_DOMAIN")

# Если сертификат для element-домена отдельный — используем его, иначе общий
[[ -f "$(cert_path "$ELEMENT_DOMAIN")" ]] \
    && ELEMENT_CERT=$(cert_path "$ELEMENT_DOMAIN") ELEMENT_KEY=$(key_path "$ELEMENT_DOMAIN") \
    || ELEMENT_CERT="$SSL_CERT" ELEMENT_KEY="$SSL_KEY"

[[ -f "$(cert_path "$ADMIN_DOMAIN")" ]] \
    && ADMIN_CERT=$(cert_path "$ADMIN_DOMAIN") ADMIN_KEY=$(key_path "$ADMIN_DOMAIN") \
    || ADMIN_CERT="$SSL_CERT" ADMIN_KEY="$SSL_KEY"

rm -f /etc/nginx/sites-enabled/acme-challenge

# ── matrix.domain — Synapse + .well-known ────────────────────────────────────
cat > /etc/nginx/sites-available/matrix << NGINX_MATRIX
# ─ Matrix Synapse ────────────────────────────────────────────────────────────
server {
    listen 80;
    server_name ${MATRIX_DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${MATRIX_DOMAIN};

    ssl_certificate     ${SSL_CERT};
    ssl_certificate_key ${SSL_KEY};
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 10m;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options SAMEORIGIN always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Matrix .well-known (автообнаружение клиентов)
    location /.well-known/matrix/client {
        return 200 '{"m.homeserver": {"base_url": "https://${MATRIX_DOMAIN}"}, "m.identity_server": {"base_url": "https://vector.im"}}';
        add_header Content-Type application/json;
        add_header Access-Control-Allow-Origin *;
    }

    location /.well-known/matrix/server {
        return 200 '{"m.server": "${MATRIX_DOMAIN}:443"}';
        add_header Content-Type application/json;
        add_header Access-Control-Allow-Origin *;
    }

    # Synapse API
    location ~ ^(/_matrix|/_synapse/client) {
        proxy_pass         http://localhost:8008;
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto https;
        proxy_http_version 1.1;
        proxy_buffering    off;
        client_max_body_size 100M;
    }

    # Synapse Admin API (доступ только с Admin UI)
    location /_synapse/admin {
        proxy_pass         http://localhost:8008;
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto https;
        proxy_http_version 1.1;
        client_max_body_size 100M;
    }
}

# ─ Federation порт 8448 ──────────────────────────────────────────────────────
server {
    listen 8448 ssl http2;
    server_name ${MATRIX_DOMAIN};

    ssl_certificate     ${SSL_CERT};
    ssl_certificate_key ${SSL_KEY};
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    location / {
        proxy_pass         http://localhost:8008;
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto https;
        proxy_http_version 1.1;
        client_max_body_size 100M;
    }
}
NGINX_MATRIX

# ── element.domain ────────────────────────────────────────────────────────────
cat > /etc/nginx/sites-available/element << NGINX_ELEMENT
server {
    listen 80;
    server_name ${ELEMENT_DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${ELEMENT_DOMAIN};

    ssl_certificate     ${ELEMENT_CERT};
    ssl_certificate_key ${ELEMENT_KEY};
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    root  ${ELEMENT_DIR};
    index index.html;

    add_header Strict-Transport-Security "max-age=31536000" always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options SAMEORIGIN always;

    # Кэширование статики
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)\$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
NGINX_ELEMENT

# ── admin.domain ──────────────────────────────────────────────────────────────
cat > /etc/nginx/sites-available/synapse-admin << NGINX_ADMIN
server {
    listen 80;
    server_name ${ADMIN_DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${ADMIN_DOMAIN};

    ssl_certificate     ${ADMIN_CERT};
    ssl_certificate_key ${ADMIN_KEY};
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    root  ${ADMIN_DIR};
    index index.html;

    # Ограничиваем доступ по IP (опционально — раскомментируй и укажи свой IP)
    # allow 1.2.3.4;
    # deny all;

    add_header Strict-Transport-Security "max-age=31536000" always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options DENY always;

    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
NGINX_ADMIN

# Активируем сайты
ln -sf /etc/nginx/sites-available/matrix        /etc/nginx/sites-enabled/
ln -sf /etc/nginx/sites-available/element       /etc/nginx/sites-enabled/
ln -sf /etc/nginx/sites-available/synapse-admin /etc/nginx/sites-enabled/

# Настройка nginx.conf
sed -i 's/# server_tokens off;/server_tokens off;/' /etc/nginx/nginx.conf || true

nginx -t || error "Ошибка в конфигурации Nginx!"
systemctl reload nginx

success "Nginx настроен"

# ==============================================================================
#  ШАГ 8 — ПОСТ-УСТАНОВКА
# ==============================================================================
step "Шаг 8/8 · Финальная настройка"

# Автообновление сертификатов
systemctl enable --now certbot.timer 2>/dev/null || {
    # Fallback: cron
    CRON_JOB="0 3 * * * /usr/bin/certbot renew --quiet --post-hook 'systemctl reload nginx'"
    (crontab -l 2>/dev/null | grep -qF 'certbot renew') \
        || (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
}

# Создаём первого admin-пользователя
ADMIN_USER="admin"
ADMIN_PASSWORD=$(rand_str 16)

info "Создание пользователя-администратора..."
set +e
register_new_matrix_user \
    -c "${SYNAPSE_CONFIG_DIR}/homeserver.yaml" \
    -u "$ADMIN_USER" \
    -p "$ADMIN_PASSWORD" \
    -a
REG_RC=$?
set -e
[[ $REG_RC -ne 0 ]] && warn "Пользователь уже существует или временная ошибка (не критично)"

# Права на файлы
chown -R matrix-synapse:matrix-synapse "$SYNAPSE_DATA_DIR"

# Перезапускаем все сервисы
systemctl restart matrix-synapse redis-server nginx

# ==============================================================================
#  ИТОГ
# ==============================================================================
echo
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${GREEN}║          ✅  УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО!               ║${RESET}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════╝${RESET}"
echo
echo -e "${BOLD}URLs:${RESET}"
echo -e "  🔒 Matrix Synapse   : ${CYAN}https://${MATRIX_DOMAIN}${RESET}"
echo -e "  💬 Element Web      : ${CYAN}https://${ELEMENT_DOMAIN}${RESET}"
echo -e "  🛠  Admin UI         : ${CYAN}https://${ADMIN_DOMAIN}${RESET}"
echo
echo -e "${BOLD}Данные администратора:${RESET}"
echo -e "  Логин    : ${YELLOW}${ADMIN_USER}${RESET}"
echo -e "  Пароль   : ${YELLOW}${ADMIN_PASSWORD}${RESET}"
echo -e "  MXID     : ${YELLOW}@${ADMIN_USER}:${MATRIX_SERVER_NAME}${RESET}"
echo
echo -e "${BOLD}База данных PostgreSQL:${RESET}"
echo -e "  Пользователь : synapse"
echo -e "  Пароль       : ${YELLOW}${PG_PASSWORD}${RESET}"
echo -e "  База данных  : synapse"
echo
echo -e "${BOLD}${RED}⚠  Сохраните пароли в надёжном месте!${RESET}"
echo
echo -e "${BOLD}Управление сервисом:${RESET}"
echo -e "  sudo systemctl restart matrix-synapse"
echo -e "  sudo systemctl status  matrix-synapse"
echo -e "  sudo journalctl -u matrix-synapse -f"
echo
echo -e "${BOLD}DNS-записи (должны быть настроены ЗАРАНЕЕ):${RESET}"
echo -e "  A  ${MATRIX_DOMAIN}  →  <IP сервера>"
echo -e "  A  ${ELEMENT_DOMAIN}  →  <IP сервера>"
echo -e "  A  ${ADMIN_DOMAIN}  →  <IP сервера>"
echo -e "  SRV _matrix._tcp.${MATRIX_SERVER_NAME}  443  ${MATRIX_DOMAIN}"
echo
echo -e "${BOLD}Для входа в Admin UI используйте:${RESET}"
echo -e "  Homeserver URL : ${CYAN}https://${MATRIX_DOMAIN}${RESET}"
echo -e "  Username       : ${YELLOW}${ADMIN_USER}${RESET}"
echo -e "  Password       : ${YELLOW}${ADMIN_PASSWORD}${RESET}"
echo
