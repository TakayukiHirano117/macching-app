#!/usr/bin/env bash
# Copy existing top-image objects from Cloudflare R2 to S3 with identical keys.
#
# Required:
#   R2_ACCOUNT_ID
#   R2_ACCESS_KEY_ID
#   R2_SECRET_ACCESS_KEY
#   R2_BUCKET
# Optional:
#   AWS_REGION (default ap-northeast-1)
#   S3_BUCKET (default macching-prod-photos-615299732848)
#   KEYS_FILE  newline-separated object keys (if omitted, copies photos/ prefix)
set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-northeast-1}"
S3_BUCKET="${S3_BUCKET:-macching-prod-photos-615299732848}"

: "${R2_ACCOUNT_ID:?R2_ACCOUNT_ID is required}"
: "${R2_ACCESS_KEY_ID:?R2_ACCESS_KEY_ID is required}"
: "${R2_SECRET_ACCESS_KEY:?R2_SECRET_ACCESS_KEY is required}"
: "${R2_BUCKET:?R2_BUCKET is required}"

ENDPOINT="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION=auto

TMPDIR_COPY=$(mktemp -d)
trap 'rm -rf "$TMPDIR_COPY"' EXIT

if [ -n "${KEYS_FILE:-}" ]; then
  mapfile -t KEYS < "$KEYS_FILE"
else
  echo "==> Listing r2://${R2_BUCKET}/photos/"
  mapfile -t KEYS < <(aws s3 ls "s3://${R2_BUCKET}/photos/" --recursive --endpoint-url "$ENDPOINT" | awk '{print $4}')
fi

if [ "${#KEYS[@]}" -eq 0 ] || [ -z "${KEYS[0]:-}" ]; then
  echo "No keys to copy. Nothing to do."
  exit 0
fi

echo "==> Copying ${#KEYS[@]} objects to s3://${S3_BUCKET} (same keys)"
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION

for key in "${KEYS[@]}"; do
  [ -n "$key" ] || continue
  local_path="${TMPDIR_COPY}/${key}"
  mkdir -p "$(dirname "$local_path")"
  AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID" \
  AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY" \
  AWS_DEFAULT_REGION=auto \
    aws s3 cp "s3://${R2_BUCKET}/${key}" "$local_path" --endpoint-url "$ENDPOINT"
  aws s3 cp "$local_path" "s3://${S3_BUCKET}/${key}" --region "$AWS_REGION"
  echo "copied ${key}"
done

echo "DONE"
