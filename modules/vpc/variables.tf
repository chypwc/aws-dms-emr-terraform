variable "env" {}
variable "vpc_cidr_block" {}
variable "public_subnet_cidrs" {
  type = list(string)
}
variable "private_subnet_cidrs" {
  type = list(string)
}

variable "region" {

}
