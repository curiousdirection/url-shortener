# 2. Deploy with ECS Express Mode

Date: 2026-11-13. Status: accepted.

## Context

The app has to run on AWS behind a load balancer, next to the private RDS database. The first design was a Network Load Balancer with an EC2 auto scaling group ([PR #10](https://github.com/curiousdirection/url-shortener/pull/10), never merged). It worked on paper but had many parts to run: a boot script that installed Node and npm packages on every boot, launch templates, instance refresh and rollback handling, AMI updates, and a release bucket.

AWS App Runner, the simple option, stopped accepting new customers on 2026-04-30. AWS recommends Amazon ECS Express Mode instead ([source](https://aws.amazon.com/apprunner/)).

## Decision

Deploy the app as a container on Amazon ECS Express Mode, on Fargate (Arm by default). From an image and two IAM roles, Express Mode creates the Application Load Balancer, the HTTPS certificate, CPU autoscaling and canary deployments. The same Terraform serves the practice deployment and full scale; only variable values differ. `infra/scripts/release.sh` builds the image, pushes it to ECR and runs `terraform apply`. See [infra/README.md](../../infra/README.md).

## Why

- **Far fewer moving parts.** The boot script, launch templates, instance refresh, AMI updates and release bucket are gone. A release is one command.
- **The image carries Node and the dependencies.** A new task never downloads Node or runs `npm ci` while starting, so scale-out doesn't depend on nodejs.org or the npm registry.
- **Rollback is built in.** Express Mode starts the new tasks beside the old ones, sends them a small share of traffic, and rolls back by itself if the deployment fails. `terraform apply` waits for the result and fails with it.

## Consequences

- **It costs more at full scale**, about $2,100/month more than NLB + EC2, almost all from ALB capacity units for new connections. Express Mode only builds ALBs. See "Cost" in [infra/README.md](../../infra/README.md).
- **The deploy check can roll back a healthy release.** Express Mode's alarm counts 4xx as well as 5xx and rolls back above 1%. It can't be changed through Express Mode or Terraform, so a burst of normal 404s during a canary could roll back a good release. See "Rollback" in [infra/README.md](../../infra/README.md).
- **The practice deployment no longer mirrors the cheaper full-scale design.** It runs the ALB design, not NLB + EC2.
- **Migrations still run inside the VPC on every start.** They now run in the container's start command (`node dist/migrate.js && exec node dist/server.js`) instead of a boot script. The reasoning in [0001](0001-run-migrations-on-every-instance.md) still holds, with tasks in place of servers.

## Alternatives considered

- **NLB + EC2 auto scaling group** ([#10](https://github.com/curiousdirection/url-shortener/pull/10)): about $2,100/month cheaper at full scale, but many more parts to build and run.
- **AWS App Runner:** closed to new customers.
- **Elastic Beanstalk:** an older way to do much the same as Express Mode.
- **Lightsail containers and a Lightsail database:** the simplest on AWS, but nothing like the full-scale design.
- **Render, Railway or Fly.io:** not AWS.

## Revisit when

The ALB cost matters (real traffic at scale), or the 4xx rollback actually bites.
