# CI/CD del proyecto

## 1. Modelo

```text
feature/fix PR
      │
      ├─ CI del submódulo (backend o frontend)
      │
      ▼
   develop (submódulo)
      │
      ├─ PR de bump de submódulos en el repo raíz
      │
      ▼
   develop (root)
      │
      ├─ CI root: submódulos + scripts + stack Docker + Gitleaks
      │
      ▼
   Deploy automático a staging
      │
      ├─ Smoke test contra URLs públicas de staging
      │
      ▼
   PR develop → master/main
      │
      ├─ Aprobación manual (GitHub Environment production)
      │
      ▼
   Deploy a producción + smoke test
```

Railway tiene un proyecto con dos entornos: `staging` y `production`. Los
servicios son los mismos (`backend-api`, `backend-worker`, `frontend`, `Redis`,
`n8n`); cada entorno tiene sus propias variables y su propio despliegue.

## 2. Pipeline del repo raíz

Workflow: `.github/workflows/ci.yml`.

| Job | Qué valida |
|---|---|
| `submodules` | Cada gitlink está publicado en `develop`, `main` o `master` del submódulo. |
| `scripts` | Sintaxis Bash y ShellCheck de `scripts/*.sh`. |
| `audit` | `npm audit --omit=dev` en backend y frontend; bloquea en `CRITICAL` y publica el reporte completo. |
| `codeql` | Análisis estático JavaScript/TypeScript de ambos submódulos. |
| `trivy` | Vulnerabilidades en el filesystem y en las imágenes; SARIF en Security. Bloquea en `CRITICAL`. |
| `integration` | `docker compose config`, build de imágenes, arranque real del stack y smoke. |
| `secrets` | Gitleaks sobre todo el historial. |
| `images` | Publica imágenes inmutables en GHCR con tag SHA, digest, SBOM y procedencia. Solo en push a `develop`/`master`/`main` o `workflow_dispatch`, y solo si pasaron `integration`, `audit`, `codeql` y `trivy`. |

El job `integration` construye el backend y el frontend, levanta Redis, API,
worker y frontend, y comprueba:

- `GET /health` del backend.
- `GET /healthz` del frontend.
- El `index.html` del frontend.
- `GET /config.js` del frontend (configuración de runtime).

No usa Gemini ni Supabase reales: `scripts/write-ci-env.sh` genera un `.env`
con valores ficticios.

## 3. CD con Railway

Workflow: `.github/workflows/cd.yml`.

- Se dispara cuando termina el workflow `CI`.
- Si la rama es `develop` y CI pasó, despliega **staging**.
- Si la rama es `master`/`main` y CI pasó, despliega **producción**.
- El job de producción usa el environment `production`; si tiene revisores
  obligatorios, el despliegue queda esperando aprobación.
- También se puede lanzar manualmente con `workflow_dispatch`.

> **Limitación de `workflow_run`:** GitHub solo evalúa este evento si el
> workflow `CD` existe en la rama por defecto del repositorio (`master`). Hasta
> que la Fase 0 se promueva a `master`, usa `workflow_dispatch` o ejecuta
> `scripts/deploy-railway.sh` localmente. Después de la promoción, el
> despliegue automático de staging y producción queda activo.

El script `scripts/deploy-railway.sh`:

1. Verifica que los submódulos apunten a la rama correcta.
2. Despliega `backend-api` desde el commit del submódulo backend.
3. Despliega `backend-worker` desde el mismo commit.
4. Despliega `frontend` desde el commit del submódulo frontend.
5. Espera a que Railway reporte cada deployment como `SUCCESS` o falla.

Métodos de despliegue:

- `image` (recomendado): resuelve el digest de
  `ghcr.io/<owner>/herramientastic-tic-<servicio>:<sha>` mediante la API OCI de
  GHCR, configura el servicio con `railway service source connect --image
  imagen@sha256:...` y despega con `railway redeploy --from-source`. Requiere
  que el job `images` haya publicado ese SHA. La imagen es idéntica en staging y
  producción; solo cambian las variables.
- `redeploy` (default): `railway redeploy --commit <sha>`. Requiere que el
  servicio esté conectado al repositorio de GitHub en Railway.
- `up`: `railway up` desde el directorio del submódulo. Sirve como fallback si
  el servicio no está conectado a GitHub, pero sube el árbol local en lugar de
  pedir un commit concreto.

Si `redeploy` falla porque el servicio no está conectado a un repositorio, el
script cae automáticamente a `up`.

### Imágenes en GHCR

- Nombres: `herramientastic-tic-backend` y `herramientastic-tic-frontend`.
- Tags: SHA completo del commit y nombre de la rama; `latest` solo en
  `master`/`main`.
- El job `images` exige `packages: write`; el CD usa `packages: read` y
  `GHCR_TOKEN` para resolver el digest.
- Railway Trial no permite registrar credenciales de registro privado. Si el
  paquete queda privado, el despliegue por digest falla al hacer pull. Verifica
  que herede la visibilidad pública del repositorio o hazlo público en
  **Package settings → Change visibility**.

La configuración del frontend (`API_URL`, `API_UPSTREAM`, `DNS_RESOLVER`,
`JOB_TIMEOUT_MS`) se aplica al arrancar el contenedor, así que promover una
imagen no requiere rebuild.

## 4. Configuración en GitHub

### 4.1 Environments

Crear dos environments en **Settings → Environments**:

- `staging`
- `production`

En `production`, añadir **Required reviewers**. Importante: GitHub no permite
que quien dispara el workflow apruebe su propia ejecución. Si el proyecto tiene
un solo colaborador, añade un segundo colaborador o desactiva temporalmente la
protección para el primer despliegue.

### 4.2 Secretos y variables por environment

| Nombre | Tipo | Ejemplo / uso |
|---|---|---|
| `RAILWAY_TOKEN` | Secret | Token de proyecto de Railway para ese entorno. |
| `RAILWAY_PROJECT_ID` | Variable | `0daa6d53-029f-4658-a89a-81ad6d1bf00d`. |
| `BACKEND_URL` | Variable | URL pública del backend de ese entorno. |
| `FRONTEND_URL` | Variable | URL pública del frontend de ese entorno. |
| `SMOKE_CHAT_CHECK` | Variable | `1` para validar que “hola” no devuelve tarjetas. |
| `SMOKE_EXPECT_DOCUMENTS` | Variable | `1` solo si staging/producción tienen documentos cargados. |
| `RAILWAY_DEPLOY_METHOD` | Variable | `image` (recomendado), `redeploy` (default) o `up`. |

Configuración con GitHub CLI (el valor del secreto se escribe de forma
interactiva, no en el historial del shell):

```bash
gh variable set RAILWAY_PROJECT_ID --env staging --body "<project-id>"
gh secret set RAILWAY_TOKEN --env staging

gh variable set BACKEND_URL --env staging --body "https://<backend-staging>"
gh variable set FRONTEND_URL --env staging --body "https://<frontend-staging>"
gh variable set SMOKE_CHAT_CHECK --env staging --body "1"
gh variable set RAILWAY_DEPLOY_METHOD --env staging --body "image"
```

Repetir con `--env production`.

Los tokens deben ser distintos por entorno. Un token de proyecto de Railway
está limitado a un entorno; no reutilices el de producción en staging.

### 4.3 Protección de ramas

El repo raíz todavía no tiene rulesets. Después de la primera ejecución de CI,
crear reglas para `develop` y `master`/`main` que exijan:

- Pull request.
- Checks requeridos: `submodules`, `scripts`, `integration`, `secrets`.
- Rama actualizada antes de mergear.
- Sin force push.

No actives los checks requeridos antes de que exista al menos una ejecución:
GitHub necesita conocer los nombres exactos.

## 5. Configuración en Railway

Los detalles operativos están en
[`runbooks/railway.md`](runbooks/railway.md). Resumen:

1. Crear el entorno `staging` en el proyecto.
2. Duplicar las variables de producción y sustituir las credenciales por las de
   staging (idealmente un proyecto Supabase separado).
3. Verificar que `backend-api`, `backend-worker` y `frontend` existan en ambos
   entornos.
4. Crear un token de proyecto por entorno y guardarlo como `RAILWAY_TOKEN`.
5. Confirmar que cada servicio está conectado al repositorio correcto de GitHub
   si se usa el método `redeploy`.

## 6. Infraestructura versionada

`infra/terraform/` declara el proyecto, entornos, servicios, volúmenes y
variables de Railway con el provider comunitario `railway ~> 0.6.3`. El
workflow `Infra` (`.github/workflows/infra.yml`) solo ejecuta `fmt`, `init
-backend=false` y `validate`; nunca aplica cambios ni requiere credenciales.

Adoptar la infraestructura existente exige copiar `imports.tf.example` a
`imports.tf` y revisar que el plan muestre imports, no creación de recursos
duplicados. El detalle está en `infra/terraform/README.md`.

## 7. Estado de la Fase 1 y pendientes

Completado:

- Imagen inmutable por servicio en GHCR con digest, SBOM y procedencia.
- Despliegue por digest (`RAILWAY_DEPLOY_METHOD=image`).
- Configuración runtime del frontend (sin `VITE_API_URL` de build).
- Cobertura con umbral en el job `test` del backend y e2e determinista del chat.
- `npm audit`, CodeQL, Trivy y Gitleaks en el pipeline.
- Infraestructura de Railway versionada (validate-only).

Pendiente:

- Configurar `RAILWAY_TOKEN` por entorno y crear el entorno `staging`.
- Healthcheck propio del worker y graceful shutdown.
- Migraciones versionadas de Supabase y validación en PR.
- Observabilidad: Sentry, métricas, alertas y panel de BullMQ.
- Volumen persistente y workflow-as-code para n8n.
- Bump automático de submódulos tras cada merge.
- Corregir los `high` de `sharp`/`undici` y subir el umbral de `audit` a `high`.

## 8. Ejecución local de los scripts

```bash
# Verificar submódulos
bash scripts/verify-submodules.sh --env any

# Smoke contra el stack local
BACKEND_URL=http://localhost:3000 FRONTEND_URL=http://localhost \
  bash scripts/smoke.sh

# Smoke con validación del chat
BACKEND_URL=https://<backend> FRONTEND_URL=https://<frontend> \
  SMOKE_CHAT_CHECK=1 bash scripts/smoke.sh

# Despliegue manual por digest (imagen ya publicada por CI)
RAILWAY_TOKEN=... RAILWAY_PROJECT_ID=... \
  bash scripts/deploy-railway.sh staging --method image

# Para paquetes privados de GHCR, exportar también GHCR_USER/GHCR_TOKEN.
RAILWAY_TOKEN=... RAILWAY_PROJECT_ID=... \
GHCR_USER=<usuario> GHCR_TOKEN=<token-con-read:packages> \
  bash scripts/deploy-railway.sh staging --method image
```

No ejecutes `scripts/write-ci-env.sh` sin `CI=true` o `--force`: sobrescribe el
`.env` local.
