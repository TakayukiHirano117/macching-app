---
name: auto-commit
description: 現在の git 差分を分析し Conventional Commits 形式のメッセージでコミットし GitHub へ push する。ユーザーが「コミットして」「自動コミット」「push して」「変更を GitHub に上げて」と依頼したとき、または /auto-commit を指定したときに使用する。
---

# Auto Commit

現在の作業ツリーの差分をもとに、コミットメッセージを生成して GitHub へ push する。

## 前提

- コミットメッセージは `.cursor/rules/conventional-commits.mdc` に従う
- `subject` と `body` は**日本語**で記述する（`type` / `scope` のみ英語 lowerCase）
- ユーザーが明示的に依頼した場合のみ実行する（勝手にコミットしない）
- 秘密情報（`.env`、認証情報など）はコミットしない
- このリポジトリは **親リポジトリ（macching-app）** である。実装は子サブモジュール（`onion-hono-sample` / `next-front`）側で行い、親では主に README・サブモジュール参照の更新を commit する

## サブモジュールの扱い

親リポジトリで `git add next-front` / `git add onion-hono-sample` すると、**子のコード diff ではなく参照 commit SHA の更新** が stage される。

- サブモジュール内の未 commit 変更は **親では commit しない**。先に各子リポジトリで commit / push する
- 親でサブモジュール参照を更新する前に、対象 commit が子リポジトリのリモートに push 済みか確認する
- 子リポジトリの実装作業を commit する依頼の場合は、該当サブモジュールディレクトリに移動してからこのワークフローを実行する

詳細は `README.md` の「サブモジュールでの開発」を参照。

## ワークフロー

### 1. 状態確認（並列実行）

```bash
git status
git diff
git diff --staged
git submodule status
git log --oneline -10
git branch -vv
```

- 変更がなければ空コミットは作らず、ユーザーに報告して終了
- ステージ済みと未ステージの両方を確認する
- サブモジュールに未 commit 変更がある場合は、親 commit 前に子側の対応を促す

### 2. コミットメッセージ作成

差分から以下を判断する:

| 変更内容 | type の目安 |
|----------|-------------|
| 新機能・新エンドポイント | `feat` |
| バグ修正 | `fix` |
| 構造変更・命名変更 | `refactor` |
| ドキュメントのみ | `docs` |
| テストのみ | `test` |
| CI / ビルド設定 | `ci` / `build` |
| サブモジュール参照更新 | `chore` |
| その他雑多 | `chore` |

- `scope` は変更の主な領域（例: `submodule`, `next-front`, `onion-hono-sample`, `cursor`, `readme`）
- `subject` は日本語・末尾に `.` なし
- `body` がある場合も日本語で記述する
- 破壊的変更がある場合は footer に `BREAKING CHANGE:` を記載（説明文は日本語）

メッセージ案をユーザーに提示してからコミットしてもよい。依頼が「自動で」系の場合は提示せず実行してよい。

### 3. ステージ・コミット（順次実行）

```bash
# 関連ファイルのみ add（秘密ファイル・意図しない submodule 変更は除外）
git add <paths>

git commit -m "$(cat <<'EOF'
<type>(<scope>): <日本語の subject>

<日本語の body（任意）>

EOF
)"
```

```bash
git status
```

- フックで失敗した場合は amend せず、修正して新規コミットする
- `--no-verify` は使わない
- `git config` は変更しない

### 4. GitHub へ push

ユーザーが push を明示依頼した場合のみ実行する。

```bash
git push -u origin HEAD
```

- リモート未設定の場合は `-u origin HEAD` で upstream を設定
- `main` / `master` への force push は禁止
- push 前に現在ブランチ名を確認する
- サブモジュール参照を更新した commit を push する前に、子リポジトリ側の commit がリモートにあることを確認する

### 5. 結果報告

以下を報告する:

- コミットメッセージ
- コミットしたファイル概要
- push 先（push した場合: ブランチ名・リモート URL）
- 失敗時はエラー内容と次のアクション

## Git 安全ルール

- 破壊的操作（`push --force`, `reset --hard` など）はユーザー明示指示がない限り禁止
- amend は次の条件をすべて満たす場合のみ: ユーザー明示依頼、直前コミットがこのセッションで作成、未 push
- リモートに push 済みのコミットは amend しない

## 例

**差分**: README にサブモジュール手順を追加

```
docs(readme): サブモジュール開発手順を追記
```

**差分**: 子リポジトリ push 後に親で参照を更新

```
chore(submodule): next-front の参照を更新
```

**差分**: auto-commit スキル追加

```
chore(cursor): auto-commit スキルを追加
```
