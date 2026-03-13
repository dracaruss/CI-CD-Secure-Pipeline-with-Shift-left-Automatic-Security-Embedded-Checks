# ─────────────────────────────────────────────────────────────
# DATA SOURCES
# ─────────────────────────────────────────────────────────────
data "aws_caller_identity" "current" {}


# Random suffix to make bucket names globally unique
resource "random_id" "suffix" {
  byte_length = 4
}


# ─────────────────────────────────────────────────────────────
# KMS KEY: Encrypt both buckets
# Using a customer-managed KMS key instead of SSE-S3 gives us
# control over key policy, rotation, and audit trail.
# ─────────────────────────────────────────────────────────────
resource "aws_kms_key" "s3" {
  description             = "Encrypt S3 buckets for CI/CD project"
  deletion_window_in_days = 7
  enable_key_rotation     = true


  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowAccountAdmin"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam:${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      }
    ]
  })
}


resource "aws_kms_alias" "s3" {
  name          = "alias/cicd-s3-key"
  target_key_id = aws_kms_key.s3.key_id
}


# ═════════════════════════════════════════════════════════════
# S3 BUCKET: Access Logs (receives logs from the data bucket)
# This bucket must exist BEFORE the data bucket's logging config.
# ═════════════════════════════════════════════════════════════
resource "aws_s3_bucket" "log_bucket" {
  # checkov:skip=CKV2_AWS_62: Event notifications are not required for this regional log repository.
  # checkov:skip=CKV_AWS_144: Cross-region replication is overkill for this regional lab environment.
  bucket = "cicd-access-logs-${random_id.suffix.hex}"
  tags   = { Name = "cicd-s3-access-logs" }
}


resource "aws_s3_bucket_versioning" "log_bucket" {
  bucket = aws_s3_bucket.log_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}


resource "aws_s3_bucket_server_side_encryption_configuration" "log_bucket" {
  bucket = aws_s3_bucket.log_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
    bucket_key_enabled = true
  }
}


resource "aws_s3_bucket_public_access_block" "log_bucket" {
  bucket                  = aws_s3_bucket.log_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


# S3 log delivery requires BucketOwnerPreferred ownership
resource "aws_s3_bucket_ownership_controls" "log_bucket" {
  # checkov:skip=CKV2_AWS_65: "BucketOwnerPreferred" is required for specific log delivery requirements in this lab setup.
  bucket = aws_s3_bucket.log_bucket.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}


# Bucket policy: Deny unencrypted transport + deny deletes
resource "aws_s3_bucket_policy" "log_bucket" {
  bucket = aws_s3_bucket.log_bucket.id


  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyUnencryptedTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.log_bucket.arn,
          "${aws_s3_bucket.log_bucket.arn}/*"
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ]
  })
}


# Lifecycle: Move log files to Glacier after 90 days, delete after 1 year
resource "aws_s3_bucket_lifecycle_configuration" "log_bucket" {
  bucket = aws_s3_bucket.log_bucket.id


  rule {
    id     = "archive-old-logs"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }


    expiration {
      days = 365
    }
  }
}




# ═════════════════════════════════════════════════════════════
# S3 BUCKET: Data Bucket (the actual bucket we're securing)
# ═════════════════════════════════════════════════════════════
resource "aws_s3_bucket" "data" {
  # checkov:skip=CKV2_AWS_62: Event notifications are not required for this regional log repository.
  # checkov:skip=CKV_AWS_144: Cross-region replication is overkill for this regional lab environment.
  bucket = "cicd-secure-data-${random_id.suffix.hex}"
  tags   = { Name = "cicd-secure-data-bucket" }
}


# Versioning: Protects against accidental deletions and overwrites
resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id
  versioning_configuration {
    status = "Enabled"
  }
}


# Encryption: KMS customer-managed key
resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
    bucket_key_enabled = true
  }
}


# Public Access Block: All four settings enabled
resource "aws_s3_bucket_public_access_block" "data" {
  bucket                  = aws_s3_bucket.data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


# Access Logging: Every read/write to this bucket is logged
resource "aws_s3_bucket_logging" "data" {
  bucket        = aws_s3_bucket.data.id
  target_bucket = aws_s3_bucket.log_bucket.id
  target_prefix = "data-bucket-access-logs/"
}


# Bucket Policy: Deny unencrypted transport
resource "aws_s3_bucket_policy" "data" {
  bucket = aws_s3_bucket.data.id


  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyUnencryptedTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.data.arn,
          "${aws_s3_bucket.data.arn}/*"
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ]
  })
}


# Lifecycle: Move to IA after 30 days, Glacier after 90, delete after 365
resource "aws_s3_bucket_lifecycle_configuration" "data" {
  bucket = aws_s3_bucket.data.id


  rule {
    id     = "lifecycle-data"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }


    transition {
      days          = 90
      storage_class = "GLACIER"
    }


    expiration {
      days = 365
    }
  }
}




# ═════════════════════════════════════════════════════════════
# SECURITY GROUP: Properly restricted (replaces the insecure one)
# ═════════════════════════════════════════════════════════════
#resource "aws_security_group" "app" {
#  name_prefix = "cicd-app-"
#  description = "App server - SSH restricted to known CIDR only"
#
#
#  # No default VPC needed — this just validates without deploying to a VPC
#  # In a real project, you'd add: vpc_id = aws_vpc.main.id
#
#
#  ingress {
#    description = "SSH from office IP only"
#    from_port   = 22
#    to_port     = 22
#    protocol    = "tcp"
#    cidr_blocks = ["203.0.113.0/24"]  # Replace with your office/VPN CIDR
#  }
#
#
#  ingress {
#    description = "HTTPS from anywhere"
#    from_port   = 443
#    to_port     = 443
#    protocol    = "tcp"
#    cidr_blocks = ["0.0.0.0/0"]
#  }
#
#  egress {
#    description = "Allow HTTPS for AWS API calls (S3/KMS) and updates"
#    from_port   = 443
#    to_port     = 443
#    protocol    = "tcp"
#    cidr_blocks = ["0.0.0.0/0"]
#  }
#
#  egress {
#    description = "Allow DNS for AWS service resolution"
#    from_port   = 53
#    to_port     = 53
#    protocol    = "udp"
#    cidr_blocks = ["0.0.0.0/0"]
#  }
#
#  egress {
#    description = "Allow DNS for AWS service resolution"
#    from_port   = 80
#    to_port     = 80
#    protocol    = "udp"
#    cidr_blocks = ["0.0.0.0/0"]
#  }
#
#  tags = { Name = "cicd-app-sg" }
#}
