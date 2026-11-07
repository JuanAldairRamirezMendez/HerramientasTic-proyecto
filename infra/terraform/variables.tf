variable "railway_token" {
  description = "Token de Railway. Preferir la variable de entorno RAILWAY_TOKEN."
  type        = string
  sensitive   = true
  default     = null
}

variable "project_name" {
  description = "Nombre del proyecto de Railway."
  type        = string
  default     = "HerramientasTIC"
}

variable "environments" {
  description = "Entornos que deben existir en el proyecto."
  type        = set(string)
  default     = ["production", "staging"]
}

variable "image_prefix" {
  description = "Prefijo de las imágenes inmutables publicadas en GHCR."
  type        = string
  default     = "ghcr.io/juanaldairramirezmendez/herramientastic-tic"
}

variable "image_tag" {
  description = "Tag por defecto cuando un servicio no tiene digest fijado."
  type        = string
  default     = "latest"
}

variable "image_digests" {
  description = "Digest inmutable por servicio (por ejemplo, sha256:...). Vacío usa image_tag."
  type        = map(string)
  default     = {}
}

variable "service_variables" {
  description = "Mapa environment -> service -> variables. No commitear secretos; pasar por TF_VAR o un tfvars ignorado."
  type        = map(map(map(string)))
  default     = {}
  sensitive   = true
}
