#!/usr/bin/env bash
# Scans the Terraform files for insecure settings with Checkov, in a throwaway virtualenv.
# Usage: infra/scripts/scan-terraform.sh
set -euo pipefail

CHECKOV_VERSION=3.4.6

cd "$(dirname "${BASH_SOURCE[0]}")/.."

venv="$(mktemp -d)"
trap 'rm -rf "$venv"' EXIT
python3 -m venv "$venv"
"$venv/bin/pip" install --quiet "checkov==$CHECKOV_VERSION"

"$venv/bin/checkov" --directory . --framework terraform --compact --quiet --skip-download
