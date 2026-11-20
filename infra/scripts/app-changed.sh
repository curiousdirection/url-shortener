#!/usr/bin/env bash
# Prints "true" if the commits between <from> and <to> change anything that goes into the zip or the app stack ("app"), or into the web page ("web"), "false" if not (docs or tests alone).
# CI's deploy job compares the deployed commit with the new one and deploys on "true".
# Usage: infra/scripts/app-changed.sh app|web <from commit> <to commit>
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

kind="${1:?Say app or web}"
from="${2:?Say the commit to compare from}"
to="${3:?Say the commit to compare to}"

# Folders end in "/"; everything else is an exact file.
APP_PATHS=(
  src/ infra/app/ .github/actions/setup-terraform/
  package.json package-lock.json tsconfig.json .node-version
  .terraform-version infra/scripts/build-zip.sh infra/scripts/app-version.sh
  .github/workflows/ci.yml .github/workflows/test.yml
  infra/scripts/check-on-main.sh infra/scripts/deploy-skip.sh infra/scripts/apply-app.sh infra/scripts/check-live.sh
)
WEB_PATHS=(
  web/ vite.config.ts package.json package-lock.json .node-version
  infra/scripts/release-web.sh .github/workflows/ci.yml
  infra/scripts/check-on-main.sh infra/scripts/deploy-skip.sh infra/scripts/check-live.sh
)
case "$kind" in
  app) PATHS=("${APP_PATHS[@]}") ;;
  web) PATHS=("${WEB_PATHS[@]}") ;;
  *) echo "Say app or web, not $kind." >&2; exit 2 ;;
esac

# If <from> is unknown (not in this history), deploy to be safe.
if ! files="$(git diff --name-only "$from" "$to" 2>/dev/null)"; then
  echo true
  exit 0
fi

while IFS= read -r file; do
  for path in "${PATHS[@]}"; do
    if [[ $file == "$path" || ($path == */ && $file == "$path"*) ]]; then
      echo "Deploys because of $file" >&2
      echo true
      exit 0
    fi
  done
done <<<"$files"
echo false
