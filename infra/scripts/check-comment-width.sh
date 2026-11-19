#!/usr/bin/env bash
# Fails if a comment line in a tracked file is wider than 65
# columns, indent included, because the owner reads in a narrow
# viewer.
# Exempt: a comment that is only a URL, and a comment after code.
# Skipped: *.md, package-lock.json and *.lock.hcl.
# Usage: infra/scripts/check-comment-width.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

git ls-files -z -- . ':!:*.md' ':!:package-lock.json' ':!:*.lock.hcl' |
  xargs -0 awk -v max=65 '
    FNR == 1 { c_style = (FILENAME ~ /\.(ts|js|mjs|jsonc?)$/) }
    {
      if (c_style) start = "^[ \t]*(//|/\\*+|\\*)"
      else         start = "^[ \t]*#"
    }
    $0 ~ start && length($0) > max {
      text = $0
      sub(start "[ \t]*", "", text)
      if (text ~ /^https?:\/\/[^ \t]*$/) next
      print FILENAME ":" FNR ": " length($0) " columns"
      bad = 1
    }
    END { exit bad }
  ' || { echo "Comment lines above are wider than 65 columns." >&2; exit 1; }
