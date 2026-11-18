# 6. Stay on ECS Express Mode and Postgres, not Lambda and DynamoDB

Date: 2026-11-18. Status: accepted.

## Context

The app runs on ECS Express Mode with RDS Postgres ([0002](0002-deploy-with-ecs-express-mode.md)). We compared it with AWS Lambda and DynamoDB, for both the practice deployment and the full scale in "Assumptions" (root README). Prices are on-demand `eu-north-1`, from the AWS Price List, November 2026.

## Decision

Keep ECS Express Mode and Postgres.

## Why

- **Full scale costs about 2.5 times as much on Lambda.** Lambda behind the load balancer with DynamoDB comes to about $14,500/month, against about $6,200 today. Lambda bills per request: its request fee alone (about $6,100) is far more than today's tasks and database together (about $870). DynamoDB reads add about $2,000, against about $430 for RDS.
- **Lambda Web Functions can't serve full scale.** They run the Hono server unchanged and need no load balancer, but each endpoint is capped at 10,000 requests per second, and the cap can't be raised. That is below the full-scale average.
- **API Gateway as the front door is worse.** It costs about $29,000/month at this volume.
- **DynamoDB changes the app.** It has no sequence, so codes need a new scheme ([0005](0005-postgres-sequence-for-short-codes.md)). Its default reads can briefly miss a link that was just created, unless a miss is retried with a strongly consistent read.
- **Faster scaling doesn't decide it.** Lambda adds capacity faster than ECS, but spikes are meant to be absorbed by caching (an in-process cache, and a CDN later), not by scaling.

## Consequences

- **Practice keeps costing about $50/month if left running**, against roughly $0 on Lambda and DynamoDB. Destroying it between sessions is still the way to keep it near zero.
- **The VPC, the database password and the migrations stay** ([0001](0001-run-migrations-on-every-instance.md), [0003](0003-split-stacks-remote-state-and-ci-deploys.md)). Most of these would go with DynamoDB, not with Lambda: Lambda with RDS still needs the VPC.

## Alternatives considered

- **Lambda Web Functions and DynamoDB:** about $0 for practice, but the 10,000 requests per second cap rules out full scale.
- **Lambda behind the load balancer, and DynamoDB:** about $14,500/month at full scale.
- **API Gateway, Lambda and DynamoDB:** about $41,000/month at full scale.
- **ECS with DynamoDB instead of RDS:** about $8,100/month at full scale; it costs more without making anything simpler.

## Revisit when

Cheap practice matters more than matching the full-scale design, the expected traffic turns out much lower, or a CDN in front takes most requests away from the origin. With a CDN, Lambda's per-request cost applies only to cache misses.
