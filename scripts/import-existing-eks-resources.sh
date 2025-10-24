#!/usr/bin/env bash
set -euo pipefail

# Usage:
#  ./scripts/import-existing-eks-resources.sh [TERRAFORM_DIR] [CLUSTER_NAME] [AWS_REGION]
# Example:
#  ./scripts/import-existing-eks-resources.sh terraform/eks/default retail-store us-east-1

TF_DIR=${1:-terraform/eks/default}
CLUSTER_NAME=${2:-${ENVIRONMENT_NAME:-retail-store}}
REGION=${3:-${AWS_REGION:-us-east-1}}

# Terraform resource addresses from the codebase (from the error output)
KMS_RESOURCE_ADDR='module.retail_app_eks.module.eks_cluster.module.kms.aws_kms_alias.this["cluster"]'
KMS_ALIAS_NAME="alias/eks/${CLUSTER_NAME}"

LOG_RESOURCE_ADDR='module.retail_app_eks.module.eks_cluster.aws_cloudwatch_log_group.this[0]'
LOG_GROUP_NAME="/aws/eks/${CLUSTER_NAME}/cluster"

echo "Terraform directory: $TF_DIR"
echo "Cluster name: $CLUSTER_NAME"
echo "Region: $REGION"

tmpdir() { mktemp -d 2>/dev/null || mktemp -d -t 'tmpdir'; }

# ensure aws cli available
if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI not found. Install and configure AWS CLI with credentials."
  exit 1
fi

if ! command -v terraform >/dev/null 2>&1; then
  echo "terraform not found. Install Terraform to continue."
  exit 1
fi

# ensure TF dir exists
if [ ! -d "$TF_DIR" ]; then
  echo "Terraform directory '$TF_DIR' not found." >&2
  exit 1
fi

pushd "$TF_DIR" >/dev/null

# terraform init (no backend changes) to ensure providers are available
echo "Running terraform init (may prompt to configure backend)..."
terraform init -input=false || true

# Helper: check if address exists in state
state_has() {
  local addr="$1"
  if terraform state list 2>/dev/null | grep -F -- "$addr" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# Robust import helper: try multiple Terraform addresses for the same resource id
# Does NOT exit the script on failure; prints warnings and continues.
try_import() {
  local id="$1"
  shift
  local addrs=("$@")
  for addr in "${addrs[@]}"; do
    # skip if state already has this address
    if state_has "$addr"; then
      echo "Terraform state already contains $addr — skipping import."
      return 0
    fi

    echo "Attempting terraform import '$addr' '$id'"
    if terraform import "$addr" "$id"; then
      echo "Imported $addr -> $id"
      terraform state show "$addr" || true
      return 0
    else
      echo "Import to $addr failed (resource may not exist or address mismatch); trying next address if available"
    fi
  done

  echo "Warning: all import attempts failed for id '$id' — continuing without failing the job"
  return 0
}

# Import KMS alias if it exists in AWS
echo "Checking for KMS alias: $KMS_ALIAS_NAME"
FOUND_KMS=$(aws kms list-aliases --region "$REGION" --query "Aliases[?AliasName=='${KMS_ALIAS_NAME}'] | [0].AliasName" --output text 2>/dev/null || true)
if [ -z "$FOUND_KMS" ] || [ "$FOUND_KMS" = "None" ]; then
  echo "KMS alias '$KMS_ALIAS_NAME' not found in AWS (region $REGION). Skipping KMS import."
else
  echo "KMS alias found: $FOUND_KMS"
  echo "Importing KMS alias into Terraform state..."
  # try the module-level address first, then the flattened top-level resource name used elsewhere
  try_import "$KMS_ALIAS_NAME" "$KMS_RESOURCE_ADDR" "aws_kms_alias.eks_cluster"
fi

# Import CloudWatch Log Group if it exists in AWS
echo "Checking for CloudWatch log group: $LOG_GROUP_NAME"
FOUND_LOG=$(aws logs describe-log-groups --region "$REGION" --log-group-name-prefix "$LOG_GROUP_NAME" --query "logGroups[?logGroupName=='${LOG_GROUP_NAME}'] | [0].logGroupName" --output text 2>/dev/null || true)
if [ -z "$FOUND_LOG" ] || [ "$FOUND_LOG" = "None" ]; then
  echo "Log group '$LOG_GROUP_NAME' not found in AWS (region $REGION). Skipping log group import."
else
  echo "Log group found: $FOUND_LOG"
  try_import "$LOG_GROUP_NAME" "$LOG_RESOURCE_ADDR" "aws_cloudwatch_log_group.eks_cluster"
fi

# Optionally import ADOT IAM roles mentioned in CI
# Addresses from CI: module.retail_app_eks.module.iam_assumable_role_adot_amp.aws_iam_role.this[0]
# and module.retail_app_eks.module.iam_assumable_role_adot_logs.aws_iam_role.this[0]

ADOT_ROLE_ADDR_AMP='module.retail_app_eks.module.iam_assumable_role_adot_amp.aws_iam_role.this[0]'
ADOT_ROLE_ADDR_LOGS='module.retail_app_eks.module.iam_assumable_role_adot_logs.aws_iam_role.this[0]'
ADOT_ROLE_NAME_AMP="${CLUSTER_NAME}-adot-col-xray"
ADOT_ROLE_NAME_LOGS="${CLUSTER_NAME}-adot-col-logs"

# Import ADOT roles if present
for addr in "$ADOT_ROLE_ADDR_AMP" "$ADOT_ROLE_ADDR_LOGS"; do
  : # placeholder to keep shellcheck happy
done

FOUND_ROLE_AMP=$(aws iam get-role --role-name "$ADOT_ROLE_NAME_AMP" --query 'Role.RoleName' --output text 2>/dev/null || true)
if [ -n "$FOUND_ROLE_AMP" ] && [ "$FOUND_ROLE_AMP" != "None" ]; then
  echo "ADOT role found: $FOUND_ROLE_AMP"
  try_import "$ADOT_ROLE_NAME_AMP" "$ADOT_ROLE_ADDR_AMP"
else
  echo "ADOT role '$ADOT_ROLE_NAME_AMP' not found in AWS. Skipping import."
fi

FOUND_ROLE_LOGS=$(aws iam get-role --role-name "$ADOT_ROLE_NAME_LOGS" --query 'Role.RoleName' --output text 2>/dev/null || true)
if [ -n "$FOUND_ROLE_LOGS" ] && [ "$FOUND_ROLE_LOGS" != "None" ]; then
  echo "ADOT role found: $FOUND_ROLE_LOGS"
  try_import "$ADOT_ROLE_NAME_LOGS" "$ADOT_ROLE_ADDR_LOGS"
else
  echo "ADOT role '$ADOT_ROLE_NAME_LOGS' not found in AWS. Skipping import."
fi

popd >/dev/null

echo "Finished import helper. Run 'terraform plan' in $TF_DIR to verify no create-errors remain."
