# agmsg-driven-development Design

## Goal

superpowers の subagent-driven-development (SDD) の実行フェーズを、fujibee/agmsg 経由の Codex に委譲する skill `agmsg-driven-development` を作る。

目的はトークン使用量の分散。最もトークンを消費する実装作業を Codex（OpenAI 側クォータ）へ移し、Claude（Anthropic 側クォータ）には意図の汲み取り——plan 管理・task brief 作成・レビュー裁定——を残す。

## Background

- **SDD**: plan をタスク分割し、タスクごとに fresh implementer subagent → task reviewer subagent、全タスク後に final reviewer を dispatch する superpowers plugin の skill。task brief / report / review package をファイル渡しして controller の context を守る
- **agmsg**: `~/.agents/skills/agmsg/scripts/` のスクリプト群による SQLite ベースのエージェント間メッセージング。`spawn.sh` で tmux pane / OS terminal に codex / claude-code を起動できる
- 旧 `agmsg-role-protocol` skill（leader / coder / reviewer の常駐チーム型）は本 skill に置き換えるため削除する。常駐型は Codex 側に context が蓄積し、SDD の「fresh context per task」の利点を失うため採らない

## Architecture

### Roles

| 役割 | 担当 | 責務 |
|---|---|---|
| controller | Claude（メインセッション） | plan 管理・task brief 作成・dispatch・レビュー裁定・progress ledger。brainstorming / writing-plans もこれまで通り Claude |
| implementer / fixer | Codex（タスクごとに fresh spawn） | TDD で実装・commit・self-review し、agmsg で報告して despawn される |
| task reviewer / final reviewer | Claude subagent | SDD のまま変更なし。spec 準拠の判断は意図の確認なので Claude 側に残す |

### Communication Discipline

本 skill の核心となる一方向の規律。

- Codex への入力は `spawn.sh --boot-prompt` のみ。dispatch ファイルのパスを渡し「これを読んで従え」とする
- Codex からの出力は agmsg メッセージ（短い status）+ report file のみ
- controller は `watch-once.sh` でブロック待ちし、`inbox.sh` で受信する
- 質問（NEEDS_CONTEXT）・BLOCKED・レビュー指摘の fix はすべて「despawn → dispatch ファイルに回答 / findings を追記 → 再 spawn」で行う

idle な Codex は後送メッセージを受信できない（agmsg の制約。spawn.sh の `--boot-prompt` はこの制約への対処として存在する）。入力を boot-prompt に限定することで、Codex を起こす手段の問題が構造的に消える。

### Skill Composition

差分参照型で書く。SKILL.md は superpowers:subagent-driven-development を invoke してプロセス全体（レビュー・ledger・file handoff・model selection・Red Flags）に従い、implementer 周りだけを置換表で差し替える。

| SDD | agmsg-DD |
|---|---|
| Task tool で implementer subagent を dispatch | `spawn.sh codex implementer --boot-prompt` |
| implementer-prompt.md | codex-dispatch-prompt.md（本 skill 同梱） |
| subagent の返値で報告 | agmsg send + report file |
| 質問に回答して継続 | despawn → 回答を含めて再 spawn |
| 完了待ち = tool return | `watch-once.sh` で待機 → `inbox.sh` |

レビュー・ledger のノウハウを複製せず superpowers の更新に追従するため、自己完結型ではなくこの形を採る。SDD の scripts（task-brief / review-package）は skill 読み込み時の base directory から解決する。

## Per-Task Flow

1. BASE commit を記録し、SDD の `task-brief` script で brief file を生成する
2. `codex-dispatch-prompt.md` template から dispatch file を生成する。内容: brief パス・作業ディレクトリ・TDD / signoff commit 指示・report contract（report file のパスと `send.sh` による status 報告コマンドを明記）
3. `spawn.sh codex implementer --project <dir> --boot-prompt "<dispatch file を読んで従え>"` を実行する
4. `watch-once.sh` で待機（timeout 付き・リトライ上限あり）→ `inbox.sh` で受信 → `despawn.sh --force` で pane を閉じる
5. DONE → `review-package` → task reviewer subagent（SDD のまま）
6. 指摘あり → fix dispatch = dispatch file に findings を追記して再 spawn（手順 3-4 と同型）
7. review clean → ledger 記録 → 次タスクへ。全タスク後の final review も SDD のまま

## Team / Identity Management

- team は run（worktree）ごとに 1 つ作る。team 名 = `<リポジトリ名>-<branch-slug>`（slug はブランチ名の `/` を `-` に置換。worktree ディレクトリ命名と同じ規則）
- identity は固定名: controller = `leader`、Codex = `implementer`。agent 名は team 内のアドレスなので、team を分離すれば並列 worktree でも衝突しない（actas lock も (team, agent) 単位）
- メッセージは宛先 agent 名への point-to-point 配送で inbox は混ざらない。`history` / `team` の観測面も team 分離により run ごとに分かれる
- run 終了時に implementer を despawn し、leader を `leave.sh` で離脱させる。`leave.sh` は空になった team を削除するため team は増殖しない
- Codex のモデルは既定を使い、必要な場合のみ `spawn.sh --model` で上書きする。SDD の Model Selection 節は Claude subagent（レビュー役）にのみ適用する

### Explicit Addressing

agmsg の project 解決（`resolve-project.sh`）は、SessionStart marker・登録済み ancestor・git common dir から「session が属する project」を推定するため、worktree からの呼び出しが main checkout に巻き戻されることがある。skill はこの ambient 解決に依存しない。

- run 開始時に TEAM・AGENT・project path（worktree の絶対パス）を確定し、以後すべてのスクリプト呼び出しに明示的に渡す（`whoami.sh` の自動解決に依存しない）
- 登録に影響する呼び出し（`join.sh`）には `AGMSG_RESOLVE_PROJECT=0` を付け、worktree パスが main checkout に書き換えられるのを防ぐ（`spawn.sh` は `--project` に対して内部で同じ対処を行っている）

## Workflow Integration

`dotfiles/.claude/CLAUDE.md` の Workflow 節に「plan 実行開始時、subagent-driven-development / agmsg-driven-development のどちらで実行するかを必ずユーザーに確認する」ルールを追加する。superpowers は plugin で writing-plans の参照先を書き換えられないため、CLAUDE.md（skill より優先）で選択を強制する。

## Error Handling

- **前提チェック**（skill 冒頭）: codex CLI・agmsg・tmux または terminal の存在を確認する。欠けていれば SDD への切り替えを提案する
- **watch-once timeout**: リトライ上限まで再待機 → report file の存在を直接確認（Codex が報告だけ忘れて完了しているケース）→ それでも不明ならユーザーへエスカレーションする
- **spawn 失敗**（name が live session に保持されている等）: `despawn --force` で掃除して 1 回だけ再試行する

## Deliverables

| # | ファイル | 内容 |
|---|---|---|
| 1 | `dotfiles/.claude/skills/agmsg-driven-development/SKILL.md` | 差分参照型本文（SDD invoke + 置換表 + agmsg 手順） |
| 2 | 同 dir の `codex-dispatch-prompt.md` | Codex 用 dispatch template |
| 3 | `~/.claude/skills/agmsg-driven-development/` | symlink 設置（ディレクトリ実体 + ファイル単位 symlink。template も symlink する） |
| 4 | `dotfiles/.claude/CLAUDE.md` | Workflow 節への選択ルール追加 |
| 5 | 削除: `agmsg-role-protocol` skill と CLAUDE.md の Team Collaboration 節 | 本ブランチに含めて commit する |

## Out of Scope

- agmsg 本体（fujibee/agmsg）への変更
- superpowers plugin への変更
- Codex 側への常駐 skill の配置（dispatch file が自己完結するため不要）
- claude-code type の agent を agmsg で spawn する構成

## Success Criteria

- 小さな plan（1〜2 タスク）を本 skill で実行し、spawn → 実装 → agmsg 報告 → review → despawn のサイクルが人手の介入なしで一周することを VERIFIED にする
- plan 実行開始時に CLAUDE.md ルールによる実行方式の選択確認が発火することを確認する
- 2 つの worktree で本 skill を並行実行し、team・identity・メッセージ配送が run 間で混ざらないことを確認する
- run 終了後に `leave.sh` により team が削除され、登録が残らないことを確認する
