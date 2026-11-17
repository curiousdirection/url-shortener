# CLAUDE.md

## When to push

When you have completed work on a worktree or using Claude Code on web push the changes to a branch and create a PR. Fill in the PR template (`.github/pull_request_template.md`); keep each section to a few lines. The person who asked for the change checks it before merging.

## API docs

APIs change faster than training data, so check the current docs before using one. For AWS use the mcp and skills available.

## Writing docs, comments and CI

- **One home per fact.** Why we decided something goes in the ADR; how to operate it (steps, commands) in `infra/README.md`; what protects what in `docs/security.md`; how a piece of code works, or a trap in it, in one comment next to that code. Everywhere else links to it or says nothing.
