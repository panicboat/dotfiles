# Codex-Driven Development: Multiplexer 抽象化 & agmsg 通信への移行

## Background

`codex-driven-development` skill（`.claude/skills/codex-driven-development/`）は herdr 固有の API（`herdr pane split` / `herdr agent start` / `herdr agent get` / `herdr pane send-text` / `send-keys`）に直接依存している。ユーザーが Orca（別の terminal multiplexer）を常用するようになり、herdr 専用の前提を汎用化したいという要望が出発点。

設計対話の中で実地検証を重ねた結果、当初の「herdr/orca 両対応の adapter を書く」という狭いスコープから、「Redispatch/Await の通信方式そのものを agmsg（cross-agent messaging skill）に委譲する」という設計に発展した。理由は、今回の Orca 実地検証で TUI キー入力方式（`send-text`+`send-keys`）の脆さ（`agent_prompt_blocked` エラー、text/enter の分離要求、ANSI 混じりの画面スクレイピング）を直接踏んだため。

## Goals

- pane 生成・破棄を herdr / Orca / 将来の multiplexer（cmux 等）に対応する汎用 adapter 契約に抽象化する
- Redispatch（生きた Codex への追加指示）と Await（完了検知）を、TUI 依存の脆い経路から agmsg 経由のメッセージングに置き換える
- agmsg 側の機構が使えない場合は、現行の TUI 注入方式にフォールバックする

## Non-Goals

- task reviewer / final reviewer の構成変更（別の検討課題。2026-08-13 に `cdd-review` team で Codex と交わした議論が別途ある）
- 汎用マルチエージェントオーケストレーション基盤の構築。あくまで SDD の implementer 差し替えの範囲に留める

## Verified Facts（本セッションでの実地検証）

このセッション中に Orca pane と herdr pane の両方で Codex を実際に起動し、agmsg の `monitor` delivery mode（BETA）を有効化して検証した。

1. **idle 状態の Codex への push が機能する**: `send.sh` で送ったメッセージが、pane を一切操作せず自動的に Codex の新しいターンとして投入された（Orca: 17:19:32 送信 → 17:19:45 応答、herdr: 17:27:07 送信 → 17:27:20 応答。いずれも約13秒）
2. **ビジー中の push は安全にキューされる**: `sleep 20` の実行中に別メッセージを push したところ、実行中のタスクは中断されず完走し（17:21:39 完了）、完了直後に次のターンとしてキューされたメッセージが処理された（17:21:46）。実行中の作業を壊すリスクは無い
3. **herdr と Orca で同一の挙動**: push の仕組みは Codex CLI 自身の websocket app-server bridge（`codex --remote ws://...`）によるもので、pane を提供する multiplexer 側の実装に依存しない。実地でも同じ結果だった
4. **turn mode ではこの用途に使えない**: agmsg の `turn` delivery mode（Stop hook 相当）は「Codex 自身のターンが終わった瞬間」にしか inbox を pull しない。idle 状態の Codex を外から起こすことはできず、Redispatch には使えない。`monitor` mode（BETA）が唯一の経路
5. **送信は delivery mode に非依存で常に成功する**: `send.sh` はメッセージを SQLite に永続化するだけなので、受信側の delivery mode に関わらず必ず成功する。Await（Codex→Claude の完了通知）はこの性質を使うので、BETA機能の bridge に依存しない
6. **同一 (project, type) の identity 衝突**: 同じ project path・type で2つの生きた Codex セッションを同時に起動すると、agmsg の bridge/thread 解決（`thread/loaded/list`）が競合し、片方の bridge しか arm されない。team を worktree 単位でスコープすることで回避する（Setup 節参照）
7. **副作用**: `delivery.sh set monitor codex <project>` はプロジェクトの working tree に `.codex/hooks.json` を書き出す。git 管理下では untracked になり、誤 commit の恐れがあるため `.git/info/exclude` への追加が必要（本セッションで dotfiles リポジトリに適用済み）

## Architecture

superpowers:subagent-driven-development（SDD）の構造は維持する。Claude が plan 管理・task brief 作成・レビュー裁定を持ち、task reviewer / final reviewer も引き続き Claude subagent。置き換えるのは implementer 周りの「pane 生成」と「通信」のみ。

- **pane 生成/破棄**: herdr 固有 API 直書き → multiplexer adapter 契約経由に抽象化
- **Redispatch**: TUI キー入力 → agmsg `send.sh` push（bridge が arm していれば）
- **Await**: report file の `STATUS:` 走査 + multiplexer 固有 `agent_status` ポーリング → Codex からの agmsg 完了通知（非同期）。report file はその内容（task reviewer が読む対象）として残すが、「終わったかどうか」のシグナルの役割からは外れる
- **新しい前提**: agmsg がインストールされており、worktree 単位の team/identity を Setup で自動プロビジョニングする

## Multiplexer Adapter Contract

pane 生成・破棄・起動直後の一度きりの対話ダイアログ処理に必要な最小インターフェース。Redispatch の定常運用は agmsg に移るため、TUI 注入系の操作は「起動直後の対話ダイアログ処理」と「bridge が arm しなかった場合のフォールバック」にのみ残る。

| 操作 | 用途 |
|---|---|
| `detect()` | この multiplexer が現在の環境で使えるか |
| `create_pane(cwd) -> pane_id` | 新しい pane を指定 cwd で作る |
| `run(pane_id, argv)` | pane で `codex "<prompt>"` を実行（Dispatch の初回投入。bridge が arm する前なので agmsg 経由にはできない） |
| `send_text(pane_id, text)` / `send_keys(pane_id, keys)` | 起動直後の対話ダイアログ処理、および fallback mode での Redispatch |
| `read(pane_id)` | pane の可視テキストを読む（対話ダイアログの種類判定、fallback mode の状態確認） |
| `close_pane(pane_id)` | pane を閉じる |

### herdr / Orca 実装マッピング（本セッションで検証済みの具体コマンド）

| 契約操作 | herdr | Orca |
|---|---|---|
| `detect()` | `command -v herdr` かつ `herdr status` で session running | `command -v orca` かつ `orca status --json` の `runtime.reachable: true` |
| `create_pane(cwd)` | `herdr pane split --cwd <cwd> ...` → `pane_id`（既存 pane が無い場合は `herdr workspace create --cwd <cwd>` で root pane を作る） | `orca terminal split --terminal <current> --direction horizontal --cwd <cwd>` → `handle`（既存 pane が無い場合は `orca terminal create --worktree <path>`） |
| `run(pane_id, argv)` | `herdr agent start <name> --kind codex --pane <id> --timeout <ms> -- "<prompt>"`（pane 選択と起動が一体） | `orca terminal split ... --command "codex ..."` または `orca terminal create --command "codex ..."`（pane 作成と起動が一体） |
| `send_text` / `send_keys` | `herdr pane send-text <id> "<text>"` / `herdr pane send-keys <id> Enter` | `orca terminal send --terminal <handle> --text "<text>"` と `--enter` は**分離して2回**送る必要がある（`--text`+`--enter` の同時指定は `agent_prompt_blocked` で拒否されるケースを実地で確認済み） |
| `read(pane_id)` | `herdr agent read <id> --source visible --lines N` | `orca terminal read --terminal <handle>`（ANSI 制御文字が混入した生テキストが返るため、パース時は考慮が必要） |
| `close_pane(pane_id)` | `herdr pane close <id>` | `orca terminal close --terminal <handle>`（本セッションで実地確認済み） |
| bridge armed 確認 | `delivery.sh status codex "$PROJECT"` の `Codex bridge: <team>/<agent> alive (pid ...)` | 同上（multiplexer 非依存） |

## Prerequisites

開始前に確認し、欠けていれば報告して中断する。

1. 使える multiplexer adapter が最低1つ存在する（herdr session / Orca runtime のいずれかが `detect()` 成功）。**複数同時に検出された場合**は、現在の Claude Code セッション自身が動いている pane を提供している multiplexer を優先する（作業中の環境と同じツールで pane を割る方が自然で、確認コストも要らない）。判定できなければユーザーに選ばせる
2. agmsg がインストールされている（`~/.agents/skills/agmsg` の存在）
3. Codex CLI があり、`codex-shim.sh` が存在する（shell function 経由の実配線は非対話スクリプトから確証できないため弱いシグナルとして扱う。実際に機能しているかは Dispatch 時の bridge armed 確認で確定させる）

## Setup

完了条件: `PROJECT`・`TEAM`・両 identity が確定していること。

1. Skill tool で superpowers:subagent-driven-development を読み込む（現行どおり）
2. `PROJECT` = 作業 worktree の絶対パスを確定する（現行どおり）
3. `TEAM` を worktree から導出する（例: `cdd-$(basename "$PROJECT")`。既存の `AGENT="impl-$(basename "$PROJECT")"` と同じ命名思想）
4. `join.sh $TEAM claude claude-code "$PROJECT"` / `join.sh $TEAM codex codex "$PROJECT"` を idempotent に実行（既に join 済みでも成功扱い）
5. `delivery.sh set monitor codex "$PROJECT"` を idempotent に実行
6. Claude 自身の delivery mode が `monitor` か確認し、なければ Monitor tool を起動する
7. `TEAM` は plan 実行全体を通して使い回す（後述 Run Teardown まで解体しない）。同一 worktree に対する再実行は既存 team に join するだけで、新規 team は作らない

## Dispatch

タスク/バッチごとに実行する。

1. BASE commit 記録・task-brief 生成（現行どおり）
2. dispatch prompt テンプレート（`codex-dispatch-prompt.md`）に一項目追加: 完了時に `send.sh $TEAM codex claude "STATUS: <DONE|DONE_WITH_CONCERNS|NEEDS_CONTEXT|BLOCKED> <要約>"` を最後に実行すること。report file への記録要求はそのまま残す（内容の正 = report file、完了シグナル = agmsg で役割分離）
3. adapter の `create_pane` + `run` で pane を作り、`codex "<boot prompt>"` を起動
4. 起動直後の一度きりの対話ダイアログ（trust/hooks/update）は adapter の `send_text`/`send_keys` で処理する。**trust 系はユーザー承認を経てから**実行する（自動承認しない）
5. **bridge armed 確認**: `delivery.sh status codex "$PROJECT"` を一定時間（例 30 秒）ポーリングし、`Codex bridge: $TEAM/codex alive` を待つ
   - armed → 以降このバッチは **push mode**
   - timeout → 以降このバッチは **fallback mode**（現行どおり TUI 注入 + report file/`agent_status` ポーリング）

## Redispatch

**push mode**: `send.sh $TEAM claude codex "<追加指示/fix内容>"` を送るのみ。ビジー中でも安全にキューされ、実行中タスクを壊さないことを実地確認済み。

**fallback mode**: 現行どおり `send-text`+`send-keys Enter`+`history.jsonl` 確認。

## Await

**push mode**: Claude 側の Monitor が既に有効なので、`STATUS:` 付き完了メッセージは非同期の task-notification として届く。ブロッキングの polling loop は不要——通知が届くまで他の作業を進めてよい。ただし「打ち切り線の無い待機」は禁止のため、通知が `WAIT_BUDGET` 内に届かない場合のフォールバックとして `inbox.sh` / `delivery.sh status`（bridge 生存確認）を軽くポーリングする安全網を残す。

**fallback mode**: 現行どおり report file の `STATUS:` + `agent_status` ポーリング。

## Teardown

2つの異なるライフサイクルに分かれる。

**Pane Teardown**（タスク/バッチごと、現行どおり）
1. `close_pane` で対象 pane を閉じる（既に閉じている場合のエラーは想定内として続行）
2. 同じ `TEAM`/identity は解体せず、次バッチでも再利用する

**Run Teardown**（plan 実行全体の最後に1回、または run 中断時）
1. 残っている implementer pane を確認し、あれば `close_pane` で閉じる（現行の全タスク完了後チェック）
2. `reset.sh "$PROJECT" codex codex` / `reset.sh "$PROJECT" claude-code claude` で両 identity を解除する

## Failure Modes（現行表への追加分）

| 症状 | 原因 | 一手 |
|---|---|---|
| bridge が `WAIT_BUDGET` 内に arm しない | Codex CLI バージョン非互換、agmsg app-server 起動失敗等（BETA機能） | fallback mode に切り替えて続行。ユーザーには push mode が使えなかった旨を報告する |
| 同一 worktree で2つの生きた Codex pane が同時に存在する | identity 衝突で bridge/thread が競合する | 現行設計では 1 pane = 1 バッチが前提のため通常発生しない。並行バッチを将来サポートする場合は team/identity をバッチ単位でさらに分ける設計変更が必要（本 spec の対象外） |
| `.codex/hooks.json` が git 管理下に出現する | `delivery.sh set monitor` の副作用 | `.git/info/exclude` に `/.codex/hooks.json` を追加する（対象リポジトリで未実施なら Setup 時に確認） |
| Orca で `send_text`+`send_keys` を同時送信すると `agent_prompt_blocked` | Orca 側のエージェント自動化ガード（詳細な発火条件は未解明） | text と enter を分離して2回に分けて送る |

## Open Risks / Follow-ups

- agmsg の Codex monitor bridge は BETA。Codex CLI のバージョンアップで app-server interface が変わると壊れる可能性がある（agmsg 側のコメントに実例あり: 0.142+ で一度発生）。fallback mode がこのリスクを吸収する設計にはなっているが、長期運用での安定性は未検証
- bridge の再接続安定性（multiplexer 再起動やセッション切れを跨いだ場合の挙動）は本セッションでは未検証
- 将来 cmux 等の multiplexer を追加する場合は、adapter マッピング表に1行足すだけで済む設計になっているはずだが、実装時に契約が本当に十分かは要確認
- herdr/Orca 双方の adapter 実装（実際のスクリプト化）は本 spec の範囲外。次工程の implementation plan で行う
