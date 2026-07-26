.PHONY: help install setup submodule submodule-status submodule-sync \
	submodule-bump submodule-bump-api submodule-bump-front submodule-commit \
	api-up api-up-d api-down api-logs api-restart api-migrate api-test api-lint api-shell api-db-shell \
	front-dev front-lint front-build \
	tf-bootstrap tf-prod-plan tf-prod-apply ecr-push \
	rds-migrate supabase-to-rds r2-to-s3 \
	lint test

API_DIR := onion-hono-sample
FRONT_DIR := next-front
API_BRANCH := develop
FRONT_BRANCH := main
API_URL := http://localhost:3000/api/v1
FRONT_PORT := 3001

.DEFAULT_GOAL := help

help: ## 利用可能なコマンド一覧を表示
	@echo "macching-app — よく使う開発コマンド"
	@echo ""
	@grep -E '^[a-zA-Z0-9_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "API 詳細: make -C $(API_DIR) help"

# --- 全体 ---

submodule: ## サブモジュールを取得・更新
	git submodule update --init --recursive

submodule-status: ## サブモジュールの状態を表示
	@git submodule status
	@echo ""
	@echo "API ($(API_BRANCH)):   $$(git -C $(API_DIR) rev-parse --short HEAD 2>/dev/null || echo '未取得') — $$(git -C $(API_DIR) log -1 --format='%s' 2>/dev/null || echo '')"
	@echo "Front ($(FRONT_BRANCH)): $$(git -C $(FRONT_DIR) rev-parse --short HEAD 2>/dev/null || echo '未取得') — $$(git -C $(FRONT_DIR) log -1 --format='%s' 2>/dev/null || echo '')"

submodule-sync: ## 親を pull しサブモジュールを同期（親 → 子）
	git pull origin $$(git branch --show-current)
	git submodule update --init --recursive
	@echo ""
	@echo "作業ブランチに戻す例:"
	@echo "  cd $(API_DIR) && git checkout $(API_BRANCH)"
	@echo "  cd $(FRONT_DIR) && git checkout $(FRONT_BRANCH)"

submodule-bump-api: ## onion-hono-sample の最新 develop を親に反映（git add まで）
	cd $(API_DIR) && git fetch origin && git checkout $(API_BRANCH) && git pull --ff-only origin $(API_BRANCH)
	git add $(API_DIR)
	@echo "ステージ済み: $(API_DIR) → $$(git -C $(API_DIR) rev-parse --short HEAD)"
	@echo "commit: make submodule-commit MSG='chore: onion-hono-sample の参照を更新'"

submodule-bump-front: ## next-front の最新 main を親に反映（git add まで）
	cd $(FRONT_DIR) && git fetch origin && git checkout $(FRONT_BRANCH) && git pull --ff-only origin $(FRONT_BRANCH)
	git add $(FRONT_DIR)
	@echo "ステージ済み: $(FRONT_DIR) → $$(git -C $(FRONT_DIR) rev-parse --short HEAD)"
	@echo "commit: make submodule-commit MSG='chore: next-front の参照を更新'"

submodule-bump: submodule-bump-api submodule-bump-front ## 両サブモジュールの最新を親に反映（git add まで）

submodule-commit: ## ステージ済みのサブモジュール参照を commit（MSG= 必須）
	@test -n "$(MSG)" || (echo "エラー: MSG= を指定してください。例: make submodule-commit MSG='chore: サブモジュール参照を更新'"; exit 1)
	git commit -m "$(MSG)"

install: submodule ## 両プロジェクトの依存関係をインストール
	cd $(API_DIR) && $(MAKE) install
	cd $(FRONT_DIR) && bun install

setup: install ## 初回セットアップ（install + Docker build + migrate）
	$(MAKE) -C $(API_DIR) setup

lint: api-lint front-lint ## API + フロントの lint

test: api-test ## テスト（現状 API のみ）

# --- API（Docker Compose）---

api-up: ## API / DB / Mail を起動（フォアグラウンド）
	$(MAKE) -C $(API_DIR) up

api-up-d: ## API / DB / Mail を起動（バックグラウンド）
	$(MAKE) -C $(API_DIR) up-d

api-down: ## API コンテナを停止
	$(MAKE) -C $(API_DIR) down

api-logs: ## API ログを追跡
	$(MAKE) -C $(API_DIR) logs

api-restart: ## API コンテナを再起動
	$(MAKE) -C $(API_DIR) restart

api-migrate: ## ローカル DB へ migration
	$(MAKE) -C $(API_DIR) migrate

api-test: ## API テスト
	$(MAKE) -C $(API_DIR) test

api-lint: ## API lint
	$(MAKE) -C $(API_DIR) lint

api-shell: ## API コンテナに入る
	$(MAKE) -C $(API_DIR) shell

api-db-shell: ## PostgreSQL に接続
	$(MAKE) -C $(API_DIR) db-shell

# --- フロント ---

front-dev: ## フロント dev サーバー（:$(FRONT_PORT)）
	cd $(FRONT_DIR) && API_BASE_URL=$(API_URL) bun run dev -- -p $(FRONT_PORT)

front-lint: ## フロント lint
	cd $(FRONT_DIR) && bun run lint

front-build: ## フロント production build
	cd $(FRONT_DIR) && bun run build

# --- AWS ---

tf-bootstrap: ## Terraform remote state bucket を作成
	cd terraform/bootstrap && terraform init && terraform apply

tf-prod-plan: ## prod Terraform plan
	cd terraform/environments/prod && terraform init -input=false && terraform plan

tf-prod-apply: ## prod Terraform apply
	cd terraform/environments/prod && terraform apply

ecr-push: ## API イメージを ECR へ push（ECR_REPOSITORY_URI / AWS_REGION 必須）
	$(API_DIR)/scripts/ecr-push.sh $(TAG)

rds-migrate: ## 本番 RDS へ ECS one-off で migration
	./scripts/run-rds-migrate.sh

supabase-to-rds: ## Supabase/ソース DB を pg_dump → RDS へ pg_restore（SUPABASE_DATABASE_URL 必須）
	./scripts/run-supabase-to-rds.sh

r2-to-s3: ## R2 画像を S3 へ同一キーでコピー（R2_* 必須）
	./scripts/r2-to-s3-copy.sh

# --- ショートカット（api-* と同義）---

up: api-up ## api-up のエイリアス
up-d: api-up-d ## api-up-d のエイリアス
down: api-down ## api-down のエイリアス
migrate: api-migrate ## api-migrate のエイリアス
dev: front-dev ## front-dev のエイリアス
