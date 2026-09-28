terraform {
  required_version = ">= 1.16.0"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 4.6"
    }
  }
}

provider "docker" {
  # Docker Desktop's socket; the walkthrough passes the real path in TF_VAR_docker_host
  host = var.docker_host
}
