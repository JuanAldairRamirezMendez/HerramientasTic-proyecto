# Runbook: despliegue y rollback

## 1. Antes de desplegar

- [ ] CI del submódulo en verde.
- [ ] PR del submódulo mergeado a `develop`.
- [ ] PR de bump de submódulos en el repo raíz apuntando a commits publicados.
- [ ] CI del repo raíz en verde (`submodules`, `scripts`, `integration`, `secrets`).
- [ ] Variables del entorno revisadas.
- [ ] Si hay migraciones de Supabase, son compatibles hacia atrás.
- [ ] Backup de Supabase y de n8n si el cambio los afecta.

## 2. Despliegue normal

```text
develop (root)  → staging automático
master/main     → production con aprobación
```

El workflow `CD` se dispara cuando termina `CI`:

1. Verifica los gitlinks de los submódulos.
2. Despliega `backend-api` desde el SHA del backend.
3. Despliega `backend-worker` desde el mismo SHA.
4. Despliega `frontend` desde el SHA del frontend.
5. Espera el estado `SUCCESS` de cada deployment.
6. Ejecuta el smoke test contra las URLs públicas.

Si el smoke falla, el workflow falla y el despliegue queda marcado como roto.

## 3. Despliegue manual

Útil para recuperar un entorno o probar staging antes de que el workflow esté
en la rama estable.

```bash
export RAILWAY_TOKEN="<token-del-entorno>"
export RAILWAY_PROJECT_ID="<project-id>"

# Staging desde develop
git checkout develop
git pull --ff-only origin develop
git submodule update --init --recursive
bash scripts/verify-submodules.sh --env staging
bash scripts/deploy-railway.sh staging

# Producción desde master
git checkout master
git pull --ff-only origin master
git submodule update --init --recursive
bash scripts/verify-submodules.sh --env production
bash scripts/deploy-railway.sh production

# Smoke
BACKEND_URL="<backend>" FRONTEND_URL="<frontend>" \
  SMOKE_CHAT_CHECK=1 bash scripts/smoke.sh
```

Para forzar el método de subida local:

```bash
bash scripts/deploy-railway.sh staging --method up
```

## 4. Rollback

### 4.1 Rollback de aplicación

El rollback debe devolver `backend-api`, `backend-worker` y `frontend` a un
estado coherente. No mezcles versiones si el cambio tocó contratos de API o
payloads de BullMQ.

**Opción A — dashboard de Railway (recomendada)**

1. Abrir el servicio → **Deployments**.
2. Localizar el último deployment `SUCCESS` anterior al cambio.
3. **Redeploy** sobre ese deployment.
4. Repetir con los servicios afectados.
5. Ejecutar el smoke test.

**Opción B — CLI con el commit conocido**

Si el servicio está conectado a GitHub:

```bash
railway redeploy \
  --project "$RAILWAY_PROJECT_ID" \
  --environment production \
  --service backend-api \
  --commit <sha-anterior> \
  --yes
```

Repetir para `backend-worker` con el mismo SHA del backend. Para el frontend,
usar el SHA anterior del frontend.

**Opción C — subida local del commit anterior**

```bash
git checkout <sha-anterior>
git submodule update --init --recursive
bash scripts/deploy-railway.sh production --method up
```

### 4.2 Orden de rollback

1. `backend-api` y `backend-worker` juntos.
2. `frontend` si el cambio visual o de contrato lo requiere.
3. `n8n` solo si el cambio fue de workflows o credenciales.

### 4.3 Rollback de base de datos

- No ejecutes migraciones destructivas en el mismo release que el código.
- Usa el patrón **expand/contract**:
  1. Añadir columnas/tablas compatibles.
  2. Desplegar código que escribe en ambos formatos.
  3. Migrar datos.
  4. Eliminar lo viejo en un release posterior.
- Si hay que revertir datos, restaurar desde backup de Supabase; no improvises
  `DROP`/`ALTER` en producción.
- Las migraciones deben ser idempotentes y versionadas en el repo backend
  (Fase 1).

## 5. Smoke test post-deploy

```bash
BACKEND_URL="https://<backend>" \
FRONTEND_URL="https://<frontend>" \
SMOKE_CHAT_CHECK=1 \
bash scripts/smoke.sh
```

Comprueba:

- `/health` del backend.
- `/healthz` del frontend.
- El HTML del frontend.
- Que “hola” responde sin `tool_results` (regresión de las tarjetas).

Si el entorno tiene documentos de prueba, añade:

```bash
SMOKE_EXPECT_DOCUMENTS=1 bash scripts/smoke.sh
```

## 6. Checklist de incidente

- [ ] Confirmar el alcance: ¿API, worker, frontend, Redis, n8n o Supabase?
- [ ] Revisar el deployment que falló y sus logs de build/deploy.
- [ ] Decidir rollback o forward-fix; no dejar producción en estado intermedio.
- [ ] Ejecutar smoke después del rollback.
- [ ] Registrar el incidente y la causa raíz.
- [ ] Añadir una prueba o check que detecte el mismo fallo.

## 7. Qué no hacer

- No hacer force push a `master`/`main` ni a `develop`.
- No desplegar un worker con un SHA distinto al de la API.
- No tocar n8n sin volumen persistente y backup.
- No ejecutar migraciones destructivas sin backup y ventana de mantenimiento.
- No commitear tokens de Railway, Supabase o Gemini.
