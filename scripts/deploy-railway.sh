#!/usr/bin/env bash
# Despliega backend-api, backend-worker y frontend en un entorno de Railway.
#
# Uso:
#   RAILWAY_TOKEN=... RAILWAY_PROJECT_ID=... scripts/deploy-railway.sh staging
#   RAILWAY_TOKEN=... RAILWAY_PROJECT_ID=... scripts/deploy-railway.sh production --method image
#   RAILWAY_TOKEN=... RAILWAY_PROJECT_ID=... scripts/deploy-railway.sh production --method up
#
# Métodos:
#   image    -> despliega la imagen inmutable de GHCR por digest (recomendado).
#   redeploy -> pide a Railway desplegar el commit exacto del submódulo.
#   up       -> sube el árbol local de cada submódulo (fallback).
#
# El método "image" exige que el job `images` del CI haya publicado
# <IMAGE_PREFIX>-<servicio> con el tag del SHA del commit raíz desplegado.
# "redeploy" requiere que los servicios estén conectados a GitHub; si no lo
# están, el script cae automáticamente a "up".
set -euo pipefail

ENVIRONMENT="${1:-}"
if [[ -z "$ENVIRONMENT" ]]; then
  echo "Uso: $0 <staging|production> [--method image|redeploy|up]" >&2
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
  image | redeploy | up) ;;
  *)
    echo "Método inválido: $METHOD (usa image, redeploy o up)" >&2
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
# Las imágenes de GHCR se etiquetan con el SHA del commit del repo raíz (el
# `github.sha` del job `images`), no con el SHA del submódulo.
ROOT_SHA="$(git rev-parse HEAD)"
WAIT_TIMEOUT="${RAILWAY_DEPLOY_TIMEOUT_SECONDS:-1200}"
OWNER="${GITHUB_REPOSITORY_OWNER:-juanaldairramirezmendez}"
IMAGE_PREFIX="${IMAGE_PREFIX:-ghcr.io/${OWNER,,}/herramientastic-tic}"

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

resolve_image_digest() {
  local image="$1"
  local tag="$2"
  local path=""
  local auth=()
  local token=""
  local digest=""

  [[ "$image" == ghcr.io/* ]] || fail "Solo se soportan imágenes de GHCR: $image"
  path="${image#ghcr.io/}"

  # GHCR exige un bearer token incluso para paquetes públicos. Para paquetes
  # privados, pasar GHCR_USER/GHCR_TOKEN (por ejemplo, el GITHUB_TOKEN del job).
  if [[ -n "${GHCR_TOKEN:-}" ]]; then
    auth=(-u "${GHCR_USER:-${GITHUB_ACTOR:-github-actions}}:${GHCR_TOKEN}")
  fi

  token="$(
    curl -fsSL "${auth[@]}" \
      "https://ghcr.io/token?service=ghcr.io&scope=repository:${path}:pull" |
      jq -r '.token // empty'
  )" || fail "No se pudo autenticar contra GHCR para $image"
  [[ -n "$token" ]] || fail "GHCR no devolvió token para $image"

  digest="$(
    curl -fsS -o /dev/null -D - \
      -H "Authorization: Bearer ${token}" \
      -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json' \
      "https://ghcr.io/v2/${path}/manifests/${tag}" |
      awk 'BEGIN { IGNORECASE = 1 } /^docker-content-digest:/ { gsub("\r", ""); print $2 }' |
      head -n1
  )" || fail "No se pudo leer el manifiesto de ${image}:${tag}"

  [[ "$digest" == sha256:* ]] || fail "Digest inválido para ${image}:${tag}: '$digest'"
  printf '%s' "$digest"
}

railway_image_deploy() {
  local service="$1"
  local sha="$2"
  local image="$3"
  local digest=""
  local ref=""
  local output=""
  local deployment_id=""
  local err_file=""

  digest="$(resolve_image_digest "$image" "$sha")"
  ref="${image}@${digest}"

  log "Configurando $service desde ${ref}"
  if ! railway service source connect \
    --project "$RAILWAY_PROJECT_ID" \
    --environment "$ENVIRONMENT" \
    --service "$service" \
    --image "$ref" \
    --json >/dev/null; then
    fail "No se pudo fijar la imagen de $service en $ref"
  fi

  log "Desplegando $service ($ENVIRONMENT)"
  err_file="$(mktemp)"
  if ! output="$(
    railway redeploy \
      --project "$RAILWAY_PROJECT_ID" \
      --environment "$ENVIRONMENT" \
      --service "$service" \
      --from-source \
      --yes --json 2>"$err_file"
  )"; then
    cat "$err_file" >&2 || true
    rm -f "$err_file"
    fail "No se pudo desplegar $service desde $ref"
  fi
  rm -f "$err_file"

  deployment_id="$(printf '%s' "$output" | jq -r '.id // empty')"
  [[ -n "$deployment_id" ]] || fail "Railway no devolvió un deployment id para $service"

  log "Deployment de $service: $deployment_id ($ref)"
  wait_deployment "$service" "$deployment_id"
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
  local image_suffix="$3"

  if [[ "$METHOD" == "image" ]]; then
    railway_image_deploy "$service" "$ROOT_SHA" "${IMAGE_PREFIX}-${image_suffix}"
    return 0
  fi

  if [[ "$METHOD" == "up" ]]; then
    railway_up "$service" "$sha"
    return 0
  fi

  railway_redeploy "$service" "$sha"
}

log "Entorno: $ENVIRONMENT | método: $METHOD | proyecto: $RAILWAY_PROJECT_ID"
log "Backend:  ${BACKEND_SHA:0:7}"
log "Frontend: ${FRONTEND_SHA:0:7}"
if [[ "$METHOD" == "image" ]]; then
  log "Imágenes: ${IMAGE_PREFIX}-<servicio>:${ROOT_SHA}"
fi

# Orden: primero la API, luego el worker (mismo commit) y al final el frontend.
# Así el worker no queda con un contrato distinto al de la API.
deploy_service backend-api "$BACKEND_SHA" backend
deploy_service backend-worker "$BACKEND_SHA" backend
deploy_service frontend "$FRONTEND_SHA" frontend

log "Todos los servicios de $ENVIRONMENT fueron desplegados"
