output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "public_subnet_cidrs" {
  value = var.public_subnet_cidrs
}

output "private_subnet_cidrs" {
  value = var.private_subnet_cidrs
}

# Security Groups

output "bastion_security_group_id" {
  description = "ID of the Bastion security group"
  value       = aws_security_group.bastion.id
}

output "postgres_security_group_id" {
  description = "ID of the PostgreSQL security group"
  value       = aws_security_group.postgres.id
}

output "dms_security_group_id" {
  description = "ID of the DMS replication instance security group"
  value       = aws_security_group.dms_sg.id
}

output "emr_managed_master_security_group" {
  value = aws_security_group.emr_master_sg.id
}

output "emr_core_sg_id" {
  value = aws_security_group.emr_core_sg.id
}

output "emr_service_access_sg_id" {
  value = aws_security_group.emr_service_access_sg.id
}
