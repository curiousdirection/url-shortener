#!/usr/bin/env bash
# Prints "true" if the commits between <before> and <after> change anything that goes into
# the image or the app stack, "false" if not (docs or tests alone). CI deploys on "true".
# Usage: infra/scripts/app-changed.sh <before sha> <after sha>
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

# Folders end in "/"; everything else is an exact file.
APP_PATHS=(
  src/ migrations/ infra/app/ .github/actions/setup-terraform/
  package.json package-lock.json tsconfig.json Dockerfile .dockerignore .node-version
  .terraform-version infra/scripts/push-image.sh
  .github/workflows/deploy.yml .github/workflows/test.yml
)

# If the previous commit is unknown (first push, force push), deploy to be safe.
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
