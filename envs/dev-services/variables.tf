variable "aws_region" {
  description = "AWS region for dev service resources."
  type        = string
  default     = "ap-northeast-2"
}

variable "project" {
  description = "Project name used in resource names."
  type        = string
  default     = "baro"
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
  default     = "dev"
}

variable "allowed_http_cidrs" {
  description = "CIDR blocks allowed to access the public ALB."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "image_tag" {
  description = "Container image tag deployed by Terraform. CI also pushes latest and forces ECS deployment."
  type        = string
  default     = "latest"
}

variable "service_desired_count" {
  description = "Desired task count per service."
  type        = number
  default     = 1
}

variable "service_cpu" {
  description = "Fargate task CPU per service."
  type        = number
  default     = 512
}

variable "service_memory" {
  description = "Fargate task memory per service."
  type        = number
  default     = 1024
}

variable "enabled_services" {
  description = "Services to create in dev services. Must match dev-shared enabled_services."
  type        = set(string)
  default     = ["user", "dispatch"]

  validation {
    condition     = alltrue([for service in var.enabled_services : contains(["control", "dispatch", "relocation", "user"], service)])
    error_message = "enabled_services must contain only: control, dispatch, relocation, user."
  }
}

variable "service_desired_counts" {
  description = "Desired task count by service."
  type        = map(number)
  default = {
    user     = 1
    dispatch = 1
  }
}

variable "service_environment" {
  description = "Additional non-secret environment variables by service name."
  type        = map(map(string))
  default     = {}
}

variable "rds_engine_version" {
  description = "PostgreSQL engine version for the shared dev RDS instance."
  type        = string
  default     = "16"
}

variable "rds_instance_class" {
  description = "Instance class for the shared dev RDS instance."
  type        = string
  default     = "db.t4g.micro"
}

variable "rds_allocated_storage" {
  description = "Allocated storage in GiB for the shared dev RDS instance."
  type        = number
  default     = 20
}

variable "rds_database_name" {
  description = "Initial database name in the shared PostgreSQL instance. Use schemas or app-owned tables to separate services logically."
  type        = string
  default     = "baro"
}

variable "rds_master_username" {
  description = "Master username for the shared dev RDS instance."
  type        = string
  default     = "baroadmin"
}

variable "onprem_cidr" {
  description = "On-premises CIDR block routed through the Site-to-Site VPN."
  type        = string
  default     = "192.168.200.0/22"
}
