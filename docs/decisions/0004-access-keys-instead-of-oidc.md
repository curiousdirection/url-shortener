# 4. Sign in to AWS with access keys instead of OIDC

Date: 2026-11-17. Status: superseded by [0011](0011-deploy-on-a-codebuild-runner.md); it superseded the OIDC sign-in in [0003](0003-split-stacks-remote-state-and-ci-deploys.md).

## Context

[0003](0003-split-stacks-remote-state-and-ci-deploys.md) had GitHub sign in to AWS with OIDC. This account is on the Free plan for projects, and AWS gives those accounts a fixed service control policy that denies `iam:*Provider*` ([the policy](https://docs.aws.amazon.com/accounts/latest/reference/scps-and-rcps-for-projects.html)). The GitHub OIDC provider can't be created or even listed; IAM users, keys and roles still can.

## Decision

Keep the two roles and their permissions. Each is trusted only by its own IAM user (deploy, plan), and that user's only permission is to assume the role. The keys are made by hand, not in Terraform, and stored as GitHub secrets: the deploy keys in the `production` environment, the plan keys in the repository. A job signs in with the key and assumes the role, so it still works on credentials that expire within an hour.

## Why

- **It works under the policy.**
- **A leaked key can only assume one role**, so the role limits from 0003 still hold.
- **Only `main` can read the deploy keys**, through the environment's branch rule.

## Consequences

- **The keys don't expire.** Rotate them by hand (the rotation steps were removed from [infra/README.md](../../infra/README.md) with [0011](0011-deploy-on-a-codebuild-runner.md), which removes the keys).
- **Any branch's CI can use the plan keys.**
- **The deploy role no longer checks the branch itself.** The environment rule is the only gate.

## Alternatives considered

- **Activate advanced features.** Removes the deny, so OIDC works again. That changes the whole account for one CI setting.
- **CodePipeline and CodeBuild inside AWS.** No keys leave AWS, but it is a second CI system to build and run.
- **`release.sh` only.** No keys at all, but every release needs a person with admin credentials, as before 0003.

## Revisit when

The account moves off the Free plan's restrictions (advanced features are activated), or a stored key becomes a worry.
