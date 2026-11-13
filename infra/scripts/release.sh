#!/usr/bin/env bash
# Build the app and upload it to the release bucket. Next steps: "Releasing" in infra/README.md.
# Usage: infra/scripts/release.sh   (run from anywhere; needs AWS credentials)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

if [ -n "$(git status --porcelain)" ]; then
  echo "Uncommitted changes: commit or stash first so the release id matches the code." >&2
  exit 1
fi
VERSION="$(git rev-parse --short HEAD)"

BUCKET="${RELEASE_BUCKET:-$(terraform -chdir=infra output -raw release_bucket)}"

npm ci
rm -rf dist # no stale compiled files in the release
npm run build

TARBALL="$(mktemp -d)/url-shortener-$VERSION.tgz"
tar -czf "$TARBALL" dist migrations package.json package-lock.json .node-version
aws s3 cp "$TARBALL" "s3://$BUCKET/releases/"

echo "Uploaded release $VERSION."
