# HerramientasTIC

Aplicación de gestión documental con backend (API + worker), frontend React y
automatizaciones n8n. El repositorio raíz orquesta dos submódulos:

- `Gestor-Inteligente-de-Documentos`: API Express, worker BullMQ y pruebas.
- `Gestor-Inteligente-de-Documentos-Frontend`: React + Vite servido por Nginx.

Cada submódulo tiene su propio repositorio, su propio CI y su propio
`Dockerfile`. El repo raíz valida la integración real de ambos.

## Ejecución local

```bash
cp .env.example .env   # completa GEMINI_API_KEY y SUPABASE_SECRET_KEY
docker compose up --build
```

- Frontend: http://localhost
- API: http://localhost:3000
- Health API: http://localhost:3000/health
- Health frontend: http://localhost/healthz

## CI/CD

La Fase 0 de CI/CD está documentada en [`docs/ci-cd.md`](docs/ci-cd.md).

Resumen:

- CI por submódulo (typecheck, lint, test, build, Docker, Gitleaks).
- CI del repo raíz: valida submódulos, scripts y levanta el stack completo.
- CD con GitHub Actions + Railway CLI:
  - `develop` → staging automático.
  - `master`/`main` → producción con aprobación manual.
  - Smoke test después de cada despliegue.

Runbooks:

- [`docs/runbooks/railway.md`](docs/runbooks/railway.md): configuración de
  servicios, entornos, tokens y n8n.
- [`docs/runbooks/deploy-rollback.md`](docs/runbooks/deploy-rollback.md):
  despliegue manual, rollback y verificación.

## Flujo de ramas

```text
master/main  ←  develop  ←  feat/*, fix/*, chore/*, docs/*
```

- Los cambios de cada submódulo se mergean a su `develop`.
- Después se actualiza el gitlink en el repo raíz con un PR a `develop`.
- La promoción a `master`/`main` dispara el despliegue a producción.
