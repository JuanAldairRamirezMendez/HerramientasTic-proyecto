#!/usr/bin/env bash
# ==============================================================================
# cloudflare-url-sync.sh
#
# Mantiene /home/azureuser/cloudflare-url.txt con la URL pública ACTIVA del
# túnel de Cloudflare. Está pensado para ejecutarse desde un timer de systemd
# cada minuto, de modo que el archivo nunca se quede con un enlace muerto
# aunque el contenedor del túnel se reinicie solo.
#
# Variables de entorno (opcionales):
#   CLOUDFLARE_URL_FILE   ruta del archivo a mantener (por defecto $HOME/cloudflare-url.txt)
#   CLOUDFLARE_URL_OWNER  dueño con el que dejar el archivo (por defecto, el dueño actual)
#   TUNNEL_CONTAINER      nombre del contenedor del túnel (por defecto herramientastic-tunnel)
#
# Salida: silencio si no hay cambios (apto para un timer). El archivo solo se
# reescribe cuando la URL cambia de verdad.
# ==============================================================================

set -uo pipefail

TUNNEL_CONTAINER="${TUNNEL_CONTAINER:-herramientastic-tunnel}"

# Ruta del archivo a mantener. Si se ejecuta con sudo, se usa el home del
# usuario real (SUDO_USER) y nunca /root.
TARGET="${CLOUDFLARE_URL_FILE:-}"
if [ -z "$TARGET" ]; then
    HOME_DIR="${HOME:-}"
    if [ -n "${SUDO_USER:-}" ]; then
        HOME_DIR="$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6 || true)"
    fi
    [ -n "$HOME_DIR" ] || HOME_DIR="/home/azureuser"
    TARGET="${HOME_DIR%/}/cloudflare-url.txt"
fi

# La URL más reciente que anunció cloudflared en sus logs.
url="$(docker logs "$TUNNEL_CONTAINER" 2>&1 \
    | grep -oE 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' \
    | tail -n 1 || true)"

# Sin contenedor o sin URL todavía: no se toca el archivo (mejor una URL vieja
# que un archivo vacío).
if [ -z "$url" ]; then
    exit 0
fi

current=""
if [ -f "$TARGET" ]; then
    current="$(cat "$TARGET" 2>/dev/null || true)"
fi

if [ "$url" = "$current" ]; then
    exit 0
fi

tmp="$(mktemp)"
printf '%s\n' "$url" >"$tmp"
chmod 600 "$tmp"
if [ -n "${CLOUDFLARE_URL_OWNER:-}" ]; then
    chown "$CLOUDFLARE_URL_OWNER" "$tmp" 2>/dev/null || true
elif [ -n "${SUDO_UID:-}" ]; then
    chown "${SUDO_UID}:${SUDO_GID:-$SUDO_UID}" "$tmp" 2>/dev/null || true
fi
mv -f "$tmp" "$TARGET"

echo "$(date -Is) URL pública actualizada en $TARGET: $url"
