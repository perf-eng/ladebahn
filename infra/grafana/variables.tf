variable "environments" {
  description = "deployment.environment values the app reports (local = the Mac, server = the demo VM)"
  type        = list(string)
  default     = ["local", "server"]

  validation {
    condition     = alltrue([for e in var.environments : contains(["local", "server"], e)])
    error_message = "Environments must be local and/or server — the values in OTEL_RESOURCE_ATTRIBUTES."
  }
}

variable "p95_threshold_seconds" {
  description = "Alert when the nearby-search p95 stays above this many seconds"
  type        = number
  default     = 0.2

  validation {
    condition     = var.p95_threshold_seconds > 0 && var.p95_threshold_seconds < 10
    error_message = "Use a threshold between 0 and 10 seconds."
  }
}
