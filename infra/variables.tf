variable "region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Name prefix and Project tag for every resource"
  type        = string
  default     = "bizapp"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.20.0.0/16"
}

variable "instance_type" {
  description = "EC2 instance type for the app servers"
  type        = string
  default     = "t3.micro"
}

variable "app_port" {
  description = "Port the Spring Boot app listens on"
  type        = number
  default     = 2330
}

variable "db_username" {
  description = "Master username for the RDS instance"
  type        = string
  default     = "bizadmin"
}

variable "environment" {
  description = "Environment name, used in resource naming and tags"
  type        = string
  default     = "prod"
}