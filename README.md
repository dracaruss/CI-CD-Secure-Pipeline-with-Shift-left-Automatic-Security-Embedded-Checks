# High Level Overview
### A GitHub Actions Automatic Security Pipeline.  
***Four security checks trigger on every push and every pull request to the repo.***
> [!IMPORTANT]
> This project sets up automatic checks to ensure that before any code can be merged into a repo, it is scanned for vulnerabilities. This setup is powered by Github Actions, which connects to AWS using OIDC federation - so there are no stored credentials, and no long-lived keys. This project demonstrates shift-left security practices using infrastructure-as-code scanning, secrets detection, Terraform validation, and secure AWS authentication via OIDC.  

# Shift-Left CI/CD Security Pipeline - Project Execution Run Through

## How the project works

The pipeline runs automatically on every PR and push to `main` in the repo, with four parallel jobs that block insecure code from ever reaching production:

**Job 1 - Secrets Scanning (TruffleHog):** Scans the full git history (`fetch-depth: 0`) for verified secrets - real AWS keys, API tokens, passwords - using `--only-verified` to reduce false positives. It actually tries the credentials to confirm they're live.

**Job 2 - IaC Scanning (Checkov):** Runs against the `terraform/` directory with `soft_fail: false`, meaning any finding kills the build. Skipped `CKV_AWS_144` (cross-region replication) and `CKV2_AWS_62` (S3 event notifications) since they weren't relevant for a lab.

**Job 3 - Terraform Syntax/Compliance:** `terraform fmt -check`, `terraform validate`, `terraform init -backend=false`. Catches HCL syntax errors, formatting drift, and provider misconfig before they hit AWS.

**Job 4 - Terraform Plan against real AWS (PR-only):** This is the OIDC-authenticated job. After all other checks pass (`needs: compliance-check`), it assumes an IAM role via OIDC, runs `terraform plan`, and posts the plan output as a PR comment so reviewers see exactly what infrastructure would change before approving the merge.

## Supply-chain hardening

Every action was **SHA-pinned**, not tag-pinned - `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1` instead of `@v4`. Version tags are mutable; a compromised upstream repo can repoint `v4` to malicious code. SHA hashes are immutable.

## OIDC auth for AWS

No static creds anywhere. The flow:

1. GitHub Actions job requested `id-token: write` permission.
2. The `aws-actions/configure-aws-credentials` action grabs a signed JWT from GitHub's OIDC provider.
3. AWS STS verified the JWT against the OIDC identity provider you registered (`token.actions.githubusercontent.com`) and the IAM role's trust policy.
4. STS returned short-lived creds (~1 hour) scoped to the role `github-actions-terraform-dracaruss`.
5. Terraform used those creds for the `plan`.

The trust policy was scoped to a single repo - even other repos under `dracaruss` couldn't assume the role.

## Issues hit

**Issue 1 - `Not authorized to perform sts:AssumeRoleWithWebIdentity`**

The TF Plan job kept failing at the `Configure AWS Credentials` step. The OIDC connection itself was working (AWS was receiving the token) - the trust policy was rejecting the claim match. The original trust policy had:

```
"token.actions.githubusercontent.com:sub": "repo:dracaruss/CI-CD-...:pull_request"
```

with `StringEquals`. The problem: GitHub's actual `sub` claim for PR events is more specific than just `:pull_request` (it includes additional context like `:pull_request` plus environment/ref info, and the exact format varies by event type). **Fix:** switched the condition to `StringLike` with a wildcard:

```json
"StringLike": {
  "token.actions.githubusercontent.com:sub": "repo:dracaruss/CI-CD-Secure-Pipeline-with-Shift-left-Automatic-Security-Embedded-Checks:*"
}
```

This let any event type from that specific repo assume the role, while still rejecting any other repo on the planet.

**Issue 2 - Push events were trying to assume the role even though plan shouldn't run on push**

The TF Plan step had `if: github.event_name == 'pull_request'`, but `Configure AWS Credentials` didn't - so on every push to main, the credentials step still ran, hit a trust policy that didn't match the push event's sub claim, and failed. **Fix:** moved the `if` condition from the step level to the **job level**, so the entire `terraform-quality-and-plan` job is skipped cleanly on pushes instead of running half-way and failing.

**Issue 3 - Inconsistent SHA pinning**

Code review caught that `actions/github-script@v7` (used to post the plan as a PR comment) was still tag-pinned while everything else was SHA-pinned. **Fix:** pinned it to commit `60a0d83039c74a4aee543508d2ffcb1c3799cdea`.

**Issue 4 - `terraform plan -backend=false` caveat**

The `init` step used `-backend=false`, which means the plan doesn't reflect real state drift - it's a syntax/validation plan, not a true infrastructure plan. Documented this in a comment so future contributors don't assume the plan output reflects actual drift.

**Issue 5 - PR comment size limit**

GitHub's PR comment body has a ~65,536 char limit. For large plans this would silently truncate. Noted as a known limitation; long-term fix would be to truncate the output or link to the full Actions log.

## What it demonstrates

This is the shift-left thesis in practice: catch IaC misconfig, leaked secrets, and bad Terraform *at the PR stage*, before merge, before deploy, before production. The OIDC federation piece eliminates the most common CI/CD attack vector - long-lived AWS access keys stored as GitHub secrets - and the SHA-pinning closes the supply-chain attack vector on the actions themselves.

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

Why re-run the scans on merge? — defense in depth  

Three real reasons, in order of importance:
1. The PR check tests the feature branch in isolation. The merge tests the actual merged result.
> When the PR check ran, it scans the feature branch as if it were the only thing that existed. But between when I open the PR and when I click merge, main might have moved. Someone else's PR could have merged in the meantime. My code, combined with their code, might produce a different result than either alone.
Together, Checkov might flag a misconfiguration that only exists in the merged state. The post-merge scan catches it.

2. Belt-and-suspenders against PR bypass
> PRs aren't the only way code reaches main. Someone with admin rights can:
> Push directly to main (git push origin main)
> Force-push to main
> Merge without waiting for checks (if branch protection isn't strict)
> Use the GitHub API to write commits directly
> 
> If the only scans run on PRs, any of those bypass routes deliver unscanned code to main. The push-to-main trigger guarantees that whatever lands on main gets scanned, regardless of how it got there. That's the "final guard" idea.

3. Catching tampering between approval and merge
> A PR can be approved at 2pm and merged at 4pm. In between, someone could push additional commits to the feature branch. GitHub re-runs PR checks on new commits — but the post-merge scan is the last word, scanning exactly what's now sitting on main.

* The trade-off
> Yes, it's "redundant" compute. You're paying for the same scans twice. For a real org this is cheap — GitHub Actions minutes on ubuntu-latest are essentially free for public repos and cheap for private. The cost of one Checkov run is seconds of CPU; the cost of a misconfigured S3 bucket reaching prod is a breach notification.

##


# Supply Chain Security  
All GitHub Actions are pinned to SHA hashes instead of version tags. Version tags are mutable - a compromised repo could move a tag to point to malicious code. SHA hashes are immutable and guarantee you're running the exact code you reviewed.  
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
***This pipeline uses OpenID Connect (OIDC) to authenticate GitHub Actions with AWS - no access keys or secrets stored anywhere.***  
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
