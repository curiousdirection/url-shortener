#!/usr/bin/env bash
# Prints the release name for the checked-out commit: the first 7 characters of its SHA.
# (Not `git rev-parse --short=7`: 7 is only its minimum, so clones could disagree.)
set -euo pipefail
git rev-parse HEAD | cut -c1-7
