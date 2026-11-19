#!/usr/bin/env bash
# Prints what applying the app stack would change, keeping the release that runs now so only infrastructure changes show.
# Read-only: runs with -lock=false.
# If the foundation isn't applied (never, or torn down), says so and exits 0, since the app stack needs its outputs.
# Usage: TF_STATE_BUCKET=<bucket> AWS_REGION=<region> infra/scripts/plan-app.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."
: "${TF_STATE_BUCKET:?Set TF_STATE_BUCKET}" "${AWS_REGION:?Set AWS_REGION}"

# Read the foundation's state file directly.
# Only "no such file" or "no outputs" mean not applied; any other error (no access, wrong bucket, not JSON) stops with its message.
state="$(mktemp)"
trap 'rm -f "$state" "$state.err"' EXIT
if aws s3api get-object --bucket "$TF_STATE_BUCKET" --key foundation/terraform.tfstate "$state" >/dev/null 2>"$state.err"; then
  outputs="$(jq '(.outputs // {}) | length' "$state")"
elif grep -q NoSuchKey "$state.err"; then
  outputs=0
else
  cat "$state.err" >&2
  exit 1
fi
if [ "$outputs" -eq 0 ]; then
  echo "Skipped: the foundation stack is not applied (or is torn down)."
  exit 0
fi

tf=(terraform -chdir=infra/app)
"${tf[@]}" init -input=false -backend-config="bucket=$TF_STATE_BUCKET" -backend-config="region=$AWS_REGION" >/dev/null
current="$("${tf[@]}" output -json)"
version="$(jq -r '.app_version.value // "none"' <<<"$current")"
hash="$(jq -r '.package_hash.value // "none"' <<<"$current")"

# The plan reuses the deployed hash, so it never reads the zip.
# The provider still wants a file at the path, so make a stand-in if there is none.
if [ ! -e build/app.zip ]; then
  mkdir -p build
  echo stand-in > build/stand-in.txt
  zip -q -X build/app.zip build/stand-in.txt
fi
"${tf[@]}" plan -input=false -lock=false -no-color -var "app_version=$version" -var "package_hash=$hash"
