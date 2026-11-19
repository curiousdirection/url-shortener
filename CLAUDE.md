# CLAUDE.md

## When to push

When you have completed work on a worktree or using Claude Code on web push the changes to a branch and create a PR. Fill in the PR template (`.github/pull_request_template.md`); keep each section to a few lines. The person who asked for the change checks it before merging.

## API docs

APIs change faster than training data, so check the current docs before using one. For AWS use the mcp and skills available.

This AWS account is a Free-plan project account, so AWS's [fixed SCPs](https://docs.aws.amazon.com/accounts/latest/reference/scps-and-rcps-for-projects.html) apply. Check them before designing on an AWS feature (for example, IAM identity providers are blocked).

## Writing docs, comments and CI

- **One home per fact.** Why we decided something goes in the ADR; how to operate it (steps, commands) in `infra/README.md`; what protects what in `docs/security.md`; how a piece of code works, or a trap in it, in one comment next to that code. Everywhere else links to it or says nothing.
- **Before committing, read the diff for repeats.** If a fact appears more than once, keep it in its home and cut the rest.
- **Comments are at most 65 columns wide, indent included** (the owner reads in a narrow viewer). One pointer per line, with paths written from the repo root. A line that is only a URL may run longer. `infra/scripts/check-comment-width.sh` checks it in CI.
