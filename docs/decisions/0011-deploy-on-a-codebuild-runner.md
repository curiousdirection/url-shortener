# 11. Deploy on a CodeBuild-hosted runner, with no access keys

Date: 2026-11-19. Status: accepted; supersedes [0004](0004-access-keys-instead-of-oidc.md) and amends the CI sign-in and the plan role in [0003](0003-split-stacks-remote-state-and-ci-deploys.md).

## Context

[0004](0004-access-keys-instead-of-oidc.md) signed CI in with the access keys of two IAM users, because this Free-plan account's service control policy blocks the OIDC provider. The keys don't expire, so they need rotating by hand, and a leaked one works from anywhere until someone notices.

CodeBuild can host GitHub Actions runners: it starts a runner in our account for each queued job, and the job runs with the credentials of the CodeBuild project's service role. CodeBuild and CodeConnections are allowed by the Free-plan policy.

## Decision

- **The deploy job runs on a CodeBuild-hosted runner.** The project's service role is the deploy role: the same permissions as before, plus writing the runner's build logs and using the GitHub connection. Only CodeBuild, for that one project in this account, can assume it.
- **No IAM users and no access keys.** CodeBuild reaches GitHub through a CodeConnections connection (the AWS GitHub App).
- **Everything else stays on GitHub-hosted runners.** The tests, the Terraform check and the build (`npm ci`, the zip and the page) run there with no AWS credentials, and the build hands the zip and the page to the deploy job as artifacts. The deploy job runs no npm packages.
- **The deploy is part of CI, not a separate workflow.** It runs on `main` after the checks pass. The separate workflow existed so that a new push could cancel a CI run without cancelling a deploy; now CI queues runs on `main` instead of cancelling them, so an apply is never cancelled and deploys go in the order they were triggered.
- **One deploy job** does the function and then the page, so a deploy uses one runner start.
- **A rollback skips the checks**, so a broken `main` can't block it. The commit was checked when it was merged.
- **No plan in CI.** The plan role, its user and the `plan` job are gone; the Terraform check (formatting and validate, no credentials) stays.
- **Fork PRs need approval to run.** The repository is public, and a fork PR can add a workflow named "CI" that claims the runner, so GitHub is set to require approval for all external contributors' runs.
- **A watchdog cancels a deploy that no runner picks up**, because a job waiting for a runner isn't covered by its timeout and would hold up later deploys for up to 24 hours.

## Why

- **Nothing to leak or rotate.** The credentials are issued per build and expire with it.
- **It works under the policy.** It needs no IAM identity provider.
- **Deploys stay automatic and still wait for CI**, because the deploy is a job of the CI run.
- **The deploy role is not reachable from GitHub** except through the runner project.

## Consequences

- **CodeBuild can filter runner jobs by workflow name, not by branch.** A workflow named "CI" on any branch could claim the runner, so anyone with write access could get the deploy role. They could change `main` anyway.
- **Two settings live outside Terraform:** the connection must be approved once in the console, and the approval setting for external contributors is set in GitHub.
- **A newer run waiting on `main` replaces an older waiting one**, so the older commit is never checked or deployed on its own; the newer one includes it.
- **Deploys use CodeBuild build minutes**, whose free tier is limited ("Cost" in [infra/README.md](../../infra/README.md)).

## Alternatives considered

- **Keep the keys.** Works, but needs rotating, and the plan keys were usable from any branch.
- **Activate advanced features** to allow OIDC. It changes the whole account for one CI setting ([0004](0004-access-keys-instead-of-oidc.md)).
- **Deploy from a laptop or CloudShell with a short-lived login.** No keys either, but every release is manual and runs with the person's own, broader permissions.
- **A CodeBuild build started by a push to `main`.** CodeBuild can't wait for GitHub's checks, so the tests would run twice or the deploy wouldn't wait for them.
- **Filter runner jobs on the triggering GitHub account too.** Anyone with write access can change `main` anyway, and the filter would have stopped their merges from deploying.
- **A plan job on a CodeBuild runner.** Any branch's workflow could name itself to claim it, so it would have been a way to run branch code with AWS access for little value.

## Revisit when

The account can use OIDC, which can check the branch, or CodeBuild can filter runner jobs by branch.
