#!/usr/bin/env bash
# Calendar audit: собирает образ из рабочей копии, поднимает изолированный контейнер
# и проверяет страницы и API только GET-запросами. Пишет REPORT (JSON).
# Провал проверок приложения — это данные отчёта (код 0); ненулевой код — сбой самого аудита.
# Переменные: REPORT (по умолчанию build/audit/report.json), TIMEOUT (секунды ожидания старта).
set -euo pipefail

cd "$(dirname "$0")/.."

REPORT="${REPORT:-build/audit/report.json}"
TIMEOUT="${TIMEOUT:-60}"
name="calendar-audit-$$"
image="calendar-audit:$$"
tmp="$(mktemp -d)"
cleanup() {
  docker rm -f "$name" >/dev/null 2>&1 || true
  docker network rm "$name" >/dev/null 2>&1 || true
  docker image rm "$image" >/dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT

mkdir -p "$(dirname "$REPORT")"
: >"$tmp/checks.jsonl"

# record <id> <путь> <ожидание> <kind: ok или вид сбоя> <HTTP-статус> <файл с фактическим выводом>
record() {
  # Не больше 2000 последних символов: вывод недоверенный и идёт агенту.
  jq -Rsc --arg id "$1" --arg path "$2" --arg expected "$3" --arg kind "$4" --arg status "$5" \
    '{id: $id, path: $path, expected: $expected, ok: ($kind == "ok"), kind: $kind, status: $status, actual: .[-2000:]}' \
    <"$6" >>"$tmp/checks.jsonl"
  echo "audit: $1: $4"
}

finish() {
  jq -s --arg commit "$(git rev-parse HEAD)" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{commit: $commit, generatedAt: $at, failed: ([.[] | select(.ok | not)] | length), checks: .}' \
    "$tmp/checks.jsonl" >"$REPORT"
  echo "audit: отчёт $REPORT, провалено проверок: $(jq .failed "$REPORT")"
  exit 0
}

docker info >/dev/null # без Docker аудит невозможен, это не находка

# Сеть бывает нестабильна: вторая попытка отделяет её сбой от ошибки сборки.
if ! docker build --progress=plain -t "$image" . >"$tmp/build.log" 2>&1 &&
  ! docker build --progress=plain -t "$image" . >"$tmp/build.log" 2>&1; then
  record docker-build Dockerfile "образ собирается" build-failed "" "$tmp/build.log"
  finish
fi
record docker-build Dockerfile "образ собирается" ok "" /dev/null

# Своя сеть без выхода наружу (без masquerade), порт открыт только на loopback.
docker network create -o com.docker.network.bridge.enable_ip_masquerade=false "$name" >/dev/null
docker run -d --name "$name" --network "$name" -p 127.0.0.1::8080 \
  --read-only --tmpfs /tmp --cap-drop ALL --security-opt no-new-privileges \
  --memory 512m --pids-limit 256 "$image" >/dev/null

base=""
for ((i = 0; i < TIMEOUT; i++)); do
  [ "$(docker inspect -f '{{.State.Running}}' "$name")" = true ] || break
  port="$(docker port "$name" 8080/tcp 2>/dev/null | head -n 1 | sed 's/.*://')"
  # Любой HTTP-ответ значит, что сервер поднялся: статус проверит api-health.
  if [ -n "$port" ] && curl -sS --max-time 5 -o /dev/null "http://127.0.0.1:$port/api/health" 2>/dev/null; then
    base="http://127.0.0.1:$port"
    break
  fi
  sleep 1
done
if [ -z "$base" ]; then
  docker logs --tail 60 "$name" >"$tmp/start.log" 2>&1 || true
  record container-start /api/health "контейнер отвечает за ${TIMEOUT} с" start-failed "" "$tmp/start.log"
  finish
fi
record container-start /api/health "контейнер отвечает за ${TIMEOUT} с" ok "" /dev/null

# fetch <путь>: тело в $tmp/body, статус и Content-Type в переменных. До трёх попыток без ответа.
fetch() {
  local meta
  : >"$tmp/body"
  if meta="$(curl -sS --get --max-time 10 --retry 2 --retry-connrefused -o "$tmp/body" \
    -w '%{http_code} %{content_type}' "$base$1" 2>"$tmp/curl.err")"; then
    status="${meta%% *}"
    ctype="${meta#* }"
  else
    status=""
    ctype=""
    cp "$tmp/curl.err" "$tmp/body"
  fi
}

# verify <HTTP-статус> <тип содержимого>: kind по результату fetch
verify() {
  kind=ok
  if [ -z "$status" ]; then
    kind=no-response
  elif [ "$status" != "$1" ]; then
    kind="http-$status"
  else
    case "$ctype" in "$2"*) ;; *) kind=content-type ;; esac
  fi
}

page() { # <id> <путь>
  fetch "$2"
  verify 200 text/html
  if [ "$kind" = ok ] && ! grep -q 'id="root"' "$tmp/body"; then kind=body; fi
  record "$1" "$2" "200 text/html с элементом #root" "$kind" "$status" "$tmp/body"
}

api() { # <id> <путь> <статус> <условие jq для тела>
  fetch "$2"
  verify "$3" application/json
  if [ "$kind" = ok ] && ! jq -e "$4" "$tmp/body" >/dev/null 2>&1; then kind=body; fi
  record "$1" "$2" "$3 application/json, тело: $4" "$kind" "$status" "$tmp/body"
}

unknown=00000000-0000-4000-8000-000000000000

page page-home /
fetch /
cp "$tmp/body" "$tmp/index.html"
page page-book /book
page page-book-slot "/book/$unknown"
page page-book-confirm "/book/$unknown/confirm"
page page-book-success /book/success
page page-admin /admin
page page-not-found /no-such-page

# Скрипты и стили главной страницы: без них страница отвечает 200, но пустая.
# Неизвестный путь возвращает index.html, поэтому сверяем и тип содержимого.
assets="$(grep -oE '(src|href)="/[^"]+\.(js|css)"' "$tmp/index.html" | cut -d'"' -f2 || true)"
kind=ok
bad=""
[ -n "$assets" ] || kind=body
for asset in $assets; do
  fetch "$asset"
  case "$asset" in
    *.js) case "$ctype" in application/javascript* | text/javascript*) want="$ctype" ;; *) want=text/javascript ;; esac ;;
    *) want=text/css ;;
  esac
  verify 200 "$want"
  if [ "$kind" != ok ]; then
    bad="$asset: $kind ($status $ctype)"
    break
  fi
done
printf '%s' "$bad" >"$tmp/assets"
record page-assets / "JS и CSS главной страницы отдаются с 200 и верным типом" "$kind" "${status:-}" "$tmp/assets"

api api-health /api/health 200 '.status == "ok"'
api api-owner /api/owner 200 '(.name | type == "string") and (.title | type == "string") and has("avatarUrl") and (.avatarUrl | type | IN("string", "null")) and .timezone == "Asia/Almaty"'
# Хранилище в памяти, новый контейнер пуст.
api api-meeting-types /api/meeting-types 200 '. == []'
api api-bookings-upcoming /api/bookings/upcoming 200 '. == []'
error='.code == "MEETING_TYPE_NOT_FOUND" and (.message | type == "string")'
api api-slots-unknown "/api/meeting-types/$unknown/slots" 404 "$error"
api api-slots-not-uuid /api/meeting-types/not-a-uuid/slots 404 "$error"

finish
