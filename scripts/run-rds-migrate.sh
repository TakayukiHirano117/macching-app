#!/usr/bin/env bash
# Run DB migration against private RDS via ECS Fargate one-off task.
set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-northeast-1}"
CLUSTER="${ECS_CLUSTER:-macching-prod-cluster}"
SERVICE="${ECS_SERVICE:-macching-prod-api}"
TASK_DEF="${ECS_TASK_DEFINITION:-macching-prod-api}"

SUBNETS=$(aws ecs describe-services \
  --cluster "$CLUSTER" \
  --services "$SERVICE" \
  --region "$AWS_REGION" \
  --query 'services[0].networkConfiguration.awsvpcConfiguration.subnets' \
  --output text | tr '\t' ',')
SG=$(aws ecs describe-services \
  --cluster "$CLUSTER" \
  --services "$SERVICE" \
  --region "$AWS_REGION" \
  --query 'services[0].networkConfiguration.awsvpcConfiguration.securityGroups[0]' \
  --output text)

echo "Running migrate on cluster=$CLUSTER subnets=$SUBNETS sg=$SG"

TASK_ARN=$(aws ecs run-task \
  --cluster "$CLUSTER" \
  --launch-type FARGATE \
  --task-definition "$TASK_DEF" \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SG],assignPublicIp=DISABLED}" \
  --overrides '{"containerOverrides":[{"name":"api","command":["bun","run","src/infra/database/migrate.ts"]}]}' \
  --region "$AWS_REGION" \
  --query 'tasks[0].taskArn' \
  --output text)

echo "TASK_ARN=$TASK_ARN"
aws ecs wait tasks-stopped --cluster "$CLUSTER" --tasks "$TASK_ARN" --region "$AWS_REGION"
aws ecs describe-tasks \
  --cluster "$CLUSTER" \
  --tasks "$TASK_ARN" \
  --region "$AWS_REGION" \
  --query 'tasks[0].containers[0].{exit:exitCode,reason:reason}' \
  --output json

TASK_ID=${TASK_ARN##*/}
aws logs get-log-events \
  --region "$AWS_REGION" \
  --log-group-name /ecs/macching-prod-api \
  --log-stream-name "api/api/${TASK_ID}" \
  --limit 50 \
  --query 'events[*].message' \
  --output text || true
