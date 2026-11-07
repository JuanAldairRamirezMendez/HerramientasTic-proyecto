#!/usr/bin/env bash
# Verifica que los gitlinks de los submódulos apunten a commits publicados
# en las ramas de integración/estables y no a ramas de trabajo.
#
# Uso:
#   scripts/verify-submodules.sh --env any
#   scripts/verify-submodules.sh --env staging
#   scripts/verify-submodules.sh --env production
#
# Esto evita el error clásico de fusionar el repo raíz apuntando a un commit
# que solo existe en la rama local de un submódulo (GitHub no podría clonarlo).
set -euo pipefail

MODE="any"
if [[ "${1:-}" == "--env" ]]; then
  MODE="${2:-any}"
elif [[ -n "${1:-}" ]]; then
  echo "Uso: $0 [--env any|staging|production]" >&2
  exit 2
fi

case "$MODE" in
  any | staging | production) ;;
  *)
    echo "Entorno inválido: $MODE (usa any, staging o production)" >&2
    exit 2
    ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Ramas permitidas según el entorno. En staging se acepta main/master solo
# para el arranque inicial; lo normal es que apunte a develop.
case "$MODE" in
  production) ALLOWED=(main master) ;;
  staging) ALLOWED=(develop main master) ;;
  *) ALLOWED=(develop main master) ;;
esac

mapfile -t SUBMODULES < <(
  git config --file .gitmodules --get-regexp '^submodule\..*\.path$' | awk '{print $2}'
)

if (( ${#SUBMODULES[@]} == 0 )); then
  echo "No se encontraron submódulos en .gitmodules" >&2
  exit 1
fi

failed=0

for path in "${SUBMODULES[@]}"; do
  if [[ ! -d "$path/.git" && ! -f "$path/.git" ]]; then
    echo "ERROR: el submódulo no está inicializado: $path" >&2
    failed=1
    continue
  fi

  sha="$(git -C "$path" rev-parse HEAD)"

  # Trae todas las ramas del remoto para poder comprobar ancestría.
  if ! git -C "$path" fetch --quiet --prune origin '+refs/heads/*:refs/remotes/origin/*'; then
    echo "ERROR: no se pudo actualizar el remoto de $path" >&2
    failed=1
    continue
  fi

  matched=""
  for branch in "${ALLOWED[@]}"; do
    if git -C "$path" rev-parse --verify --quiet "origin/$branch" >/dev/null; then
      if git -C "$path" merge-base --is-ancestor "$sha" "origin/$branch"; then
        matched="origin/$branch"
        break
      fi
    fi
  done

  if [[ -z "$matched" ]]; then
    echo "ERROR: $path apunta a ${sha:0:7}, que no está en: ${ALLOWED[*]}" >&2
    echo "       Ramas remotas que contienen ese commit:" >&2
    git -C "$path" branch -r --contains "$sha" 2>/dev/null | sed 's/^/       /' >&2 || true
    failed=1
    continue
  fi

  echo "OK: $path -> ${sha:0:7} (contenido en $matched)"

  if [[ "$MODE" == "staging" && "$matched" != "origin/develop" ]]; then
    echo "AVISO: staging normalmente despliega origin/develop; este commit está en $matched." >&2
  fi
done

exit "$failed"
