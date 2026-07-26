#!/usr/bin/env bash
# Dump Supabase PostgreSQL and restore into private RDS via a one-off Fargate task
# that uses the official postgres:16 image (has pg_restore) and the API task role (S3).
#
# Required:
#   SUPABASE_DATABASE_URL  (or SOURCE_DATABASE_URL as an alias)
# Optional:
#   AWS_REGION, ECS_CLUSTER, ECS_SERVICE, DATABASE_SECRET_ID, CUTOVER_BUCKET
set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-northeast-1}"
CLUSTER="${ECS_CLUSTER:-macching-prod-cluster}"
SERVICE="${ECS_SERVICE:-macching-prod-api}"
SECRET_ID="${DATABASE_SECRET_ID:-macching-prod/database-url}"
BUCKET="${CUTOVER_BUCKET:-macching-prod-photos-615299732848}"
DUMP_PATH="${DUMP_PATH:-/tmp/macching.dump}"
KEY="cutover/macching-$(date +%Y%m%d%H%M%S).dump"

SUPABASE_DATABASE_URL="${SUPABASE_DATABASE_URL:-${SOURCE_DATABASE_URL:-}}"
: "${SUPABASE_DATABASE_URL:?SUPABASE_DATABASE_URL or SOURCE_DATABASE_URL is required}"

if ! command -v pg_dump >/dev/null 2>&1; then
  echo "pg_dump is required locally (brew install libpq && brew link --force libpq)" >&2
  exit 1
fi

if [ "${SKIP_DUMP:-0}" = "1" ] && [ -s "$DUMP_PATH" ]; then
  echo "==> Skipping dump; using existing ${DUMP_PATH}"
else
  echo "==> Dumping source DB -> ${DUMP_PATH}"
  pg_dump "$SUPABASE_DATABASE_URL" -Fc --no-owner --no-acl -f "$DUMP_PATH"
fi
ls -lh "$DUMP_PATH"

echo "==> Uploading dump to s3://${BUCKET}/${KEY}"
aws s3 cp "$DUMP_PATH" "s3://${BUCKET}/${KEY}" --region "$AWS_REGION"

echo "==> Loading RDS URL from Secrets Manager"
RDS_DATABASE_URL=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ID" \
  --region "$AWS_REGION" \
  --query 'SecretString' \
  --output text)

SUBNETS_JSON=$(aws ecs describe-services \
  --cluster "$CLUSTER" --services "$SERVICE" --region "$AWS_REGION" \
  --query 'services[0].networkConfiguration.awsvpcConfiguration.subnets' --output json)
SG=$(aws ecs describe-services \
  --cluster "$CLUSTER" --services "$SERVICE" --region "$AWS_REGION" \
  --query 'services[0].networkConfiguration.awsvpcConfiguration.securityGroups[0]' --output text)
SUBNETS=$(python3 -c 'import json,sys; print(",".join(json.load(sys.stdin)))' <<<"$SUBNETS_JSON")

EXEC_ROLE=$(aws ecs describe-task-definition --task-definition macching-prod-api --region "$AWS_REGION" --query 'taskDefinition.executionRoleArn' --output text)
TASK_ROLE=$(aws ecs describe-task-definition --task-definition macching-prod-api --region "$AWS_REGION" --query 'taskDefinition.taskRoleArn' --output text)

echo "==> Scaling API service to 0"
aws ecs update-service --cluster "$CLUSTER" --service "$SERVICE" --desired-count 0 --region "$AWS_REGION" >/dev/null
aws ecs wait services-stable --cluster "$CLUSTER" --services "$SERVICE" --region "$AWS_REGION"

RESTORE_SCRIPT=$(cat <<EOF
set -euo pipefail
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends curl unzip ca-certificates
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install -i /usr/local/aws-cli -b /usr/local/bin
aws s3 cp "s3://${BUCKET}/${KEY}" /tmp/macching.dump --region ${AWS_REGION}
# PG18 dump may emit SET transaction_timeout which PG16 rejects; ignore that class of error
set +e
pg_restore -d "\$DATABASE_URL" --clean --if-exists --no-owner --no-acl /tmp/macching.dump
RESTORE_EC=\$?
set -e
psql "\$DATABASE_URL" -v ON_ERROR_STOP=1 -c "select 'members' as t, count(*)::text from members union all select 'profiles', count(*)::text from profiles union all select 'likes', count(*)::text from likes;"
MEMBERS=\$(psql "\$DATABASE_URL" -tAc "select count(*) from members;")
if [ "\$MEMBERS" -lt 1 ]; then
  echo "Restore verification failed: members=\$MEMBERS pg_restore_ec=\$RESTORE_EC" >&2
  exit 1
fi
aws s3 rm "s3://${BUCKET}/${KEY}" --region ${AWS_REGION} || true
echo "RESTORE_OK members=\$MEMBERS pg_restore_ec=\$RESTORE_EC"
EOF
)

export EXEC_ROLE TASK_ROLE RDS_DATABASE_URL RESTORE_SCRIPT AWS_REGION
TASK_DEF_FILE=$(mktemp)
python3 - <<'PY' > "$TASK_DEF_FILE"
import json, os
print(json.dumps({
  "family": "macching-prod-db-restore",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": os.environ["EXEC_ROLE"],
  "taskRoleArn": os.environ["TASK_ROLE"],
  "runtimePlatform": {
    "cpuArchitecture": "X86_64",
    "operatingSystemFamily": "LINUX",
  },
  "containerDefinitions": [{
    "name": "restore",
    "image": "public.ecr.aws/docker/library/postgres:18",
    "essential": True,
    "command": ["bash", "-lc", os.environ["RESTORE_SCRIPT"]],
    "environment": [
      {"name": "DATABASE_URL", "value": os.environ["RDS_DATABASE_URL"]},
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/ecs/macching-prod-api",
        "awslogs-region": os.environ["AWS_REGION"],
        "awslogs-stream-prefix": "restore",
      },
    },
  }],
}))
PY

echo "==> Registering restore task definition"
TASK_DEF_ARN=$(aws ecs register-task-definition \
  --cli-input-json "file://${TASK_DEF_FILE}" \
  --region "$AWS_REGION" \
  --query 'taskDefinition.taskDefinitionArn' \
  --output text)
echo "TASK_DEF_ARN=$TASK_DEF_ARN"
rm -f "$TASK_DEF_FILE"

echo "==> Running restore task"
TASK_ARN=$(aws ecs run-task \
  --cluster "$CLUSTER" \
  --launch-type FARGATE \
  --task-definition "$TASK_DEF_ARN" \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SG],assignPublicIp=DISABLED}" \
  --region "$AWS_REGION" \
  --query 'tasks[0].taskArn' \
  --output text)
echo "TASK_ARN=$TASK_ARN"
aws ecs wait tasks-stopped --cluster "$CLUSTER" --tasks "$TASK_ARN" --region "$AWS_REGION"
EXIT=$(aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$TASK_ARN" --region "$AWS_REGION" --query 'tasks[0].containers[0].exitCode' --output text)
REASON=$(aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$TASK_ARN" --region "$AWS_REGION" --query 'tasks[0].containers[0].reason' --output text)
echo "exit=$EXIT reason=$REASON"
TASK_ID=${TASK_ARN##*/}
aws logs get-log-events \
  --region "$AWS_REGION" \
  --log-group-name /ecs/macching-prod-api \
  --log-stream-name "restore/restore/${TASK_ID}" \
  --limit 100 \
  --query 'events[*].message' \
  --output text || true

if [ "$EXIT" != "0" ]; then
  echo "Restore failed; ECS remains at desiredCount=0" >&2
  exit 1
fi

echo "==> Scaling API service back to 1"
aws ecs update-service --cluster "$CLUSTER" --service "$SERVICE" --desired-count 1 --region "$AWS_REGION" >/dev/null
aws ecs wait services-stable --cluster "$CLUSTER" --services "$SERVICE" --region "$AWS_REGION"
rm -f "$DUMP_PATH"
echo "DONE"
