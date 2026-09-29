variable "environments" {
  description = "deployment.environment values the app reports (local = the Mac, server = the demo VM, ci = the throwaway stack in GitHub Actions)"
  type        = list(string)
  default     = ["local", "server", "ci"]

  validation {
    condition     = alltrue([for e in var.environments : contains(["local", "server", "ci"], e)])
    error_message = "Environments must be local, server and/or ci — the values in OTEL_RESOURCE_ATTRIBUTES."
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
