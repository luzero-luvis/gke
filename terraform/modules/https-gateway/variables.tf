variable "cluster_name" {
  description = "Short name also used for supporting resources."
  type        = string
  default     = "production-gke"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,19}[a-z0-9]$", var.cluster_name))
    error_message = "Use 4–21 lowercase letters, digits, or hyphens; start with a letter and end with a letter or digit."
  }
}

variable "public_app" {
  description = "Optional public HTTPS endpoint. Supply an owned hostname and an existing public Cloud DNS zone in this project. Workload Gateway must be applied separately."
  type = object({
    hostname                   = string
    dns_managed_zone           = string
    waf_preview                = optional(bool, true)
    requests_per_minute_per_ip = optional(number, 600)
  })
  default = null
  validation {
    condition = var.public_app == null ? true : (
      can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?\\.[a-z]{2,}$", var.public_app.hostname)) &&
      var.public_app.requests_per_minute_per_ip >= 10 && floor(var.public_app.requests_per_minute_per_ip) == var.public_app.requests_per_minute_per_ip
    )
    error_message = "Supply a lowercase hostname without a trailing dot and an integer rate limit of at least 10."
  }
}
