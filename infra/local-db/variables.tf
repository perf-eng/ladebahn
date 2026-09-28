variable "docker_host" {
  description = "Docker daemon socket, e.g. unix:///Users/<you>/.docker/run/docker.sock"
  type        = string
  default     = "unix:///var/run/docker.sock"
}

variable "host_port" {
  description = "Port on the Mac for the Terraform database (compose owns 5432)"
  type        = number
  default     = 5433

  validation {
    condition     = var.host_port >= 1024 && var.host_port <= 65535 && var.host_port != 5432
    error_message = "Use a port from 1024 to 65535, and not 5432, which the compose database owns."
  }
}

variable "shared_buffers" {
  description = "Postgres shared_buffers — the database's own page cache"
  type        = string
  default     = "512MB"

  validation {
    condition     = can(regex("^[0-9]+(kB|MB|GB)$", var.shared_buffers))
    error_message = "Use a whole number with kB, MB or GB, e.g. 512MB."
  }
}

variable "work_mem" {
  description = "Postgres work_mem — memory per sort or hash step before spilling to disk"
  type        = string
  default     = "16MB"

  validation {
    condition     = can(regex("^[0-9]+(kB|MB|GB)$", var.work_mem))
    error_message = "Use a whole number with kB, MB or GB, e.g. 16MB."
  }
}

variable "effective_cache_size" {
  description = "Postgres effective_cache_size — planner's estimate of total cache available"
  type        = string
  default     = "1536MB"

  validation {
    condition     = can(regex("^[0-9]+(kB|MB|GB)$", var.effective_cache_size))
    error_message = "Use a whole number with kB, MB or GB, e.g. 1536MB."
  }
}

variable "max_connections" {
  description = "Postgres max_connections"
  type        = number
  default     = 100

  validation {
    condition     = var.max_connections >= 10 && var.max_connections <= 500
    error_message = "Keep max_connections between 10 and 500."
  }
}
