terraform {
  required_version = ">= 1.7.0"

  required_providers {
    railway = {
      source  = "terraform-community-providers/railway"
      version = "~> 0.6.3"
    }
  }
}

provider "railway" {
  # Si no se define, el provider lee RAILWAY_TOKEN del entorno.
  token = var.railway_token
}
