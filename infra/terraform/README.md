# Infraestructura de Railway como código

Este directorio describe el proyecto, entornos, servicios, volúmenes y
variables de Railway con el provider comunitario
[`terraform-community-providers/railway`](https://registry.terraform.io/providers/terraform-community-providers/railway).
La versión está fijada en `~> 0.6.3`.

## Qué gestiona y qué no

Gestiona:

- proyecto y entornos (`production`, `staging`);
- servicios `backend-api`, `backend-worker`, `frontend`, `redis` y `n8n`;
- imagen de origen (tag o digest), comando de arranque, healthcheck, política de
  reinicio y volúmenes persistentes;
- variables por entorno y servicio (sin secretos en el repositorio).

No gestiona:

- el **despliegue** de una imagen nueva. Railway no expone un recurso de
  deployment en este provider; el CD actualiza el digest con
  `railway service source connect --image ...` / `railway redeploy` y, cuando
  se adopte Terraform en operación, con un `terraform apply` limitado al
  servicio.
- dominios públicos generados por Railway (usar `railway_service_domain` si se
  quieren declarar).
- secretos. Se pasan por `RAILWAY_TOKEN` y `TF_VAR_*` o por un tfvars ignorado.

## Flujo seguro

Terraform no se aplica automáticamente en CI. El pipeline solo valida formato y
sintaxis. Aplicar sin importar primero los recursos existentes intentaría
crear un proyecto duplicado.

```bash
cd infra/terraform
terraform init

# 1. Adoptar la infraestructura existente (una sola vez).
cp imports.tf.example imports.tf
terraform plan     # debe mostrar imports, no creates
terraform apply    # solo tras revisar el plan

# 2. A partir de aquí, cambios declarativos.
terraform plan
terraform apply
```

Antes de compartir el estado entre personas o runners, configurar un backend
remoto (Terraform Cloud, S3 u otro). El estado local contiene IDs y valores
sensibles; nunca debe commitearse.

## Variables

| Variable | Uso |
| --- | --- |
| `RAILWAY_TOKEN` | Token de cuenta/workspace con permisos sobre el proyecto. |
| `TF_VAR_image_digests` | Digests inmutables por servicio (`sha256:...`). |
| `TF_VAR_service_variables` | Variables por entorno/servicio; no commitear secretos. |
| `TF_VAR_image_tag` | Solo bootstrap; en operación usar digests. |

Ejemplo de digests:

```bash
export TF_VAR_image_digests='{
  "backend-api": "sha256:...",
  "backend-worker": "sha256:...",
  "frontend": "sha256:..."
}'
```

## Validación en CI

El job `terraform` del workflow raíz ejecuta:

```bash
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
```

No requiere credenciales ni aplica cambios.

## Límites de Railway Trial

Cada servicio está limitado a 1 GB de RAM y 2 vCPU, con política `ON_FAILURE` y
máximo 10 reintentos. `n8n` necesita el volumen `n8n-data` montado en
`/home/node/.n8n`; sin él, cada redeploy pierde workflows y credenciales.
