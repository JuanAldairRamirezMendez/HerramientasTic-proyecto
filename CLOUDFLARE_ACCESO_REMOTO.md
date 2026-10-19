# Guía de Acceso Remoto con Cloudflare Tunnel

Esta guía explica cómo acceder al frontend y a la aplicación completa de **Gestor Inteligente de Documentos** desde cualquier dispositivo (celular, tablet, otra laptop o PC) y desde cualquier lugar del mundo mediante **Cloudflare Tunnel**, manteniendo tu computadora encendida.

---

## 1. ¿Cómo funciona?

Cloudflare Tunnel (`cloudflared`) crea una conexión cifrada y saliente (HTTPS / QUIC) desde tu máquina local hacia la red global de Cloudflare. 

**Ventajas clave:**
- **No requiere abrir puertos** en tu router ni configurar Port Forwarding.
- **Funciona detrás de CGNAT** (redes móviles, Wi-Fi compartido, Claro, Movistar, etc.).
- **Proporciona HTTPS con certificado SSL automático y gratuito.**
- **Acceso unificado**: Tanto el frontend (Vite/React) como las llamadas a la API (`/upload`, `/chat/stream`, `/documents`) viajan transparentemente a través del contenedor Nginx en el puerto `80`.

---

## 2. Uso Rápido (Comandos)

En la raíz del proyecto tienes a disposición el script `tunnel.sh`:

### Iniciar el túnel
```bash
./tunnel.sh start
```
*Inicia el contenedor del túnel con Docker Compose, espera unos segundos a que Cloudflare asigne la dirección y te muestra la URL pública.*

### Consultar la URL pública activa
```bash
./tunnel.sh url
```
*Imprime la URL pública HTTPS activa, la copia al portapapeles y la **guarda** en `$HOME/cloudflare-url.txt` para que puedas copiarla de ahí cuando quieras.*

> Los subdominios `trycloudflare.com` son **temporales**: cada vez que el contenedor del túnel se reinicia, Cloudflare asigna uno nuevo. Por eso la URL no se debe memorizar ni compartir de forma permanente, y conviene leerla siempre del archivo `cloudflare-url.txt`.

### Reiniciar el túnel
```bash
./tunnel.sh restart
```
*Reinicia la conexión y genera una nueva URL.*

### Ver logs en tiempo real
```bash
./tunnel.sh logs
```

### Detener el túnel
```bash
./tunnel.sh stop
```

### Ejecutar túnel local directo en terminal (sin Docker)
```bash
./tunnel.sh local
```

---

## 3. Integración en Docker Compose

El servicio `tunnel` ya se encuentra integrado en [`docker-compose.yml`](docker-compose.yml):

```yaml
  tunnel:
    image: cloudflare/cloudflared:latest
    container_name: herramientastic-tunnel
    restart: unless-stopped
    command: tunnel --no-autoupdate --url http://frontend:80
    depends_on:
      - frontend
```

Gracias a `restart: unless-stopped`, mientras dejes tu PC encendida, el túnel permanecerá activo y se reiniciará automáticamente si hay microcortes de conexión.

### El archivo `cloudflare-url.txt`

Como el reinicio automático cambia la URL, el proyecto incluye
[`scripts/cloudflare-url-sync.sh`](scripts/cloudflare-url-sync.sh): lee la URL más
reciente de los logs del contenedor y la deja en `cloudflare-url.txt` (solo
escribe cuando cambia de verdad).

En este servidor se ejecuta solo, cada minuto, mediante un **timer de systemd**
(unidades `cloudflare-url-sync.service` y `cloudflare-url-sync.timer`), de modo
que el archivo nunca se queda con un enlace muerto aunque el túnel se reinicie
sin que nadie ejecute `tunnel.sh`. Para instalarlo en otra máquina Linux:

```bash
sudo tee /etc/systemd/system/cloudflare-url-sync.service >/dev/null <<'UNIT'
[Unit]
Description=Sincroniza la URL publica del tunel de Cloudflare en cloudflare-url.txt
After=docker.service
Wants=docker.service

[Service]
Type=oneshot
Environment=CLOUDFLARE_URL_FILE=%h/cloudflare-url.txt
Environment=CLOUDFLARE_URL_OWNER=%u
ExecStart=/ruta/al/proyecto/scripts/cloudflare-url-sync.sh
UNIT

sudo tee /etc/systemd/system/cloudflare-url-sync.timer >/dev/null <<'UNIT'
[Unit]
Description=Revisa cada minuto la URL publica del tunel de Cloudflare

[Timer]
OnBootSec=30s
OnUnitActiveSec=60s
AccuracySec=5s
Unit=cloudflare-url-sync.service

[Install]
WantedBy=timers.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable --now cloudflare-url-sync.timer
```

Comprobación manual en cualquier momento:

```bash
./scripts/cloudflare-url-sync.sh   # deja la URL en $HOME/cloudflare-url.txt
./tunnel.sh url                    # la muestra y también la guarda
```

---

## 4. Opcional: Configurar un dominio propio permanente (Túnel con Token)

Si cuentas con una cuenta gratuita en [Cloudflare Zero Trust](https://one.dash.cloudflare.com/) y un dominio propio (por ejemplo `midominio.com`):

1. Ve a **Networks** > **Tunnels** > **Create a tunnel**.
2. Selecciona **Cloudflare Tunnel** y copia el token generado.
3. En tu archivo `.env` añade:
   ```env
   CLOUDFLARE_TUNNEL_TOKEN=eyJhIjoi...tu_token_aqui...
   ```
4. En [`docker-compose.yml`](docker-compose.yml), cambia el comando del servicio `tunnel` a:
   ```yaml
   command: tunnel --no-autoupdate run --token ${CLOUDFLARE_TUNNEL_TOKEN}
   ```
5. En el panel de Cloudflare, apunta el Hostname público (ej. `gestor.midominio.com`) al servicio HTTP `http://frontend:80`.
6. Con esto tendrás un enlace fijo y permanente sin depender de subdominios temporales `trycloudflare.com`.

---

## 5. Recomendaciones para mantener la PC encendida y accesible

Para asegurar que tu PC no se suspenda ni entre en reposo mientras estés fuera:

1. **Evitar suspensión del sistema:**
   - En entornos KDE / GNOME / XFCE: Desactiva la suspensión automática en *Configuración del Sistema > Ahorro de energía*.
   - Alternativamente, puedes usar el comando nativo de Linux:
     ```bash
     systemd-inhibit --what=idle:sleep:handle-lid-switch --why="Servidor Gestor Documental" sleep infinity
     ```
2. **Reconexión automática:**
   - Docker y Cloudflare reintentan la conexión automáticamente ante caídas temporales de tu proveedor de internet.
