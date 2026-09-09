variable "cluster_name" {
  description = "Short name also used for supporting resources."
  type        = string
  default     = "production-gke"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,19}[a-z0-9]$", var.cluster_name))
    error_message = "Use 4–21 lowercase letters, digits, or hyphens; start with a letter and end with a letter or digit."
  }
}

variable "public_apps" {
  description = "Public HTTPS endpoints, keyed by short app name, sharing one static IP/cert map/SSL policy/Gateway. Each entry needs an owned hostname and an existing public Cloud DNS zone in this project. Workload Gateway and one HTTPRoute per app must be applied separately."
  type = map(object({
    hostname                   = string
    dns_managed_zone           = string
    waf_preview                = optional(bool, true)
    requests_per_minute_per_ip = optional(number, 600)
  }))
  default = {}
  validation {
    condition = alltrue([for app in var.public_apps :
      can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?\\.[a-z]{2,}$", app.hostname)) &&
      app.requests_per_minute_per_ip >= 10 && floor(app.requests_per_minute_per_ip) == app.requests_per_minute_per_ip
    ])
    error_message = "Supply a lowercase hostname without a trailing dot and an integer rate limit of at least 10 for every app."
  }
}
