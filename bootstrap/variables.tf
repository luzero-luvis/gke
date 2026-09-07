variable "project_id" {
  type        = string
  description = "Existing administration project with billing and Storage API enabled."
}
variable "bucket_name" {
  type        = string
  description = "Globally unique name for Terraform state."
}
variable "location" {
  type        = string
  description = "Approved GCS region or multi-region for state residency and recovery."
}
variable "state_admin_members" {
  type        = set(string)
  description = "Operators or CI identities needing state object access (serviceAccount:..., group:...)."
  default     = []
}

