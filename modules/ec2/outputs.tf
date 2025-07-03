output "instance_id" {
  value = aws_instance.bastion.id
}

output "instance_public_ip" {
  value = aws_instance.bastion.public_ip
}

output "postgres_private_ip" {
  description = "Private IP of the PostgreSQL EC2 instance"
  value       = aws_instance.postgres.private_ip
}

