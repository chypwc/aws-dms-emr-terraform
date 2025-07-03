output "bucket_ids" {
  description = "IDs of the created S3 buckets"
  value = [
    for name in var.bucket_names :
    aws_s3_bucket.buckets[name].id
  ]
}


output "bucket_arns" {
  description = "ARNs of the created S3 buckets in input order"
  value = [
    for name in var.bucket_names :
    aws_s3_bucket.buckets[name].arn
  ]
}

