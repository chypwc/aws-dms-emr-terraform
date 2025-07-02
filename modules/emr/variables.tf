variable "log_bucket" {
  description = "S3 bucket for EMR logs"
  type        = string
}

variable "script_bucket" {
  description = "S3 bucket for EMR scripts"
  type        = string
}

variable "env" {
  type    = string
  default = "dev"
}

variable "raw_data_bucket" {
  type = string
}
variable "silver_data_bucket" {
  type = string
}

variable "silver_data_folder" {

}

variable "subnet_id" {}
variable "emr_managed_master_security_group" {}
variable "emr_core_sg_id" {}
variable "emr_service_access_sg_id" {}

variable "key_name" {
  description = "SSH key pair name"
}
