variable "cluster_name" {
  description = "Short name also used for supporting resources."
  type        = string
  default     = "production-gke"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,19}[a-z0-9]$", var.cluster_name))
    error_message = "Use 4–21 lowercase letters, digits, or hyphens; start with a letter and end with a letter or digit."
  }
}

variable "region" {
  description = "Region chosen for latency, residency, capacity, and recovery requirements."
  type        = string
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
