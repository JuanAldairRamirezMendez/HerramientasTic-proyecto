# Runbook: Railway

Proyecto: `HerramientasTIC` (`0daa6d53-029f-4658-a89a-81ad6d1bf00d`).
Entornos: `staging` y `production`.

Railway ya no recomienda `railway.toml` para Config as Code. La configuración
de cada servicio se mantiene en el dashboard y este documento registra el
estado esperado para detectar deriva.

## 1. Servicios

| Servicio | Repositorio | Start command | Healthcheck | Puerto público |
|---|---|---|---|---|
| `backend-api` | backend | `node dist/index.js` | `GET /health` | Sí |
| `backend-worker` | backend | `node dist/workers/document.worker.js` | Ninguno (gap conocido) | No |
| `frontend` | frontend | `nginx -g 'daemon off;'` (CMD del Dockerfile) | `GET /healthz` | Sí |
| `Redis` | imagen `redis:7-alpine` | — | `redis-cli ping` | No |
| `n8n` | imagen oficial | — | `GET /healthz` | Sí |

Reglas:

- `backend-api` y `backend-worker` deben desplegarse desde el **mismo commit**.
  Un worker con un contrato distinto puede fallar al procesar la cola.
- El worker todavía no expone un healthcheck HTTP. Railway solo puede validar
  que el proceso esté vivo; la Fase 1 debe añadir un servidor mínimo de salud.
- `frontend` no debe tener dominio propio en staging si se quiere evitar
  indexación accidental; usa el dominio de Railway y protege el acceso si hace
  falta.

## 2. Variables por servicio

### backend-api y backend-worker

| Variable | Notas |
|---|---|
| `GEMINI_API_KEY` | Obligatoria. Distinta por entorno. |
| `GEMINI_MODEL` | `gemini-3.5-flash-lite` por defecto. |
| `GEMINI_TIMEOUT_MS` | `45000`. |
| `GEMINI_THINKING_LEVEL` | `minimal`. |
| `IA_MOBILE_MAX_TOKENS` | `768`. |
| `SUPABASE_URL` | URL del proyecto Supabase del entorno. |
| `SUPABASE_SECRET_KEY` | Secreto de servicio. Nunca en el frontend. |
| `REDIS_URL` | Referencia al servicio Redis del mismo entorno. |
| `QUEUE_ENABLED` | `true` en producción y staging. |
| `FRONTEND_URL` | URL pública del frontend de ese entorno. |
| `N8N_WEBHOOK_URL` | Solo si se usa n8n; no debe quedar en servicios que no lo necesitan. |
| `N8N_WEBHOOK_TOKEN` | Secreto compartido con n8n. |
| `NODE_ENV` | `production`. |

### frontend

Se leen al **arrancar el contenedor** (`docker-entrypoint.d/40-runtime-config.sh`),
no al construir la imagen. La misma imagen sirve para staging y producción.

| Variable | Notas |
|---|---|
| `API_URL` | URL absoluta del backend para el navegador. Vacía = mismo origen con proxy de nginx. |
| `API_UPSTREAM` | URL interna que nginx usa como upstream cuando `API_URL` está vacía. En Railway: `http://backend-api.railway.internal:3000`. |
| `DNS_RESOLVER` | DNS para resolver `API_UPSTREAM`. En Railway: `fd12::10` (nginx lo escribe como `[fd12::10]`). Se autodetecta de `/etc/resolv.conf` si no se define. |
| `JOB_TIMEOUT_MS` | Presupuesto de polling de jobs. `720000` (12 min) por defecto. |

`VITE_API_URL` y `VITE_JOB_TIMEOUT_MS` siguen aceptándose como fallback de
build time en desarrollo, pero el despliegue normal no los usa.

### n8n

| Variable | Valor |
|---|---|
| `N8N_ENCRYPTION_KEY` | Clave fija y respaldada. Sin ella se pierden credenciales al recrear el contenedor. |
| `TZ` | `America/Lima` |
| `GENERIC_TIMEZONE` | `America/Lima` |
| `N8N_HOST` | Dominio público de n8n. |
| `N8N_PROTOCOL` | `https` |
| `WEBHOOK_URL` | `https://<dominio-n8n>/` |
| `N8N_EDITOR_BASE_URL` | `https://<dominio-n8n>/` |

## 3. Volúmenes

| Servicio | Mount path | Motivo |
|---|---|---|
| `n8n` | `/home/node/.n8n` | Workflows, credenciales y SQLite. **Obligatorio antes de cualquier redeploy.** |
| `Redis` | `/data` | Persistencia de la cola. Sin volumen, un redeploy pierde jobs. |

Si n8n no tiene volumen, un redeploy borra workflows y credenciales. Antes de
tocar n8n:

1. Adjuntar volumen en `/home/node/.n8n`.
2. Configurar `N8N_ENCRYPTION_KEY` y respaldarla.
3. Exportar los workflows a JSON y versionarlos en
   `infra/n8n/workflows/` (Fase 2).
4. Hacer backup de `database.sqlite` antes del cambio.

## 4. Entornos y tokens

- `staging` y `production` son entornos del mismo proyecto Railway.
- Los servicios se comparten, pero las variables y los deployments son
  independientes.
- Crear un **token de proyecto** por entorno:
  - Railway → Project Settings → Tokens → Create Token → seleccionar entorno.
  - Guardarlo como `RAILWAY_TOKEN` en el environment correspondiente de
    GitHub. No reutilizar el token de producción en staging.
- El token se usa solo en `scripts/deploy-railway.sh` y en los workflows de
  GitHub Actions. No se imprime ni se commitea.

## 5. Imágenes y despliegue por digest

El CI publica en GHCR:

- `ghcr.io/<owner>/herramientastic-tic-backend:<sha>`
- `ghcr.io/<owner>/herramientastic-tic-frontend:<sha>`

Cada imagen lleva digest, SBOM y procedencia. El despliegue recomendado es
`RAILWAY_DEPLOY_METHOD=image`: el script resuelve el digest con la API OCI de
GHCR y configura el servicio con `imagen@sha256:...`.

Requisitos:

- El job `images` debe haber publicado el SHA del submódulo.
- Railway Trial no admite credenciales de registro privado: el paquete GHCR
  debe ser público o el pull fallará. Verificar en **Package settings →
  Change visibility**.
- Para paquetes privados, el CD usa `GHCR_TOKEN` (el `GITHUB_TOKEN` del job con
  `packages: read`). Localmente, exportar `GHCR_USER`/`GHCR_TOKEN`.

Si se usa `redeploy`, el servicio debe estar conectado al repositorio de GitHub
en Railway. `up` queda solo como fallback de emergencia.

## 6. Restart policy y límites del Trial

- Plan Trial: 1 GB de RAM y 2 vCPU por servicio.
- Restart policy: `On Failure`, máximo 10 reintentos.
- No usar reinicios infinitos: un crash loop debe quedar visible.
- El backend incluye Chromium para generar PDFs; vigilar memoria en cargas
  concurrentes.

## 7. Verificación operativa

```bash
# Estado del proyecto y servicios
railway status --project "$RAILWAY_PROJECT_ID" --environment production

# Últimos deployments
railway deployment list \
  --project "$RAILWAY_PROJECT_ID" \
  --environment production \
  --service backend-api \
  --limit 10

# Logs de build y ejecución
railway logs --project "$RAILWAY_PROJECT_ID" --environment production \
  --service backend-api --build --lines 100
railway logs --project "$RAILWAY_PROJECT_ID" --environment production \
  --service backend-api --deployment --lines 100

# Smoke
BACKEND_URL=https://<backend> FRONTEND_URL=https://<frontend> \
  SMOKE_CHAT_CHECK=1 bash scripts/smoke.sh
```

## 8. Deriva de configuración

La configuración declarativa vive en `infra/terraform/` y el workflow `Infra`
solo valida (`fmt`, `init -backend=false`, `validate`). Mientras el estado de
Terraform no se haya importado y aplicado, el dashboard sigue siendo la fuente
de verdad. Revisar periódicamente:

- Start command de cada servicio.
- Healthcheck path y puerto.
- Restart policy.
- Volúmenes de n8n y Redis.
- Variables de entorno por entorno.
- Dominios públicos.

Para adoptar Terraform sin recrear recursos, copiar `imports.tf.example` a
`imports.tf`, revisar que `terraform plan` muestre imports y aplicar solo
después. El estado local contiene IDs y valores sensibles: configurar backend
remoto antes de compartirlo.
