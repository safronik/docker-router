#!/usr/bin/env bash
#
# Скачивает docker-router и запускает deploy-local.sh — разворачивает
# роутер одной командой на чистой машине, без предварительного git clone.
#
# Использование:
#   curl -fsSL https://raw.githubusercontent.com/safronik/docker-router/main/deploy-via-download.sh | bash
#
# Каталог назначения — DIR (по умолчанию ./router), переопределяется
# первым аргументом или переменной окружения ROUTER_DIR:
#   curl -fsSL .../deploy-via-download.sh | bash -s -- /opt/router

set -euo pipefail

readonly REPO_URL='https://github.com/safronik/docker-router.git'
readonly DIR="${1:-${ROUTER_DIR:-./router}}"

log() { printf '%s\n' "$*" >&2; }
die() { log "Ошибка: $*"; exit 1; }

command -v git >/dev/null || die 'git не найден в PATH'
command -v docker >/dev/null || die 'docker не найден в PATH'

if [[ -d "${DIR}/.git" ]]; then
	log "Репозиторий уже есть в ${DIR}, обновляю"
	git -C "${DIR}" pull --ff-only
else
	git clone "${REPO_URL}" "${DIR}"
fi

exec "${DIR}/deploy-local.sh"
