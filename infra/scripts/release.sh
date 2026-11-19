#!/usr/bin/env bash
# Build the app zip and apply infra/app. For the first run and releases from your machine; CI does the same on main. See "Deploy" in infra/README.md.
# Usage: infra/scripts/release.sh   (needs AWS credentials, Node and the setup in that README)
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

if [ -n "$(git status --porcelain)" ]; then
  echo "Uncommitted changes: commit or stash first so the release name matches the code." >&2
  exit 1
fi
VERSION="$(infra/scripts/app-version.sh)"

npm ci
HASH="$(infra/scripts/build-zip.sh)"

terraform -chdir=infra/app apply -var "app_version=$VERSION" -var "package_hash=$HASH"
