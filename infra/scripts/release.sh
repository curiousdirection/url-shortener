#!/usr/bin/env bash
# Build the app image, push it to ECR and deploy it (the app stack, infra/app). See "Deploy" in
# infra/README.md. The deploy workflow (.github/workflows/deploy.yml) does the same on every
# push to main; use this script for the first run, and when you want to release from your
# machine.
#
# It does NOT apply the foundation stack (network, database, roles). Do that first, yourself,
# after reading its plan: terraform -chdir=infra/foundation apply
#
# Usage: infra/scripts/release.sh   (run from anywhere; needs AWS credentials and Docker, and
#        `terraform -chdir=infra/app init -backend-config=../backend.hcl` done once, and
#        `state_bucket` set in infra/app/terraform.tfvars; see "Set up" in infra/README.md)
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
# <account>.dkr.ecr.<region>.amazonaws.com/<name>
REGISTRY="${REPO%%/*}"
REGION="$(cut -d. -f4 <<<"$REGISTRY")"

# Tags are immutable, so an image that is already there is kept. Only "no such image" means
# it is missing; any other error stops the script with its message.
if out="$(aws ecr describe-images --region "$REGION" --repository-name "${REPO#*/}" --image-ids "imageTag=$VERSION" 2>&1)"; then
  echo "Image $VERSION is already in ECR."
elif grep -q ImageNotFoundException <<<"$out"; then
  aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"
  # Arm, to match cpu_architecture in infra/app/main.tf (slower on an x86 machine, which emulates it).
  docker build --platform linux/arm64 --build-arg NODE_VERSION="$(cat .node-version)" -t "$REPO:$VERSION" .
  docker push "$REPO:$VERSION"
else
  echo "$out" >&2
  exit 1
fi

"${tf[@]}" apply -var "app_version=$VERSION"
