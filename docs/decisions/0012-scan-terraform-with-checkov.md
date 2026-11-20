# 12. Scan the Terraform with Checkov, and skip checks inline

Date: 2026-11-20. Status: accepted.

## Context

Nothing checked the Terraform for insecure settings such as open permissions or missing encryption. The scan has to run without AWS credentials and without a paid plan or a new secret.

## Decision

- **Checkov scans `infra/` on every push**, as the `scan` job of `.github/workflows/terraform.yml`, which `infra/scripts/scan-terraform.sh` runs. A failed check fails CI, so `build` and the deploy wait for it.
- **The job has no AWS credentials and a read-only token.** Checkov is installed with pip, pinned to one version, so the job runs third-party code.
- **A check we don't follow is skipped inside the resource, with a one-line reason** (`#checkov:skip=<id>: <reason>`). There is no list of skipped checks elsewhere, so a skip sits next to the code it excuses.

## Why

- **Checkov is a plain pip package.** It needs no GitHub Action, so there is no action to pin and no downloaded binary to verify.
- **The skips record decisions.** Most findings were for features that are off for practice and on at full scale, or that docs/security.md already explains.

## Consequences

- **Its default set includes cost and resilience checks**, not only security ones: replication, access logs, event notifications, KMS keys. Each new resource may need a skip with a reason.
- **The pip install isn't hash-pinned.** The version is pinned, but a package it depends on could change between runs. The job's lack of credentials limits what that could do.
- **It reads the Terraform source, not the plan**, so it doesn't see values only known at apply time.

## Alternatives considered

- **Trivy.** Fewer low-value findings, but it needs its action or a downloaded binary, which means a SHA to keep current for either.
- **Allow only a chosen list of checks.** Quieter, but new checks would never run.
- **Skip checks in a central config file.** One file is easier to read, but the reasons would be far from the resources.

## Revisit when

The skips outnumber the real checks, or the job needs a hash-pinned install.
