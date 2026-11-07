resource "railway_project" "this" {
  name           = var.project_name
  description    = "Gestor Inteligente de Documentos (API, worker, frontend, Redis y n8n)"
  private        = true
  has_pr_deploys = false
}

resource "railway_environment" "this" {
  for_each = var.environments

  name       = each.value
  project_id = railway_project.this.id
}

locals {
  # El backend comparte imagen entre API y worker; el frontend usa la suya.
  image_for = {
    backend-api    = "backend"
    backend-worker = "backend"
    frontend       = "frontend"
  }

  # Digest por servicio. Si está vacío se usa image_tag (solo bootstrap).
  digests = {
    backend-api    = lookup(var.image_digests, "backend-api", "")
    backend-worker = lookup(var.image_digests, "backend-worker", "")
    frontend       = lookup(var.image_digests, "frontend", "")
  }

  # Los servicios con digest fijado se despliegan por digest (inmutable).
  services = {
    backend-api = {
      image                      = local.digests["backend-api"] != "" ? "${var.image_prefix}-${local.image_for["backend-api"]}@${local.digests["backend-api"]}" : "${var.image_prefix}-${local.image_for["backend-api"]}:${var.image_tag}"
      start_command              = "node dist/index.js"
      healthcheck_path           = "/health"
      restart_policy_type        = "ON_FAILURE"
      restart_policy_max_retries = 10
      volume                     = null
    }
    backend-worker = {
      image                      = local.digests["backend-worker"] != "" ? "${var.image_prefix}-${local.image_for["backend-worker"]}@${local.digests["backend-worker"]}" : "${var.image_prefix}-${local.image_for["backend-worker"]}:${var.image_tag}"
      start_command              = "node dist/workers/document.worker.js"
      healthcheck_path           = null
      restart_policy_type        = "ON_FAILURE"
      restart_policy_max_retries = 10
      volume                     = null
    }
    frontend = {
      image                      = local.digests["frontend"] != "" ? "${var.image_prefix}-${local.image_for["frontend"]}@${local.digests["frontend"]}" : "${var.image_prefix}-${local.image_for["frontend"]}:${var.image_tag}"
      start_command              = null
      healthcheck_path           = "/healthz"
      restart_policy_type        = "ON_FAILURE"
      restart_policy_max_retries = 10
      volume                     = null
    }
    redis = {
      image                      = "redis:7-alpine"
      start_command              = "redis-server --appendonly yes"
      healthcheck_path           = null
      restart_policy_type        = "ON_FAILURE"
      restart_policy_max_retries = 10
      volume = {
        name       = "redis-data"
        mount_path = "/data"
      }
    }
    n8n = {
      image                      = "n8nio/n8n:2.46.6"
      start_command              = null
      healthcheck_path           = "/healthz"
      restart_policy_type        = "ON_FAILURE"
      restart_policy_max_retries = 10
      volume = {
        name       = "n8n-data"
        mount_path = "/home/node/.n8n"
      }
    }
  }

  # environment -> service -> variables, solo para combinaciones no vacías.
  variable_collections = merge([
    for environment_name, services in var.service_variables : {
      for service_name, variables in services : "${environment_name}/${service_name}" => {
        environment_id = railway_environment.this[environment_name].id
        service_id     = railway_service.this[service_name].id
        variables      = [for name, value in variables : { name = name, value = value }]
      } if length(variables) > 0
    }
  ]...)
}

resource "railway_service" "this" {
  for_each = local.services

  name                       = each.key
  project_id                 = railway_project.this.id
  source_image               = each.value.image
  start_command              = each.value.start_command
  healthcheck_path           = each.value.healthcheck_path
  restart_policy_type        = each.value.restart_policy_type
  restart_policy_max_retries = each.value.restart_policy_max_retries
  volume                     = each.value.volume
}

# Las variables sensibles no viven en el repositorio: se pasan por TF_VAR o por
# un terraform.tfvars ignorado. Cambiarlas dispara un redeploy del servicio.
resource "railway_variable_collection" "this" {
  for_each = local.variable_collections

  environment_id = each.value.environment_id
  service_id     = each.value.service_id
  variables      = each.value.variables
}
