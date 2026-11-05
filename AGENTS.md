# AGENTS.md

## Priority

- このファイルのルールは skill・default 動作・既存コード / ドキュメントの前例より優先する
- ルールに反する可能性がある操作は、実行前にユーザーに確認する
- subagent に作業を委譲するときは、このファイルのルールを指示に含める
- skill が完了時に次アクション（提示文言・実行選択肢）を示したら、従う前にこのファイルおよび CLAUDE.md の該当ルールと突き合わせる

## Language

- **出力言語**: 日本語
- **コード・Git**: 英語（変数名・関数名・コメント・コミットメッセージ・PR タイトル）
- **ドキュメント**: 見出しは英語、本文は日本語

## Naming

- 現在の状態を表す名前をつける（変更履歴を名前に含めない）
- 比較表現（"simple", "complex", "easy", "hard" など）を避ける

## Documentation

各媒体は答えるべき問いが異なる。同じ情報を複数の媒体に重複させない。

### Media

- コード → How
- テストコード → What（振る舞い・仕様。テスト名とアサーションで表す）
- コミットログ / PR description → Why（変更の背景・意思決定）
- コードコメント → Why not（他のやり方を採らなかった理由＝制約・落とし穴）
- README / design doc → What（現在の状態・動作）と Why（選んだ理由）

### Content Rules

- "why" には、知らないと現在の構成を理解できない非自明な情報（技術制約・bug 回避・互換性・パフォーマンス特性）を書く（例: "chart v82 の RBAC bug 回避のため X を disable"）
- "when"（変更履歴・現在のタスクや修正への言及。例: "Fixed for X"）は Git history / PR description に、"future"（未来予定）は plan / spec ドキュメントに任せる
- source-of-truth（helmfile / lockfile / Terraform 等）で取得できる値は書かない。設計意図に基づく安定値（retention・mode・識別子 等）は書く
- 1コメントは1行に収める（docstring も書かない）。収まらない非自明な制約は design doc / README に書き、コードには要点と参照を残す

## Instructions

ルール・prompt・subagent への指示に適用する。

- 実行可能または検証可能な文だけを書く（「注意深く」「よく考えて」等は不可）
- 手順には順序と完了条件を明示する

## Implementation

### Think Before Coding

- 新機能の実装前に、類似の既存実装・ヘルパーを grep で探して読み、参照した箇所をチャットに書く。既存で足りるなら新しく書かない
- 設計判断を伴う実装の前に、複数のアプローチとトレードオフをチャットに書く
- ライブラリ・API は、lockfile・実コードで実際のバージョンと signature を確認してから使う
- 非同期処理・background process・リソースを起動する前に「誰が止めるか」「誰が完了を待つか」「エラーはどこへ届くか」に答える。どれかが「誰もいない」なら起動しない
- 依存関係を追加する前にユーザーに確認する

### Code Markers

- 一時的な実装には `// TODO:` を追加
- フォールバック処理には `// FALLBACK:` を追加
- エラーを意図的に握りつぶす場合は `// SILENT:` を追加

### Goal-Driven Execution

- テストを書いていない実装は完了とみなさない
- 完了報告前に、diff で追加・変更したコメントを Content Rules（タスク・修正への言及、複数行）と突き合わせ、満たさないものを削除する
- 報告の主張には検証レベルを明示する: VERIFIED（実行して確認。コマンドと出力を添える）/ REASONED（コード読解による推論）/ ASSUMED（未確認の仮定）。証拠のない成功報告をしない

### Refactoring Checklist

リファクタリングの対象を洗い出すときは、次の観点ごとに確認し、結果を一覧にする。

- 層の向き: ENV・IO・終了コードを扱う場所が、定めた層だけにあるか
- 処理の重複: 同じ規則や処理が複数の場所に書かれていないか
- 定義のずれ: 同じ概念（名前・識別子・値の形式）の判定を入口から出口まで grep し、ある段階で通る値が次の段階で拒否・無視されないか
- 実際の利用: 設定項目・入力・出力・コマンドごとに、利用側のコードと実行履歴で使われているか
- 黙った失敗: エラーにならず何も起きない経路や、対象 0 件で通る検査がないか
- 維持コスト: 機能を残すか決めるときは、実行時間だけでなく、その機能のためだけにあるコードも数える

### Failure Handling

- バグ修正の前に、症状を再現する失敗テストまたはコマンドを作り、その出力をチャットに貼る。再現できない場合は修正せず、確認した事実と仮説をユーザーに報告する
- 原因が ASSUMED のうちは修正コードを書かない

## Git

- コミットには `-s`（`--signoff`）を付ける
- コミットメッセージに `Co-Authored-By` を付けない
- 新規ブランチの初回 push は `git push -u origin HEAD` で行う
- 作業ブランチが一区切りしたら push し、`gh pr create --draft` で Draft PR を作る（Draft 以外で作らない）
- PR・issue を作成する前に、同じ種類のテンプレートを次の順に探し、最初に見つかったものの見出し構成とコメントの指示どおりに本文を書く（`gh pr create --body`・`gh issue create --body` ではテンプレートが自動適用されないため）
  1. リポジトリ（`.github/pull_request_template.md`・`.github/ISSUE_TEMPLATE/` 等）
  2. owner の `.github` リポジトリ（`gh api repos/<owner>/.github/contents/<path>`）
  3. `panicboat/.github`（PR のみ）
- PR・issue のタイトルに Conventional Commits の type を付ける
- PR・issue の本文は 1 文ごとに改行する。箇条書きの項目は要点 1 文だけにし、理由・補足はその下の階層の項目に分ける

## Worktree

- リポジトリ内の `.worktrees/<dir>` にディレクトリを作成する。`<dir>` はブランチ名の `/` を `-` に置換した値（例: `feat/login` → `.worktrees/feat-login/`）
- `.git/info/exclude` に `/.worktrees/` がなければ追加する
- 新規ブランチは default branch を base に作成する: `git worktree add -b <branch> .worktrees/<dir> origin/<default-branch>`
