variable "project_id" {
  description = "Existing, billing-enabled project dedicated to this environment."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Use a valid Google Cloud project ID."
  }
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

variable "project_number" {
  type        = string
  description = "Numeric Google Cloud project number."
}
