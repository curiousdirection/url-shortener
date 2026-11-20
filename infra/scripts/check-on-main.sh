#!/usr/bin/env bash
# Fails unless the checked-out commit is in main's history, so a rollback can only deploy code that was merged.
# Used by CI's build job when it is run by hand with a ref.
# Usage: infra/scripts/check-on-main.sh
set -euo pipefail

git merge-base --is-ancestor HEAD origin/main ||
  { echo "::error::$(git rev-parse --short=7 HEAD) is not in main's history"; exit 1; }
