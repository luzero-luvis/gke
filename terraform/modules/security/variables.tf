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

variable "cluster_access_members" {
  description = "IAM principals allowed to discover clusters and connect via DNS. Kubernetes RBAC must grant their workload permissions separately."
  type        = set(string)
  default     = []
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

variable "gke_service_agent_email" {
  type        = string
  description = "GKE service agent generated after enabling the API."
}

variable "labels" {
  type        = map(string)
  description = "Environment and ownership resource labels."
}
