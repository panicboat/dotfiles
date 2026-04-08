# CLAUDE.md

## Language

- **出力言語**: 日本語
- **コード内の要素**: 英語（変数名・関数名・コメント・コミットメッセージ）
- **ドキュメント**: 見出しは英語、本文は日本語

## Naming

- 現在の状態を表す名前をつける（変更履歴をコメントやメソッド名に含めない）
- 比較表現（"simple", "complex", "easy", "hard" など）を避ける

## Implementation

- 新機能実装前に類似機能を調査し、既存パターンに従う
- 推測でコードを書かず、既存の実装を読んでから書く
- 既存コードのスタイル・パターンとの一貫性を保つ
- 一時的な実装には `// TODO:` を追加
- フォールバック処理には `// FALLBACK:` を追加
- エラーを意図的に握りつぶす場合は `// SILENT:` を追加

## Testing

- 機能追加・変更時は対応するテストもセットで作成
- カバレッジは 100% 不要だが、現実的な範囲で高く保つ

## Workflow

- 実装に入る前に必ず「worktree を使うか」をユーザーに確認する
- worktree を使う場合の運用ルール:
  - リポジトリと同階層に `<repo>-<branch>` の形式でディレクトリを作成する（例: `panicboat/` に対して `panicboat-feat-login/`）
  - 新規ブランチは default branch を base に作成する: `git worktree add -b <branch> ../<repo>-<branch> origin/<default-branch>`
  - 既存ブランチをチェックアウトする場合は `-b` を省略する: `git worktree add ../<repo>-<branch> <branch>`
  - 同じブランチを複数の worktree で同時にチェックアウトすることはできない（git の制約）
  - 作業完了・マージ後は `git worktree remove <path>` で速やかに削除し、必要に応じて `git worktree prune` で残骸を整理する
- worktree を使わない場合で、現在のブランチが default branch のときは、変更前に新規ブランチを作成するかユーザーに確認する
