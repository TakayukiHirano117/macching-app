# macching-app

マッチングアプリを題材にした学習・実装プロジェクトです。ビジネスルールは API（`onion-hono-sample`）の Domain 層に置き、Web UI（`next-front`）は BFF として API を呼び出します。

## プロジェクト構成

| ディレクトリ | 役割 |
|---|---|
| `onion-hono-sample/` | API。DDD / オニオンアーキテクチャ（Hono + PostgreSQL） |
| `next-front/` | Web UI。Next.js 16 App Router + BFF |

詳細は各サブプロジェクトの README / `AGENTS.md` を参照してください。

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
# API（onion-hono-sample/ の README 参照）
# フロント
cd next-front
bun install
ONION_API_BASE_URL=http://localhost:3001/api/v1 bun run dev
```

フロントの作業ルールは `next-front/AGENTS.md`、API は `onion-hono-sample/README.md` を参照してください。

## 参照

- [Next.jsの考え方（Zenn）](https://zenn.dev/akfm/books/nextjs-basic-principle)
- [章本文（GitHub）](https://github.com/AkifumiSato/zenn-article/tree/main/books/nextjs-basic-principle)
