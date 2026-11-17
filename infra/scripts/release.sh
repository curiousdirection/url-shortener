#!/usr/bin/env bash
# Build the app image, push it to ECR and apply infra/app. For the first run and releases
# from your machine; CI does the same on main. See "Deploy" in infra/README.md.
# Usage: infra/scripts/release.sh   (needs AWS credentials, Docker and the setup in that README)
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

if [ -n "$(git status --porcelain)" ]; then
  echo "Uncommitted changes: commit or stash first so the image tag matches the code." >&2
  exit 1
fi
# The first 7 characters of the commit SHA, the same as the deploy workflow, so an image built
# by either is reused. (Not `git rev-parse --short=7`: 7 is only its minimum, so a full clone
# can give a longer name than the workflow's shallow checkout.)
SHA="$(git rev-parse HEAD)"
VERSION="${SHA:0:7}"
tf=(terraform -chdir=infra/app)

# The repository has to exist before the first push, and the service needs the image. So on
# the first release create just the repository; the full apply is last. (The app stack reads
# the foundation outputs, so this needs the foundation stack applied already.)
# (`output -raw` prints nothing for an empty state, and fails on any real error.)
REPO="$("${tf[@]}" output -raw ecr_repository_url)"
if [ -z "$REPO" ]; then
  "${tf[@]}" apply -auto-approve -target=aws_ecr_repository.app -var "app_version=$VERSION"
  REPO="$("${tf[@]}" output -raw ecr_repository_url)"
fi
infra/scripts/push-image.sh "$REPO" "$VERSION"

"${tf[@]}" apply -var "app_version=$VERSION"
