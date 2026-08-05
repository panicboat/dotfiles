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

1. agmsg-driven-development（実装を Codex に委譲してトークン使用量を分散）
2. subagent-driven-development（Claude subagent で実行）
3. executing-plans（このセッションでインライン実行）

## agmsg

agmsg 系 skill を利用する際の運用ルール。

### Team Selection

セッション内で初めて agmsg 系 skill を利用する前に、team の扱いを以下から選択するようユーザーに確認する
**skill 側の default flow より本ルールを優先する**

事前に以下を実行し、既存 team 名と参加 agent を選択肢に併記する

- `~/.agents/skills/agmsg/scripts/whoami.sh "$(pwd)"` で現在の登録状況と `available_teams` を取得
- `available_teams` の各 team について `~/.agents/skills/agmsg/scripts/team.sh <team>` を実行し、参加 agent 名を取得

1. 新規 team を作成する（team 名と agent 名を指定）
2. 既存 team に join する（team 名と agent 名を指定）
3. 現在登録済みの identity のまま使う（`whoami.sh` の出力を提示）

既存 team は agent 名（agent_id）で member を識別する。agent 名が team 内で unique であれば、同 type 複数の agent を同居させても構わない（例: `planner` (claude-code) + `reviewer` (claude-code) + `impl-a` (codex) + `impl-b` (codex) の 4 名構成）。ただし同一 project から同 type で複数の agent 名を登録すると `whoami.sh` が `multiple=true` を返し、以降 `reset.sh` などで agent 名の明示指定が必須になる — 特別な要件がなければ 1 project 1 type 1 agent 名に留めるのが素直。

確認が完了するまで agmsg の team join・message 送信を行わない。

### Delivery Mode

Team Selection で 1 or 2（`join.sh` を実行する経路）を選んだあとは、delivery mode の選択をユーザーに聞かず `monitor` に設定する。
**skill 側の mode 選択プロンプトより本ルールを優先する**

1. `~/.agents/skills/agmsg/scripts/delivery.sh set monitor <cli-type> "$(pwd)"` を実行する（`<cli-type>` は Claude Code なら `claude-code`、Codex なら `codex`）
2. 標準出力の指示に従う
   - Claude Code: `AGMSG-DIRECTIVE` ブロックに書かれた command で Monitor tool を invoke する（現 session で受信を開始するため。無視すると次回 session 起動まで受信が始まらない）
   - Codex: bridge 反映のため Codex session を再起動する（shim・PATH は準備済み前提）
