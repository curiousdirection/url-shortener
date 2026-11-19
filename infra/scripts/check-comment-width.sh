#!/usr/bin/env bash
# Fails on comment lines wider than 65 characters, indent
# included (the rule is in CLAUDE.md).
# Comments: `#` everywhere but ts/js/json; `//` and `/* */` in
# ts/js/json and .tf.
# Exempt: a comment that is only a URL, and a comment after code.
# Skipped: *.md, package-lock.json and *.lock.hcl.
# Usage: infra/scripts/check-comment-width.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

# Perl, not awk: mawk counts bytes, so "—" would count as 3.
git ls-files -z -- . ':!:*.md' ':!:package-lock.json' ':!:*.lock.hcl' |
  xargs -0 perl -CSD -ne '
    if ($ARGV ne $file) {
      $file = $ARGV;
      $c = $file =~ /\.(ts|js|mjs|jsonc?)$/;
      $slash = $c || $file =~ /\.tf$/;
      $block = 0;
    }
    chomp;
    $comment = 0;
    if ($block) { $comment = 1; $block = !m{\*/} }
    elsif ($slash && m{^\s*/\*}) { $comment = 1; $block = !m{\*/} }
    elsif ($slash && m{^\s*//}) { $comment = 1 }
    elsif (!$c && m{^\s*#}) { $comment = 1 }
    if ($comment && length > 65) {
      ($text = $_) =~ s{^\s*(?:#|//|/\*+|\*)\s*}{};
      unless ($text =~ m{^https?://\S*$}) {
        print "$ARGV:$.: ", length, " characters\n";
        $bad = 1;
      }
    }
    close ARGV if eof;
    END { exit($bad ? 1 : 0) }
  ' || { echo "Comment lines above are wider than 65 characters." >&2; exit 1; }
