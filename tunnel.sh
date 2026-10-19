#!/usr/bin/env bash
# ==============================================================================
# Script de Gestión de Cloudflare Tunnel para Gestor Inteligente de Documentos
# ==============================================================================

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
cd "$DIR"

CONTAINER_NAME="herramientastic-tunnel"
SERVICE_NAME="tunnel"

# Archivo donde se deja la URL pública para copiarla cómodamente. Si se ejecuta
# con sudo, se usa el home del usuario real (nunca /root).
URL_FILE="${CLOUDFLARE_URL_FILE:-}"
if [ -z "$URL_FILE" ]; then
    HOME_DIR="${HOME:-}"
    if [ -n "${SUDO_USER:-}" ]; then
        HOME_DIR="$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6 || true)"
    fi
    [ -n "$HOME_DIR" ] || HOME_DIR="$HOME"
    URL_FILE="${HOME_DIR%/}/cloudflare-url.txt"
fi

# Colores para la terminal
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # No Color
BOLD='\033[1m'

print_banner() {
    echo -e "${CYAN}${BOLD}"
    echo "============================================================"
    echo "   CLOUDFLARE TUNNEL - ACCESO REMOTO AL FRONTEND"
    echo "============================================================"
    echo -e "${NC}"
}

get_tunnel_url() {
    local max_retries=15
    local retry=0
    local url=""

    while [ $retry -lt $max_retries ]; do
        url=$(docker logs "$CONTAINER_NAME" 2>&1 | grep -o 'https://[a-zA-Z0-9-]*\.trycloudflare\.com' | tail -n 1 || true)
        if [ -n "$url" ]; then
            echo "$url"
            return 0
        fi
        retry=$((retry + 1))
        sleep 1
    done
    return 1
}

# Deja la URL activa en $URL_FILE para que siempre se pueda copiar de ahí,
# incluso cuando el túnel se reinicia solo y cambia de dirección.
save_url() {
    local url="$1"

    [ -n "$url" ] || return 0
    if [ "$(cat "$URL_FILE" 2>/dev/null || true)" = "$url" ]; then
        return 0
    fi

    mkdir -p "$(dirname "$URL_FILE")" 2>/dev/null || true
    if printf '%s\n' "$url" > "$URL_FILE" 2>/dev/null; then
        chmod 600 "$URL_FILE" 2>/dev/null || true
        if [ -n "${SUDO_USER:-}" ]; then
            chown "$SUDO_USER:$(id -gn "$SUDO_USER" 2>/dev/null || echo "$SUDO_USER")" "$URL_FILE" 2>/dev/null || true
        fi
        echo -e "${YELLOW}💾 URL guardada en $URL_FILE${NC}"
    else
        echo -e "${YELLOW}⚠️  No se pudo escribir $URL_FILE${NC}"
    fi
}

show_url() {
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo -e "${YELLOW}⚠️  El contenedor de Cloudflare Tunnel no está corriendo.${NC}"
        echo -e "Iniciándolo ahora..."
        start_tunnel
        return
    fi

    echo -e "${BLUE}🔍 Obteniendo URL pública activa...${NC}"
    URL=$(get_tunnel_url || true)

    if [ -n "$URL" ]; then
        save_url "$URL"
        echo ""
        echo -e "${GREEN}${BOLD}============================================================${NC}"
        echo -e "${GREEN}${BOLD}  🌐 URL PÚBLICA DEL FRONTEND (ACCESO DESDE CUALQUIER LUGAR):${NC}"
        echo -e "${CYAN}${BOLD}  👉  $URL${NC}"
        echo -e "${GREEN}${BOLD}============================================================${NC}"
        echo ""
        echo -e "Puedes abrir este enlace en tu celular, tablet o cualquier PC externa."
        echo -e "También queda guardado en: ${CYAN}$URL_FILE${NC}"
        echo -e "Nota: Tu PC debe permanecer encendida para mantener el servicio activo."
        echo ""

        # Intentar copiar al portapapeles si hay herramienta disponible
        if command -v wl-copy >/dev/null 2>&1; then
            echo -n "$URL" | wl-copy 2>/dev/null && echo -e "${YELLOW}📋 (URL copiada al portapapeles con wl-copy)${NC}"
        elif command -v xclip >/dev/null 2>&1; then
            echo -n "$URL" | xclip -selection clipboard 2>/dev/null && echo -e "${YELLOW}📋 (URL copiada al portapapeles con xclip)${NC}"
        fi
    else
        echo -e "${RED}❌ No se pudo encontrar la URL en los logs aún.${NC}"
        echo "Revisa los logs con: ./tunnel.sh logs"
    fi
}

start_tunnel() {
    print_banner
    echo -e "${BLUE}🚀 Iniciando servicio de Cloudflare Tunnel con Docker Compose...${NC}"
    docker compose up -d "$SERVICE_NAME"
    echo -e "${YELLOW}⏳ Esperando a que Cloudflare asigne la dirección pública...${NC}"
    sleep 3
    show_url
}

stop_tunnel() {
    print_banner
    echo -e "${YELLOW}🛑 Deteniendo Cloudflare Tunnel...${NC}"
    docker compose stop "$SERVICE_NAME"
    echo -e "${GREEN}✓ Cloudflare Tunnel detenido correctamente.${NC}"
}

restart_tunnel() {
    print_banner
    echo -e "${YELLOW}🔄 Reiniciando Cloudflare Tunnel...${NC}"
    docker compose restart "$SERVICE_NAME"
    echo -e "${YELLOW}⏳ Esperando nueva conexión segura...${NC}"
    sleep 4
    show_url
}

show_logs() {
    docker compose logs -f "$SERVICE_NAME"
}

run_local() {
    print_banner
    if ! command -v cloudflared >/dev/null 2>&1; then
        echo -e "${RED}❌ 'cloudflared' no está instalado en el sistema.${NC}"
        echo "Usa './tunnel.sh start' para ejecutarlo mediante Docker."
        exit 1
    fi
    echo -e "${GREEN}Iniciando túnel local directo a http://localhost:80...${NC}"
    echo -e "${YELLOW}Presiona Ctrl+C para detenerlo cuando desees.${NC}"
    echo ""
    cloudflared tunnel --url http://localhost:80
}

help_menu() {
    print_banner
    echo "Uso: ./tunnel.sh [comando]"
    echo ""
    echo "Comandos disponibles:"
    echo "  start       Inicia el túnel en segundo plano y muestra la URL pública"
    echo "  url         Muestra la URL pública actualmente activa"
    echo "  restart     Reinicia el túnel y obtiene una nueva URL pública"
    echo "  stop        Detiene el túnel"
    echo "  logs        Muestra los logs en tiempo real del contenedor del túnel"
    echo "  local       Ejecuta cloudflared directamente en la terminal (sin Docker)"
    echo "  help        Muestra esta ayuda"
    echo ""
    echo "Ejemplo:"
    echo "  ./tunnel.sh url"
    echo ""
    echo "La URL activa queda guardada en: $URL_FILE"
    echo "(se puede cambiar con la variable de entorno CLOUDFLARE_URL_FILE)"
}

case "${1:-url}" in
    start)
        start_tunnel
        ;;
    url|status)
        show_url
        ;;
    stop)
        stop_tunnel
        ;;
    restart)
        restart_tunnel
        ;;
    logs)
        show_logs
        ;;
    local)
        run_local
        ;;
    help|--help|-h)
        help_menu
        ;;
    *)
        echo -e "${RED}Comando desconocido: $1${NC}"
        help_menu
        exit 1
        ;;
esac
