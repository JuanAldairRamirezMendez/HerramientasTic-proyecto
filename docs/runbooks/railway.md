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

| Variable | Notas |
|---|---|
| `VITE_API_URL` | **Build-time**. Debe ser la URL pública del backend del entorno. Cambiarla exige rebuild. |
| `VITE_JOB_TIMEOUT_MS` | Opcional; build-time. |

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

## 5. Restart policy y límites del Trial

- Plan Trial: 1 GB de RAM y 2 vCPU por servicio.
- Restart policy: `On Failure`, máximo 10 reintentos.
- No usar reinicios infinitos: un crash loop debe quedar visible.
- El backend incluye Chromium para generar PDFs; vigilar memoria en cargas
  concurrentes.

## 6. Verificación operativa

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

## 7. Deriva de configuración

Como la configuración vive en el dashboard, revisar periódicamente:

- Start command de cada servicio.
- Healthcheck path y puerto.
- Restart policy.
- Volúmenes de n8n y Redis.
- Variables de entorno por entorno.
- Dominios públicos.

La Fase 2 puede automatizar esta verificación con la API de Railway, pero no
conviene introducir Config as Code mientras el equipo dependa del dashboard.
