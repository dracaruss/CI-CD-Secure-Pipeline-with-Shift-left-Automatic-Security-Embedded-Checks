# Overview
### A GitHub Actions Automatic Security Pipeline.  
***Four security checks trigger on every push and every pull request to the repo.***
> [!IMPORTANT]
> This project sets up automatic checks to ensure that before any code can be merged into a repo, it is scanned for vulnerabilities. This setup is powered by Github Actions, which connects to AWS using OIDC federation — so there are no stored credentials, and no long-lived keys. This project demonstrates shift-left security practices using infrastructure-as-code scanning, secrets detection, Terraform validation, and secure AWS authentication via OIDC.  

##

# Architecture Deisgn  
<img width="742" height="962" alt="Image" src="https://github.com/user-attachments/assets/fa97c1eb-5157-4afb-b24d-b5eafcda62cf" />

##

# What the Pipeline Automatically Checks 

### ***Secrets Scanning***  
*Tool Used*: TruffleHog  
>Full checks on security misconfigurations on AWS keys, passwords, API tokens etc. in code or git history.  

### ***IaC Scanning***  
*Tool Used*: Checkov  
>Full comprehensive checks via Checkov  

### ***Syntax Validation***
*Tool Used*: Terraform  
>Invalid HCL, formatting issues, provider errors

### ***Terraform Plan***  
*Tool Used*: Terraform + AWS OIDC  
>Infrastructure changes reviewed before merge.  
<img width="1430" height="483" alt="Image" src="https://github.com/user-attachments/assets/e624d969-5f64-41c8-ae3d-f64083aa394d" />

## 

# Supply Chain Security  
All GitHub Actions are pinned to SHA hashes instead of version tags. Version tags are mutable — a compromised repo could move a tag to point to malicious code. SHA hashes are immutable and guarantee you're running the exact code you reviewed.  
```
yaml

# Mutable tag (risky)
uses: actions/checkout@v4

# Immutable SHA (secure)
uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
```
<img width="1027" height="422" alt="Image" src="https://github.com/user-attachments/assets/72904587-17a4-4172-b960-0d7352b43df8" />

##


# AWS Authentication (OIDC Federation)  
***This pipeline uses OpenID Connect (OIDC) to authenticate GitHub Actions with AWS — no access keys or secrets stored anywhere.***  
1. GitHub Actions requests a short-lived OIDC token from GitHub's identity provider.  
2. The token is presented to AWS IAM, which verifies it against a pre-configured trust policy.  
3. AWS returns temporary credentials (valid ~1 hour) scoped to a specific IAM role.  
4. Terraform uses those credentials to run plan against real infrastructure.
<img width="1451" height="537" alt="Image" src="https://github.com/user-attachments/assets/7e267d6a-09e1-4311-8c50-060bfbe17307" />
<br>

***The trust policy is locked down to:***  
- A single specific repository
- Only pull request events
<br>

*This means even other repos under the same GitHub account cannot assume the role.*  

##

# How to Use  
> [!NOTE]
> * Fork this repository.
> * Rename main_insecure.tf.disabled to main_insecure.tf.
> * Remove or rename main.tf.
> * Push to a branch and create a Pull Request.
> * Watch Checkov fail with specific findings.
> * Swap back to the secure version.
> * Push again and watch the pipeline pass.  

##

# To enable the Terraform Plan, add this step in your fork:  
> [!IMPORTANT]
> 1. Create an OIDC Identity Provider in your AWS account for token.actions.githubusercontent.com
> 2. Create an IAM Role with a trust policy scoped to your fork's repo.
> 3. Update the role-to-assume ARN in security-pipeline.yml.
> 4. Open a PR and the plan will run automatically.  

*Note:* The Terraform Plan will only trigger on the Pull request, not the Push. It will not enact the last check on the Push:  
<img width="1255" height="565" alt="Image" src="https://github.com/user-attachments/assets/1e35a8bc-6620-4346-9608-3bbef89d7f0f" />

##

# Trade-offs and Design Decisions  
**soft_fail: false:**  
> The pipeline blocks merges on any finding. In a real organization, you might start with soft_fail: true (warnings only) and
tighten over time as the team adapts.

**skip_check:**  
>I skipped CKV_AWS_144 (cross-region replication) because this is a lab environment where cross-region redundancy isn't needed.
In production, I would enable it for any bucket containing business data.

**KMS vs SSE-S3:**  
>I chose a customer-managed KMS key over SSE-S3 default encryption because it gives us audit trail (CloudTrail logs key usage),
key policy control, and automatic annual rotation. The trade-off is cost: ($1/month per key + $0.03 per 10,000 API calls).

**No Terraform remote state:**  
>For this lab, state is local. In production, I would use an S3 backend with DynamoDB locking and encryption.  

**OIDC over static keys:**  
>OIDC federation means no AWS credentials are stored in GitHub Secrets. Credentials are temporary, automatically rotated, and
scoped to the minimum permissions needed.  

**SHA-pinned actions:**  
>Every third-party action is pinned to a full commit SHA rather than a mutable version tag, protecting against supply chain attacks
like the tj-actions/changed-files incident in early 2025.  

##  

# What I Would Add in an Enterprise Setting
> [!IMPORTANT]
> * DAST scanning (OWASP ZAP) against a staging deployment.
> * SCA scanning (Snyk or Trivy) for dependency vulnerabilities.
> * Separate AWS accounts for dev/staging/prod with cross-account deploy roles.
> * Manual approval gate before production deployment.
> * Dependabot or Renovate to automatically update pinned action SHAs.
> * S3 backend with DynamoDB locking for Terraform remote state.
