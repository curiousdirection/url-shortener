#!/usr/bin/env bash
# Uploads the built web page (build/web) to its bucket and clears CloudFront's copy of index.html.
# Run `npm run web:build` first; it isn't run here, so the deploy workflow can build before it signs in.
# Used by release.sh and the deploy workflow.
# Needs AWS credentials and `terraform init` done in infra/app (release.sh and the workflow do both).
# Usage: infra/scripts/release-web.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

[ -f build/web/index.html ] || { echo "No build/web: run npm run web:build first." >&2; exit 1; }
BUCKET="$(terraform -chdir=infra/app output -raw web_bucket)"
DISTRIBUTION="$(terraform -chdir=infra/app output -raw distribution_id)"

# The files in assets have hashed names, so they never change.
# No --delete: the page that is live still needs its old files until the new index.html is out, and the deploy role can't delete anyway.
aws s3 sync build/web/assets "s3://$BUCKET/assets" --cache-control "public, max-age=31536000, immutable"

# index.html comes last, so it never points at a file that isn't there yet.
# CloudFront keeps it until the invalidation below.
aws s3 cp build/web/index.html "s3://$BUCKET/index.html" --cache-control "public, max-age=0, s-maxage=31536000"

# "/" is cached separately from "/index.html".
id="$(aws cloudfront create-invalidation --distribution-id "$DISTRIBUTION" --paths "/" "/index.html" --query Invalidation.Id --output text)"
aws cloudfront wait invalidation-completed --distribution-id "$DISTRIBUTION" --id "$id"
