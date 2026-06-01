variable "aws_region" {
  description = "AWS region for dev shared resources."
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

variable "enabled_services" {
  description = "Services that need shared ECR repositories and secret placeholders."
  type        = set(string)
  default     = ["user", "dispatch"]

  validation {
    condition     = alltrue([for service in var.enabled_services : contains(["control", "dispatch", "relocation", "user"], service)])
    error_message = "enabled_services must contain only: control, dispatch, relocation, user."
  }
}

variable "ecr_image_retention_count" {
  description = "Number of recent ECR images to keep per service."
  type        = number
  default     = 20
}
