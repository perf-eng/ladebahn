locals {
  # The same settings as compose.yaml, with the tuning knobs as variables
  postgres_settings = {
    shared_preload_libraries   = "pg_stat_statements"
    "pg_stat_statements.track" = "all"
    shared_buffers             = var.shared_buffers
    work_mem                   = var.work_mem
    effective_cache_size       = var.effective_cache_size
    max_connections            = var.max_connections
    log_min_duration_statement = 200
  }

  # ["postgres", "-c", "key=value", "-c", "key=value", ...]
  postgres_command = concat(
    ["postgres"],
    flatten([for key, value in local.postgres_settings : ["-c", "${key}=${value}"]])
  )
}

resource "docker_container" "db" {
  name    = "ladebahn-tf-db"
  image   = docker_image.postgres.image_id
  command = local.postgres_command

  env = [
    "POSTGRES_DB=ladebahn",
    "POSTGRES_USER=ladebahn",
    "POSTGRES_PASSWORD=ladebahn", # local lab only, same as compose.yaml
  ]

  ports {
    internal = 5432
    external = var.host_port
    ip       = "127.0.0.1"
  }

  volumes {
    volume_name    = docker_volume.pgdata.name
    container_path = "/var/lib/postgresql/data"
  }

  networks_advanced {
    name = docker_network.ladebahn.name
  }

  healthcheck {
    test     = ["CMD-SHELL", "pg_isready -U ladebahn -d ladebahn"]
    interval = "5s"
    timeout  = "3s"
    retries  = 10
  }

  # apply only finishes once the healthcheck reports healthy
  wait         = true
  wait_timeout = 120
}
