# Terraform — macching-app AWS

東京リージョン (`ap-northeast-1`) に本番基盤を作る。

## 構成

| リソース | 用途 |
|---|---|
| VPC / NAT×1 | 公開 ALB + private ECS/RDS |
| ECR | API コンテナイメージ |
| ECS Fargate (1 task) | Hono API |
| ALB + ACM | `api.hirano-ta.com` |
| RDS PostgreSQL (`db.t4g.micro`, Single-AZ) | 本番 DB |
| S3 + CloudFront OAC | `images.hirano-ta.com` |
| Amplify Hosting (WEB_COMPUTE) | `hirano-ta.com` |
| Secrets Manager | `DATABASE_URL` |
| IAM `macching-prod-gha-deploy` | 親 repo GitHub Actions（OIDC）から ECR/ECS デプロイ |

## 前提

- AWS CLI 認証済み (`aws sts get-caller-identity`)
- Route 53 hosted zone `hirano-ta.com` が同一アカウントにある
- Amplify 用 GitHub PAT（`repo` スコープ）
- Docker / Terraform >= 1.5

## 1. Bootstrap（remote state）

```bash
cd terraform/bootstrap
terraform init
terraform plan
terraform apply
```

## 2. Prod apply

```bash
cd terraform/environments/prod
cp terraform.tfvars.example terraform.tfvars
# github_access_token を設定

terraform init
terraform plan
terraform apply
```

初回は ECR にイメージが無いため、先に ECR だけ作成して push してから ECS を安定させる。

```bash
# ECR 作成後
cd ../../..
export AWS_REGION=ap-northeast-1
export ECR_REPOSITORY_URI="$(terraform -chdir=terraform/environments/prod output -raw ecr_repository_url)"
./onion-hono-sample/scripts/ecr-push.sh "$(git -C onion-hono-sample rev-parse --short HEAD)"

# 必要なら container_image を指定して再 apply
terraform -chdir=terraform/environments/prod apply \
  -var="container_image=${ECR_REPOSITORY_URI}:$(git -C onion-hono-sample rev-parse --short HEAD)"
```

## 3. DB migration / データ移行

```bash
# Secrets Manager の DATABASE_URL を ECS one-off task または一時踏み台から使う
# Supabase → RDS:
#   pg_dump "$SUPABASE_DATABASE_URL" -Fc -f dump.dump
#   pg_restore -d "$RDS_DATABASE_URL" --no-owner --no-acl dump.dump
```

詳細手順はルート `README.md` の移行節を参照。

## 4. 破壊的操作

`terraform destroy` は RDS・S3・DNS を消す。本番では最終確認後のみ実行。state bucket は `prevent_destroy`。

## Outputs

- `ecr_repository_url`
- `ecs_cluster_name` / `ecs_service_name`
- `api_url` / `front_url` / `images_public_base_url`
- `amplify_app_id`
- `database_secret_arn`
- `github_actions_deploy_role_arn`

## GitHub Actions OIDC

親 `main` からのデプロイ用ロールは `module.github_oidc_deploy`。  
すでに CLI で作成済みの場合は import してから apply:

```bash
terraform import 'module.github_oidc_deploy.aws_iam_role.gha_deploy' macching-prod-gha-deploy
```

ロール ARN を親リポジトリ Secret `AWS_ROLE_ARN` に設定する（手順は `docs/aws-cutover.md`）。
