# AWS 切替手順（Supabase → RDS / Amplify + ECS）

## 公開 URL

| 用途 | URL |
|---|---|
| Front | https://hirano-ta.com |
| API | https://api.hirano-ta.com/api/v1 |
| Images | https://images.hirano-ta.com |

## 順序

1. `terraform/bootstrap` apply
2. `terraform/environments/prod` apply（API / RDS / S3 / CloudFront）
3. API イメージを ECR push → ECS service 安定確認
4. Amplify: `enable_amplify=true` + GitHub PAT で apply（`API_BASE_URL=https://api.hirano-ta.com/api/v1`）
5. Domain association で `hirano-ta.com` を紐付け、build 成功を確認
6. 保守時間を取りソース DB を `pg_dump` → RDS へ `pg_restore`（`./scripts/run-supabase-to-rds.sh`）
7. 既存画像があれば R2 → S3 へ同一キーでコピー（`./scripts/r2-to-s3-copy.sh`）
8. 画像アップロード（prepare → S3 POST → complete）と CloudFront 表示を確認
9. DNS が意図どおりか確認後、旧 Cloudflare を縮退

## 環境変数

| 変数 | 用途 |
|---|---|
| `API_BASE_URL` | フロント → API（例: `https://api.hirano-ta.com/api/v1`） |
| `TF_VAR_github_access_token` | Amplify の GitHub 接続 |
| `SUPABASE_DATABASE_URL` / `SOURCE_DATABASE_URL` | pg_dump 元 |
| `SKIP_DUMP=1` | 既存 `/tmp/macching.dump` を使う（バージョン不一致時の Docker dump など） |
| `R2_*` | R2 → S3 コピー用（`r2-to-s3-copy.sh`） |

## Amplify

```bash
cd terraform/environments/prod
TF_VAR_enable_amplify=true \
TF_VAR_github_access_token='***' \
terraform apply -var="container_image=$(terraform output -raw ecr_repository_url):<tag>"
```

- App: `macching-prod`（`d1a2brpcbmlcj1`）
- Platform: `WEB_COMPUTE`（Next.js SSR）
- 環境変数: `API_BASE_URL=https://api.hirano-ta.com/api/v1`
- apex `hirano-ta.com` は Route 53 alias → Amplify CloudFront

## pg_dump / pg_restore

```bash
export SUPABASE_DATABASE_URL='postgresql://...'
./scripts/run-supabase-to-rds.sh
```

注意:

- dump ファイルと接続文字列をリポジトリに置かない
- ソースが PostgreSQL 18 で RDS が 16 の場合、Docker の `postgres:18` で dump し、`SKIP_DUMP=1 DUMP_PATH=/tmp/macching.dump` で restore する
- PG18 dump の `SET transaction_timeout` は PG16 で無視される（スクリプトは件数で成否判定）
- 2026-07-26 時点: Supabase `macching-app` を restore したが業務データは 0 件だったため、ローカル `onion_hono` DB（members 5）を restore 元にした

## R2 → S3

```bash
export R2_ACCOUNT_ID=...
export R2_ACCESS_KEY_ID=...
export R2_SECRET_ACCESS_KEY=...
export R2_BUCKET=...
./scripts/r2-to-s3-copy.sh
```

`profiles.top_image_path` が空ならコピー対象なし（現行データは画像パス無し）。

## DATABASE_URL（RDS）

Secrets Manager `macching-prod/database-url` と ECS task definition の `DATABASE_URL` は次を満たす:

1. パスワードを `urlencode` する（特殊文字で node-pg の URL parse が壊れる）
2. `sslmode=no-verify` を付ける（RDS `force_ssl` + node-pg の CA 検証エラー対策）
   - 参考: [node-postgres#2558](https://github.com/brianc/node-postgres/issues/2558)
   - AWS: [Using SSL with PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/PostgreSQL.Concepts.General.SSL.html)

Terraform の `module.rds.database_url` 出力も同様。secret だけ直しても ECS は task definition 埋め込み値を使う点に注意。

## レート制限（コスト増ゼロ）

API はアプリ内インメモリでレート制限する（WAF / Redis / ECS オートスケールは未導入・コスト理由）。

| 対象 | 上限 |
|---|---|
| 全体 | 60 req / 分 / IP |
| signup | 5 req / 15 分 / IP |
| login | 10 req / 15 分 / IP |

超過時は 429。詳細は `onion-hono-sample/.cursor/rules/rate-limit.mdc`。

## CI / 本番リリース（PR → main）

親 `macching-app` の `main` は ruleset `restrict-direct-push` により直プッシュ不可。  
本番 API デプロイは親 `main` への PR マージ（または `workflow_dispatch`）のみ。

| 対象 | トリガー | 仕組み |
|---|---|---|
| API | 親 `main` マージ（paths: `onion-hono-sample`, `deploy-aws.yml`） | [`.github/workflows/deploy-aws.yml`](../.github/workflows/deploy-aws.yml) |
| Front | `next-front` の `main` 更新 | Amplify auto build |
| DB migrate | 手動 | `make rds-migrate` など |

### GitHub Secrets / Variables（親リポジトリ）

| 種別 | 名前 | 例 |
|---|---|---|
| Secret | `AWS_ROLE_ARN` | `arn:aws:iam::615299732848:role/macching-prod-gha-deploy` |
| Variable | `AWS_REGION` | `ap-northeast-1` |
| Variable | `ECR_REPOSITORY` | `macching-prod-api` |
| Variable | `ECS_CLUSTER` | `macching-prod-cluster` |
| Variable | `ECS_SERVICE` | `macching-prod-api` |
| Variable | `ECS_CONTAINER_NAME` | `api` |

OIDC: AWS 側に `token.actions.githubusercontent.com` provider と  
`macching-prod-gha-deploy` ロール（`repo:TakayukiHirano117/macching-app:ref:refs/heads/main` のみ Assume 可）。

Terraform 管理: [`terraform/modules/github_oidc_deploy`](../terraform/modules/github_oidc_deploy/main.tf)  
（手動作成済みロールを state に載せる場合）

```bash
cd terraform/environments/prod
terraform import 'module.github_oidc_deploy.aws_iam_role.gha_deploy' macching-prod-gha-deploy
```

### マージ後の確認

- `curl -sS https://api.hirano-ta.com/api/v1/health` → `{"status":"ok"}`
- Amplify コンソールで Front ビルド成功
- `https://hirano-ta.com/login` → 200
- Amplify の `API_BASE_URL` が `https://api.hirano-ta.com/api/v1` であること

## 検証（実施済み 2026-07-26）

- `curl -sS https://api.hirano-ta.com/api/v1` → 200
- `curl -sS https://api.hirano-ta.com/api/v1/health` → `{"status":"ok"}`
- `https://hirano-ta.com/login` → 200
- Amplify domain status: `AVAILABLE`
- 会員登録 → `/auth/members/login` → prepare → S3 POST (204) → complete → `https://images.hirano-ta.com/photos/...` 200
- S3 バケット直リンクは 403（非公開）

