#!/usr/bin/env bash
# ==============================================================================
# cloudflare-url-mail.sh
#
# Avisa por correo cuando cambia la URL pública del túnel de Cloudflare.
#
# Pensado para ejecutarse desde un timer de systemd cada minuto (junto con
# cloudflare-url-sync.sh). Como el aviso SOLO interesa cuando la URL cambió, el
# script se apoya en un archivo de estado y aplica dos frenos para no llenar el
# buzón:
#
#   - Espera a que la URL se asiente (por defecto 90 s) antes de avisar, así un
#     reinicio en cadena no manda varios correos de direcciones intermedias.
#   - No manda más de un correo cada 10 minutos (por defecto).
#
# Configuración (archivo aparte, NUNCA en el repositorio):
#   $HOME/.config/cloudflare-url-mail.conf   -> SMTP_HOST, SMTP_PORT, SMTP_USER,
#                                               SMTP_PASS, MAIL_TO, MAIL_FROM_ADDR,
#                                               MAIL_FROM_NAME
# Variables de entorno (opcionales):
#   CLOUDFLARE_MAIL_CONF    ruta del archivo de configuración
#   CLOUDFLARE_MAIL_STATE   ruta del archivo de estado
#   CLOUDFLARE_URL_FILE     ruta del archivo con la URL activa
#   TUNNEL_CONTAINER        nombre del contenedor del túnel
#   MAIL_STABLE_SECONDS     segundos que debe mantenerse la URL antes de avisar
#   MAIL_MIN_INTERVAL       segundos mínimos entre dos avisos
#   MAIL_MAX_ATTEMPTS       intentos por URL antes de rendirse
#
# Uso:
#   ./cloudflare-url-mail.sh            # modo normal (lo llama el timer)
#   ./cloudflare-url-mail.sh --test     # manda un correo de prueba y sale
# ==============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

# --- Home real: con sudo, $HOME es /root, así que se usa SUDO_USER ------------
HOME_DIR="${HOME:-}"
if [ -n "${SUDO_USER:-}" ]; then
    HOME_DIR="$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6 || true)"
fi
[ -n "$HOME_DIR" ] || HOME_DIR="${HOME:-/home/azureuser}"

CONF_FILE="${CLOUDFLARE_MAIL_CONF:-$HOME_DIR/.config/cloudflare-url-mail.conf}"
STATE_FILE="${CLOUDFLARE_MAIL_STATE:-$HOME_DIR/.config/cloudflare-url-mail.state}"
URL_FILE="${CLOUDFLARE_URL_FILE:-$HOME_DIR/cloudflare-url.txt}"
TUNNEL_CONTAINER="${TUNNEL_CONTAINER:-herramientastic-tunnel}"

STABLE_SECONDS="${MAIL_STABLE_SECONDS:-90}"
MIN_INTERVAL_SECONDS="${MAIL_MIN_INTERVAL:-600}"
MAX_ATTEMPTS="${MAIL_MAX_ATTEMPTS:-3}"

MODE="normal"
case "${1:-}" in
    --test | -t) MODE="test" ;;
esac

log() { echo "$(date -Is) $*"; }

# --- 1. URL activa: del archivo y, si no hay, de los logs --------------------
url=""
if [ -s "$URL_FILE" ]; then
    url="$(head -n 1 "$URL_FILE" | tr -d '[:space:]')"
fi
if [ -z "$url" ]; then
    url="$(docker logs "$TUNNEL_CONTAINER" 2>&1 \
        | grep -oE 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' \
        | tail -n 1 || true)"
fi
if [ -z "$url" ]; then
    log "Sin URL activa todavía: no hay nada que avisar"
    exit 0
fi

# --- 2. Estado del último aviso ---------------------------------------------
NOTIFIED_URL=""
LAST_SENT_EPOCH=0
FAILED_URL=""
FAIL_COUNT=0
LAST_ATTEMPT_EPOCH=0
# shellcheck disable=SC1090
[ -f "$STATE_FILE" ] && . "$STATE_FILE"

now="$(date +%s)"

if [ "$MODE" = "normal" ]; then
    # Ya se avisó de esta misma URL.
    if [ "$url" = "$NOTIFIED_URL" ]; then
        exit 0
    fi
    # Esta URL ya agotó sus intentos.
    if [ "$url" = "$FAILED_URL" ] && [ "$FAIL_COUNT" -ge "$MAX_ATTEMPTS" ]; then
        exit 0
    fi
    # Freno entre avisos: los cambios en cadena se agrupan en un solo correo.
    if [ "$LAST_ATTEMPT_EPOCH" -gt 0 ] \
        && [ "$((now - LAST_ATTEMPT_EPOCH))" -lt "$MIN_INTERVAL_SECONDS" ]; then
        exit 0
    fi
    # Espera a que la URL se asiente (evita correos de direcciones transitorias).
    if [ -f "$URL_FILE" ]; then
        mtime="$(stat -c %Y "$URL_FILE" 2>/dev/null || echo 0)"
        if [ "$mtime" -gt 0 ] && [ "$((now - mtime))" -lt "$STABLE_SECONDS" ]; then
            log "La URL cambió hace $((now - mtime))s: se espera a que se asiente antes de avisar"
            exit 0
        fi
    fi
fi

# --- 3. Configuración de correo ---------------------------------------------
if [ ! -r "$CONF_FILE" ]; then
    log "Sin configuración de correo ($CONF_FILE): no se envía aviso"
    exit 0
fi
# shellcheck disable=SC1090
. "$CONF_FILE"

SMTP_HOST="${SMTP_HOST:-smtp.gmail.com}"
SMTP_PORT="${SMTP_PORT:-465}"
MAIL_TO="${MAIL_TO:-}"
MAIL_FROM_ADDR="${MAIL_FROM_ADDR:-${SMTP_USER:-}}"
MAIL_FROM_NAME="${MAIL_FROM_NAME:-Gestor de Documentos}"

if [ -z "${SMTP_USER:-}" ] || [ -z "${SMTP_PASS:-}" ] || [ -z "$MAIL_TO" ]; then
    log "Configuración de correo incompleta en $CONF_FILE: no se envía aviso"
    exit 0
fi

# --- 4. Armar y enviar el correo --------------------------------------------
# Puerto 465 -> TLS implícito (smtps). Otros puertos (587) -> STARTTLS.
if [ "$SMTP_PORT" = "465" ] || [ "$SMTP_PORT" = "smtps" ]; then
    SMTP_URL="smtps://$SMTP_HOST:$SMTP_PORT"
    SMTP_TLS_OPTS=()
else
    SMTP_URL="smtp://$SMTP_HOST:$SMTP_PORT"
    SMTP_TLS_OPTS=(--ssl-reqd)
fi

if [ "$MODE" = "test" ]; then
    subject="[PRUEBA] Aviso de enlace - Gestor de Documentos"
else
    subject="Nuevo enlace del Gestor de Documentos (el anterior ya no responde)"
fi

body="$(
    cat <<EOF
La dirección pública del Gestor Inteligente de Documentos cambió.

  Enlace nuevo:    $url
  Enlace anterior: ${NOTIFIED_URL:-(sin registro)}

Copia el enlace nuevo donde lo guardes: el anterior ya no responde.
El cambio ocurre cuando el servidor o el túnel se reinician, y Cloudflare
asigna un subdominio temporal distinto.

  Aviso automático generado el $(date '+%Y-%m-%d a las %H:%M:%S %Z')
EOF
)"

msg_file="$(mktemp)"
err_file="$(mktemp)"
trap 'rm -f "$msg_file" "$err_file"' EXIT

{
    printf 'From: %s <%s>\r\n' "$MAIL_FROM_NAME" "$MAIL_FROM_ADDR"
    printf 'To: %s\r\n' "$MAIL_TO"
    printf 'Subject: %s\r\n' "$subject"
    printf 'Date: %s\r\n' "$(date -R)"
    printf 'MIME-Version: 1.0\r\n'
    printf 'Content-Type: text/plain; charset=UTF-8\r\n'
    printf 'Content-Transfer-Encoding: 8bit\r\n'
    printf '\r\n'
    printf '%s\r\n' "$body"
} >"$msg_file"

if curl -sS --url "$SMTP_URL" \
    "${SMTP_TLS_OPTS[@]}" \
    --user "$SMTP_USER:$SMTP_PASS" \
    --mail-from "$MAIL_FROM_ADDR" \
    --mail-rcpt "$MAIL_TO" \
    --upload-file "$msg_file" \
    --connect-timeout 15 --max-time 60 >/dev/null 2>"$err_file"; then
    mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null || true
    {
        printf "NOTIFIED_URL='%s'\n" "$url"
        printf 'LAST_SENT_EPOCH=%s\n' "$now"
        printf "FAILED_URL=''\n"
        printf 'FAIL_COUNT=0\n'
        printf 'LAST_ATTEMPT_EPOCH=%s\n' "$now"
    } >"$STATE_FILE"
    if [ -n "${SUDO_USER:-}" ]; then
        chown "$SUDO_USER:$(id -gn "$SUDO_USER" 2>/dev/null || echo "$SUDO_USER")" "$STATE_FILE" 2>/dev/null || true
    fi
    chmod 600 "$STATE_FILE" 2>/dev/null || true
    log "Aviso enviado a $MAIL_TO con el enlace $url"
else
    fail_count=$((FAIL_COUNT + 1))
    mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null || true
    {
        printf "NOTIFIED_URL='%s'\n" "$NOTIFIED_URL"
        printf 'LAST_SENT_EPOCH=%s\n' "$LAST_SENT_EPOCH"
        printf "FAILED_URL='%s'\n" "$url"
        printf 'FAIL_COUNT=%s\n' "$fail_count"
        printf 'LAST_ATTEMPT_EPOCH=%s\n' "$now"
    } >"$STATE_FILE"
    if [ -n "${SUDO_USER:-}" ]; then
        chown "$SUDO_USER:$(id -gn "$SUDO_USER" 2>/dev/null || echo "$SUDO_USER")" "$STATE_FILE" 2>/dev/null || true
    fi
    chmod 600 "$STATE_FILE" 2>/dev/null || true
    log "No se pudo enviar el aviso (intento $fail_count de $MAX_ATTEMPTS): $(head -c 300 "$err_file" | tr '\n' ' ')"
    exit 1
fi
