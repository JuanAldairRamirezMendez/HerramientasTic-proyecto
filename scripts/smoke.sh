#!/usr/bin/env bash
# Smoke test para CI local y para después de cada despliegue.
#
# Variables:
#   BACKEND_URL            URL pública o local del backend (default http://localhost:3000)
#   FRONTEND_URL           URL pública o local del frontend (default http://localhost)
#   SMOKE_TIMEOUT_SECONDS  Tiempo máximo esperando que los servicios arranquen (default 120)
#   SMOKE_CHAT_CHECK       "1" para comprobar que "hola" no devuelve tarjetas
#   SMOKE_EXPECT_DOCUMENTS "1" para exigir tarjetas en un listado explícito
set -euo pipefail

BACKEND_URL="${BACKEND_URL:-http://localhost:3000}"
FRONTEND_URL="${FRONTEND_URL:-http://localhost}"
TIMEOUT="${SMOKE_TIMEOUT_SECONDS:-120}"
INTERVAL="${SMOKE_INTERVAL_SECONDS:-3}"

log() { printf '[smoke] %s\n' "$*"; }
fail() {
  printf '[smoke] ERROR: %s\n' "$*" >&2
  exit 1
}

fetch_until() {
  local url="$1"
  local label="$2"
  local expected="$3"
  local deadline=$((SECONDS + TIMEOUT))
  local body=""

  while (( SECONDS < deadline )); do
    if body="$(curl -fsS --max-time 10 "$url" 2>/dev/null)"; then
      if [[ -z "$expected" || "$body" == *"$expected"* ]]; then
        log "OK: $label"
        return 0
      fi
      log "Esperando $label (respuesta inesperada)"
    else
      log "Esperando $label ..."
    fi
    sleep "$INTERVAL"
  done

  fail "$label no respondió como se esperaba en ${TIMEOUT}s ($url)"
}

chat_stream_to_file() {
  local payload="$1"
  local output="$2"

  # Un error HTTP de Gemini también cierra el stream; no lo tratamos como
  # fallo de red para poder inspeccionar los eventos que sí llegaron.
  curl -sS -N --max-time "${SMOKE_CHAT_TIMEOUT_SECONDS:-90}" \
    -H 'Content-Type: application/json' \
    --data "$payload" \
    "$BACKEND_URL/chat/stream" >"$output" 2>/dev/null || true
}

log "Backend: $BACKEND_URL"
log "Frontend: $FRONTEND_URL"

fetch_until "$BACKEND_URL/health" "backend /health" '"status":"ok"'
fetch_until "$FRONTEND_URL/healthz" "frontend /healthz" 'ok'
fetch_until "$FRONTEND_URL/" "frontend index.html" 'Gestor Inteligente de Documentos'

if [[ "${SMOKE_CHAT_CHECK:-0}" == "1" ]]; then
  log "Comprobando que un saludo no devuelve tarjetas de documentos"
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT

  chat_stream_to_file '{"message":"hola","history":[]}' "$tmp"

  if grep -q '"type":"tool_results"' "$tmp"; then
    fail "el chat devolvió tool_results para el mensaje 'hola'"
  fi
  if ! grep -q '"type":"content"' "$tmp"; then
    fail "el chat no devolvió contenido; revisa los logs del backend"
  fi

  rm -f "$tmp"
  trap - EXIT
  log "OK: 'hola' responde sin tarjetas"
fi

if [[ "${SMOKE_EXPECT_DOCUMENTS:-0}" == "1" ]]; then
  log "Comprobando que un listado explícito devuelve tarjetas"
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT

  chat_stream_to_file \
    '{"message":"¿Qué documentos hay?","history":[],"includeDocuments":true}' \
    "$tmp"

  if ! grep -q '"type":"tool_results"' "$tmp"; then
    fail "el listado explícito no devolvió tool_results"
  fi

  rm -f "$tmp"
  trap - EXIT
  log "OK: el listado explícito devuelve tarjetas"
fi

log "Smoke test completado correctamente"
