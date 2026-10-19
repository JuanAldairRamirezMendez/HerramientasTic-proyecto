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

### Arranque automático de la VM (servicio systemd)

La VM de Azure se apaga sola por desuso, así que al encenderla debe quedar todo
levantado y con la URL nueva disponible. De eso se encarga el servicio
`gestor-documentos.service`, que ejecuta `/opt/gestor-documentos/start.sh`:

1. Levanta el stack con `docker compose -f docker-compose.yml up -d`.
2. Espera a que Cloudflare anuncie la URL (hasta 2 minutos) y la deja en
   `cloudflare-url.txt`.
3. Registra la URL en el log: `journalctl -t gestor-documentos`.

El arranque **no notifica a nadie por sí mismo**: solo escribe la URL en el
archivo y en el log. El aviso al móvil lo manda el correo (ver "Aviso por correo
cuando cambia la URL"), que corre en su propio timer; de ese modo un fallo de
SMTP no puede tumbar el arranque.

> **Ojo con el archivo compose**: el script apuntaba a `docker-compose.azure.yml`,
> que no existe, y con `set -e` moría en la primera línea: el stack no lo
> levantaba él y la URL no se guardaba en el arranque. Si algún día se renombra
> `docker-compose.yml`, hay que actualizar esa ruta.

### Se retiró el aviso por WhatsApp (19 oct 2026)

El arranque intentaba mandar la URL por WhatsApp con la API de Meta y fallaba con
**401 (token vencido)**. Su único uso era esta URL y el correo ya la manda, así
que se quitó el canal. Las piezas quedaron **desactivadas, no borradas**:

| Pieza | Estado |
|---|---|
| `/opt/gestor-documentos/start.sh` | bloque de WhatsApp eliminado (copia: `start.sh.bak-whatsapp-20261019`) |
| `/opt/gestor-documentos/send-whatsapp-url.sh` | renombrado a `.disabled` (no lo llamaba nadie) |
| `/etc/gestor-documentos/whatsapp.env` | renombrado a `.disabled` |
| `/etc/systemd/system/gestor-documentos.service` | sin la línea `EnvironmentFile=` |
| Copias con las credenciales | `/root/whatsapp.env.bak-20261019`, `/root/send-whatsapp-url.sh.bak-20261019`, `/root/gestor-documentos.service.bak-whatsapp-20261019` |

Para reactivarlo habría que reponer el bloque y el `EnvironmentFile`, y renovar
el token en Meta.

Como red de seguridad, los timers de systemd repasan la URL cada minuto, así que
aunque el servicio de arranque falle o el túnel tarde en aparecer, el archivo se
corrige solo.

### Aviso por correo cuando cambia la URL

`scripts/cloudflare-url-mail.sh` manda un correo con el enlace nuevo (y el
anterior) cuando detecta un cambio, avisando de que el viejo ya no responde. Es
el canal de aviso al móvil desde que se retiró WhatsApp:

- Espera **90 s** a que la URL se asiente, para no avisar de direcciones
  transitorias si el servidor reinicia en cadena.
- No manda más de **un correo cada 10 minutos**; los cambios seguidos se agrupan.
- Hasta **3 intentos** por URL y después se rinde (sin bucles si el SMTP falla).
- Solo avisa cuando la URL cambia de verdad.

Configuración (nunca en el repositorio):

```bash
cp scripts/cloudflare-url-mail.conf.example ~/.config/cloudflare-url-mail.conf
chmod 600 ~/.config/cloudflare-url-mail.conf
nano ~/.config/cloudflare-url-mail.conf     # SMTP_USER, SMTP_PASS, MAIL_TO
./scripts/cloudflare-url-mail.sh --test     # envía un correo de prueba
```

Para Gmail hace falta una **contraseña de aplicación** (no la del correo), que se
genera en <https://myaccount.google.com/apppasswords> con la verificación en dos
pasos activada.

Activación del aviso automático (los dos timers, cada minuto):

```bash
sudo systemctl enable --now cloudflare-url-sync.timer cloudflare-url-mail.timer
systemctl list-timers 'cloudflare-url-*'    # comprobar que están activos
journalctl -u cloudflare-url-mail.service   # ver los envíos y los errores
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
