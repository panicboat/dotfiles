# CLAUDE.md

## Priority

- このファイルのルールは最優先。skill・subagent・default 動作・既存コード / ドキュメントの前例より上位
- ルール違反の可能性がある操作の前に、必ずユーザー確認を取る
- subagent に作業を委譲する場合も、このルールを明示的に伝える

## Judgment

- 影響評価は system 全体で行う（一貫性・他コンポーネントへの影響まで見る）
- 目先が動くかではなく、保守性・将来の技術的負債への影響まで評価して選ぶ（後で高くつく選択を避ける）
- 結論を確定する前に別の視点から反証を試み、誤りが見つかったら sunk cost に流されず訂正する

## Language

- **出力言語**: 日本語
- **コード内の要素**: 英語（変数名・関数名・コメント・コミットメッセージ）
- **ドキュメント**: 見出しは英語、本文は日本語

## Naming

- 現在の状態を表す名前をつける（変更履歴を名前に含めない）
- 比較表現（"simple", "complex", "easy", "hard" など）を避ける

## Documentation

各媒体は答えるべき問いが異なる。同じ情報を複数の媒体に重複させない。

### Media

- コード → How（どう実現するか。実装そのものが語る）
- テストコード → What（何をすべきか＝振る舞い・仕様。テスト名とアサーションで表す）
- コミットログ / PR description → Why（なぜこの変更をしたか＝背景・意思決定）
- コードコメント → Why not（なぜ "他のやり方" を採らなかったか＝制約・落とし穴。自明な "what" は書かない）
- README / design doc → What（現在の状態・動作）と Why（選んだ理由）

### Content Rules

- "why" には非自明な技術制約・bug 回避・互換性・パフォーマンス特性など、それを知らないと現在の構成を理解できない情報を含める（例: "chart v82 の RBAC bug 回避のため X を disable"）
- "when"（変更履歴）は Git history に、"future"（未来予定）は plan / spec ドキュメントに任せる
- source-of-truth（helmfile / lockfile / Terraform 等）で取得できる値は書かない。設計意図に基づく安定値（retention・mode・識別子 等）は書く

## Instructions

ルール・prompt・subagent への指示に適用する。

- 実行可能または検証可能な文だけを書く（「注意深く」「よく考えて」等は不可）
- 手順には順序と完了条件を明示する

## Workflow

ファイルへの書き込み（docs・plan・コードを問わず）を行う前に、以下のいずれかを選択するようユーザーに確認する。brainstorming など会話のみで完結する段階では確認不要。

1. worktree を使って進める
2. worktree を使わず新規ブランチを作成して進める
3. このブランチ（`<現在のブランチ名>`）で進める ※選択肢を提示する際は実際のブランチ名を表示すること
4. 任意入力（上記以外の方法をユーザーが指定）

例外: 実装 plan 実行のために dispatch された実装担当（task brief 等の明示的な作業指示に従い、作業対象の worktree/branch が既に確定した状態で単一タスクを実装する場合）は、この確認を行わず確定済みのブランチで in-place に作業する。ブランチ・worktree・実行方式を問い直さない。

### Worktree Operations

- リポジトリ内の `.claude/worktrees/<dir>` にディレクトリを作成する。`<dir>` はブランチ名の `/` を `-` に置換した値（例: `feat/login` → `.claude/worktrees/feat-login/`）
- 初回利用時は `.git/info/exclude` に `/.claude/worktrees/` を追加しておく（個人ローカルでの除外）
- 新規ブランチは default branch を base に作成する: `git worktree add -b <branch> .claude/worktrees/<dir> origin/<default-branch>`
- 作業完了・マージ後は `git worktree remove .claude/worktrees/<branch>` で削除し、必要に応じて `git worktree prune` で残骸を整理する

## Superpowers

superpowers 系 skill を利用する際の運用ルール。

### Artifacts

skill が生成する spec / plan を commit するかを作業開始時に一度確認する（Workflow の branch / worktree 確認と同じタイミングでよい）。skill 側の `save and commit` および既定の保存先より本ルールを優先する。

1. commit する: skill 既定の保存先に従う
2. commit しない: `.claude/superpowers/` 以下に保存し、`/.claude/superpowers/` を `.git/info/exclude` に追加する（skill 既定の保存先は commit を前提としがちなため、非管理の成果物と混在させない）

### Plan Execution

実装 plan の実行を開始する前に、実行方式を以下から選択するようユーザーに確認する（skill 側の既定の提案より優先する）

1. agmsg-driven-development（実装を Codex に委譲してトークン使用量を分散）
2. subagent-driven-development（Claude subagent で実行）
3. executing-plans（このセッションでインライン実行）

## Implementation

### Think Before Coding

- 新機能実装前に類似機能・既存実装を読んでからパターンに従う（推測で書かない）
- 実装前にトレードオフを明示し、複数のアプローチを比較検討する
- ライブラリ・API の使い方を記憶で書かない。lockfile・実コードで実際のバージョンと signature を確認してから使う
- 非同期処理・background process・リソースを起動する前に「誰が止めるか」「誰が完了を待つか」「エラーはどこへ届くか」に答える。どれかが「誰もいない」なら起動しない

### Simplicity First

- ヘルパー・抽象化を書く前に既存実装を grep で検索する。既存で足りるなら再発明せず、将来の仮定のためには作らない（YAGNI）
- 頼まれていない依存関係を追加しない

### Surgical Changes

- 頼まれた箇所だけを変更し、周辺コードのリファクタを勝手にしない
- 変更していないコードにドキュメント・コメント・型注釈を追加しない
- 既存コードのスタイル・パターンとの一貫性を保つ

### Code Markers

- 一時的な実装には `// TODO:` を追加
- フォールバック処理には `// FALLBACK:` を追加
- エラーを意図的に握りつぶす場合は `// SILENT:` を追加

### Goal-Driven Execution

- 成功基準を事前に定義し、実装後に検証してから完了とする
- テストを書いていない実装は完了とみなさない
- 報告の主張には検証レベルを明示する: VERIFIED（実行して確認。コマンドと出力を添える）/ REASONED（コード読解による推論）/ ASSUMED（未確認の仮定）。証拠のない成功報告をしない

### Failure Handling

- 修正の前に因果を言語化する。「X が Y を引き起こす。なぜなら Z」と言えないうちは相関にすぎない。Z を特定してから直す
- 同種の失敗が繰り返されたら、「症状 → ありがちな間違い → 正しい一手」の形式で CLAUDE.md / skill への追記を提案する

## Git

- コミット時に `-s`（`--signoff`）オプションを使用する
- コミットメッセージに `Co-Authored-By` を付与することを禁止
- 新規ブランチの初回 push は必ず `git push -u origin HEAD` でトラッキングを設定する
- 作業ブランチが一区切りしたら push し、**Draft PR を作成して可視化する**（`gh pr create --draft`。Draft 以外で作らない）
- PR のタイトル（件名）は英語で記述する
