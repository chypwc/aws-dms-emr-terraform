variable "postgresql_secret_name" {
  description = "Name of the PostgreSQL secret in AWS Secrets Manager"
  type        = string
  default     = "postgresql_dms"
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket for DMS target"
  type        = string
}

variable "bucket_folder" {
  description = "Prefix of raw data folder"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where resources will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the replication subnet group"
  type        = list(string)
}

variable "region" {
  type = string
}

variable "dms_security_group_ids" {}

variable "server_name" {
  description = "Private IP of the PostgreSQL EC2 instance"
  type        = string
}
