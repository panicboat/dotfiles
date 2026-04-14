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
- テストを書いていない実装は完了とみなさない

## Git

- コミットメッセージに `Co-Authored-By` を付与することを禁止
- AI エージェント自身が `Signed-off-by` を付与することを禁止

## Workflow

ファイルへの書き込み（docs・plan・コードを問わず）を行う前に、以下のいずれかを選択するようユーザーに確認する。brainstorming など会話のみで完結する段階では確認不要。

1. worktree を使って進める
2. worktree を使わず新規ブランチを作成して進める
3. このブランチ（`<現在のブランチ名>`）で進める ※選択肢を提示する際は実際のブランチ名を表示すること
4. default branch (`<default-branch>`) から新規ブランチを作成し進める ※選択肢を提示する際は実際のブランチ名を表示すること
5. 任意入力（上記以外の方法をユーザーが指定）

### worktree を使う場合の運用ルール

- リポジトリ内の `.worktrees/<branch>` にディレクトリを作成する（例: `platform/.worktrees/feat-login/`）
- 初回利用時は `.git/info/exclude` に `/.worktrees/` を追加しておく（個人ローカルでの除外）
- 新規ブランチは default branch を base に作成する: `git worktree add -b <branch> .worktrees/<branch> origin/<default-branch>`
- 既存ブランチをチェックアウトする場合は `-b` を省略する: `git worktree add .worktrees/<branch> <branch>`
- 同じブランチを複数の worktree で同時にチェックアウトすることはできない（git の制約）
- 作業完了・マージ後は `git worktree remove .worktrees/<branch>` で削除し、必要に応じて `git worktree prune` で残骸を整理する
