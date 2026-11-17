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
VERSION="$(infra/scripts/image-tag.sh)"
tf=(terraform -chdir=infra/app)

# On the first release, create just the ECR repository and the log group: the image must be
# pushed (and the setup task logged) before the service that runs it can exist.
REPO="$("${tf[@]}" output -raw ecr_repository_url)"
if [ -z "$REPO" ]; then
  "${tf[@]}" apply -auto-approve -target=aws_ecr_repository.app -target=aws_cloudwatch_log_group.app \
    -var "app_version=$VERSION"
  REPO="$("${tf[@]}" output -raw ecr_repository_url)"
fi
infra/scripts/push-image.sh "$REPO" "$VERSION"

# The app logs in as its own database user, which has to exist before a task starts.
infra/scripts/setup-db.sh "$REPO:$VERSION"

"${tf[@]}" apply -var "app_version=$VERSION"
