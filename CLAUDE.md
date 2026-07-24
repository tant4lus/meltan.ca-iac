# meltan.ca-iac

Terraform for meltan.ca's AWS infrastructure (S3, CloudFront, ACM, Route 53). Companion repo to `meltan.ca` (the Hexo site) — this repo manages infrastructure only. Content deployment (S3 sync, CloudFront invalidation) stays in `meltan.ca`'s own GitHub Actions workflow and isn't touched here.

## Structure

- `modules/static-site-bucket` — S3 bucket in `public` or `oai` mode; see the module's README
- `modules/cdn` — CloudFront distribution + directory-index CloudFront Function; see the module's README
- `global/` — account-wide, environment-agnostic DNS: the `meltan.ca` hosted zone, MX (Google Workspace mail), TXT (site verification). NS/SOA records are never imported — they're AWS-managed and importing them is a reliable way to create permanent phantom diffs.
- `environments/prod/` — prod bucket (`oai` mode) + CloudFront (aliases `meltan.ca`/`www.meltan.ca`/`blog.meltan.ca`) + its own ACM cert + Route 53 alias records for those three hostnames
- `environments/staging/` — staging bucket (`public` mode) + its own CloudFront distribution (alias `stage.meltan.ca`) + its own ACM cert + Route 53 alias record

## Workflow

- Terraform Cloud, VCS-driven, one workspace per environment (`meltan-ca-global`, `meltan-ca-prod`, `meltan-ca-staging`), each scoped to its own working directory. Each workspace's trigger patterns should include `modules/**`, so a shared-module change replans everywhere it's used.
- No `.tfvars` — nothing in this config is sensitive (bucket names, hostnames, cert domains are already public), so config is passed as literal arguments in each environment's `main.tf`. Actual secrets (AWS auth for Terraform Cloud) live in TFC workspace variables or OIDC, never in this repo.
- State locking and remote state are handled by Terraform Cloud — no S3 backend/DynamoDB lock table needed.

## Import discipline

Every resource in `global`, `prod`, and staging's bucket already exists in AWS — they were built by hand before this repo existed. **Never apply a new resource block against something that already exists.** The sequence is always: write the resource block matching current reality → `terraform import` (or an `import` block) → `terraform plan` and confirm **zero diff** → only then is `apply` safe. Applying blind risks recreating or replacing live production infrastructure, including the actual site people read.

The `claude-code-readonly` IAM user (used for reading AWS state during Claude sessions) is intentionally never imported into this repo — the credential managing infra shouldn't manage itself.

## Related

- `meltan.ca` — the Hexo site and its CLAUDE.md, which documents the deploy pipeline this repo's resources support.
