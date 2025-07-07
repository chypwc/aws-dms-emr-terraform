
output "bastion_host" {
  value = module.ec2.instance_public_ip
}

output "mwaa_env_name" {
  value = module.mwaa.mwaa_env_name
}
