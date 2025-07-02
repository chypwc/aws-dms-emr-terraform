output "bucket_ids" {
  description = "IDs of the created S3 buckets"
  value       = [for b in aws_s3_bucket.buckets : b.id]
}

output "bucket_arns" {
  description = "ARNs of the created S3 buckets"
  value       = [for b in aws_s3_bucket.buckets : b.arn]
}
