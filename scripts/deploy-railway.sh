#!/usr/bin/env bash
# Despliega backend-api, backend-worker y frontend en un entorno de Railway.
#
# Uso:
#   RAILWAY_TOKEN=... RAILWAY_PROJECT_ID=... scripts/deploy-railway.sh staging
#   RAILWAY_TOKEN=... RAILWAY_PROJECT_ID=... scripts/deploy-railway.sh production --method up
#
# Métodos:
#   redeploy (default) -> pide a Railway desplegar el commit exacto del submódulo.
#   up                 -> sube el árbol local de cada submódulo (fallback).
#
# El método "redeploy" requiere que los servicios estén conectados a GitHub.
# Si no lo están, el script cae automáticamente a "up".
set -euo pipefail

ENVIRONMENT="${1:-}"
if [[ -z "$ENVIRONMENT" ]]; then
  echo "Uso: $0 <staging|production> [--method redeploy|up]" >&2
  exit 2
fi
shift

METHOD="${RAILWAY_DEPLOY_METHOD:-redeploy}"
while (( $# > 0 )); do
  case "$1" in
    --method)
      METHOD="${2:-}"
      shift 2
      ;;
    *)
      echo "Argumento desconocido: $1" >&2
      exit 2
      ;;
  esac
done

case "$ENVIRONMENT" in
  staging | production) ;;
  *)
    echo "Entorno inválido: $ENVIRONMENT (usa staging o production)" >&2
    exit 2
    ;;
esac

case "$METHOD" in
  redeploy | up) ;;
  *)
    echo "Método inválido: $METHOD (usa redeploy o up)" >&2
    exit 2
    ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

: "${RAILWAY_PROJECT_ID:?Falta RAILWAY_PROJECT_ID}"
: "${RAILWAY_TOKEN:?Falta RAILWAY_TOKEN}"

command -v railway >/dev/null || {
  echo "Falta Railway CLI (npm install -g @railway/cli@5.71.0)" >&2
  exit 1
}
command -v jq >/dev/null || {
  echo "Falta jq para leer el estado de los deployments" >&2
  exit 1
}

BACKEND_PATH="$ROOT_DIR/Gestor-Inteligente-de-Documentos"
FRONTEND_PATH="$ROOT_DIR/Gestor-Inteligente-de-Documentos-Frontend"
BACKEND_SHA="$(git -C "$BACKEND_PATH" rev-parse HEAD)"
FRONTEND_SHA="$(git -C "$FRONTEND_PATH" rev-parse HEAD)"
WAIT_TIMEOUT="${RAILWAY_DEPLOY_TIMEOUT_SECONDS:-1200}"

log() { printf '[deploy] %s\n' "$*"; }
fail() {
  printf '[deploy] ERROR: %s\n' "$*" >&2
  exit 1
}

railway_up() {
  local service="$1"
  local sha="$2"
  local path="$BACKEND_PATH"

  if [[ "$service" == "frontend" ]]; then
    path="$FRONTEND_PATH"
  fi

  log "Subiendo $path como $service (método up)"
  (
    cd "$path"
    railway up \
      --project "$RAILWAY_PROJECT_ID" \
      --environment "$ENVIRONMENT" \
      --service "$service" \
      --ci \
      --message "CD $ENVIRONMENT ${sha:0:7}"
  )
}

wait_deployment() {
  local service="$1"
  local deployment_id="$2"
  local deadline=$((SECONDS + WAIT_TIMEOUT))
  local status=""

  while (( SECONDS < deadline )); do
    status="$(
      railway deployment list \
        --project "$RAILWAY_PROJECT_ID" \
        --environment "$ENVIRONMENT" \
        --service "$service" \
        --limit 30 \
        --json 2>/dev/null |
        jq -r --arg id "$deployment_id" '.[] | select(.id == $id) | .status' |
        head -n1 || true
    )"

    case "$status" in
      SUCCESS)
        log "OK: $service desplegado ($deployment_id)"
        return 0
        ;;
      FAILED | CRASHED | REMOVED | REMOVING)
        railway logs "$deployment_id" \
          --project "$RAILWAY_PROJECT_ID" \
          --environment "$ENVIRONMENT" \
          --service "$service" \
          --build --lines 120 >&2 || true
        railway logs "$deployment_id" \
          --project "$RAILWAY_PROJECT_ID" \
          --environment "$ENVIRONMENT" \
          --service "$service" \
          --deployment --lines 120 >&2 || true
        fail "$service terminó en estado $status ($deployment_id)"
        ;;
      "")
        log "  $service: esperando a que Railway registre el deployment..."
        ;;
      *)
        log "  $service: $status"
        ;;
    esac

    sleep 10
  done

  fail "Timeout esperando $service ($deployment_id) después de ${WAIT_TIMEOUT}s"
}

railway_redeploy() {
  local service="$1"
  local sha="$2"
  local err_file=""
  local output=""
  local deployment_id=""

  log "Desplegando $service en $ENVIRONMENT desde ${sha:0:7}"
  err_file="$(mktemp)"

  if ! output="$(
    railway redeploy \
      --project "$RAILWAY_PROJECT_ID" \
      --environment "$ENVIRONMENT" \
      --service "$service" \
      --commit "$sha" \
      --yes --json 2>"$err_file"
  )"; then
    if grep -qi "not connected to a repository" "$err_file"; then
      log "El servicio no está conectado a GitHub; usando el fallback 'up'."
      rm -f "$err_file"
      railway_up "$service" "$sha"
      return 0
    fi
    cat "$err_file" >&2 || true
    rm -f "$err_file"
    fail "No se pudo desplegar $service"
  fi

  rm -f "$err_file"
  deployment_id="$(printf '%s' "$output" | jq -r '.id // empty')"
  [[ -n "$deployment_id" ]] || fail "Railway no devolvió un deployment id para $service"

  log "Deployment de $service: $deployment_id"
  wait_deployment "$service" "$deployment_id"
}

deploy_service() {
  local service="$1"
  local sha="$2"

  if [[ "$METHOD" == "up" ]]; then
    railway_up "$service" "$sha"
    return 0
  fi

  railway_redeploy "$service" "$sha"
}

log "Entorno: $ENVIRONMENT | método: $METHOD | proyecto: $RAILWAY_PROJECT_ID"
log "Backend:  ${BACKEND_SHA:0:7}"
log "Frontend: ${FRONTEND_SHA:0:7}"

# Orden: primero la API, luego el worker (mismo commit) y al final el frontend.
# Así el worker no queda con un contrato distinto al de la API.
deploy_service backend-api "$BACKEND_SHA"
deploy_service backend-worker "$BACKEND_SHA"
deploy_service frontend "$FRONTEND_SHA"

log "Todos los servicios de $ENVIRONMENT fueron desplegados"
