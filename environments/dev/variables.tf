variable "region" {
  description = "AWS Region to deploy resources"
  type        = string
  default     = "ap-southeast-2"
}
variable "env" {}

# S3
variable "source_bucket" {}
variable "destination_bucket" {}

# Glue tables
variable "raw_data_bucket" { type = string }
variable "raw_data_folder" { type = string }
variable "raw_database_name" { type = string }
variable "silver_data_bucket" { type = string }
variable "silver_data_folder" { type = string }
variable "silver_database_name" { type = string }

# EC2
variable "ami_id" {}
variable "instance_type" {}
variable "key_name" {}

# DMS
variable "postgresql_secret_name" {}
# variable "s3_bucket_name" {}
# variable "vpc_id" {}
# variable "subnet_ids" {}
