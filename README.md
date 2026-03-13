## Overview
A GitHub Actions pipeline that enforces security checks on every pull request
before code can merge to main. Demonstrates shift-left security practices
using infrastructure-as-code scanning, secrets detection, and Terraform validation.


## What the Pipeline Checks
| Check             | Tool       |                                                What It Catches |
|-------------------|------------|----------------------------------------------------------------|
| Secrets Scanning  | TruffleHog | AWS keys, passwords, API tokens in code or git history         |
| IaC Scanning      | Chekhov    | S3 misconfigurations, open security groups, missing encryption |
| Syntax Validation | Terraform  | Invalid HCL, formatting issues, provider errors                |


## Security Controls Implemented
- S3 bucket with KMS encryption (customer-managed key)
- S3 versioning enabled
- S3 public access fully blocked (all four settings)
- S3 access logging to a separate log bucket
- S3 bucket policy denying unencrypted transport (HTTP)
- S3 lifecycle policies (IA → Glacier → delete)
- Security group with SSH restricted to specific CIDR (not 0.0.0.0/0)


## How to Use
1. Fork this repository
2. Rename `main_insecure.tf.disabled` to `main_insecure.tf`
3. Remove or rename `main.tf`
4. Push to a branch and create a Pull Request
5. Watch Checkov fail with specific findings
6. Swap back to the secure version
7. Push again and watch the pipeline pass


## Trade-offs and Design Decisions
- **soft_fail: false**: The pipeline blocks merges on any finding. In a real
  organization, you might start with `soft_fail: true` (warnings only) and
  tighten over time as the team adapts.
- **skip_check**: I skipped CKV_AWS_144 (cross-region replication) because
  this is a lab environment where cross-region redundancy isn't needed.
  In production, I would enable it for any bucket containing business data.
- **KMS vs SSE-S3**: I chose a customer-managed KMS key over SSE-S3 default
  encryption because it gives us audit trail (CloudTrail logs key usage),
  key policy control, and automatic annual rotation. The trade-off is cost
  ($1/month per key + $0.03 per 10,000 API calls).
- **No Terraform remote state**: For this lab, state is local. In production,
  I would use an S3 backend with DynamoDB locking and encryption.


## What I Would Add in an Enterprise Setting
- DAST scanning (OWASP ZAP) against a staging deployment
- SCA scanning (Snyk or Trivy) for dependency vulnerabilities
- Terraform plan output posted as a PR comment for reviewer visibility
- OIDC federation for AWS credentials (no stored access keys)
- Separate AWS accounts for dev/staging/prod with cross-account deploy roles
- Manual approval gate before production deployment
