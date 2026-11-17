#!/usr/bin/env bash
# Make sure the image <repo>:<tag> is in ECR: build and push it if it's missing. Tags are
# immutable, so an existing image is never rebuilt. Used by release.sh and the deploy workflow.
#
# Usage: infra/scripts/push-image.sh <repository url> <tag> [--no-build]
#   --no-build  only check that the image exists (for a rollback); fail if it doesn't.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

REPO="${1:?Usage: push-image.sh <repository url> <tag> [--no-build]}"
TAG="${2:?Usage: push-image.sh <repository url> <tag> [--no-build]}"
REGISTRY="${REPO%%/*}"                      # <account>.dkr.ecr.<region>.amazonaws.com
REGION="$(cut -d. -f4 <<<"$REGISTRY")"

# Only "no such image" means missing; any other error stops with its message.
if out="$(aws ecr describe-images --region "$REGION" --repository-name "${REPO#*/}" --image-ids "imageTag=$TAG" 2>&1)"; then
  echo "Image $TAG is already in ECR."
elif ! grep -q ImageNotFoundException <<<"$out"; then
  echo "$out" >&2
  exit 1
elif [ "${3:-}" = "--no-build" ]; then
  echo "There is no image tagged $TAG in ECR." >&2
  exit 1
else
  aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"
  # Arm, to match cpu_architecture in infra/app/main.tf (emulated, so slower, on x86).
  docker build --platform linux/arm64 --build-arg NODE_VERSION="$(cat .node-version)" -t "$REPO:$TAG" .
  docker push "$REPO:$TAG"
fi
