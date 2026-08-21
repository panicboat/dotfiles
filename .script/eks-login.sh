#!/usr/bin/env bash
# eks-login.sh - Source this to assume eks-admin-${env} role and update
# kubeconfig for the panicboat platform EKS cluster.
#
# Usage:
#   source ./eks-login.sh [environment] [region]
#
# Default environment: production.
# Region defaults are derived from environment to match workflow-config.yaml
# in panicboat/platform (production -> ap-northeast-1, develop -> us-east-1).
# For environments not listed below, region must be passed explicitly as 2nd arg.
#
# MUST be sourced (not executed) so that AWS_* env vars persist in the
# parent shell. Session is valid for 1 hour (matches the role's
# max_session_duration in aws/eks/modules/iam_admin.tf).
#
# Prerequisites:
#   - aws CLI v2 with credentials configured for an IAM principal that has
#     sts:AssumeRole permission on the eks-admin-${env} role
#   - jq
#   - kubectl

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "ERROR: This script must be sourced, not executed." >&2
  echo "Usage: source $(basename "$0") [environment] [region]" >&2
  exit 1
fi

_env="${1:-production}"

# Default region/account per environment matches workflow-config.yaml in
# panicboat/platform. Add new envs here when creating develop/staging EKS.
# production/develop each live in their own dedicated AWS account (member
# accounts under the panicboat Organization) since the account-separation
# migration; eks-admin-${env} only trusts its own account's root, so we must
# hop through OrganizationAccountAccessRole from the management account
# first (a direct assume from the default identity gets AccessDenied).
case "${_env}" in
  production) _region="${2:-ap-northeast-1}"; _account_id="337169763788" ;;
  develop)    _region="${2:-us-east-1}";      _account_id="270242382571" ;;
  *)          _region="${2:-}";               _account_id="" ;;
esac

if [ -z "${_region}" ] || [ -z "${_account_id}" ]; then
  echo "[eks-login] ERROR: unknown environment '${_env}', add its region/account to eks-login.sh" >&2
  unset _env _region _account_id
  return 1
fi

echo "[eks-login] Assuming OrganizationAccountAccessRole in ${_account_id}..."
_org_creds=$(aws sts assume-role \
  --role-arn "arn:aws:iam::${_account_id}:role/OrganizationAccountAccessRole" \
  --role-session-name "kubectl-${USER:-debug}-org" \
  --query 'Credentials' \
  --output json)

_role_arn="arn:aws:iam::${_account_id}:role/eks-admin-${_env}"
echo "[eks-login] Assuming ${_role_arn} in ${_region}..."
_creds=$(AWS_ACCESS_KEY_ID=$(echo "${_org_creds}" | jq -r .AccessKeyId) \
  AWS_SECRET_ACCESS_KEY=$(echo "${_org_creds}" | jq -r .SecretAccessKey) \
  AWS_SESSION_TOKEN=$(echo "${_org_creds}" | jq -r .SessionToken) \
  aws sts assume-role \
  --role-arn "${_role_arn}" \
  --role-session-name "kubectl-${USER:-debug}" \
  --query 'Credentials' \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo "${_creds}" | jq -r .AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(echo "${_creds}" | jq -r .SecretAccessKey)
export AWS_SESSION_TOKEN=$(echo "${_creds}" | jq -r .SessionToken)

aws sts get-caller-identity --query 'Arn' --output text
aws eks update-kubeconfig --region "${_region}" --name "eks-${_env}"

echo "[eks-login] Done. AWS_* env vars exported. Session valid for 1 hour."
unset _env _region _account_id _role_arn _org_creds _creds
