#!/usr/bin/env bash
# Creates the AWS OIDC identity provider + IAM roles that let HCP Terraform
# Cloud (org "meltan") assume AWS credentials for the meltan-ca-stage,
# meltan-ca-prod, and meltan-ca-global workspaces, each scoped to just the
# resources it manages (an S3 bucket for stage/prod, the meltan.ca Route 53
# hosted zone for global).
#
# Run this yourself with a write-capable AWS profile (defaults to "default"):
#   ./scripts/bootstrap-tfc-oidc.sh
# or, to use a different profile:
#   AWS_PROFILE=some-other-profile ./scripts/bootstrap-tfc-oidc.sh
#
# To reuse for another site, just change the config block below and, if the
# managed resources differ from modules/static-site-bucket, adjust the
# permission policy built in create_role_and_policy.
#
# Safe to re-run: the OIDC provider and each role are only created if they
# don't already exist (existing roles get their trust policy refreshed
# instead), and put-role-policy always overwrites the permission policy in
# place.
#
# This script only sets up the AWS side (OIDC provider + IAM roles). It does
# NOT create the HCP Terraform workspace, connect its VCS repo, or set its
# workspace variables — those still need to happen per workspace, either
# through the TFC UI or its API/MCP tooling:
#   1. Create the workspace (org "meltan", project "meltan-ca"), scoped to
#      its own working directory.
#   2. Connect VCS from that workspace's own Settings -> Version Control
#      page (the org-level "Add a VCS Provider" page can show the GitHub App
#      option as falsely greyed out - use the workspace-level path instead).
#   3. Set trigger prefixes to the workspace's working directory (plus
#      "modules" if its config uses a shared module).
#   4. Set the TFC_AWS_PROVIDER_AUTH=true and TFC_AWS_RUN_ROLE_ARN=<role ARN
#      from this script's output> workspace variables (category: env).

set -euo pipefail

# ---- config: change this block to reuse for another site/org/project ----
PROFILE="${AWS_PROFILE:-default}"
TFC_HOSTNAME="app.terraform.io"
OIDC_URL="https://${TFC_HOSTNAME}"
AUDIENCE="aws.workload.identity"
TFC_ORG="meltan"
TFC_PROJECT="meltan-ca"
GLOBAL_HOSTED_ZONE_ID="Z038765422KUTVSCFJIK2"  # meltan.ca
# ---------------------------------------------------------------------------

ACCOUNT_ID="$(aws sts get-caller-identity --profile "${PROFILE}" --query Account --output text)"

WORKDIR="$(mktemp -d)"
echo "Writing policy documents to: ${WORKDIR}"

echo "==> Checking for an existing IAM OIDC identity provider for ${OIDC_URL}"
OIDC_PROVIDER_ARN=$(aws iam list-open-id-connect-providers \
  --profile "${PROFILE}" \
  --query "OpenIDConnectProviderList[?ends_with(Arn, ':oidc-provider/${TFC_HOSTNAME}')].Arn | [0]" \
  --output text)

if [ -z "${OIDC_PROVIDER_ARN}" ] || [ "${OIDC_PROVIDER_ARN}" = "None" ]; then
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
else
  echo "    already exists: ${OIDC_PROVIDER_ARN}"
fi

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

  local write_website_actions=""
  if [ "${include_website_actions}" = "true" ]; then
    write_website_actions='
        "s3:PutBucketWebsite",
        "s3:DeleteBucketWebsite",'
  fi

  # Portable capitalization (macOS ships bash 3.2, which lacks ${var^}).
  local env_name_cap
  env_name_cap="$(tr '[:lower:]' '[:upper:]' <<< "${env_name:0:1}")${env_name:1}"

  # The AWS provider's base aws_s3_bucket resource still reads a whole set of
  # legacy/deprecated sub-attributes on every refresh (acl, versioning,
  # logging, CORS, replication, request payer, accelerate config, object
  # lock, website) regardless of which ones this module actually manages as
  # separate resources -- none of these are set in HCL, so only Get*
  # (read) access is needed, never Put*/Delete*, and it's needed on both
  # stage and prod even though only stage separately manages website config.
  #
  # s3:ListBucket is also required even though this role never lists
  # objects: the provider's bucket-existence check calls HeadBucket, which
  # AWS's IAM model authorizes via s3:ListBucket rather than a dedicated
  # action. Without it, HeadBucket gets AccessDenied and Terraform reads
  # that as the bucket having been deleted, producing a false
  # destroy-and-recreate plan.
  cat > "${perms_file}" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3${env_name_cap}BucketManage",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:GetBucketAcl",
        "s3:GetBucketVersioning",
        "s3:GetBucketLogging",
        "s3:GetBucketCORS",
        "s3:GetReplicationConfiguration",
        "s3:GetBucketRequestPayment",
        "s3:GetAccelerateConfiguration",
        "s3:GetBucketObjectLockConfiguration",
        "s3:GetBucketWebsite",
        "s3:GetLifecycleConfiguration",
        "s3:GetBucketTagging",
        "s3:PutBucketTagging",
        "s3:GetBucketOwnershipControls",
        "s3:PutBucketOwnershipControls",
        "s3:GetBucketPublicAccessBlock",
        "s3:PutBucketPublicAccessBlock",
        "s3:GetEncryptionConfiguration",
        "s3:PutEncryptionConfiguration",${write_website_actions}
        "s3:GetBucketPolicy",
        "s3:PutBucketPolicy",
        "s3:DeleteBucketPolicy"
      ],
      "Resource": "arn:aws:s3:::${bucket_name}"
    }
  ]
}
EOF

  if aws iam get-role --profile "${PROFILE}" --role-name "${role_name}" >/dev/null 2>&1; then
    echo "==> Role ${role_name} already exists; updating its trust policy"
    aws iam update-assume-role-policy \
      --profile "${PROFILE}" \
      --role-name "${role_name}" \
      --policy-document "file://${trust_file}"
  else
    echo "==> Creating role ${role_name}"
    aws iam create-role \
      --profile "${PROFILE}" \
      --role-name "${role_name}" \
      --assume-role-policy-document "file://${trust_file}" \
      --description "HCP Terraform OIDC role for workspace ${workspace_name}"
  fi

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

create_global_role_and_policy() {
  local workspace_name="meltan-ca-global"
  local role_name="meltan-ca-global-tfc"

  local trust_file="${WORKDIR}/trust-global.json"
  local perms_file="${WORKDIR}/perms-global.json"

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

  # Route 53 is a global service: ARNs have no region/account segment. GetChange
  # is scoped to change/* rather than the hosted zone, since ChangeResourceRecordSets
  # returns a dynamic change ID that isn't known ahead of time.
  cat > "${perms_file}" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Route53GlobalZoneManage",
      "Effect": "Allow",
      "Action": [
        "route53:GetHostedZone",
        "route53:ListTagsForResource",
        "route53:ChangeTagsForResource",
        "route53:UpdateHostedZoneComment",
        "route53:ListResourceRecordSets",
        "route53:ChangeResourceRecordSets"
      ],
      "Resource": "arn:aws:route53:::hostedzone/${GLOBAL_HOSTED_ZONE_ID}"
    },
    {
      "Sid": "Route53ChangeStatus",
      "Effect": "Allow",
      "Action": "route53:GetChange",
      "Resource": "arn:aws:route53:::change/*"
    }
  ]
}
EOF

  if aws iam get-role --profile "${PROFILE}" --role-name "${role_name}" >/dev/null 2>&1; then
    echo "==> Role ${role_name} already exists; updating its trust policy"
    aws iam update-assume-role-policy \
      --profile "${PROFILE}" \
      --role-name "${role_name}" \
      --policy-document "file://${trust_file}"
  else
    echo "==> Creating role ${role_name}"
    aws iam create-role \
      --profile "${PROFILE}" \
      --role-name "${role_name}" \
      --assume-role-policy-document "file://${trust_file}" \
      --description "HCP Terraform OIDC role for workspace ${workspace_name}"
  fi

  echo "==> Attaching inline permission policy to ${role_name}"
  aws iam put-role-policy \
    --profile "${PROFILE}" \
    --role-name "${role_name}" \
    --policy-name "${role_name}-route53" \
    --policy-document "file://${perms_file}"

  local role_arn
  role_arn=$(aws iam get-role --profile "${PROFILE}" --role-name "${role_name}" --query 'Role.Arn' --output text)
  echo "    ${role_name} ARN: ${role_arn}"
}

attach_stage_cdn_policy() {
  local role_name="meltan-ca-stage-tfc"
  local perms_file="${WORKDIR}/perms-stage-cdn.json"

  # stage.meltan.ca's own CloudFront distribution + ACM cert + Route 53
  # record, per modules/cdn. Route 53 record management is scoped to the
  # meltan.ca zone (not ListHostedZones — see the comment in
  # environments/stage/main.tf for why that's looked up by hardcoded ID
  # instead). ACM/CloudFront resource IDs don't exist yet at policy-write
  # time, so those are scoped to account/region wildcards instead of exact
  # ARNs.
  cat > "${perms_file}" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Route53StageRecordManage",
      "Effect": "Allow",
      "Action": [
        "route53:ListResourceRecordSets",
        "route53:ChangeResourceRecordSets"
      ],
      "Resource": "arn:aws:route53:::hostedzone/${GLOBAL_HOSTED_ZONE_ID}"
    },
    {
      "Sid": "Route53ChangeStatus",
      "Effect": "Allow",
      "Action": "route53:GetChange",
      "Resource": "arn:aws:route53:::change/*"
    },
    {
      "Sid": "AcmStageCertManage",
      "Effect": "Allow",
      "Action": [
        "acm:RequestCertificate",
        "acm:DescribeCertificate",
        "acm:DeleteCertificate",
        "acm:AddTagsToCertificate",
        "acm:ListTagsForCertificate",
        "acm:RemoveTagsFromCertificate"
      ],
      "Resource": "arn:aws:acm:us-east-1:${ACCOUNT_ID}:certificate/*"
    },
    {
      "Sid": "CloudFrontStageOaiManage",
      "Effect": "Allow",
      "Action": [
        "cloudfront:CreateCloudFrontOriginAccessIdentity",
        "cloudfront:GetCloudFrontOriginAccessIdentity",
        "cloudfront:GetCloudFrontOriginAccessIdentityConfig",
        "cloudfront:UpdateCloudFrontOriginAccessIdentity",
        "cloudfront:DeleteCloudFrontOriginAccessIdentity"
      ],
      "Resource": "arn:aws:cloudfront::${ACCOUNT_ID}:origin-access-identity/*"
    },
    {
      "Sid": "CloudFrontStageFunctionManage",
      "Effect": "Allow",
      "Action": [
        "cloudfront:CreateFunction",
        "cloudfront:DescribeFunction",
        "cloudfront:GetFunction",
        "cloudfront:UpdateFunction",
        "cloudfront:DeleteFunction",
        "cloudfront:PublishFunction"
      ],
      "Resource": "arn:aws:cloudfront::${ACCOUNT_ID}:function/*"
    },
    {
      "Sid": "CloudFrontStageDistributionManage",
      "Effect": "Allow",
      "Action": [
        "cloudfront:CreateDistribution",
        "cloudfront:GetDistribution",
        "cloudfront:GetDistributionConfig",
        "cloudfront:UpdateDistribution",
        "cloudfront:DeleteDistribution",
        "cloudfront:TagResource",
        "cloudfront:UntagResource",
        "cloudfront:ListTagsForResource"
      ],
      "Resource": "arn:aws:cloudfront::${ACCOUNT_ID}:distribution/*"
    }
  ]
}
EOF

  echo "==> Attaching inline CDN permission policy to ${role_name}"
  aws iam put-role-policy \
    --profile "${PROFILE}" \
    --role-name "${role_name}" \
    --policy-name "${role_name}-cdn" \
    --policy-document "file://${perms_file}"
}

create_role_and_policy "stage" "meltan-ca-stage" "meltan-ca-stage-tfc" "meltan.ca-staging" "true"
attach_stage_cdn_policy
create_role_and_policy "prod" "meltan-ca-prod" "meltan-ca-prod-tfc" "meltan.ca" "false"
create_global_role_and_policy

echo ""
echo "Done. OIDC provider: ${OIDC_PROVIDER_ARN}"
echo "Use these role ARNs for each workspace's TFC_AWS_RUN_ROLE_ARN variable:"
aws iam get-role --profile "${PROFILE}" --role-name meltan-ca-stage-tfc --query 'Role.Arn' --output text
aws iam get-role --profile "${PROFILE}" --role-name meltan-ca-prod-tfc --query 'Role.Arn' --output text
aws iam get-role --profile "${PROFILE}" --role-name meltan-ca-global-tfc --query 'Role.Arn' --output text
echo ""
echo "This only set up the AWS side. For any workspace that isn't fully wired up yet,"
echo "still needed: create the TFC workspace, connect VCS from its own Settings ->"
echo "Version Control page, set trigger prefixes, and set the TFC_AWS_PROVIDER_AUTH /"
echo "TFC_AWS_RUN_ROLE_ARN workspace variables (see header comment for details)."
