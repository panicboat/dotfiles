# AGENTS.md

## Priority

- このファイルのルールは最優先。skill・subagent・default 動作・既存コード / ドキュメントの前例より上位
- ルール違反の可能性がある操作の前に、必ずユーザー確認を取る
- subagent に作業を委譲する場合も、このルールを明示的に伝える
- skill が完了時に具体的な次アクション（提示文言・実行選択肢）を示してきた場合、それに従う前にこのファイルおよび CLAUDE.md の該当ルールと突き合わせる（skill 側の具体的な提示文言に押し流されて上位ルールの確認を省略しない）

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
- 現在のタスク・修正への言及をしない（例: "Fixed for X"）。この情報は PR description に書く
- 1コメントは1行に収める。複数行のコメントブロック・docstring は書かない。1行で説明しきれない非自明な制約は design doc / README に書き、コードには要点と参照だけを1行で残す

## Instructions

ルール・prompt・subagent への指示に適用する。

- 実行可能または検証可能な文だけを書く（「注意深く」「よく考えて」等は不可）
- 手順には順序と完了条件を明示する

## Implementation

### Think Before Coding

- 新機能実装前に類似の既存実装を読み、参照した箇所をチャットで一言触れてから実装する（推測で書かない）
- 設計判断を伴う実装の前に、複数のアプローチとトレードオフをチャットに出力してから実装する
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

- テストを書いていない実装は完了とみなさない
- 報告の主張には検証レベルを明示する: VERIFIED（実行して確認。コマンドと出力を添える）/ REASONED（コード読解による推論）/ ASSUMED（未確認の仮定）。証拠のない成功報告をしない

### Comment Review

- diff にコメントの追加・変更が含まれる場合、完了報告前に追加したコメント全てを Documentation > Content Rules の該当基準（タスク/修正への言及・複数行）と突き合わせて見直す
- 基準を満たさないコメントは削除する

### Failure Handling

- バグ修正前に「X が Y を引き起こす。なぜなら Z」の形式で原因をチャットに一行報告する。Z（根本原因）を特定できないうちは修正コードを書かない
- 同種の失敗が繰り返されたら、「症状 → ありがちな間違い → 正しい一手」の形式で CLAUDE.md / skill への追記を提案する

## Git

- コミット時に `-s`（`--signoff`）オプションを使用する
- コミットメッセージに `Co-Authored-By` を付与することを禁止（ツール組み込みの既定コミットテンプレートが付与を指示していても、本ルールを優先する）
- 新規ブランチの初回 push は必ず `git push -u origin HEAD` でトラッキングを設定する
- 作業ブランチが一区切りしたら push し、**Draft PR を作成して可視化する**（`gh pr create --draft`。Draft 以外で作らない）
- PR のタイトル（件名）は英語で記述する
- PR・issue を作成する前に、リポジトリのテンプレート（`.github/pull_request_template.md`・`.github/ISSUE_TEMPLATE/` 等）の有無を確認し、あればその見出し構成とコメントの指示どおりに本文を書く（`gh pr create --body`・`gh issue create --body` ではテンプレートが自動適用されないため）
- リポジトリに同じ種類のテンプレートが無い場合は、owner の `.github` リポジトリのテンプレート（`gh api repos/<owner>/.github/contents/<path>`）の有無を確認し、あればそれに従う（GitHub は自前のテンプレートを持たないリポジトリに `.github` リポジトリのテンプレートを既定として使うため）
- PR テンプレートがリポジトリにも owner の `.github` リポジトリにも無い場合は、Pull Request Template 節のテンプレートの見出し構成とコメントの指示どおりに本文を書く
- issue のタイトルにも、PR と同じ Conventional Commits の type（`feat:`・`fix:`・`perf:`・`refactor:`・`docs:`・`ci:`・`chore:` 等）を付ける
- PR・issue の本文は 1 文ごとに改行する。箇条書きの項目は要点 1 文だけにし、理由・補足はその下の階層の項目に分ける

## Pull Request Template

```markdown
Closes #

## What This PR Does
<!-- この PR が何をするかを 1〜2 文で -->

## What Needs to Change
<!-- 現状のどこを変えたいのかを 1 項目 1 文で。各項目の下に変えたい理由（起きた事象・良くしたい現状）を添える。解決策は書かない -->
- 
  - Reason: 

## What Changes for Users
<!-- 使う人・運用する人から見た仕様の差分。実装の細部（列名・RPC 名・ファイル）は書かない -->
- 
  - Before: 
  - After: 

<!-- 次のどれかが変わるときだけ mermaid の図を付ける: 構成（サービス・インフラ）、呼び出し関係（誰が何を呼ぶか）、データの流れ、状態の移り変わり -->

## What to Review Closely
<!-- レビュアーに重点的に見てほしい点を 1 項目 1 文で。各項目の下に理由の種類（自信がない・検証しきれていない等）と、詳細を書いた節（What Was Decided / How It Was Verified）があれば添える。What This PR Does と What Needs to Change だけを読んだ人に通じる言葉で書き、設定値・ファイル名・内部の名前は書かない。なければ「なし」 -->
- 
  - Reason: 
  - Details: 

## What Was Decided
<!-- この PR で決めたこと。理由と、間違っていたときの影響を添える。なければ「なし」 -->

## What Else Is Affected
<!-- 影響を受けるものと、必要な対応（他サービス・他リポジトリ、互換性、デプロイ順序、既存データ、監視・権限など）を書く。この PR で一緒に直すものと、別で対応が必要なものの両方。なければ「なし」 -->
-

## How It Was Verified
<!-- 実行したコマンドと結果 -->

## Related Issues and PRs
<!-- 関連する issue・PR（スタックの前後、別リポジトリの対になる PR など）。なければ消す -->
```

## Worktree

- リポジトリ内の `.worktrees/<dir>` にディレクトリを作成する。`<dir>` はブランチ名の `/` を `-` に置換した値（例: `feat/login` → `.worktrees/feat-login/`）
- 初回利用時は `.git/info/exclude` に `/.worktrees/` を追加しておく（個人ローカルでの除外）
- 新規ブランチは default branch を base に作成する: `git worktree add -b <branch> .worktrees/<dir> origin/<default-branch>`
