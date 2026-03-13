variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-2"
}


variable "aws_profile" {
  description = "AWS CLI profile name"
  type        = string
  default     = "cicd"
}
