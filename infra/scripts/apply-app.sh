#!/usr/bin/env bash
# Plans infra/app for the checked-out commit, shows the plan in $GITHUB_STEP_SUMMARY and applies exactly that plan.
# -lock-timeout waits for a local release.sh.
# Usage: infra/scripts/apply-app.sh <package hash from build-zip.sh>
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

hash="${1:?Pass the hash that build-zip.sh printed}"
version="$(infra/scripts/app-version.sh)"
terraform -chdir=infra/app plan -input=false -lock-timeout=10m -no-color \
  -var "app_version=$version" -var "package_hash=$hash" -out=tfplan | tee plan.txt
{ echo '### Terraform plan'; echo '```'; head -c 900000 plan.txt; echo '```'; } >> "$GITHUB_STEP_SUMMARY"
terraform -chdir=infra/app apply -input=false -lock-timeout=10m tfplan
