#!/usr/bin/env bash
# Creates the database user the app logs in as, by running the image's setup script
# (src/setupDb.ts) as a one-off ECS task. The script logs in with the master password, which
# only this task can read, so CI never runs it; release.sh does, on every release (it is safe
# to run again).
# Usage: infra/scripts/setup-db.sh <image>   (needs AWS credentials, jq and the foundation applied)
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

IMAGE="${1:?Usage: setup-db.sh <image>}"
REGISTRY="${IMAGE%%/*}"                     # <account>.dkr.ecr.<region>.amazonaws.com
REGION="$(cut -d. -f4 <<<"$REGISTRY")"
FAMILY=url-shortener-db-setup
LOG_GROUP=/url-shortener/app                # made in infra/app/main.tf; streams start with db-setup
ecs=(aws ecs --region "$REGION")

out="$(terraform -chdir=infra/foundation output -json)"
get() { jq -r ".$1.value" <<<"$out"; }

# Normally created by Express Mode, which on the first release comes after this task.
if [ "$("${ecs[@]}" describe-clusters --clusters default --query "length(clusters[?status=='ACTIVE'])")" = 0 ]; then
  "${ecs[@]}" create-cluster --cluster-name default >/dev/null
fi

# A new revision each time, so it always runs the image being released.
taskdef="$(jq -n \
  --arg family "$FAMILY" --arg image "$IMAGE" --arg region "$REGION" --arg group "$LOG_GROUP" \
  --arg role "$(get db_setup_execution_role_arn)" --arg secret "$(get db_password_parameter_arn)" \
  --arg url "postgres://$(get db_username)@$(get db_address):5432/$(get db_name)?sslmode=verify-full" \
  '{
    family: $family, requiresCompatibilities: ["FARGATE"], networkMode: "awsvpc",
    cpu: "256", memory: "512", executionRoleArn: $role,
    runtimePlatform: { cpuArchitecture: "ARM64", operatingSystemFamily: "LINUX" },
    containerDefinitions: [{
      name: "db-setup", image: $image, essential: true,
      command: ["node", "dist/setupDb.js"],
      environment: [{ name: "DATABASE_URL", value: $url }],
      secrets: [{ name: "PGPASSWORD", valueFrom: $secret }],
      logConfiguration: { logDriver: "awslogs", options: {
        "awslogs-group": $group, "awslogs-region": $region, "awslogs-stream-prefix": "db-setup" } }
    }]
  }')"
revision="$("${ecs[@]}" register-task-definition --cli-input-json "$taskdef" --query 'taskDefinition.taskDefinitionArn' --output text)"

# A public IP: the subnets have no NAT, so that is how the task pulls the image from ECR.
network="$(jq -cn --argjson subnets "$(get public_subnet_ids)" --arg sg "$(get app_security_group_id)" \
  '{awsvpcConfiguration: {subnets: $subnets, securityGroups: [$sg], assignPublicIp: "ENABLED"}}')"
run="$("${ecs[@]}" run-task --cluster default --launch-type FARGATE --task-definition "$revision" \
  --network-configuration "$network" --output json)"
task="$(jq -r '.tasks[0].taskArn // empty' <<<"$run")"
if [ -z "$task" ]; then
  jq .failures <<<"$run" >&2
  exit 1
fi
echo "Running the database setup task: $task"
"${ecs[@]}" wait tasks-stopped --cluster default --tasks "$task"

result="$("${ecs[@]}" describe-tasks --cluster default --tasks "$task" \
  --query 'tasks[0].{code: containers[0].exitCode, reason: stoppedReason}' --output json)"
if [ "$(jq -r .code <<<"$result")" != 0 ]; then
  echo "Database setup failed: $(jq -r .reason <<<"$result")" >&2
  echo "Log: group $LOG_GROUP, stream db-setup/db-setup/${task##*/}" >&2
  exit 1
fi
echo "Database setup done."
