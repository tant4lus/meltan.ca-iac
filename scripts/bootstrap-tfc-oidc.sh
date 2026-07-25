#!/usr/bin/env bash
# Creates the AWS OIDC identity provider + two IAM roles that let HCP Terraform
# Cloud (org "meltan") assume AWS credentials for the meltan-ca-stage and
# meltan-ca-prod workspaces, scoped to just their own S3 bucket for now.
#
# Run this yourself with a write-capable AWS profile, e.g.:
#   AWS_PROFILE=terraform-mtan ./scripts/bootstrap-tfc-oidc.sh
#
# To reuse for another site, just change the config block below and, if the
# managed resources differ from modules/static-site-bucket, adjust the
# permission policy built in create_role_and_policy.
#
# Everything here is idempotent-ish (uses `|| true` on the provider create in
# case it partially ran before) but re-running create-role/put-role-policy on
# an existing role is safe: create-role will just error harmlessly if the role
# already exists, and put-role-policy always overwrites in place.

set -euo pipefail

# ---- config: change this block to reuse for another site/org/project ----
PROFILE="${AWS_PROFILE:-terraform-mtan}"
TFC_HOSTNAME="app.terraform.io"
OIDC_URL="https://${TFC_HOSTNAME}"
AUDIENCE="aws.workload.identity"
TFC_ORG="meltan"
TFC_PROJECT="meltan.ca"
# ---------------------------------------------------------------------------

WORKDIR="$(mktemp -d)"
echo "Writing policy documents to: ${WORKDIR}"

echo "==> Fetching OIDC server certificate thumbprint for ${TFC_HOSTNAME}"
THUMBPRINT="$(
  openssl s_client -servername "${TFC_HOSTNAME}" -showcerts -connect "${TFC_HOSTNAME}:443" </dev/null 2>/dev/null \
    | openssl x509 -fingerprint -sha1 -noout \
    | sed 's/.*=//; s/://g' \
    | tr 'A-Z' 'a-z'
)"
echo "    thumbprint: ${THUMBPRINT}"

echo "==> Creating IAM OIDC identity provider for ${OIDC_URL}"
OIDC_PROVIDER_ARN=$(aws iam create-open-id-connect-provider \
  --profile "${PROFILE}" \
  --url "${OIDC_URL}" \
  --client-id-list "${AUDIENCE}" \
  --thumbprint-list "${THUMBPRINT}" \
  --query 'OpenIDConnectProviderArn' --output text)
echo "    provider ARN: ${OIDC_PROVIDER_ARN}"

create_role_and_policy() {
  local env_name="$1"          # "stage" or "prod"
  local workspace_name="$2"    # "meltan-ca-stage" or "meltan-ca-prod"
  local role_name="$3"         # "meltan-ca-stage-tfc" or "meltan-ca-prod-tfc"
  local bucket_name="$4"       # "meltan.ca-staging" or "meltan.ca"
  local include_website_actions="$5"  # "true" for stage (public mode), "false" for prod (oai mode)

  local trust_file="${WORKDIR}/trust-${env_name}.json"
  local perms_file="${WORKDIR}/perms-${env_name}.json"

  cat > "${trust_file}" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${OIDC_PROVIDER_ARN}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${TFC_HOSTNAME}:aud": "${AUDIENCE}"
        },
        "StringLike": {
          "${TFC_HOSTNAME}:sub": "organization:${TFC_ORG}:project:${TFC_PROJECT}:workspace:${workspace_name}:run_phase:*"
        }
      }
    }
  ]
}
EOF

  local website_actions=""
  if [ "${include_website_actions}" = "true" ]; then
    website_actions='
        "s3:GetBucketWebsite",
        "s3:PutBucketWebsite",
        "s3:DeleteBucketWebsite",'
  fi

  cat > "${perms_file}" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3${env_name^}BucketManage",
      "Effect": "Allow",
      "Action": [
        "s3:GetBucketLocation",
        "s3:GetBucketTagging",
        "s3:PutBucketTagging",
        "s3:GetBucketOwnershipControls",
        "s3:PutBucketOwnershipControls",
        "s3:GetBucketPublicAccessBlock",
        "s3:PutBucketPublicAccessBlock",
        "s3:GetEncryptionConfiguration",
        "s3:PutEncryptionConfiguration",${website_actions}
        "s3:GetBucketPolicy",
        "s3:PutBucketPolicy",
        "s3:DeleteBucketPolicy"
      ],
      "Resource": "arn:aws:s3:::${bucket_name}"
    }
  ]
}
EOF

  echo "==> Creating role ${role_name}"
  aws iam create-role \
    --profile "${PROFILE}" \
    --role-name "${role_name}" \
    --assume-role-policy-document "file://${trust_file}" \
    --description "HCP Terraform OIDC role for workspace ${workspace_name}"

  echo "==> Attaching inline permission policy to ${role_name}"
  aws iam put-role-policy \
    --profile "${PROFILE}" \
    --role-name "${role_name}" \
    --policy-name "${role_name}-s3" \
    --policy-document "file://${perms_file}"

  local role_arn
  role_arn=$(aws iam get-role --profile "${PROFILE}" --role-name "${role_name}" --query 'Role.Arn' --output text)
  echo "    ${role_name} ARN: ${role_arn}"
}

# Note: bash ${var^} used above capitalizes the first letter (env_name -> Stage/Prod) for the Sid.
create_role_and_policy "stage" "meltan-ca-stage" "meltan-ca-stage-tfc" "meltan.ca-staging" "true"
create_role_and_policy "prod" "meltan-ca-prod" "meltan-ca-prod-tfc" "meltan.ca" "false"

echo ""
echo "Done. OIDC provider: ${OIDC_PROVIDER_ARN}"
echo "Give these role ARNs to Claude for the TFC_AWS_RUN_ROLE_ARN workspace variables:"
aws iam get-role --profile "${PROFILE}" --role-name meltan-ca-stage-tfc --query 'Role.Arn' --output text
aws iam get-role --profile "${PROFILE}" --role-name meltan-ca-prod-tfc --query 'Role.Arn' --output text
