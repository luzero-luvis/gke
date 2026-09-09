variable "project_id" {
  description = "Existing, billing-enabled project dedicated to this environment."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Use a valid Google Cloud project ID."
  }
}

variable "region" {
  description = "Region chosen for latency, residency, capacity, and recovery requirements."
  type        = string
}

variable "zones" {
  description = "At least two distinct zones in the selected region."
  type        = list(string)
  validation {
    condition     = length(distinct(var.zones)) == length(var.zones) && length(var.zones) >= 2 && alltrue([for z in var.zones : startswith(z, "${var.region}-")])
    error_message = "Choose at least two distinct zones within region."
  }
}

variable "cluster_name" {
  description = "Short name also used for supporting resources."
  type        = string
  default     = "production-gke"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,19}[a-z0-9]$", var.cluster_name))
    error_message = "Use 4–21 lowercase letters, digits, or hyphens; start with a letter and end with a letter or digit."
  }
}

variable "environment" {
  description = "Environment label; use separate projects and state prefixes for each environment."
  type        = string
  default     = "production"
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be development, staging, or production."
  }
}

variable "network_cidr" {
  description = "One non-overlapping RFC1918 /14 allocation. Carved into nodes /20, Pods /16, Services /20. Review against all connected networks before creation."
  type        = string
  default     = "10.64.0.0/14"
  validation {
    condition = try(
      tonumber(split("/", var.network_cidr)[1]) == 14 && cidrhost(var.network_cidr, 0) == split("/", var.network_cidr)[0] &&
      (startswith(var.network_cidr, "10.") ||
      (startswith(var.network_cidr, "172.") && tonumber(split(".", var.network_cidr)[1]) >= 16 && tonumber(split(".", var.network_cidr)[1]) <= 28)),
      false
    )
    error_message = "Provide an aligned RFC1918 IPv4 /14 (for example 10.64.0.0/14)."
  }
}

variable "machine_type" {
  description = "On-demand node machine type; size from load tests and allocatable resources."
  type        = string
  default     = "e2-standard-4"
}

variable "max_nodes_per_zone" {
  description = "Autoscaler upper bound PER ZONE, excluding surge nodes; total bound is three times this value."
  type        = number
  default     = 10
  validation {
    condition     = var.max_nodes_per_zone >= 2 && var.max_nodes_per_zone <= 160 && floor(var.max_nodes_per_zone) == var.max_nodes_per_zone
    error_message = "Use an integer from 2 to 160; the Pod /16 reserves /25 per node, including upgrade surge."
  }
}

variable "release_channel" {
  description = "Managed release channel. Test upgrades in staging before production."
  type        = string
  default     = "REGULAR"
  validation {
    condition     = contains(["REGULAR", "STABLE"], var.release_channel)
    error_message = "Use REGULAR or STABLE for this foundation."
  }
}

variable "maintenance_window" {
  description = "Recurring UTC window; retain at least 48 eligible hours per rolling 32 days in blocks of at least 4 hours. Default is 8 hours every Saturday and Sunday."
  type = object({
    start_time = string
    end_time   = string
    recurrence = string
  })
  default = {
    start_time = "2026-01-03T00:00:00Z"
    end_time   = "2026-01-03T08:00:00Z"
    recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
  }
}

variable "authenticator_security_group" {
  description = "Optional Google Groups for RBAC parent group, gke-security-groups@your-domain."
  type        = string
  default     = null
  validation {
    condition     = var.authenticator_security_group == null ? true : can(regex("^gke-security-groups@[^ ]+\\.[^ ]+$", var.authenticator_security_group))
    error_message = "Use the gke-security-groups@your-domain parent group."
  }
}

variable "cluster_access_members" {
  description = "IAM principals allowed to discover clusters and connect via DNS. Kubernetes RBAC must grant their workload permissions separately."
  type        = set(string)
  default     = []
}

variable "secret_access" {
  description = "Resource-scoped WIF grants for existing Secret Manager secrets. No secret values or service-account keys enter Terraform. Use namespace apps and KSA app for the supplied workload."
  type = map(object({
    secret_id       = string
    namespace       = string
    service_account = string
  }))
  default = {}
}

variable "notification_channels" {
  description = "Existing Cloud Monitoring channel resource names for alert delivery. An empty list creates visible incidents with no external delivery."
  type        = list(string)
  default     = []
}

variable "backup_region" {
  description = "Required separate, supported Backup for GKE location; select for data residency and recovery needs."
  type        = string
  validation {
    condition     = length(var.backup_region) > 0 && var.backup_region != var.region
    error_message = "Choose a supported backup region different from the cluster region."
  }
}

variable "backup_namespaces" {
  description = "Application namespaces to back up; exclude system namespaces."
  type        = list(string)
  default     = ["apps"]
  validation {
    condition     = length(var.backup_namespaces) > 0 && alltrue([for n in var.backup_namespaces : !startswith(n, "kube-") && can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", n))])
    error_message = "Select at least one valid application namespace, excluding kube-* namespaces."
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

variable "binary_authorization_attestors" {
  description = "Existing attestor resource names. Empty enables audit-only deny policy; supplying attestors enforces trusted attestations for all application images."
  type        = list(string)
  default     = []
  validation {
    condition     = alltrue([for a in var.binary_authorization_attestors : can(regex("^projects/[^/]+/attestors/[^/]+$", a))])
    error_message = "Use projects/PROJECT/attestors/ATTESTOR resource names."
  }
}
