#!/usr/bin/env bash
# Prints "true" if the commits between <from> and <to> change
# anything that goes into the zip or the app stack, "false" if
# not (docs or tests alone).
# The deploy workflow compares the deployed commit with the new
# one and deploys on "true".
# Usage: infra/scripts/app-changed.sh <from commit> <to commit>
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

# Folders end in "/"; everything else is an exact file.
APP_PATHS=(
  src/ infra/app/ .github/actions/setup-terraform/
  package.json package-lock.json tsconfig.json .node-version
  .terraform-version infra/scripts/build-zip.sh infra/scripts/app-version.sh
  .github/workflows/deploy.yml .github/workflows/test.yml
)

# If <from> is unknown (not in this history), deploy to be safe.
if ! files="$(git diff --name-only "$1" "$2" 2>/dev/null)"; then
  echo true
  exit 0
fi

while IFS= read -r file; do
  for path in "${APP_PATHS[@]}"; do
    if [[ $file == "$path" || ($path == */ && $file == "$path"*) ]]; then
      echo "Deploys because of $file" >&2
      echo true
      exit 0
    fi
  done
done <<<"$files"
echo false
