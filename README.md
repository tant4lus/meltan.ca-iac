# meltan.ca-iac

Terraform for [meltan.ca](https://github.com/tant4lus/meltan.ca)'s AWS infrastructure — S3, CloudFront, ACM, and Route 53. This repo manages infrastructure only; content deployment (S3 sync, CloudFront invalidation) stays in that repo's own GitHub Actions workflow.

---

## Structure

- `modules/static-site-bucket` — S3 bucket, in `public` mode (staging, served straight from the S3 website endpoint) or `oai` mode (prod, private and restricted to a CloudFront Origin Access Identity)
- `modules/cdn` — CloudFront distribution, including a CloudFront Function that fixes directory-style URLs (e.g. `/about/`) 403ing against an OAI-restricted S3 origin
- `global/` — account-wide, environment-agnostic DNS: the `meltan.ca` hosted zone, MX (mail), TXT (site verification)
- `environments/prod/` — production bucket + CDN + ACM cert + Route 53 records
- `environments/stage/` — staging bucket + CDN + ACM cert + Route 53 records
- `scripts/bootstrap-tfc-oidc.sh` — creates the AWS OIDC provider and the per-workspace IAM roles that let Terraform Cloud authenticate to AWS without static keys

---

## Local development

```bash
git clone https://github.com/tant4lus/meltan.ca-iac.git
cd meltan.ca-iac/environments/prod   # or global, or environments/stage
terraform init
terraform plan
```

Requires AWS credentials for the account this infrastructure lives in. There are no `.tfvars` files — nothing in this config is sensitive, so values are passed as literal arguments in each environment's `main.tf`.

---

## Import discipline

Every resource this repo manages already existed in AWS before the repo did — none of it started out Terraform-managed. Never write a new resource block and `apply` it blind:

1. Write the resource block matching current reality
2. `terraform import` it (or use an `import` block)
3. `terraform plan` — confirm **zero diff**
4. Only then is `apply` safe

---

## Deployment

Terraform Cloud, VCS-driven, one workspace per environment (`meltan-ca-global`, `meltan-ca-prod`, `meltan-ca-stage`), each scoped to its own working directory, in the `meltan` org / `meltan-ca` project. AWS auth uses OIDC (see `scripts/bootstrap-tfc-oidc.sh`) rather than static keys. State locking and remote state are handled by Terraform Cloud, so there's no S3 backend or DynamoDB lock table to manage.

`meltan-ca-stage` and `meltan-ca-prod` are wired up and migrated. `meltan-ca-global` is pending until `global/`'s resource blocks are written.

---

## Related

- [meltan.ca](https://github.com/tant4lus/meltan.ca) — the Hexo site whose infrastructure this repo manages

---

## License

Personal project — not intended as a reusable template.
