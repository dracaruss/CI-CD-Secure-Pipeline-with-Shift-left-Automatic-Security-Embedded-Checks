output "data_bucket_name" {
  description = "Name of the secure data bucket"
  value       = aws_s3_bucket.data.id
}


output "data_bucket_arn" {
  description = "ARN of the secure data bucket"
  value       = aws_s3_bucket.data.arn
}


output "log_bucket_name" {
  description = "Name of the access log bucket"
  value       = aws_s3_bucket.log_bucket.id
}


output "log_bucket_arn" {
  description = "ARN of the access log bucket"
  value       = aws_s3_bucket.log_bucket.arn
}


output "kms_key_arn" {
  description = "ARN of the KMS key encrypting both buckets"
  value       = aws_kms_key.s3.arn
}


#output "security_group_id" {
#  description = "ID of the app security group"
#  value       = aws_security_group.app.id
#}
