variable "aws_region" {
  description = "AWS region for dev resources."
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

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets."
  type        = list(string)
  default     = ["10.20.0.0/24", "10.20.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets."
  type        = list(string)
  default     = ["10.20.10.0/24", "10.20.11.0/24"]
}

variable "allowed_http_cidrs" {
  description = "CIDR blocks allowed to access the public ALB."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "domain_name" {
  description = "Route 53 hosted zone domain name for dev ALB alias records."
  type        = string
  default     = "barocloud.com"
}

variable "app_domain_name" {
  description = "Fully qualified domain name for the dev ALB. Defaults to <environment>.<domain_name>."
  type        = string
  default     = ""
}

variable "image_tag" {
  description = "Container image tag deployed by Terraform. CI also pushes latest and forces ECS deployment."
  type        = string
  default     = "latest"
}

variable "runtime_enabled" {
  description = "Whether to run cost-incurring dev runtime resources such as NAT, ALB, and ECS services. Set false to suspend runtime without deleting preserved secrets/ECR."
  type        = bool
  default     = true
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
  description = "Services to create in dev."
  type        = set(string)
  default     = ["gateway", "user", "dispatch", "control", "admin", "relocation", "mobile"]

  validation {
    condition     = alltrue([for service in var.enabled_services : contains(["gateway", "control", "dispatch", "relocation", "user", "admin", "mobile"], service)])
    error_message = "enabled_services must contain only: gateway, control, dispatch, relocation, user, admin, mobile."
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

variable "internal_api_key_secret_name" {
  description = "Existing Secrets Manager secret name that stores INTERNAL_API_KEY for service-to-service internal APIs."
  type        = string
  default     = "baro-dev/dispatch/INTERNAL_API_KEY"
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
  description = "On-premises network CIDR routed through Site-to-Site VPN."
  type        = string
  default     = "192.168.200.0/22"
}

variable "onprem_vm_cidr" {
  description = "OpenStack internal VM network CIDR routed through Site-to-Site VPN."
  type        = string
  default     = "10.10.10.0/24"
}
