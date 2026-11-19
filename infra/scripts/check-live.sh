#!/usr/bin/env bash
# Checks that the function ("app") or the web page ("web") answers after a deploy, and says so in $GITHUB_STEP_SUMMARY.
# The page check also checks the routing: / must serve the checked-out commit's page, not the function or an old cached copy.
# Usage: infra/scripts/check-live.sh app|web   (needs `terraform init` in infra/app)
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

kind="${1:?Say app or web}"
url="$(terraform -chdir=infra/app output -raw url)"
version="$(infra/scripts/app-version.sh)"
get=(curl -fsS --retry 6 --retry-delay 10 --retry-all-errors)

case "$kind" in
  app)
    "${get[@]}" "$url/health"
    line="Deployed \`$version\` to $url"
    ;;
  web)
    "${get[@]}" "$url/" | grep -q "name=\"release\" content=\"$version\"" ||
      { echo "::error::$url/ does not serve release $version"; exit 1; }
    line="Page \`$version\` is live at $url"
    ;;
  *) echo "Say app or web, not $kind." >&2; exit 2 ;;
esac
echo "### $line${ROLLBACK_TO:+ (rollback)}" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
