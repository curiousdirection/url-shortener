# 13. Log API calls with one CloudTrail trail and alarm on the worst events

Date: 2026-11-20. Status: accepted.

## Context

Nothing recorded who did what in the account, so a misused credential or a changed resource couldn't be traced. The Free-plan SCP blocks GuardDuty and Security Hub ([AWS's list](https://docs.aws.amazon.com/accounts/latest/reference/scps-and-rcps-for-projects.html)); CloudTrail, CloudWatch Logs and S3 are allowed. The account is limited to its project Region and to read-only CloudWatch in us-east-1, where root sign-ins and IAM calls are recorded.

## Decision

- **One multi-Region trail of management events**, made in `infra/foundation` like the alarms, so CI can't change it. It also logs global events, such as root sign-ins.
- **A private S3 bucket** (SSE-S3, public access blocked, non-TLS refused) with log file validation on. Logs expire after 90 days.
- **One alarm on the existing alarm topic**, for use of the root user, or `StopLogging` or `DeleteTrail`. The trail also sends events to a log group kept for 7 days, which the alarm's metric filter reads.
- **The deploy role is denied** every CloudTrail write and the trail bucket, on top of not being granted them.

## Why

- **It costs about nothing.** The first copy of management events is free, the logs are small, and S3 and CloudWatch Logs charge cents. The alarm is the 10th, within the free 10.
- **A multi-Region trail** is the only way to see the events AWS records in us-east-1 from a stack in our Region.
- **SSE-S3, not KMS.** A KMS key costs $1 a month and logs every use as another event.

## Consequences

- **Only those events alert.** Anything else needs someone to read the logs, which nobody does on a schedule.
- **Not an audit-grade record.** The bucket has no object lock or second account, so someone with admin rights can delete it. Validation shows tampering with the files but not deletion.
- **Stopping the trail on purpose also sends an email.**

## Alternatives considered

- **CloudTrail Lake or Insights:** charged per GB ingested, with no free tier.
- **An EventBridge rule for root sign-ins:** the event is in us-east-1, where the SCP blocks EventBridge.
- **AWS Config:** charged per recorded change, and not needed for who-did-what.
