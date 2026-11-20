# 11. Deploy on a CodeBuild-hosted runner, with no access keys

Date: 2026-11-19. Status: accepted; supersedes [0004](0004-access-keys-instead-of-oidc.md) and amends the CI sign-in and the plan role in [0003](0003-split-stacks-remote-state-and-ci-deploys.md).

## Context

[0004](0004-access-keys-instead-of-oidc.md) signed CI in with the access keys of two IAM users, because this Free-plan account's service control policy blocks the OIDC provider. The keys don't expire, so they need rotating by hand, and a leaked one works from anywhere until someone notices.

CodeBuild can host GitHub Actions runners: it starts a runner in our account for each queued job, and the job runs with the credentials of the CodeBuild project's service role. CodeBuild, CodeConnections and CodeStar Connections are allowed by the Free-plan policy.

## Decision

- **The deploy job runs on a CodeBuild-hosted runner.** The project's service role is the deploy role, with the same permissions as before. Only CodeBuild, for that one project in this account, can assume it.
- **The build stays on a GitHub-hosted runner.** It runs `npm ci` and builds the zip and the page, with no AWS credentials, and hands them to the deploy job as artifacts. The deploy job runs no npm packages.
- **One deploy job** does the function and then the page, so a deploy uses one runner start.
- **No IAM users and no access keys.** CodeBuild reaches GitHub through a CodeConnections connection (the AWS GitHub App), which a person approves once.
- **No plan in CI.** The plan role, its user and the `plan` job are gone; the Terraform check (formatting and validate, no credentials) stays. The deploy's plan is in the run's summary, and you can plan from your machine.
- **Only the deployer's runs start the runner.** The repository is public, and CodeBuild's webhook can't tell a fork PR's workflow named "Deploy" from ours by name alone. So the webhook also filters on the triggering account's ID (`deployer_github_id`), and GitHub is set to require approval for all external contributors' workflow runs. How they protect the runner: "Access to AWS" in [docs/security.md](../security.md).
- **A watchdog cancels a deploy that no runner picks up**, because a job waiting for a runner has no timeout and would hold up later deploys.
- **Tests run once**, on GitHub-hosted runners in CI. Deploy waits for CI as before.

## Why

- **Nothing to leak or rotate.** The credentials are issued per build and expire with it.
- **It works under the policy.** It needs no IAM identity provider.
- **The deploy role is not reachable from GitHub** except through the runner project.

## Consequences

- **CodeBuild can filter runner jobs by workflow name and triggering account, not by branch.** A workflow named "Deploy" on any branch that the deployer triggers could claim the runner and get the deploy role.
- **The account filter is unproven for a deploy that CI starts.** CodeBuild matches the webhook payload's `sender.id`, and for a run started by `workflow_run` we don't know which account GitHub puts there. A wrong ID leaves the job queued until the watchdog cancels it, so the first deploys must be checked ("If the Deploy job never starts" in [infra/README.md](../../infra/README.md)).
- **`environment: production` is only GitHub's deployment history now**, not a gate.
- **Free tier:** 100 build minutes a month on the small instance; a deploy takes a few minutes, longer when CloudFront changes.
- **A one-time approval** of the connection in the console, which Terraform can't do.

## Alternatives considered

- **Keep the keys.** Works, but needs rotating, and the plan keys were usable from any branch.
- **Activate advanced features** to allow OIDC. It changes the whole account for one CI setting ([0004](0004-access-keys-instead-of-oidc.md)).
- **CodePipeline and CodeBuild without GitHub Actions.** A second CI system to build and run.
- **A plan job on a CodeBuild runner.** Any branch's workflow could name itself to claim it, so it would have been a way to run branch code with AWS access for little value.

## Revisit when

The account can use OIDC, which can check the branch, or CodeBuild can filter runner jobs by branch.
