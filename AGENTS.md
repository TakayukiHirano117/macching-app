# AGENTS.md

## Purpose

このワークスペースは、マッチングアプリを題材にした学習・実装プロジェクトです。
ユーザー、プロフィール、いいね、マッチング、認証といったアプリの中核概念を、API と Web UI に分けて育てます。
ルートのこのファイルは、変わりにくい前提と参照先だけを書く入口です。
実装の詳細やコマンドは、必ず対象サブプロジェクト側のドキュメントと `package.json` を確認してください。

## Project Shape

- `onion-hono-sample/`: API。DDD / オニオンアーキテクチャで、マッチングアプリのビジネスルールを表現する場所。
- `next-front/`: Web UI。ユーザー体験、画面、入力、API 呼び出しを表現する場所。
- ルートは両者の関係を説明するだけに留め、実装判断は対象ディレクトリに近いドキュメントを優先します。
- サブディレクトリの `AGENTS.md` は、その配下で作業するときのより具体的な指示として扱います。

## Stable Product Model

- 会員は、プロフィールを持ち、他の会員に「いいね」を送れます。
- 双方向の関心は、将来的にマッチングとして扱う前提です。
- 認証は、会員本人として操作するための横断関心事です。
- アプリ固有の制約は API の Domain 層に置き、フロントはそれを重複実装しません。
- UI は Domain の用語を尊重しつつ、ユーザーに伝わる表現へ翻訳します。

## Canonical References

- リポジトリ概要: `README.md`
- API の現状説明: `onion-hono-sample/README.md`
- API の作業ルール: `onion-hono-sample/AGENTS.md`
- API の層構造ルール: `onion-hono-sample/.cursor/rules/ddd-onion-architecture.mdc`
- API の実際の入口: `onion-hono-sample/src/Cmd/bun.ts`（ローカル）、`onion-hono-sample/src/Cmd/worker.ts`（Cloudflare Workers）
- Frontend の作業ルール: `next-front/AGENTS.md`
- Frontend の実装前確認: `next-front/node_modules/next/dist/docs/`

## Working Rules

- 変更前に、対象ディレクトリに最も近い `AGENTS.md` と関連 README を読む。
- 仕様は推測しない。実装済みの Controller、ApplicationService、Domain、README を根拠にする。
- ビジネスルールを追加・変更する場合は、API の Domain 層を起点に考える。
- `as any` は使わない。型を壊すより、型設計か境界の置き方を見直す。
- 本質的な実装と関係ないリファクタ、整形、ファイル移動を混ぜない。
- サブプロジェクト横断の設計変更、認証方式変更、DB スキーマ変更は事前に確認する。

## Verification

- 実行コマンドは各サブプロジェクトの `package.json` を正とする。
- API 変更では、影響範囲に応じて test / lint / format check を行う。
- Domain の振る舞いを変えたら、対応するテストを追加または更新する。
- Frontend 変更では、Next.js 16 のローカル docs を確認してから lint / build を行う。
- 検証できなかった場合は、何を実行できなかったかと理由を報告する。
