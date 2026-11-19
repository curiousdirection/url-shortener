#!/usr/bin/env bash
# Checks the Terraform files the way CI does: formatting, then validate for each stack (without reaching the state in S3).
# Usage: infra/scripts/check-terraform.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

terraform fmt -check -recursive -diff .
for stack in bootstrap foundation app; do
  echo "== $stack"
  terraform -chdir="$stack" init -backend=false -input=false >/dev/null
  terraform -chdir="$stack" validate
done
