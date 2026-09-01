#!/usr/bin/env bash
#
# Установка роутера: спрашивает DEFAULT_EMAIL, кладёт его в .env и
# поднимает стек через docker compose.
#
# DEFAULT_EMAIL нужен контейнеру letsencrypt (docker-compose.yml) —
# на этот адрес приходят уведомления Let's Encrypt об истечении
# сертификатов при сбое автопродления.
#
# Использование:
#   ./deploy.sh

set -euo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ENV_FILE="${ROOT}/.env"

log() { printf '%s\n' "$*" >&2; }
die() { log "Ошибка: $*"; exit 1; }

command -v docker >/dev/null || die 'docker не найден в PATH'

existing_email=''
[[ -f "${ENV_FILE}" ]] && existing_email="$(sed -n 's/^DEFAULT_EMAIL=//p' "${ENV_FILE}")"

prompt="Email для Let's Encrypt (DEFAULT_EMAIL)"
[[ -n "${existing_email}" ]] && prompt+=" [${existing_email}]"
read -rp "${prompt}: " input_email
email="${input_email:-${existing_email}}"

[[ -n "${email}" ]] || die 'email не может быть пустым'
[[ "${email}" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]] \
	|| die "некорректный email: ${email}"

if [[ -f "${ENV_FILE}" ]] && grep -q '^DEFAULT_EMAIL=' "${ENV_FILE}"; then
	sed -i "s|^DEFAULT_EMAIL=.*|DEFAULT_EMAIL=${email}|" "${ENV_FILE}"
else
	printf 'DEFAULT_EMAIL=%s\n' "${email}" >> "${ENV_FILE}"
fi

log "DEFAULT_EMAIL=${email} записан в ${ENV_FILE}"

"${ROOT}/bin/gen-default-cert.sh"

docker compose -f "${ROOT}/docker-compose.yml" up -d

log 'Роутер запущен: docker compose ps для проверки статуса.'
