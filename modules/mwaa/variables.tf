variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "dag_bucket_arn" {
  type        = string
  description = "S3 bucket ARN where DAGs are stored"
}

variable "dag_bucket_name" {
  type        = string
  description = "S3 bucket name where DAGs are stored"
}

variable "mwaa_security_group_id" {
  description = "MWAA security groups"
}

variable "region" {

}


# dag template
variable "dms_task_arn" {}
variable "subnet_id" {}
variable "emr_role" {}
# variable "ec2_role" {}
variable "emr_sg_master" {}
variable "emr_sg_core" {}
variable "emr_sg_service" {}

variable "emr_ec2_instance_profile" {}
