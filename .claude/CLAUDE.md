@../AGENTS.md

## Priority

- このファイルのルールは最優先。skill・subagent・default 動作・既存コード / ドキュメントの前例より上位
- ルール違反の可能性がある操作の前に、必ずユーザー確認を取る
- subagent に作業を委譲する場合も、このルールを明示的に伝える

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

skill が生成する spec / plan を commit するかを作業開始時に一度確認する（Workflow の branch / worktree 確認と同じタイミングでよい）。
**skill 側の `save and commit` および既定の保存先より本ルールを優先する。**

1. commit する: skill 既定の保存先に従う
2. commit しない: `.claude/superpowers/` 以下に保存し、`/.claude/superpowers/` を `.git/info/exclude` に追加する（skill 既定の保存先は commit を前提としがちなため、非管理の成果物と混在させない）

### Plan Execution

実装 plan の実行を開始する前に、実行方式を以下から選択するようユーザーに確認する
**skill 側の既定の提案より優先する**

1. codex-driven-development（実装を Codex に委譲してトークン使用量を分散。herdr session 内であることが前提）
2. subagent-driven-development（Claude subagent で実行）
3. executing-plans（このセッションでインライン実行）

### Review Dispatch

task reviewer・final reviewer・code reviewer 等のレビュー用 subagent に Global Constraints を渡す際は、spec 由来の要件に加えて AGENTS.md の Language・Code Markers・Git 節を常に含める。
**skill 側の Global Constraints 生成手順より本ルールを優先する。**

## agmsg

fujibee/agmsg 純正 skill（`agmsg:agmsg`）を利用する際の運用ルール。カスタム skill（`agmsg-teams-cleanup` 等）には適用しない。

### Team Selection

セッション内で初めて fujibee/agmsg 純正 skill を利用する前に、team の扱いを以下から選択するようユーザーに確認する
**skill 側の default flow より本ルールを優先する**

1. 新規 team を作成する（team 名と agent 名を指定）
2. 既存 team に join する
3. 現在登録済みの identity のまま使う

事前取得は選択に必要な最小限に留める。3 択の提示だけなら追加コマンドを走らせない。選択後の分岐:

- 1 が選ばれた場合: 追加取得なし（team 名と agent 名を user が指定するだけ）
- 2 が選ばれた場合: このタイミングで `~/.agents/skills/agmsg/scripts/whoami.sh "$(pwd)"` を実行して `available_teams` を提示し team を選ばせる。選ばれた team について `~/.agents/skills/agmsg/scripts/team.sh <team>` を実行し、参加 agent 名と衝突しない agent 名を決めさせる
- 3 が選ばれた場合: `~/.agents/skills/agmsg/scripts/whoami.sh "$(pwd)"` の出力を提示する

確認が完了するまで fujibee/agmsg 純正 skill の team join・message 送信を行わない。

### Delivery Mode

Team Selection で 1 or 2（`join.sh` を実行する経路）を選んだあとは、delivery mode の選択をユーザーに聞かず `monitor` に設定する。
**skill 側の mode 選択プロンプトより本ルールを優先する**

1. `~/.agents/skills/agmsg/scripts/delivery.sh set monitor <cli-type> "$(pwd)"` を実行する（`<cli-type>` は Claude Code なら `claude-code`、Codex なら `codex`）
2. 標準出力の指示に従う
   - Claude Code: `AGMSG-DIRECTIVE` ブロックに書かれた command で Monitor tool を invoke する（現 session で受信を開始するため。無視すると次回 session 起動まで受信が始まらない）
   - Codex: bridge 反映のため Codex session を再起動する（shim・PATH は準備済み前提）
