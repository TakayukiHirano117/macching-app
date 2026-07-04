# macching-app

マッチングアプリを題材にした学習・実装プロジェクトです。ビジネスルールは API（`onion-hono-sample`）の Domain 層に置き、Web UI（`next-front`）は BFF として API を呼び出します。

## プロジェクト構成

| ディレクトリ | 役割 |
|---|---|
| `onion-hono-sample/` | API。DDD / オニオンアーキテクチャ（Hono + PostgreSQL） |
| `next-front/` | Web UI。Next.js 16 App Router + BFF |

詳細は各サブプロジェクトの README / `AGENTS.md` を参照してください。

`onion-hono-sample` と `next-front` は Git サブモジュールです。親リポジトリ（この `macching-app`）は **各サブモジュールが指す commit SHA だけ** を記録し、実装そのものは子リポジトリ側で行います。

| サブモジュール | リポジトリ | 通常の作業ブランチ |
|---|---|---|
| `onion-hono-sample/` | [onion-hono-sample](https://github.com/TakayukiHirano117/onion-hono-sample) | `develop` |
| `next-front/` | [next-front](https://github.com/TakayukiHirano117/next-front) | `main` |

### 日常の開発（子 → 親）

実装作業は **子リポジトリで行い、親は参照する commit を更新する** のが基本です。

```bash
# 1. 子リポジトリで実装・commit・push
cd onion-hono-sample   # または next-front
git checkout develop   # next-front の場合は main
# ... 実装 ...
git add .
git commit -m "feat: ..."
git push origin develop

# 2. 親リポジトリでサブモジュールのポインタを更新
cd ..
git add onion-hono-sample   # または next-front
git commit -m "chore: onion-hono-sample のサブモジュール参照を更新"
git push origin main
```

ポイント:

- 親の `git add next-front` は **コードのマージではなく、使う commit の固定** です。
- **子を push してから親を push** してください。親だけ先に push すると、他の環境で存在しない commit を参照してしまいます。
- API とフロントを同時に進めた場合は、子それぞれを push したあと、親で両方のポインタをまとめて更新しても構いません。

### 初回 clone と同期（親 → 子）

clone 直後や、他人が親のサブモジュール参照を更新したあとは、**親 → 子** の方向で揃えます。

```bash
# 初回 clone（サブモジュール込み）
git clone --recurse-submodules git@github.com:TakayukiHirano117/macching-app.git

# すでに clone 済みの場合
git submodule update --init --recursive

# 親を pull したあと、記録どおりの commit に揃える
git pull origin main
git submodule update --init --recursive
```

`git submodule update` のあと、作業ブランチに戻す場合:

```bash
cd onion-hono-sample && git checkout develop
cd ../next-front && git checkout main
```

### 状態確認

```bash
# 親が記録している commit と、ローカル checkout 中の commit の差分
git submodule status

# 先頭に + がある場合、親が指す commit とローカルが一致していない
# 親側で git add <submodule> が必要
```

### よくあるつまずき

| 症状 | 原因 | 対処 |
|---|---|---|
| 親は更新したのに中身が古い | `git submodule update` 未実行 | `git submodule update --init --recursive` |
| サブモジュールが detached HEAD | `submodule update` のデフォルト動作 | 各子で `git checkout develop` / `main` |
| clone した人の環境で submodule が空 | `--recurse-submodules` なしで clone | `git submodule update --init --recursive` |
| 親 PR だけマージして CI が壊れる | 子の commit がリモートにない | 先に子リポジトリを push してから親を更新 |

参考: [Git Book - Submodules](https://git-scm.com/book/en/v2/Git-Tools-Submodules)

## フロントエンドの設計方針

`next-front` は [Next.jsの考え方](https://zenn.dev/akfm/books/nextjs-basic-principle)（akfm）の次のプラクティスに沿って実装しています。

- **Container / Presentational**: データ取得は Container（Server Component）、表示は Presentation
- **Route コロケーション**: 各ルート配下の `_containers/<block-name>/` に UI ブロックを配置
- **Server Actions**: データ変更は Server Actions + `revalidatePath` / `redirect`
- **DAL**: 認可付きデータアクセスは `src/shared/dal/` に集約
- **認証**: URL 認可は各 `page.tsx` の `verifySession()`、Cookie 操作は Server Actions のみ
- **フォーム**: Conform + Zod（`@conform-to/react`, `@conform-to/zod`）
- **エラー**: 予測不能エラーは `error.tsx`、バリデーションエラーは Action の戻り値

### ディレクトリ構成（`next-front/src`）

```
app/
├── page.tsx                    # セッション有無で /login または /members へ redirect
├── login/
│   ├── page.tsx
│   ├── loading.tsx, error.tsx
│   └── _containers/login-form/ # index.tsx, container.tsx, presentational.tsx, form.tsx, actions.ts
├── register/
│   └── _containers/register-form/
└── members/
    └── _containers/
        ├── members-header/     # ログアウト
        └── member-list/        # 一覧・いいね

shared/
├── api/    # HTTP トランスポート（server-only）
├── dal/    # データアクセス層（認可・fetch）
├── ui/     # 再利用 UI（PageShell, ErrorFallback など）
└── store/  # Zustand（UI 状態のみ）
```

`page.tsx` は Container の組み立てのみ行い、`_containers/<name>/index.tsx` から Container だけを import します。

### データの流れ

```
page.tsx ── middleware（未ログイン → /login）
    ↓
Container ── DAL（findMembers 等）
    ↓
shared/api ── onion-hono-sample（/api/v1/*）
    ↓
Presentation ── Client 末端（form.tsx, like-button.tsx）
    ↓
Server Actions ── revalidatePath / redirect
```

## 準拠の範囲

コアの設計・ディレクトリ規約は本に準拠しています。次は学習プロジェクトとして意図的に簡略化している点です。

- ログイン会員 ID は BFF の `member_id` Cookie で保持（API に `GET /auth/members/me` は未実装）
- キャッシュ（Cache Components / `use cache`）・Suspense 分割・DataLoader は未導入
- マッチング・プロフィール詳細など未実装 API に対応する画面はない

## 開発の始め方

各サブプロジェクトの `package.json` を正とします。

```bash
# リポジトリ取得（初回のみ）
git clone --recurse-submodules git@github.com:TakayukiHirano117/macching-app.git
cd macching-app

# API（onion-hono-sample/ の README 参照）
cd onion-hono-sample
bun install
# README の手順に従って DB 起動・マイグレーション・dev サーバー起動

# フロント（別ターミナル）
cd next-front
bun install
ONION_API_BASE_URL=http://localhost:3001/api/v1 bun run dev
```

フロントの作業ルールは `next-front/AGENTS.md`、API は `onion-hono-sample/README.md` を参照してください。

## 参照

- [Next.jsの考え方（Zenn）](https://zenn.dev/akfm/books/nextjs-basic-principle)
- [章本文（GitHub）](https://github.com/AkifumiSato/zenn-article/tree/main/books/nextjs-basic-principle)
