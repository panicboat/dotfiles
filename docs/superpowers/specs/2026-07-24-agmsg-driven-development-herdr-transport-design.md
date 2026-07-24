# agmsg-driven-development: herdr Transport Redesign

## Goal

`agmsg-driven-development` skill の implementer 委譲の transport を、agmsg（fujibee/agmsg）から herdr（ogulcancelik/herdr）へ全面的に置き換える。skill 名は据え置く（"agent-message-driven development" の概念ラベルとし、herdr が実体の transport）。

目的は従来どおりトークン使用量の分散。実装（最もトークンを消費する工程）を herdr 経由の Codex に委譲し、Claude には意図の判断——plan 管理・task brief 作成・レビュー裁定——を残す。

## Background

- **現状**: agmsg 版は Codex を tmux pane に spawn し、SQLite ベースの team/identity で messaging、despawn で tmux pane を kill する。tmux 前提（despawn が tmux pane しか閉じられない）・worktree ごとの team 分離・`AGMSG_RESOLVE_PROJECT=0` 等の回避策を要した
- **herdr**: AI エージェント専用のマルチプレクサ（Rust 単一バイナリ、socket API）。protocol 17 / herdr 0.7.5 で確認した API:
  - `pane.split`（`direction` 必須、`cwd`/`env`/`target_pane_id`/`workspace_id`/`ratio`/`focus` 任意）
  - `agent.start`（`kind`/`name`/`pane_id` 必須、`args`/`timeout_ms` 任意）— codex は組み込み integration（`herdr integration install codex`）
  - `agent.prompt`（`target`/`text` 必須、`wait` 任意）— boot prompt も追加指示も生きた agent に投げる
  - `agent.wait`（`target` 必須、`until` に状態配列、`timeout_ms` 任意）— 状態 `idle/working/blocked/done/unknown` をネイティブ検出
  - `pane.close`（`pane_id` 必須）
  - CLI: `herdr pane split|run|close|send-text|current`, `herdr agent start|prompt|wait|get|read|explain`。socket コマンドは herdr server 稼働が前提

herdr は agmsg と機能が重なるため、この skill では agmsg を残さず herdr に一本化する。

## Architecture

差分参照型は維持する。SKILL.md は superpowers:subagent-driven-development（SDD）を invoke してプロセス全体（Pre-Flight Plan Review・レビュー・progress ledger・File Handoffs・Model Selection・Red Flags）に従い、implementer 周りだけを置き換える。task reviewer / final reviewer は SDD どおり Claude subagent。

### Roles

| 役割 | 担当 | 責務 |
|---|---|---|
| controller | Claude（herdr session 内） | plan 管理・brief 作成・dispatch・レビュー裁定・progress ledger |
| implementer / fixer | Codex（herdr の追跡対象 agent として pane 内起動） | TDD で実装・commit・self-review し、report file に報告 |
| task reviewer / final reviewer | Claude subagent | SDD のまま。spec 準拠の判断は意図の確認なので Claude 側に残す |

### Communication

- Codex への入力は `agent.prompt`（boot も redispatch も）
- 完了検知は `agent.wait`（herdr が Codex の semantic state を追跡）
- 詳細報告は report file。STATUS 行（DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED）が意味論の source of truth、herdr state は「いつ report を読むか」の liveness
- agmsg の team / SQLite / send / inbox / watch-once / despawn は全廃

### Context granularity

- タスク N → N+1 は `pane.close` して新 pane + 新 codex（SDD の fresh-per-task を維持）
- タスク途中の質問（NEEDS_CONTEXT）・レビュー指摘の fix は `agent.prompt` で生きた codex に投げ返し、作業中の文脈を保持する。agmsg 版の「despawn → respawn で文脈を捨てる」問題が消える

### Skill Composition (substitutions)

| SDD | 本 skill |
|---|---|
| Task tool で implementer subagent を dispatch | Dispatch 節の手順で Codex を herdr agent として起動 |
| implementer-prompt.md | 本 skill 同梱の codex-dispatch-prompt.md |
| implementer の返値による報告 | report file + herdr agent state（Await 節） |
| 質問回答・追加 context・fix の再依頼 | 生きた codex への `agent.prompt`（Redispatch 節） |
| implementer への Model Selection | Codex は既定モデル。SDD の Model Selection は Claude subagent（レビュー役）にのみ適用 |

## Per-Task Flow

1. BASE commit を記録し、SDD の task-brief script で brief file を生成。codex-dispatch-prompt.md template から `task-N-dispatch.md` を生成
2. `pane.split`（`direction`, `cwd=<worktree 絶対パス>`）→ 新 pane id を取得
3. `agent.start`（`kind=codex`, `name=implementer`, `pane_id=<新 pane>`）→ codex 起動
4. `agent.prompt`（`text="Read <dispatch file 絶対パス> and follow it exactly."`）→ boot
5. `agent.wait`（`until=[done, blocked]`）でブロック → report file の STATUS を読む
6. NEEDS_CONTEXT / レビュー指摘の fix → `agent.prompt` で回答・findings を生きた codex に投げる → `agent.wait` 再び（Redispatch）
7. DONE → SDD どおり review-package → task reviewer subagent
8. review clean → `pane.close` で implementer 破棄 → ledger 記録 → 次タスクは新 pane + 新 codex
9. 全タスク後 final review（SDD のまま）→ 残 pane を close

## Prerequisites & Setup

開始前に確認する。欠けていれば報告して SDD での実行を提案する。

1. `command -v herdr` が成功する
2. controller が herdr session 内である（`herdr pane current` が成功する）
3. codex integration が入っている（`herdr integration status` で確認。未導入なら `herdr integration install codex` を促す）

controller は herdr session 内で動く。並列 worktree は herdr の session 単位で分離し、pane id は session スコープ。`pane.split` に `cwd=<worktree>` を渡すことで作業ディレクトリを明示し、agmsg 版の worktree→main 巻き戻し対策（`AGMSG_RESOLVE_PROJECT=0`）は不要になる。

## Removed Complexity

herdr 化で以下が不要になる: team / identity 管理、`AGMSG_RESOLVE_PROJECT=0`、worktree→main checkout 巻き戻し対策、`whoami.sh`/`join.sh`/`leave.sh`、watch-once timeout リトライ、despawn の tmux 限定制約、tmux 前提そのもの。

## Reverts & Deliverables

### dotfiles（PR #38 の続き）

| # | ファイル | 内容 |
|---|---|---|
| 1 | `.claude/skills/agmsg-driven-development/SKILL.md` | herdr 版に全面書き換え（Prerequisites/Setup/Substitutions/Dispatch/Await/Redispatch/Teardown/Red Flags） |
| 2 | `.claude/skills/agmsg-driven-development/codex-dispatch-prompt.md` | report contract を herdr 前提に更新（agmsg send.sh の status 行を削除。「report を書いて停止、herdr が完了検知」） |
| 3 | `.config/tmux/tmux.conf` | 削除。手動作成した `~/.config/tmux/tmux.conf` symlink も撤去 |
| 4 | `.zshrc` | tmux 版 `claude()` ラッパーを herdr 内起動版に差し替え（tmux 参照を消す）。exact な起動機構は実装フェーズで検証（herdr が初期コマンド起動を持たない場合のフォールバックはそこで確定）。既存の agmsg `codex()` shim wrapper は現状維持 |

### ansible（PR #30 の転換）

| # | ファイル | 内容 |
|---|---|---|
| 5 | `roles/homebrew/tasks/main.yaml` | 「tmux を install へ移動」を撤回し、tmux は uninstall へ戻す。代わりに `herdr` を install リストへ追加 |

### 手元の後始末

- 検証用に brew install した tmux を uninstall する

## Error Handling

- **前提欠如**（herdr 未導入 / server 未起動 / codex integration 未 install）→ 欠けている項目を報告して SDD へフォールバック提案
- **`agent.wait` timeout** → report file を確認。無ければ `agent.read` で pane 出力を採取してユーザーへエスカレーション（勝手に再起動しない）
- **`pane.split` / `agent.start` 失敗** → 生成済み pane があれば close し、1 回だけ再試行。再失敗はユーザーへ報告

## Out of Scope

- herdr 本体（ogulcancelik/herdr）への変更
- superpowers plugin への変更
- claude 以外の agent 種別を herdr で駆動する構成
- agmsg の他用途（この skill 以外での agmsg 利用）への変更

## Success Criteria

- headless `herdr server` を立て、実 API で `pane.split` → `agent.start(codex)` → `agent.prompt` → `agent.wait` → `pane.close` の各引数綴りと戻り値（特に split の新 pane id 取得方法）を VERIFIED にする
- ミニ plan（1〜2 タスク）を本 skill で実行し、fresh-per-task と「タスク途中の `agent.prompt` 再投入」の両経路が人手の介入なしで通ることを VERIFIED にする
- 2 つの worktree で並行実行し、herdr session 分離により pane が混ざらないことを確認する
- plan 実行開始時に CLAUDE.md の実行方式選択で agmsg-driven-development（herdr transport）が提示されることを確認する
- `.zshrc` の herdr 版 `claude()` ラッパーが claude を herdr session 内で起動する（またはフォールバックが機能する）ことを VERIFIED にする
- tmux 資産（tmux.conf・symlink・.zshrc の tmux 参照・ansible の tmux install）が残っていないことを確認する
