output "emr_role" {
  value = aws_iam_role.emr_service_role
}


output "emr_ec2_instance_profile" {
  value = aws_iam_instance_profile.emr_ec2_instance_profile
}
