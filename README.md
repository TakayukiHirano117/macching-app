# macching-app

マッチングアプリを題材にした学習・実装プロジェクトです。ビジネスルールは API（`onion-hono-sample`）の Domain 層に置き、Web UI（`next-front`）は BFF として API を呼び出します。

## できること（現状）

| 区分 | 機能 |
|------|------|
| 認証 | 会員登録、ログイン、ログアウト |
| 会員 | 一覧閲覧、詳細閲覧、いいね送信・取り消し、いいね済み会員一覧 |
| マイページ | 自分のプロフィール表示、トップ画像アップロード |

未実装: チャット、マッチング成立（相互いいね）、画像審査

## プロジェクト構成

| ディレクトリ | 役割 | 詳細 |
|---|---|---|
| [`onion-hono-sample/`](onion-hono-sample/) | API（Hono + PostgreSQL、DDD / オニオンアーキテクチャ） | [README](onion-hono-sample/README.md) / [AGENTS.md](onion-hono-sample/AGENTS.md) |
| [`next-front/`](next-front/) | Web UI（Next.js 16 App Router + BFF） | [AGENTS.md](next-front/AGENTS.md) |

`onion-hono-sample` と `next-front` は Git サブモジュールです。親リポジトリ（この `macching-app`）は **各サブモジュールが指す commit SHA だけ** を記録し、実装そのものは子リポジトリ側で行います。

| サブモジュール | リポジトリ | 通常の作業ブランチ |
|---|---|---|
| `onion-hono-sample/` | [onion-hono-sample](https://github.com/TakayukiHirano117/onion-hono-sample) | `develop` |
| `next-front/` | [next-front](https://github.com/TakayukiHirano117/next-front) | `main` |

## 開発の始め方

各サブプロジェクトの `package.json` を正とします。

### 1. リポジトリ取得

```bash
git clone --recurse-submodules git@github.com:TakayukiHirano117/macching-app.git
cd macching-app
```

すでに clone 済みの場合:

```bash
git submodule update --init --recursive
```

### 2. API 起動

[`onion-hono-sample/README.md`](onion-hono-sample/README.md) の手順に従います。

```bash
cd onion-hono-sample
docker compose up db
bun install
bun run migrate
bun run dev
```

API は `http://localhost:3000/api/v1` で起動します。

### 3. フロント起動（別ターミナル）

Next.js のデフォルトポート（3000）と API が競合するため、フロントは **3001** で起動します。

```bash
cd next-front
bun install
ONION_API_BASE_URL=http://localhost:3000/api/v1 bun run dev -- -p 3001
```

ブラウザで `http://localhost:3001` を開きます。

### 環境変数

| 変数 | 必須 | 説明 |
|------|------|------|
| `ONION_API_BASE_URL` | はい | API のベース URL（例: `http://localhost:3000/api/v1`） |

## アーキテクチャ概要

```
Browser
  ↓
next-front（BFF）
  ├── middleware.ts … session_id Cookie による URL 保護
  ├── Container … DAL 経由でデータ取得（Server Component）
  ├── Presentation … 表示 + Client 末端（form, like-button 等）
  └── Server Actions … データ変更 + revalidatePath / redirect
        ↓
onion-hono-sample（API）
  Presentation → ApplicationService → Domain
                        ↓
                      Infra
```

### フロントエンドの設計方針

[`next-front`](next-front/) は [Next.jsの考え方](https://zenn.dev/akfm/books/nextjs-basic-principle)（akfm）に沿って実装しています。

- **Container / Presentational**: データ取得は Container、表示は Presentation
- **Route コロケーション**: `_containers/<block-name>/` に UI ブロックを配置
- **Server Actions**: データ変更は Server Actions + `revalidatePath` / `redirect`
- **DAL**: 認可付きデータアクセスは `src/shared/dal/` に集約
- **認証**: URL 保護は `src/middleware.ts`（`/login`, `/signup` は公開）。会員 ID は `member_id` Cookie。Cookie 操作は Server Actions のみ
- **フォーム**: Conform + Zod v3

### 画面構成（`next-front/src/app`）

```
app/
├── page.tsx                         # /members へ redirect
├── login/_containers/login-form/
├── signup/_containers/signup-form/
├── members/
│   ├── page.tsx                     # 会員一覧・いいね
│   ├── likes/page.tsx               # いいね済み会員一覧
│   ├── [memberId]/page.tsx          # 会員詳細
│   └── _containers/
│       ├── member-list/             # 一覧 + like-button
│       ├── liked-member-list/
│       ├── member-detail/
│       ├── members-header/
│       └── bottom-nav/
└── mypage/
    └── _containers/
        ├── profile-view/
        └── top-image-upload/

shared/
├── api/    # HTTP トランスポート（server-only）
├── dal/    # データアクセス層
├── ui/     # 再利用 UI
└── store/  # Zustand（UI 状態のみ）
```

### 意図的な簡略化

学習プロジェクトとして、次は未導入または簡略化しています。

- ログイン会員 ID は BFF の `member_id` Cookie で保持（API に `GET /auth/members/me` は未実装）
- キャッシュ（Cache Components / `use cache`）・Suspense 分割は未導入
- TanStack Query は使わず Server Actions + DAL で完結

## Git サブモジュール運用

### 日常の開発（子 → 親）

```bash
# 1. 子リポジトリで実装・commit・push
cd onion-hono-sample   # または next-front
git checkout develop   # next-front の場合は main
git add .
git commit -m "feat: ..."
git push origin develop

# 2. 親リポジトリでサブモジュールのポインタを更新
cd ..
git add onion-hono-sample   # または next-front
git commit -m "chore: onion-hono-sample のサブモジュール参照を更新"
git push origin main
```

- 親の `git add next-front` は **コードのマージではなく、使う commit の固定** です
- **子を push してから親を push** してください

### 同期（親 → 子）

```bash
git pull origin main
git submodule update --init --recursive

# 作業ブランチに戻す
cd onion-hono-sample && git checkout develop
cd ../next-front && git checkout main
```

### 状態確認

```bash
git submodule status
# 先頭に + がある場合、親が指す commit とローカルが一致していない
```

### よくあるつまずき

| 症状 | 対処 |
|---|---|
| 親は更新したのに中身が古い | `git submodule update --init --recursive` |
| サブモジュールが detached HEAD | 各子で `git checkout develop` / `main` |
| clone した人の環境で submodule が空 | `git clone --recurse-submodules` または `git submodule update --init --recursive` |
| 親 PR だけマージして CI が壊れる | 先に子リポジトリを push してから親を更新 |

参考: [Git Book - Submodules](https://git-scm.com/book/en/v2/Git-Tools-Submodules)

## 参照

| 資料 | 内容 |
|------|------|
| [AGENTS.md](AGENTS.md) | ワークスペース全体の作業ルール |
| [onion-hono-sample/README.md](onion-hono-sample/README.md) | API の技術スタック・レイヤー構成 |
| [next-front/AGENTS.md](next-front/AGENTS.md) | フロントの実装規約 |
| [Next.jsの考え方（Zenn）](https://zenn.dev/akfm/books/nextjs-basic-principle) | フロント設計の参照書 |
