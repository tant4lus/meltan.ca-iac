# meltan.ca-iac

Terraform for meltan.ca's AWS infrastructure (S3, CloudFront, ACM, Route 53). Companion repo to `meltan.ca` (the Hexo site) — this repo manages infrastructure only. Content deployment (S3 sync, CloudFront invalidation) stays in `meltan.ca`'s own GitHub Actions workflow and isn't touched here.

## Structure

- `modules/static-site-bucket` — S3 bucket in `public` or `oai` mode; see the module's README
- `modules/cdn` — CloudFront distribution + directory-index CloudFront Function; see the module's README
- `global/` — account-wide, environment-agnostic DNS: the `meltan.ca` hosted zone, MX (Google Workspace mail), TXT (site verification). NS/SOA records are never imported — they're AWS-managed and importing them is a reliable way to create permanent phantom diffs.
- `environments/prod/` — prod bucket (`oai` mode) + CloudFront (aliases `meltan.ca`/`www.meltan.ca`/`blog.meltan.ca`) + its own ACM cert + Route 53 alias records for those three hostnames
- `environments/stage/` — staging bucket (`oai` mode, S3 name `meltan.ca-staging`) + its own CloudFront distribution (alias `stage.meltan.ca`) + its own ACM cert + Route 53 alias record — same shape as prod, via `modules/cdn`, converted from the original plain public/S3-website setup so stage and prod don't silently diverge. Directory is named `stage` to match the `stage` GitHub Actions environment in `meltan.ca`; the underlying S3 bucket keeps its existing `meltan.ca-staging` name.

## Workflow

- Terraform Cloud, VCS-driven, one workspace per environment (`meltan-ca-global`, `meltan-ca-prod`, `meltan-ca-stage`), each scoped to its own working directory. TFC org is `meltan`, project is `meltan-ca` (not `meltan.ca` — TFC project names can't contain periods). All three workspaces are live and migrated.
- VCS connection uses HCP Terraform's GitHub App integration (not a custom OAuth app) — simpler for a personal account, no Client ID/Secret to manage. If the org-level "Add a VCS Provider" page shows the GitHub App option greyed out as "(Installed)" even when nothing is installed yet, that's a known HashiCorp UI bug — connect from a workspace's own Settings → Version Control page instead.
- AWS auth to TFC is OIDC via `scripts/bootstrap-tfc-oidc.sh`, which creates the IAM OIDC provider plus one IAM role per workspace (e.g. `meltan-ca-stage-tfc`), trust-scoped by `sub` claim so each workspace can only assume its own role.
- Each workspace's trigger prefixes are its own working directory, plus `modules` for any workspace whose config actually uses a shared module — so a shared-module change replans everywhere it's used. `global/` doesn't use `modules/`, so its trigger prefix is just `global`.
- Connecting VCS to an already-existing CLI-driven workspace doesn't reliably auto-queue a run on the next merge — the first VCS-triggered run may need to be kicked off manually (`create_run` via the terraform MCP tool, or "Start new plan" in the TFC UI). Runs after that should trigger normally.
- No `.tfvars` — nothing in this config is sensitive (bucket names, hostnames, cert domains are already public), so config is passed as literal arguments in each environment's `main.tf`. Actual secrets (AWS auth for Terraform Cloud) live in TFC workspace variables or OIDC, never in this repo.
- State locking and remote state are handled by Terraform Cloud — no S3 backend/DynamoDB lock table needed.

## Import discipline

Every resource this repo manages — `global`'s hosted zone and DNS records, `prod` and `stage`'s buckets — already existed in AWS, built by hand before this repo existed. **Never apply a new resource block against something that already exists.** The sequence is always: write the resource block matching current reality → `terraform import` (or an `import` block) → `terraform plan` and confirm **zero diff** → only then is `apply` safe. Applying blind risks recreating or replacing live production infrastructure, including the actual site people read.

A missing IAM read permission on a TFC workspace's role can produce exactly this failure mode. AWS providers often read more than what's explicitly declared in HCL — e.g. `aws_s3_bucket` reads legacy sub-attributes (ACL, versioning, lifecycle, replication, etc.) on every refresh regardless of which ones are separately managed — and some of those reads hide behind non-obvious IAM actions (S3's `HeadBucket` existence check requires `s3:ListBucket`, not a dedicated action). If any of these get `AccessDenied`, Terraform can read that as the resource having been deleted and plan to destroy-and-recreate it. **Never apply a plan that unexpectedly wants to destroy/recreate a resource that demonstrably still exists** — verify live state via the read-only AWS MCP tool and fix the role's permission policy (`scripts/bootstrap-tfc-oidc.sh`) instead.

The `claude-code-readonly` IAM user (used for reading AWS state during Claude sessions) is intentionally never imported into this repo — the credential managing infra shouldn't manage itself.

## AWS credentials

- For AWS reads (during a Claude session), use the dedicated read-only `claude-code-readonly` IAM user via the AWS MCP tool — never the shared `default` AWS CLI profile via a shell command. Melissa's own terminal and a Claude session's shell can both be live on the same machine at once; hitting the same `default` profile/session cache from both sides at the same time has already caused a credential-refresh race (session reporting "refreshed but still expired") that cost real troubleshooting time.
- Any actual `import`/`plan`/`apply` needs write-capable credentials Claude doesn't have — give Melissa the exact command to run herself, in her own terminal, using her `default` AWS CLI profile. This is safe from the collision above because Claude never touches `default` via shell — AWS reads always go through the `claude-code-readonly` MCP profile instead.

## Git workflow

Always create a branch and open a PR — never commit directly to `main`, even for a brand-new repo's very first commit or when there's no CI configured yet to preview against. The review discipline itself is the point, not just whatever staging-preview side effect happens to come with it in `meltan.ca`.

The repo has "Automatically delete head branches" enabled, so merging a PR cleans up the branch on the remote — but not the matching local branch, and `git branch --merged` can't be trusted to find it because most merges here are squash merges, which break commit-ancestry-based detection. After confirming a PR merged (`gh pr view <n> --json state,mergedAt` — don't just assume from context, verify), delete the local branch explicitly (`git branch -D <branch>`) and run `git fetch origin --prune` to clear stale remote-tracking refs. Do this promptly: pushing a new commit to a branch whose PR already merged silently recreates an orphaned branch under the same name that will never actually land in `main` — exactly what happened with `feat/prod-cdn-import` (fixed in PR #20).

## Related

- `meltan.ca` — the Hexo site and its CLAUDE.md, which documents the deploy pipeline this repo's resources support.
