#!/usr/bin/env bash
# Genera un .env ficticio para levantar docker compose en CI.
# No contiene secretos y nunca debe usarse en producción.
#
# El script se niega a sobrescribir un .env existente fuera de CI para no
# destruir la configuración local de un desarrollador.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ "${CI:-}" != "true" && "${1:-}" != "--force" ]]; then
  echo "Este script sobrescribe .env." >&2
  echo "Ejecútalo con CI=true o con --force si es lo que quieres." >&2
  exit 1
fi

cat >.env <<'EOF'
# Generado por scripts/write-ci-env.sh para pruebas de integración.
# Valores ficticios: no sirven para hablar con Gemini ni con Supabase.
GEMINI_API_KEY=ci-dummy-key
GEMINI_MODEL=gemini-3.5-flash-lite
GEMINI_TIMEOUT_MS=45000
GEMINI_THINKING_LEVEL=minimal
IA_MOBILE_MAX_TOKENS=768
QUEUE_ENABLED=false
SUPABASE_URL=https://example.supabase.co
SUPABASE_SECRET_KEY=ci-dummy-secret
FRONTEND_URL=http://localhost
EOF

echo "OK: .env de CI generado"
