# CLAUDE.md

## Language

- **出力言語**: 日本語
- **コード内の要素**: 英語（変数名・関数名・コメント・コミットメッセージ）
- **ドキュメント**: 見出しは英語、本文は日本語

## Naming

- 現在の状態を表す名前をつける（変更履歴をコメントやメソッド名に含めない）
- 比較表現（"simple", "complex", "easy", "hard" など）を避ける

## Implementation

### Think Before Coding

- 新機能実装前に類似機能を調査し、既存パターンに従う
- 推測でコードを書かず、既存の実装を読んでから書く
- 実装前にトレードオフを明示し、複数のアプローチを比較検討する

### Simplicity First

- 不要な抽象化・ヘルパー関数・ユーティリティを作らない
- 頼まれていない依存関係を追加しない
- 将来の仮定のために設計しない（YAGNI）

### Surgical Changes

- 頼まれた箇所だけを変更し、周辺コードのリファクタを勝手にしない
- 変更していないコードにドキュメント・コメント・型注釈を追加しない
- 既存コードのスタイル・パターンとの一貫性を保つ

### Goal-Driven Execution

- 成功基準を事前に定義し、実装後に検証してから完了とする
- テストを書いていない実装は完了とみなさない

### Code Markers

- 一時的な実装には `// TODO:` を追加
- フォールバック処理には `// FALLBACK:` を追加
- エラーを意図的に握りつぶす場合は `// SILENT:` を追加

## Git

- コミットメッセージに `Co-Authored-By` を付与することを禁止
- コミット時に `-s`（`--signoff`）オプションを使用する

## Workflow

ファイルへの書き込み（docs・plan・コードを問わず）を行う前に、以下のいずれかを選択するようユーザーに確認する。brainstorming など会話のみで完結する段階では確認不要。

1. worktree を使って進める
2. worktree を使わず新規ブランチを作成して進める
3. このブランチ（`<現在のブランチ名>`）で進める ※選択肢を提示する際は実際のブランチ名を表示すること
4. 任意入力（上記以外の方法をユーザーが指定）

### worktree を使う場合の運用ルール

- リポジトリ内の `.claude/worktrees/<branch>` にディレクトリを作成する（例: `platform/.claude/worktrees/feat-login/`）
- 初回利用時は `.git/info/exclude` に `/.claude/worktrees/` を追加しておく（個人ローカルでの除外）
- 新規ブランチは default branch を base に作成する: `git worktree add -b <branch> .claude/worktrees/<branch> origin/<default-branch>`
- 既存ブランチをチェックアウトする場合は `-b` を省略する: `git worktree add .claude/worktrees/<branch> <branch>`
- 同じブランチを複数の worktree で同時にチェックアウトすることはできない（git の制約）
- 作業完了・マージ後は `git worktree remove .claude/worktrees/<branch>` で削除し、必要に応じて `git worktree prune` で残骸を整理する
