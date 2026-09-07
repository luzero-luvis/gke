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

variable "cluster_name" {
  description = "Short name also used for supporting resources."
  type        = string
  default     = "production-gke"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,19}[a-z0-9]$", var.cluster_name))
    error_message = "Use 4–21 lowercase letters, digits, or hyphens; start with a letter and end with a letter or digit."
  }
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

variable "notification_channels" {
  description = "Existing Cloud Monitoring channel resource names for alert delivery. An empty list creates visible incidents with no external delivery."
  type        = list(string)
  default     = []
}

variable "labels" {
  type        = map(string)
  description = "Environment and ownership resource labels."
}
