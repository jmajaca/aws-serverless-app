variable "application_name" {
  description = "Name of the application"
  type        = string
}

variable "application_version" {
  description = "Version of the application to run"
  type        = string
}

variable "application_port" {
  description = "Application traffic port"
  type        = number
}

variable "application_health_check_path" {
  description = "Relative application URL health check path"
  type        = string
}

variable "min_replicas" {
  description = "Min number of application replicas to run"
  type        = number
}

variable "max_replicas" {
  description = "Max number of application replicas to run"
  type        = number
}

variable "alarm_emails" {
  description = "List of emails for sending alarms"
  type        = list(string)
}

variable "ecs_cluster" {
  description = "ECS Cluster"
  type = object({
    id   = string
    name = string
  })
}

variable "aws_kms_key_id" {
  description = "ID of the KMS key"
  type        = string
}

variable "ecs_execution_role_arn" {
  description = "ARN of the ECS execution role"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "public_subnets" {
  description = "ID list of public subnets"
  type        = list(string)
}

variable "private_subnets" {
  description = "ID list of public subnets"
  type        = list(string)
}