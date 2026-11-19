#!/usr/bin/env bash
# Prints the release name for the checked-out commit: the first 7 characters of its SHA.
# The one place this rule lives; release.sh and the deploy workflow both use it, so they agree.
# (Not `git rev-parse --short=7`: 7 is only its minimum, so clones could disagree.)
set -euo pipefail
git rev-parse HEAD | cut -c1-7
