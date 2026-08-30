#!/usr/bin/env bash
#
# Генерирует self-signed сертификат-заглушку certs/default.{crt,key}.
#
# Зачем: nginx-proxy подставляет default.crt в каждый server-блок, для которого
# нет настоящего сертификата (все хосты .loc). Без файла nginx не стартует.
# В git сертификаты не хранятся (certs/* в .gitignore), поэтому в свежем
# checkout их надо создать этим скриптом до `docker compose up -d`.
#
# acme-companion умеет создавать эту заглушку сам, но в v2.6.3 печатает:
# "there is no future support planned for the self signed default certificate
# creation feature and it might be removed in a future release" — полагаться
# на него нельзя.
#
# CN=acme-companion выставляется намеренно: только с таким CN companion
# считает сертификат своим и перевыпускает его, когда до истечения остаётся
# меньше 90 дней (/app/entrypoint.sh, функция check_default_cert_key).
# С любым другим CN сертификат считается пользовательским и тихо протухает.
#
# dhparam здесь не генерируется: nginx-proxy 1.11 сам кладёт в
# /etc/nginx/dhparam/dhparam.pem стандартную группу RFC 7919 ffdhe4096,
# если файла нет, и предупреждает, если подложен свой.
#
# Использование:
#   bin/gen-default-cert.sh            # создать, если нет или протухает
#   bin/gen-default-cert.sh --force    # перевыпустить безусловно
#   DAYS=825 bin/gen-default-cert.sh   # свой срок вместо 365 дней

set -euo pipefail

# Git Bash / MSYS переписывает аргумент /CN=... в путь Windows, из-за чего
# openssl req -subj падает. Исключаем только его: остальные аргументы —
# пути вида /d/code/... — конвертировать по-прежнему нужно, нативный
# openssl.exe понимает только D:\code\... На Linux переменная игнорируется.
export MSYS2_ARG_CONV_EXCL='/CN='

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly CERTS="${ROOT}/certs"
readonly CRT="${CERTS}/default.crt"
readonly KEY="${CERTS}/default.key"
readonly CN='acme-companion'
readonly DAYS="${DAYS:-365}"
readonly RENEW_BEFORE=$((90 * 24 * 3600))   # 90 дней в секундах
readonly FALLBACK_IMAGE='nginxproxy/acme-companion:2.6'

FORCE=0
[[ "${1:-}" == '--force' ]] && FORCE=1

log() { printf '%s\n' "$*" >&2; }
die() { log "Ошибка: $*"; exit 1; }

# Ставит openssl штатным пакетным менеджером. Возвращает 1, если менеджер
# не опознан или установка не прошла — вызывающий откатится на docker.
install_openssl() {
	local sudo=''
	[[ $EUID -ne 0 ]] && sudo='sudo'
	[[ -n $sudo ]] && ! command -v sudo >/dev/null && return 1

	if command -v apt-get >/dev/null; then
		log 'Ставлю openssl через apt-get...'
		$sudo apt-get update -qq && $sudo apt-get install -y -qq openssl
	elif command -v apk >/dev/null; then
		log 'Ставлю openssl через apk...'
		$sudo apk add --no-cache openssl
	elif command -v dnf >/dev/null; then
		log 'Ставлю openssl через dnf...'
		$sudo dnf install -y openssl
	elif command -v yum >/dev/null; then
		log 'Ставлю openssl через yum...'
		$sudo yum install -y openssl
	elif command -v pacman >/dev/null; then
		log 'Ставлю openssl через pacman...'
		$sudo pacman -Sy --noconfirm openssl
	else
		return 1
	fi
}

# Печатает команду-обёртку для openssl: либо хостовый бинарник, либо
# одноразовый контейнер с примонтированным certs/.
resolve_openssl() {
	if command -v openssl >/dev/null; then
		OPENSSL=(openssl); OPENSSL_CERTS="${CERTS}"; return
	fi

	log 'openssl на хосте не найден.'
	if install_openssl && command -v openssl >/dev/null; then
		OPENSSL=(openssl); OPENSSL_CERTS="${CERTS}"; return
	fi

	command -v docker >/dev/null \
		|| die 'нет ни openssl, ни docker — поставь openssl вручную'
	log "Пакет поставить не вышло, работаю через ${FALLBACK_IMAGE}."
	OPENSSL=(docker run --rm -v "${CERTS}:/certs" --entrypoint openssl "${FALLBACK_IMAGE}")
	OPENSSL_CERTS='/certs'
}

mkdir -p "${CERTS}"
resolve_openssl

if [[ $FORCE -eq 0 && -f $CRT && -f $KEY ]]; then
	if "${OPENSSL[@]}" x509 -in "${OPENSSL_CERTS}/default.crt" \
		-noout -checkend "${RENEW_BEFORE}" >/dev/null 2>&1
	then
		log "Сертификат ${CRT} действителен ещё дольше 90 дней. Нечего делать."
		log 'Перевыпустить принудительно: bin/gen-default-cert.sh --force'
		exit 0
	fi
	log 'Текущий default.crt истёк или истекает в ближайшие 90 дней, перевыпускаю.'
fi

"${OPENSSL[@]}" req -x509 \
	-newkey rsa:4096 -sha256 -nodes -days "${DAYS}" \
	-subj "/CN=${CN}" \
	-keyout "${OPENSSL_CERTS}/default.key.new" \
	-out "${OPENSSL_CERTS}/default.crt.new"

mv "${KEY}.new" "${KEY}"
mv "${CRT}.new" "${CRT}"
# При работе через контейнер файлы принадлежат root — chmod может не пройти.
chmod 600 "${KEY}" 2>/dev/null || log "Не удалось выставить 600 на ${KEY}, проверь права вручную."
chmod 644 "${CRT}" 2>/dev/null || true

log "Готово: ${CRT} (CN=${CN}, ${DAYS} дней)"
log 'Применить: docker exec router-nginx nginx -s reload'
