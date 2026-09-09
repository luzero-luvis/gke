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

variable "network_name" {
  type        = string
  description = "VPC network name."
}

variable "subnetwork_name" {
  type        = string
  description = "Regional subnetwork name with pods and services secondary ranges."
}

variable "secrets_key_id" {
  type        = string
  description = "KMS key for application-layer encryption."
}

variable "node_service_account" {
  type        = string
  description = "Least-privilege node service account email."
}

variable "labels" {
  type        = map(string)
  description = "Environment and ownership resource labels."
}
