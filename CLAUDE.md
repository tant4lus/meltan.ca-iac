# meltan.ca-iac

Terraform for meltan.ca's AWS infrastructure (S3, CloudFront, ACM, Route 53). Companion repo to `meltan.ca` (the Hexo site) — this repo manages infrastructure only. Content deployment (S3 sync, CloudFront invalidation) stays in `meltan.ca`'s own GitHub Actions workflow and isn't touched here.

## Structure

- `modules/static-site-bucket` — S3 bucket in `public` or `oai` mode; see the module's README
- `modules/cdn` — CloudFront distribution + directory-index CloudFront Function; see the module's README
- `global/` — account-wide, environment-agnostic DNS: the `meltan.ca` hosted zone, MX (Google Workspace mail), TXT (site verification). NS/SOA records are never imported — they're AWS-managed and importing them is a reliable way to create permanent phantom diffs.
- `environments/prod/` — prod bucket (`oai` mode) + CloudFront (aliases `meltan.ca`/`www.meltan.ca`/`blog.meltan.ca`) + its own ACM cert + Route 53 alias records for those three hostnames
- `environments/stage/` — staging bucket (`public` mode, S3 name `meltan.ca-staging`) + its own CloudFront distribution (alias `stage.meltan.ca`) + its own ACM cert + Route 53 alias record. Directory is named `stage` to match the `stage` GitHub Actions environment in `meltan.ca`; the underlying S3 bucket keeps its existing `meltan.ca-staging` name.

## Workflow

- Terraform Cloud, VCS-driven, one workspace per environment (`meltan-ca-global`, `meltan-ca-prod`, `meltan-ca-stage`), each scoped to its own working directory. Each workspace's trigger patterns should include `modules/**`, so a shared-module change replans everywhere it's used.
- No `.tfvars` — nothing in this config is sensitive (bucket names, hostnames, cert domains are already public), so config is passed as literal arguments in each environment's `main.tf`. Actual secrets (AWS auth for Terraform Cloud) live in TFC workspace variables or OIDC, never in this repo.
- State locking and remote state are handled by Terraform Cloud — no S3 backend/DynamoDB lock table needed.

## Import discipline

Every resource in `global`, `prod`, and `stage`'s bucket already exists in AWS — they were built by hand before this repo existed. **Never apply a new resource block against something that already exists.** The sequence is always: write the resource block matching current reality → `terraform import` (or an `import` block) → `terraform plan` and confirm **zero diff** → only then is `apply` safe. Applying blind risks recreating or replacing live production infrastructure, including the actual site people read.

The `claude-code-readonly` IAM user (used for reading AWS state during Claude sessions) is intentionally never imported into this repo — the credential managing infra shouldn't manage itself.

## AWS credentials

- For AWS reads (during a Claude session), use the dedicated read-only `claude-code-readonly` IAM user via the AWS MCP tool — never the shared `default` AWS CLI profile via a shell command. Melissa's own terminal and a Claude session's shell can both be live on the same machine at once; hitting the same `default` profile/session cache from both sides at the same time has already caused a credential-refresh race (session reporting "refreshed but still expired") that cost real troubleshooting time.
- Any actual `import`/`plan`/`apply` needs write-capable credentials Claude doesn't have — give Melissa the exact command to run herself, in her own terminal, using her own profile (she keeps a separate named profile, e.g. `terraform-mtan`, rather than `default`, to avoid the same collision).

## Git workflow

Always create a branch and open a PR — never commit directly to `main`, even for a brand-new repo's very first commit or when there's no CI configured yet to preview against. The review discipline itself is the point, not just whatever staging-preview side effect happens to come with it in `meltan.ca`.

## Related

- `meltan.ca` — the Hexo site and its CLAUDE.md, which documents the deploy pipeline this repo's resources support.
