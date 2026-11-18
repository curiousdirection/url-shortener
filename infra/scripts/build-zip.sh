#!/usr/bin/env bash
# Bundles the app into build/app.zip, the package Lambda runs, and prints the zip's hash (the
# value infra/app takes as package_hash) as the only thing on stdout. Run `npm ci` first.
# Used by release.sh, the deploy workflow and the test workflow.
# Usage: infra/scripts/build-zip.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

rm -rf build
npm run bundle >&2
# A fixed file time and no extra file attributes, so the same code always gives the same zip, and
# so the same hash. Otherwise every release would look like a code change.
# The time is set in UTC because zip stores local time. -t works with both GNU and macOS touch.
chmod 644 build/lambda/index.mjs
TZ=UTC touch -t 200001010000 build/lambda/index.mjs
(cd build/lambda && TZ=UTC zip -q -X ../app.zip index.mjs)

# Terraform and Lambda both write this hash as base64 of the raw SHA-256.
openssl dgst -sha256 -binary build/app.zip | openssl base64 -A
echo
