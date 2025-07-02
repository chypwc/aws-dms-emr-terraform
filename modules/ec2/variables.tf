variable "env" {}
variable "ami_id" {}
variable "instance_type" {}
variable "key_name" {}
variable "vpc_id" {}
variable "public_subnet_id" {}
variable "private_subnet_id" {}

# postgresql server
variable "db_name" {
  type    = string
  default = "imba"
}

variable "s3_bucket" {
  type    = string
  default = "source-bucket-chien"
}

variable "region" {
  type = string
}

variable "postgres_security_group_ids" {}
variable "bastion_security_group_ids" {}
