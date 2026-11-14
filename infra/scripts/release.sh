#!/usr/bin/env bash
# Build the app image, push it to ECR and deploy it. See "Deploy" in infra/README.md.
# Usage: infra/scripts/release.sh [terraform apply options]   (run from anywhere; needs AWS credentials and Docker)
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

if [ -n "$(git status --porcelain)" ]; then
  echo "Uncommitted changes: commit or stash first so the image tag matches the code." >&2
  exit 1
fi
VERSION="$(git rev-parse --short HEAD)"
tf=(terraform -chdir=infra)

# The repository has to exist before the first push, and the service needs the image. So on
# the first release create just the repository; the full apply is last.
REPO="$("${tf[@]}" output -raw ecr_repository_url 2>/dev/null || true)"
if [ -z "$REPO" ]; then
  "${tf[@]}" apply -auto-approve -target=aws_ecr_repository.app -var "app_version=$VERSION"
  REPO="$("${tf[@]}" output -raw ecr_repository_url)"
fi
# <account>.dkr.ecr.<region>.amazonaws.com/<name>
REGISTRY="${REPO%%/*}"
REGION="$(cut -d. -f4 <<<"$REGISTRY")"

# Tags are immutable, so an image that is already there is kept.
if aws ecr describe-images --region "$REGION" --repository-name "${REPO#*/}" --image-ids "imageTag=$VERSION" >/dev/null 2>&1; then
  echo "Image $VERSION is already in ECR."
else
  aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"
  # Arm, to match cpu_architecture in infra/app.tf (slower on an x86 machine, which emulates it).
  docker build --platform linux/arm64 --build-arg NODE_VERSION="$(cat .node-version)" -t "$REPO:$VERSION" .
  docker push "$REPO:$VERSION"
fi

"${tf[@]}" apply -var "app_version=$VERSION" "$@"
