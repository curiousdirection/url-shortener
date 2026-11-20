#!/usr/bin/env bash
# Decides whether the deploy can skip the function ("app") or the web page ("web"), and if so sets SKIP_APP or SKIP_WEB.
# CI never recreates a torn-down stack; release.sh does.
# A rollback (ROLLBACK_TO set) never skips because nothing changed.
# Usage: infra/scripts/deploy-skip.sh app|web   (needs AWS credentials, `terraform init` in infra/app and GitHub's $GITHUB_ENV and $GITHUB_STEP_SUMMARY)
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

kind="${1:?Say app or web}"
case "$kind" in
  app) resource=aws_lambda_function.app; what="Deploy"; var=SKIP_APP ;;
  web) resource=aws_s3_bucket.web; what="Page upload"; var=SKIP_WEB ;;
  *) echo "Say app or web, not $kind." >&2; exit 2 ;;
esac

skip() {
  echo "$var=$1" >> "$GITHUB_ENV"
  echo "### $what skipped: $2" >> "$GITHUB_STEP_SUMMARY"
  exit 0
}

if ! list="$(terraform -chdir=infra/app state list 2>err.txt)"; then
  grep -q "No state file was found" err.txt || { cat err.txt >&2; exit 1; }
fi
grep -qx "$resource" <<<"${list:-}" ||
  skip torn-down "the app is not deployed. Run \`infra/scripts/release.sh\` to bring it up."

[ -z "${ROLLBACK_TO:-}" ] || exit 0

# The commit that is live now.
# The function's is a Terraform output; the page's is the <meta name="release"> it serves.
# If the page has none yet, it deploys.
if [ "$kind" = app ]; then
  live="$(terraform -chdir=infra/app output -raw app_version)"
else
  url="$(terraform -chdir=infra/app output -raw url)"
  live="$(curl -fsS "$url/" | sed -n 's/.*<meta name="release" content="\([^"]*\)".*/\1/p' || true)"
fi
if [ -n "$live" ] && [ "$(infra/scripts/app-changed.sh "$kind" "$live" HEAD)" = false ]; then
  skip unchanged "nothing in it changed since the live commit \`$live\`."
fi
