# Codex-Driven Development Multiplexer & agmsg Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generalize `codex-driven-development` skill's herdr-only prerequisite into a multiplexer adapter contract (herdr + Orca), and replace its TUI-based Redispatch/Await with agmsg's Codex monitor bridge, falling back to TUI injection when the bridge doesn't arm.

**Architecture:** A new `multiplexer-adapters.md` reference doc holds the adapter contract and the concrete herdr/Orca command mappings. `SKILL.md` is restructured section-by-section (Prerequisites, Setup, Dispatch, Redispatch, Await, Teardown, Failure Modes) to reference the adapter contract instead of herdr directly, and to route Redispatch/Await through agmsg `send.sh` when the Codex monitor bridge is armed, falling back to today's TUI injection otherwise. `codex-dispatch-prompt.md` gains one new requirement: send an agmsg completion message as the implementer's last action.

**Tech Stack:** Markdown skill files (no compiled code). Verification is done by running the actual `herdr`/`orca`/`agmsg` CLI commands referenced in each section against a real environment, not by an automated test suite — this skill has none, matching its existing files.

**Spec:** `docs/superpowers/specs/2026-09-03-codex-driven-development-multiplexer-design.md`

## Global Constraints

- Skill prose is Japanese; code/commands/identifiers inside it stay as-is (shell, English flag names) — this matches the existing file's style, do not translate commands.
- `TEAM`/`PROJECT`/`PANE` placeholder names used in code blocks must stay consistent with the existing file's naming (`PROJECT`, `PANE`, `AGENT`, `BASE`) plus the new `TEAM`.
- Every section keeps the existing "完了条件" (completion condition) convention where the original section had one.
- Do not touch `Batching Strategy` or `Substitutions` table rows that don't mention herdr — they are unaffected by this change (per spec Non-Goals).
- No unverified claims: mark anything not run against a real herdr/Orca/agmsg environment in this plan's steps with a comment saying so, rather than asserting it works.

---

## File Structure

- **Create:** `.claude/skills/codex-driven-development/multiplexer-adapters.md` — adapter contract table + concrete herdr/Orca command mappings. Referenced from `SKILL.md`'s Dispatch/Redispatch/Teardown sections instead of inlining multiplexer-specific commands there.
- **Modify:** `.claude/skills/codex-driven-development/SKILL.md` — frontmatter description, Substitutions table (one row), Prerequisites, Setup, Dispatch, Redispatch, Await, Teardown, Failure Modes, Red Flags.
- **Modify:** `.claude/skills/codex-driven-development/codex-dispatch-prompt.md` — generalize "herdr" wording, add the agmsg completion-message requirement, update the completion-detection wording in the Report section.
- **Modify:** `.claude/CLAUDE.md` — the "Plan Execution" option 1 description hardcodes "herdr session 内であることが前提"; update to match the generalized skill.

---

### Task 1: Create the multiplexer adapter reference doc

**Files:**
- Create: `.claude/skills/codex-driven-development/multiplexer-adapters.md`

**Interfaces:**
- Produces: the adapter contract operations `detect()`, `create_pane(cwd)`, `run(pane_id, argv)`, `send_text(pane_id, text)`, `send_keys(pane_id, keys)`, `read(pane_id)`, `close_pane(pane_id)`, and the "bridge armed" check command — all referenced by name from Tasks 3–5.

- [ ] **Step 1: Write the file**

```markdown
# Multiplexer Adapter Contract

codex-driven-development が pane 生成・破棄・起動直後の対話ダイアログ処理に要求する最小インターフェースと、対応 multiplexer ごとの具体コマンド。Redispatch の定常運用は agmsg（`../../../../.agents/skills/agmsg` 相当。実際のパスは `~/.agents/skills/agmsg`）に移るため、ここでの TUI 操作は「起動直後の一度きりの対話ダイアログ処理」と「agmsg bridge が arm しなかった場合の fallback mode」にのみ使う。

## Contract

| 操作 | 用途 |
|---|---|
| `detect()` | この multiplexer が現在の環境で使えるか |
| `create_pane(cwd) -> pane_id` | 新しい pane を指定 cwd で作る |
| `run(pane_id, argv)` | pane で `codex "<prompt>"` を実行する（Dispatch の初回投入。bridge が arm する前なので agmsg 経由にはできない） |
| `send_text(pane_id, text)` / `send_keys(pane_id, keys)` | 起動直後の対話ダイアログ処理、および fallback mode での Redispatch |
| `read(pane_id)` | pane の可視テキストを読む（対話ダイアログの種類判定、fallback mode の状態確認） |
| `close_pane(pane_id)` | pane を閉じる |

adapter の選択は SKILL.md の Prerequisites 節で行う。以降の節は選ばれた adapter に応じて、この2つの表のうち片方だけを見ればよい。

## herdr

Claude Code 自身が herdr pane の中で動いている（`herdr pane current` が成功する）ことが前提。

| 契約操作 | コマンド |
|---|---|
| `detect()` | `command -v herdr` が成功し、かつ `herdr pane current` が成功する |
| `create_pane(cwd)` | `herdr pane split --current --direction right --cwd "<cwd>" \| jq -r '.result.pane.pane_id'`（既存 SKILL.md の Dispatch 節が使っていたのと同じフィールドパス） |
| `run(pane_id, argv)` | `herdr agent start <name> --kind codex --pane <pane_id> --timeout <ms> -- "<prompt>"`（pane 選択と codex 起動が一体。`<name>` はサーバー全体で一意にする必要があり、`impl-$(basename "$PROJECT")` のように `PROJECT` から導出する） |
| `send_text(pane_id, text)` | `herdr pane send-text <pane_id> "<text>"` |
| `send_keys(pane_id, keys)` | `herdr pane send-keys <pane_id> <keys>`（例: `Enter`） |
| `read(pane_id)` | `herdr agent read <pane_id> --source visible --lines <N>` |
| `close_pane(pane_id)` | `herdr pane close <pane_id>` |

## Orca

Claude Code 自身が Orca 管理下の pane で動いていることが前提。Orca には herdr の `pane current` に相当する「自分がどの pane か」を直接返すコマンドが無いため、`orca terminal list --json` を実行し、`worktreePath` が現在の作業ディレクトリと一致し `agentIdentity` が `claude` である要素の `handle` を自分の pane として扱う。

| 契約操作 | コマンド |
|---|---|
| `detect()` | `command -v orca` が成功し、`orca status --json` の `result.runtime.reachable` が `true` |
| `create_pane(cwd)` | 自分の pane の handle が分かれば `orca terminal split --terminal <own_handle> --direction horizontal --cwd "<cwd>"` → `result.split.handle`。分からなければ `orca terminal create --worktree "path:<cwd>"` → `result.handle` |
| `run(pane_id, argv)` | pane 作成時に `--command "codex \"<prompt>\""` を渡して同時に起動する（`create_pane` 呼び出しと同時に行う） |
| `send_text(pane_id, text)` | `orca terminal send --terminal <pane_id> --text "<text>"`（**`--enter` と同時指定しない** — 同時指定は `agent_prompt_blocked` で拒否されるケースを実地確認済み） |
| `send_keys(pane_id, "Enter")` | `orca terminal send --terminal <pane_id> --enter`（`send_text` とは別呼び出しにする） |
| `read(pane_id)` | `orca terminal read --terminal <pane_id> --json` → `result.terminal.tail`（ANSI 制御文字混じりの生テキストが返るため、パース時は考慮する） |
| `close_pane(pane_id)` | `orca terminal close --terminal <pane_id>` |

## bridge armed 確認（multiplexer 非依存）

どちらの adapter を使う場合も、Dispatch 後に以下で agmsg の Codex monitor bridge が arm したかを確認する:

```sh
~/.agents/skills/agmsg/scripts/delivery.sh status codex "$PROJECT"
```

出力に `Codex bridge: <team>/<agent> alive (pid <pid>)` の行が含まれれば armed。含まれなければ（例: `Codex bridge: <team>/<agent> not running`）、fallback mode に切り替える。
```

- [ ] **Step 2: Verify the herdr commands against a real session**

herdr サーバーが動いていない場合は起動する:

```sh
herdr status
# server.status が "not running" なら:
herdr server > /tmp/herdr-plan-verify.log 2>&1 &
disown
sleep 2
herdr status
```

pane を1つ作り、`run` まで一通り実行して壊れていないことを確認する:

```sh
WS=$(herdr workspace create --cwd "$(pwd)" --label "adapter-doc-verify")
PANE=$(echo "$WS" | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['root_pane']['pane_id'])")
herdr agent start plan-verify --kind codex --pane "$PANE" --timeout 30000 -- 'こんにちはとだけ返信して待機して'
sleep 8
herdr agent read "$PANE" --source visible --lines 10
```

Expected: `agent start` が JSON を返し、`agent read` に Codex の応答（「こんにちは」を含む行）が出力される。

- [ ] **Step 3: Clean up the verification pane**

```sh
WORKSPACE_ID=$(echo "$WS" | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['workspace']['workspace_id'])")
herdr workspace close "$WORKSPACE_ID"
```

Expected: `{"result":{"type":"ok"}}` 相当の成功レスポンス。

- [ ] **Step 4: Verify the Orca commands against a real session**

Orca がこのセッションの multiplexer である場合のみ実行する（そうでなければこの手順はスキップし、ステップ内容が正しいことをコードレビューで確認する旨を PR に書く）:

```sh
orca terminal list --json | python3 -c "
import json,sys
d = json.load(sys.stdin)
cwd = __import__('os').getcwd()
for t in d['result']['terminals']:
    if t.get('worktreePath') == cwd and t.get('agentIdentity') == 'claude':
        print(t['handle'])
"
```

Expected: 自分自身の pane の handle が1件だけ出力される。出力されたら、その handle を使って `orca terminal split --terminal <handle> --direction horizontal --command "echo adapter-doc-verify"` を実行し、成功レスポンスの `result.split.handle` が返ることを確認する。確認後 `orca terminal close --terminal <新しい handle>` で閉じる。

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/codex-driven-development/multiplexer-adapters.md
git commit -s -m "docs(codex-driven-development): add multiplexer adapter contract doc"
```

---

### Task 2: Generalize SKILL.md frontmatter, Substitutions row, Prerequisites, and Setup

**Files:**
- Modify: `.claude/skills/codex-driven-development/SKILL.md:1-8,29-35` (frontmatter, intro, Substitutions table row)
- Modify: `.claude/skills/codex-driven-development/SKILL.md:10-23` (Prerequisites, Setup)

**Interfaces:**
- Consumes: `multiplexer-adapters.md` from Task 1 (referenced by path, not by function call — this is a doc, not code).
- Produces: `PROJECT`, `TEAM` shell variables and the join/delivery-mode commands that Tasks 3–5 assume are already set.

- [ ] **Step 1: Replace the frontmatter description**

Current (`SKILL.md:1-4`):

```markdown
---
name: codex-driven-development
description: 実装 plan を実行するとき、implementer を herdr pane 上の Codex に委譲してトークン使用量を分散する。superpowers:subagent-driven-development の実行構造（タスクごとの実装 → タスクレビュー → 最終レビュー）は維持し、implementer 周りだけを置き換える。動作条件は herdr session 内で実行していること・codex integration が導入済みであることで、満たさなければ何も起動せず SDD での実行を提案する。plan の実行方式として codex-driven-development が選択されたときに使用する。
---
```

Replace with:

```markdown
---
name: codex-driven-development
description: 実装 plan を実行するとき、implementer を multiplexer pane 上の Codex に委譲してトークン使用量を分散する。superpowers:subagent-driven-development の実行構造（タスクごとの実装 → タスクレビュー → 最終レビュー）は維持し、implementer 周りだけを置き換える。動作条件は対応する multiplexer（herdr/Orca）のセッション内で実行していること・agmsg がインストールされていることで、満たさなければ何も起動せず SDD での実行を提案する。plan の実行方式として codex-driven-development が選択されたときに使用する。
---
```

- [ ] **Step 2: Update the intro paragraph**

Current (`SKILL.md:8`):

```markdown
superpowers:subagent-driven-development（以下 SDD）の実行構造を維持したまま、implementer だけを herdr pane 上の Codex に置き換えて plan を実行する。実装（最もトークンを消費する工程）を Codex に移し、Claude には意図の判断——plan 管理・task brief 作成・レビュー裁定——を残す。
```

Replace with:

```markdown
superpowers:subagent-driven-development（以下 SDD）の実行構造を維持したまま、implementer だけを multiplexer pane 上の Codex に置き換えて plan を実行する。実装（最もトークンを消費する工程）を Codex に移し、Claude には意図の判断——plan 管理・task brief 作成・レビュー裁定——を残す。pane の生成・破棄には `multiplexer-adapters.md` に定義された adapter 契約を使う。生きた Codex への追加指示（Redispatch）と完了検知（Await）は agmsg の Codex monitor bridge を使い、bridge が使えない場合のみ multiplexer 固有の TUI 操作にフォールバックする。
```

- [ ] **Step 3: Update the Substitutions table row that names herdr**

Current (`SKILL.md:29-35`, only the affected row shown):

```markdown
| Task tool で implementer subagent を dispatch | Codex を herdr agent として起動（Dispatch 節） |
```

Replace with:

```markdown
| Task tool で implementer subagent を dispatch | Codex を multiplexer pane 上の agent として起動（Dispatch 節、`multiplexer-adapters.md`） |
```

- [ ] **Step 4: Replace the Prerequisites section**

Current (`SKILL.md:10-17`):

```markdown
## Prerequisites

開始前に以下を確認する。ひとつでも欠けていれば、欠けている項目を報告して SDD での実行を提案する。

1. `command -v herdr` が成功する
2. herdr session 内である（`herdr pane current` が成功する）。session 外なら herdr を起動してその中で claude を動かすようユーザーに促す。`protocol_mismatch` なら server 再起動が要り、エラーメッセージが socket path 付きの `herdr server stop` を示すのでユーザーに提示する。**server 再起動は既存 pane のプロセスを落とす**ため、勝手に実行しない
3. codex integration が入っている（`herdr integration status | grep '^codex:'` の行が `not installed` でない。語彙は `current (vN)` / `not installed` で、`installed` という文字列は出力されない）。未導入なら `herdr integration install codex` を促す。これが無いと `agent_status` が更新されず Await の補助信号が死ぬ
```

Replace with:

```markdown
## Prerequisites

開始前に以下を確認する。ひとつでも欠けていれば、欠けている項目を報告して SDD での実行を提案する。

1. 使える multiplexer が最低1つある。`multiplexer-adapters.md` の `detect()` 手順を herdr → Orca の順に試す。**両方使えると判定された場合**は、現在の Claude Code セッション自身が動いている pane を提供している方を選ぶ（作業中の環境と同じツールで pane を割る方が自然で、確認コストも要らない）。判定できなければユーザーに選ばせる
2. agmsg がインストールされている（`~/.agents/skills/agmsg` が存在する）。無ければ agmsg のインストールをユーザーに促し、SDD での実行を提案する
3. Codex CLI があり、`~/.agents/skills/agmsg/scripts/drivers/types/codex/codex-shim.sh` が存在する（`codex` コマンドが shim 経由で起動する実配線は非対話スクリプトから確証できないため、ここでは弱いシグナルとして扱う。実際に機能しているかは Dispatch 節の bridge armed 確認で確定させる）
4. herdr を選んだ場合のみ: herdr session 内である（`herdr pane current` が成功する）。session 外なら herdr を起動してその中で claude を動かすようユーザーに促す。`protocol_mismatch` なら server 再起動が要り、エラーメッセージが socket path 付きの `herdr server stop` を示すのでユーザーに提示する。**server 再起動は既存 pane のプロセスを落とす**ため、勝手に実行しない
```

Note: the old requirement "codex integration が入っている（`herdr integration status`）" is dropped — the new design's completion signal comes from agmsg (Task 4), not herdr's own `agent_status`, so herdr's codex integration is no longer a hard prerequisite. `agent_status` is still read opportunistically as an auxiliary signal in fallback mode (Task 4), but its absence no longer blocks Dispatch.

- [ ] **Step 5: Replace the Setup section**

Current (`SKILL.md:18-23`):

```markdown
## Setup

完了条件: PROJECT が確定していること。

1. Skill tool で superpowers:subagent-driven-development を読み込む。以後、Substitutions 節に挙げた項目以外はすべて SDD の指示に従う（Pre-Flight Plan Review・レビュー・progress ledger・File Handoffs・Red Flags を含む）。SDD の scripts（task-brief / review-package）は SDD 読み込み時に表示される base directory から解決する
2. `PROJECT` = 作業 worktree の絶対パスを確定する
```

Replace with:

```markdown
## Setup

完了条件: `PROJECT`・`TEAM`・agmsg の両 identity が確定していること。

1. Skill tool で superpowers:subagent-driven-development を読み込む。以後、Substitutions 節に挙げた項目以外はすべて SDD の指示に従う（Pre-Flight Plan Review・レビュー・progress ledger・File Handoffs・Red Flags を含む）。SDD の scripts（task-brief / review-package）は SDD 読み込み時に表示される base directory から解決する
2. `PROJECT` = 作業対象ディレクトリの絶対パスを確定する（多くの場合 worktree だが、単一ブランチでの作業等 worktree を使わないケースもあり、`PROJECT` はそのどちらでもよい）
3. `TEAM` を `PROJECT` から導出する（例: `cdd-$(basename "$PROJECT")`。既存の `AGENT="impl-$(basename "$PROJECT")"` と同じ命名思想。`PROJECT` のパスから決定的に導出できればよい）
4. 以下を idempotent に実行する（既に実行済みでも成功扱い）:

   ```sh
   ~/.agents/skills/agmsg/scripts/join.sh "$TEAM" claude claude-code "$PROJECT"
   ~/.agents/skills/agmsg/scripts/join.sh "$TEAM" codex codex "$PROJECT"
   ~/.agents/skills/agmsg/scripts/delivery.sh set monitor codex "$PROJECT"
   ```

5. Claude 自身の delivery mode を確認し、`monitor` でなければ Monitor tool を起動する:

   ```sh
   ~/.agents/skills/agmsg/scripts/delivery.sh status claude-code "$PROJECT"
   ```

   `mode: monitor` でなければ `~/.agents/skills/agmsg/scripts/delivery.sh set monitor claude-code "$PROJECT"` を実行し、出力される `AGMSG-DIRECTIVE` の指示に従って Monitor tool を起動する
6. `TEAM` は plan 実行全体を通して使い回す（後述 Run Teardown まで解体しない）。同一 `PROJECT` に対する再実行は既存 team に join するだけで、新規 team は作らない
```

- [ ] **Step 6: Verify the Setup commands against the real dotfiles worktree**

```sh
cd /Users/takanokenichi/GitHub/panicboat/dotfiles/.claude/worktrees/feat-cdd-multiplexer-support
TEAM="cdd-$(basename "$PWD")"
~/.agents/skills/agmsg/scripts/join.sh "$TEAM" claude claude-code "$PWD"
~/.agents/skills/agmsg/scripts/join.sh "$TEAM" codex codex "$PWD"
~/.agents/skills/agmsg/scripts/delivery.sh set monitor codex "$PWD"
~/.agents/skills/agmsg/scripts/delivery.sh status claude-code "$PWD"
```

Expected: all four commands succeed (exit 0); the last one prints `mode: monitor` (this session already has monitor mode + a live Monitor task, so it should already say `monitor`). Re-running the two `join.sh` calls a second time must not error (idempotency).

- [ ] **Step 7: Commit**

```bash
git add .claude/skills/codex-driven-development/SKILL.md
git commit -s -m "refactor(codex-driven-development): generalize prerequisites and setup to multiplexer + agmsg"
```

---

### Task 3: Rewrite the Dispatch section

**Files:**
- Modify: `.claude/skills/codex-driven-development/SKILL.md:58-109` (current Dispatch section)

**Interfaces:**
- Consumes: `TEAM`, `PROJECT` from Task 2; adapter operations from Task 1.
- Produces: `PANE`, and the "push mode" / "fallback mode" decision that Task 4 branches on.

- [ ] **Step 1: Read the current Dispatch section in full**

Read `SKILL.md:58-109` in the editor before making changes — lines 58-68 contain the batch-validation guidance ("Dispatch 前チェック") that must be preserved unchanged; only steps 3-5 (lines 70-108, pane-creation and completion-signal) change.

- [ ] **Step 2: Replace the pane-creation steps**

Current (`SKILL.md:70-108`, the part that changes — the "Dispatch 前チェック" paragraph above it, lines 60-68, stays untouched):

```markdown
1. BASE commit を記録し、SDD の task-brief script で brief file を生成する
2. codex-dispatch-prompt.md の `{{...}}` をすべて埋め、brief と同じディレクトリの `task-N-dispatch.md` に書く
3. Codex 用の pane を作る（controller の pane を分割、cwd を worktree に）。**`PANE` が取れたことを確認してから進む**——取れないまま進むと以降の全コマンドが空文字列を target にして無関係なエラーを出す:

   ```sh
   PANE=$(herdr pane split --current --direction right --cwd "$PROJECT" | jq -r '.result.pane.pane_id')
   case "$PANE" in ""|null) echo "SPLIT_FAILED"; exit 1;; esac
   ```

4. **dispatch prompt を argv に載せて** Codex を起動する。agent 名は herdr server 全体で一意でなければならないため worktree 名から導出する:

   ```sh
   AGENT="impl-$(basename "$PROJECT")"
   BOOT="Read $PROJECT/path/to/task-N-dispatch.md and follow it exactly."   # 絶対パスに置き換える
   for i in $(seq 1 10); do
     OUT=$(herdr agent start "$AGENT" --kind codex --pane "$PANE" --timeout 120000 -- "$BOOT" 2>&1)
     printf '%s' "$OUT" | grep -q '"error"' || break
     printf '%s' "$OUT" | grep -q 'agent_name_taken' && break   # 待っても解消しない
     sleep 2
   done
   printf '%s' "$OUT" | grep -q '"error"' && { echo "START_FAILED"; printf '%s\n' "$OUT"; exit 1; }
   ```

   `--` 以降は codex の positional PROMPT にそのまま渡る（`codex [OPTIONS] [PROMPT]`）。**prompt が起動時に確定するので TUI への投入競合が無い**。起動直後にモーダルが出ても prompt はキューされ、モーダルを閉じた時点で自動投入される。リトライは `agent_pane_busy`（split 直後の shell がまだ idle 判定されていない）向けで、`agent_name_taken` は待っても解消しないので即座に抜けて `AGENT` に suffix を足して 1 度だけやり直す。それ以外でリトライが枯渇したらユーザーに報告して指示を待つ
5. prompt が処理に入ったことを確認する。`agent start` 直後は `idle`（まだ処理を始めていない）を通るため**単発チェックでは判定できない**。遷移するまでポーリングする:

   ```sh
   for i in $(seq 1 20); do
     ST=$(herdr agent get "$PANE" | jq -r '.result.agent.agent_status')
     case "$ST" in working|done|blocked) break;; esac
     sleep 3
   done
   echo "status=$ST"
   ```

   - `working` / `done` — prompt は届いている。Await へ進む
   - `blocked` — モーダルで入力待ち。Failure Modes の該当行で解消する
   - `idle` のまま枯渇 — `tail -1 ~/.codex/history.jsonl` の末尾が今の boot prompt かを見る。一致すれば届いており Codex が遅いだけ、不一致なら届いていない
```

Replace with:

```markdown
1. BASE commit を記録し、SDD の task-brief script で brief file を生成する
2. codex-dispatch-prompt.md の `{{...}}`（`{{TEAM}}` を含む。Task 6 でテンプレート自体を multiplexer 名を含まない汎用の文言に更新済み）をすべて埋め、brief と同じディレクトリの `task-N-dispatch.md` に書く
3. `multiplexer-adapters.md` の選ばれた adapter の `create_pane(cwd=$PROJECT)` を実行する。**`PANE` が取れたことを確認してから進む**——取れないまま進むと以降の全コマンドが空文字列を target にして無関係なエラーを出す:

   ```sh
   PANE="$(<adapter の create_pane コマンドの出力から pane id / handle を抽出>)"
   case "$PANE" in ""|null) echo "CREATE_PANE_FAILED"; exit 1;; esac
   ```

4. adapter の `run(pane_id, argv)` で **dispatch prompt を argv に載せて** Codex を起動する。agent 名/pane 名はサーバー全体で一意でなければならないため worktree 名から導出する（herdr の場合。Orca は pane 単位で衝突しないため不要）:

   ```sh
   AGENT="impl-$(basename "$PROJECT")"
   BOOT="Read $PROJECT/path/to/task-N-dispatch.md and follow it exactly."   # 絶対パスに置き換える
   ```

   `multiplexer-adapters.md` の `run` の行に従って `codex "$BOOT"` を起動する。**prompt が起動時に確定するので TUI への投入競合が無い**。起動直後にモーダルが出ても prompt はキューされ、モーダルを閉じた時点で自動投入される
5. 起動直後の一度きりの対話ダイアログ（`Do you trust the contents of this directory?` / `Hooks need review` / update 確認）が出たら、adapter の `read(pane_id)` で内容を判定し、`send_text`/`send_keys` で応答する。**trust 系（directory trust・hooks trust）はユーザー承認を得てから**応答する。自動承認しない
6. **bridge armed 確認**: 起動から一定時間（30秒を目安）、以下を数秒おきにポーリングする:

   ```sh
   ~/.agents/skills/agmsg/scripts/delivery.sh status codex "$PROJECT"
   ```

   - `Codex bridge: $TEAM/codex alive (pid ...)` が出たら → 以降このバッチは **push mode**（Redispatch/Await 節を参照）
   - タイムアウトしても出なければ → 以降このバッチは **fallback mode**（現行の TUI 注入 + `agent_status`/`herdr agent read` ポーリングに切り替える）。ユーザーには push mode が使えなかった旨を報告する
```

- [ ] **Step 3: Verify the bridge-armed check against the real environment**

```sh
cd /Users/takanokenichi/GitHub/panicboat/dotfiles/.claude/worktrees/feat-cdd-multiplexer-support
TEAM="cdd-$(basename "$PWD")"
~/.agents/skills/agmsg/scripts/delivery.sh status codex "$PWD"
```

Expected: prints `mode: monitor` (set in Task 2's verification) and either `Codex bridge: $TEAM/codex alive (pid ...)` if a Codex session for this identity is currently running, or `Codex bridge: $TEAM/codex not running` if not — both are valid outputs to confirm the grep pattern used in the section text (`grep -q 'alive'`) works against real output; run it once with no live Codex session (expect "not running") to confirm the fallback path's trigger string matches.

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/codex-driven-development/SKILL.md
git commit -s -m "refactor(codex-driven-development): route Dispatch through the multiplexer adapter and bridge-armed check"
```

---

### Task 4: Rewrite Redispatch and Await

**Files:**
- Modify: `.claude/skills/codex-driven-development/SKILL.md:110-191` (current Await section at 110-152, Redispatch section at 153-191 — Await comes first in the file, Redispatch second; this task edits both)

**Interfaces:**
- Consumes: `TEAM`, `PROJECT`, `PANE`, and the push-mode/fallback-mode decision from Task 3.
- Produces: nothing new consumed by later tasks except the mode decision already produced in Task 3.

- [ ] **Step 1: Replace the Redispatch section**

Current (`SKILL.md:153-190`):

```markdown
## Redispatch

NEEDS_CONTEXT・BLOCKED・レビュー指摘の fix は、生きた Codex に投げ返す（pane を閉じない）。完了条件: prompt 投入を確認し、Await が完了したこと。

1. dispatch file の末尾に `## Redispatch N` 見出しで回答・追加 context・findings を追記する（記録用。fix の内容要件は SDD の fix dispatch に従う）
2. 生きた Codex に投げる。既に起動済みなので argv は使えず、TUI への投入になる:

   ```sh
   herdr pane send-text "$PANE" "<回答/findings。詳細は task-N-dispatch.md の ## Redispatch N を見よ>"
   sleep 2
   herdr pane send-keys "$PANE" Enter
   ```

   `herdr agent prompt` を使わない。`--wait --until working` を付けても、起動直後の一過性の `working` を拾って投入せずに成功を返すことがある（`--help` の "It does not track turns"）

   **send-text に含める文言に必ず「report file を上書きすること」を再度書く。** dispatch prompt にも同じ規約があるが、redispatch 経由でその指示を Codex に思い出させないと append されてしまい、次の Await が前ラウンドの STATUS で誤検知する。毎回 1 行入れるコストで stale 誤検知を確実に潰せる
3. **投入されたことを確認する。** 手順 2 は成否を返さないので、これが唯一の判定手段:

   ```sh
   tail -1 ~/.codex/history.jsonl
   ```

   Codex は受け取った prompt をここに追記する。行数が増え、末尾が今の prompt であることを確認する
4. Await を実行する。ただし report file には前ラウンドの `STATUS:` が既にあり第一信号が誤検知する。「Await」節末尾の「`STATUS:` が信号として使えない場合の代替信号」を参照して、commit 数か round 見出しに切り替える。commit 数ベースの例:

   ```sh
   EXPECTED=<このラウンドで積むはずの累計 commit 数>
   while :; do
     N=$(cd "$PROJECT" && git rev-list --count "$BASE"..HEAD 2>/dev/null || echo 0)
     [ "$N" -ge "$EXPECTED" ] && { OUTCOME=commits; break; }
     ST=$(herdr agent get "$PANE" 2>/dev/null | jq -r '.result.agent.agent_status')
     case "$ST" in blocked) OUTCOME="state:blocked"; break;; esac
     [ "$(date +%s)" -ge "$DEADLINE" ] && break
     sleep 5
   done
   ```

生きた Codex に投げ返すことで作業中の文脈を保持する。バッチ境界を跨ぐとき（次バッチ）だけ pane を閉じて fresh に開き直す（「Batching Strategy」参照）。バッチ内の fix round では常に同じ pane を live で使う。
```

Replace with:

```markdown
## Redispatch

NEEDS_CONTEXT・BLOCKED・レビュー指摘の fix は、生きた Codex に投げ返す（pane を閉じない）。完了条件: 投入を確認し、Await が完了したこと。モードは Dispatch 節末尾で決まった push mode / fallback mode に従う。

1. dispatch file の末尾に `## Redispatch N` 見出しで回答・追加 context・findings を追記する（記録用。fix の内容要件は SDD の fix dispatch に従う）
2. **push mode**: agmsg で送るだけでよい。

   ```sh
   ~/.agents/skills/agmsg/scripts/send.sh "$TEAM" claude codex "<回答/findings。詳細は task-N-dispatch.md の ## Redispatch N を見よ。完了したら report file を上書きして STATUS を送ること>"
   ```

   ビジー中の Codex に送っても実行中のターンを中断せず、完了後に次のターンとして安全にキューされることを実地確認済み。**送信するメッセージ本文に必ず「report file を上書きすること」を再度書く**——dispatch prompt にも同じ規約があるが、redispatch 経由で思い出させないと append されてしまい、次の Await が前ラウンドの STATUS で誤検知する

3. **fallback mode**: 現行どおり multiplexer adapter の `send_text`/`send_keys` で TUI に投入する:

   ```sh
   # herdr の場合
   herdr pane send-text "$PANE" "<回答/findings>"
   sleep 2
   herdr pane send-keys "$PANE" Enter
   # Orca の場合は send_text と send_keys(Enter) を分離して2回送る（multiplexer-adapters.md 参照）
   ```

   `herdr agent prompt` は使わない。`--wait --until working` を付けても、起動直後の一過性の `working` を拾って投入せずに成功を返すことがある（`--help` の "It does not track turns"）。**投入されたことを確認する**（`tail -1 ~/.codex/history.jsonl` の行数が増え、末尾が今の prompt であること）
4. Await を実行する（次節）。fallback mode の場合、report file には前ラウンドの `STATUS:` が既にあり第一信号が誤検知するため、「Await」節末尾の「`STATUS:` が信号として使えない場合の代替信号」を参照して commit 数か round 見出しに切り替える

生きた Codex に投げ返すことで作業中の文脈を保持する。バッチ境界を跨ぐとき（次バッチ）だけ pane を閉じて fresh に開き直す（「Batching Strategy」参照）。バッチ内の fix round では常に同じ pane を live で使う。
```

- [ ] **Step 2: Replace the Await section**

Current (`SKILL.md:110-152`, up to but not including `## Redispatch`):

```markdown
## Await

完了条件: Codex の停止を検知し、report の STATUS を読んだこと。

1. report file の `STATUS:` を第一信号、`agent_status` を補助信号として待つ。`WAIT_BUDGET` は打ち切り線:

   ```sh
   REPORT="/abs/path/to/task-N-report.md"   # 実際の絶対パスに置き換える
   WAIT_BUDGET=1200   # 秒
   DEADLINE=$(( $(date +%s) + WAIT_BUDGET ))
   OUTCOME=timeout
   while :; do
     grep -q '^STATUS:' "$REPORT" 2>/dev/null && { OUTCOME=report; break; }
     ST=$(herdr agent get "$PANE" 2>/dev/null | jq -r '.result.agent.agent_status')
     case "$ST" in done|blocked) OUTCOME="state:$ST"; break;; esac
     [ "$(date +%s)" -ge "$DEADLINE" ] && break
     sleep 5
   done
   echo "OUTCOME=$OUTCOME"
   ```

   完了状態に `idle` を含めない。`idle` は初回 prompt を処理する前にも通る状態で、完了と区別できない。turn の完了は integration が `done` として報告する
2. `OUTCOME=state:blocked` なら実行途中の承認要求。Failure Modes に従って解消し、ループに戻る
3. `OUTCOME=report` なら STATUS 行（DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED）を読む。STATUS が「何が起きたか」の source of truth
4. `OUTCOME=timeout` なら停止ではなくチェックポイントとして扱う（Failure Modes 参照）
5. STATUS は SDD の Handling Implementer Status に従って処理する。DONE → SDD どおり review-package → task reviewer subagent

**report file を第一信号にする理由**: `STATUS:` 行は dispatch prompt が Codex に「最後に書け」と指示している本 skill 自身の契約であり、herdr の state machine から独立している。`herdr agent wait` は使わない——`--until` の集合を間違えると無言で永久にブロックし、停止と正常な待機の区別が最も付きにくい形の失敗になる。

### `STATUS:` が信号として使えない場合の代替信号

初回 dispatch は `STATUS:` で問題ないが、以下の場面では `STATUS:` を第一信号にすると誤検知する。実運用で頻出:

- **redispatch 直後**: 前ラウンドの `STATUS: BLOCKED` (等) が report 先頭に残っており、Codex が上書きする前にループが「report あり」で即抜ける。ゼロ秒完了 → 実際は未着手というパターン
- **Codex が上書きし忘れる**: dispatch prompt に「上書きしろ」と書いてあっても、実際には append することがある。この場合 STATUS 行は「先頭のもの」しか読まれず、常に前ラウンドの結果として解釈される

このどちらかが疑わしい場面（= 全ての redispatch）では、**Codex の出力に依存しない信号**に切り替える。有力な選択肢:

- **commit 数** — バッチが期待する commit 数 (`N`) を事前に決めておき、`git rev-list --count $BASE..HEAD >= N` を第一信号にする。fix round の場合は `git rev-list --count $FIX_BASE..HEAD >= 1` (fix の追加コミット) で足りる
- **round 見出しの新規追加** — dispatch prompt に「`## Fix round N` 見出しを report に追記しろ」と書き、`grep -q "^## Fix round $N" "$REPORT"` を第一信号にする（この場合は overwrite ではなく append を要求）

どちらを使うかは round ごとに controller が選ぶ。commit 数ベースが最も堅牢（Codex の書き方に依存しない）。切り替えたときは `agent_status=blocked` の補助信号は残す（Codex が実行中モーダルで止まったら拾いたいため）。
```

Replace with:

```markdown
## Await

完了条件: Codex の完了通知を受け取り、report の STATUS を読んだこと。モードは Dispatch 節末尾で決まった push mode / fallback mode に従う。

**push mode**:

1. Claude 側の Monitor が Setup 節で有効化済みなので、Codex が dispatch prompt の指示どおり `send.sh` で送る `STATUS: <...>` 付きメッセージは非同期の task-notification として届く。届くまでブロッキングで待つ必要はない——他の作業を進めてよい
2. ただし「打ち切り線の無い待機」は禁止（Red Flags 参照）。通知が `WAIT_BUDGET`（1200秒を目安）内に届かない場合の安全網として、以下を軽くポーリングする:

   ```sh
   ~/.agents/skills/agmsg/scripts/inbox.sh "$TEAM" claude
   # 何も届いていなければ bridge がまだ生きているか確認する
   ~/.agents/skills/agmsg/scripts/delivery.sh status codex "$PROJECT"
   ```

   `inbox.sh` に STATUS 付きメッセージが見つかったら通知を受け取ったのと同じ扱いにする。`delivery.sh status` で bridge が落ちていたら（`not running` に変わっていたら）fallback mode に切り替える
3. 通知または `inbox.sh` で受け取った `STATUS:` 行（DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED）を読む。report file には実装内容の詳細（commit hashes、テスト結果、self-review メモ）が書かれているので、STATUS 受領後に report file を読んで内容を確認する
4. STATUS は SDD の Handling Implementer Status に従って処理する。DONE → SDD どおり review-package → task reviewer subagent

**fallback mode**（現行どおり）:

1. report file の `STATUS:` を第一信号、`agent_status`（herdr の場合のみ）を補助信号として待つ。`WAIT_BUDGET` は打ち切り線:

   ```sh
   REPORT="/abs/path/to/task-N-report.md"   # 実際の絶対パスに置き換える
   WAIT_BUDGET=1200   # 秒
   DEADLINE=$(( $(date +%s) + WAIT_BUDGET ))
   OUTCOME=timeout
   while :; do
     grep -q '^STATUS:' "$REPORT" 2>/dev/null && { OUTCOME=report; break; }
     # herdr の場合のみ agent_status を補助信号にする。Orca の fallback では read(pane_id) の出力を都度確認する
     [ "$(date +%s)" -ge "$DEADLINE" ] && break
     sleep 5
   done
   echo "OUTCOME=$OUTCOME"
   ```

2. `OUTCOME=report` なら STATUS 行を読む。`OUTCOME=timeout` なら停止ではなくチェックポイントとして扱う（Failure Modes 参照）
3. STATUS は SDD の Handling Implementer Status に従って処理する

### `STATUS:` が信号として使えない場合の代替信号

push mode・fallback mode いずれでも、以下の場面では report file の `STATUS:` を素朴に信じると誤検知する:

- **redispatch 直後**: 前ラウンドの `STATUS: BLOCKED` (等) が report 先頭に残っており、Codex が上書きする前に「report あり」で即抜ける
- **Codex が上書きし忘れる**: dispatch/redispatch のメッセージに「上書きしろ」と書いてあっても、実際には append することがある

このどちらかが疑わしい場面（= 全ての redispatch）では、**Codex の出力に依存しない信号**に切り替える:

- **commit 数** — バッチが期待する commit 数 (`N`) を事前に決めておき、`git rev-list --count $BASE..HEAD >= N` を確認する。fix round の場合は `git rev-list --count $FIX_BASE..HEAD >= 1` で足りる
- **round 見出しの新規追加** — dispatch prompt に「`## Fix round N` 見出しを report に追記しろ」と書き、`grep -q "^## Fix round $N" "$REPORT"` を確認する（この場合は overwrite ではなく append を要求）

commit 数ベースが最も堅牢（Codex の書き方に依存しない）。push mode でも、STATUS 通知を受け取った後にこれらで裏取りしてよい。
```

- [ ] **Step 3: Verify the agmsg inbox/status fallback commands against the real environment**

```sh
cd /Users/takanokenichi/GitHub/panicboat/dotfiles/.claude/worktrees/feat-cdd-multiplexer-support
TEAM="cdd-$(basename "$PWD")"
~/.agents/skills/agmsg/scripts/inbox.sh "$TEAM" claude
```

Expected: either "No new messages." or a list of pending messages — both are valid; confirms the command runs without error against this session's live team.

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/codex-driven-development/SKILL.md
git commit -s -m "refactor(codex-driven-development): route Redispatch/Await through agmsg with a TUI fallback"
```

---

### Task 5: Split Teardown, update Failure Modes and Red Flags

**Files:**
- Modify: `.claude/skills/codex-driven-development/SKILL.md:192-197` (current Teardown)
- Modify: `.claude/skills/codex-driven-development/SKILL.md:199-210` (current Failure Modes table)
- Modify: `.claude/skills/codex-driven-development/SKILL.md:212-226` (current Red Flags — line numbers will have shifted after Tasks 2-4's edits; locate by the `## Red Flags` heading instead of trusting these numbers)

**Interfaces:**
- Consumes: `TEAM`, `PROJECT` from Task 2; `PANE` from Task 3.

- [ ] **Step 1: Replace the Teardown section**

Current:

```markdown
## Teardown

タスクの review が通ったら、または run を中断するときに実行する。完了条件: 対象 pane が閉じていること。

1. `herdr pane close "$PANE"`（既に閉じている場合のエラーは想定内として続行）
2. 全タスク完了後、`herdr pane list` で残っている implementer pane を確認し、あれば同様に `herdr pane close <PANE_ID>` で閉じる
```

Replace with:

```markdown
## Teardown

2つの異なるライフサイクルに分かれる。pane の寿命と `TEAM`/identity の寿命は一致しない——`TEAM` は plan 実行全体で使い回すため、バッチごとに解体しない。

**Pane Teardown**（タスク/バッチの review が通ったら都度実行）
1. adapter の `close_pane(pane_id)` で対象 pane を閉じる（既に閉じている場合のエラーは想定内として続行）
2. `TEAM`/identity は解体しない。次のバッチも同じ `TEAM` に join したまま新しい pane を作る

**Run Teardown**（plan 実行全体が完了した最後に1回、または run を中断するときに実行）
1. 残っている implementer pane がないか確認し、あれば同様に `close_pane` で閉じる
2. 以下で agmsg の identity を解除する:

   ```sh
   ~/.agents/skills/agmsg/scripts/reset.sh "$PROJECT" codex codex
   ~/.agents/skills/agmsg/scripts/reset.sh "$PROJECT" claude-code claude
   ```
```

- [ ] **Step 2: Add new rows to the Failure Modes table**

Locate the `## Failure Modes` table (the row order in the existing file must be preserved; add the new rows at the end of the table, before `## Red Flags`). Append these four rows:

```markdown
| bridge が `WAIT_BUDGET` 内に arm しない | Codex CLI バージョン非互換、agmsg app-server 起動失敗等（BETA機能） | fallback mode に切り替えて続行する。ユーザーには push mode が使えなかった旨を報告する |
| 同一 `PROJECT` で2つの生きた Codex pane が同時に存在する | agmsg の identity 衝突で bridge/thread が競合し、片方の bridge しか arm されない | 現行設計では 1 pane = 1 バッチが前提のため通常発生しない。並行バッチを将来サポートする場合は別途設計が必要 |
| `.codex/hooks.json` が git 管理下に出現する | `delivery.sh set monitor` の副作用でプロジェクトの working tree に書き出される | `.git/info/exclude` に `/.codex/hooks.json` を追加する（Setup 実行時に未対応なら確認する） |
| Orca で `send_text`+`send_keys` を同時送信すると `agent_prompt_blocked` になる | Orca 側のエージェント自動化ガード（詳細な発火条件は未解明） | text と enter を分離して2回に分けて送る（`multiplexer-adapters.md` 参照） |
```

- [ ] **Step 3: Update the Red Flags list**

Current entries that name herdr specifically:

```markdown
- herdr session 外で実行する（pane split の元 pane が無い）
- codex integration 未導入で実行する（`agent_status` が更新されず Await の補助信号が死ぬ）
```

Replace with:

```markdown
- 使える multiplexer が無い状態で実行する（pane を作る元 pane が無い）
- agmsg 未導入で実行する（push mode が使えず、常に fallback mode に落ちる）
```

Leave every other Red Flags line unchanged, including `- \`herdr agent start\` の出力を捨てる（起動失敗に気づけない）` — it names herdr but remains an accurate herdr-specific caution (not a false "herdr is the only option" claim), same as the herdr-specific Dispatch/Redispatch fallback-mode commands kept elsewhere in this file.

- [ ] **Step 4: Commit**

```bash
git add .claude/skills/codex-driven-development/SKILL.md
git commit -s -m "refactor(codex-driven-development): split pane/run teardown, update failure modes and red flags"
```

---

### Task 6: Update the dispatch prompt template

**Files:**
- Modify: `.claude/skills/codex-driven-development/codex-dispatch-prompt.md`

**Interfaces:**
- Consumes: `TEAM` (new `{{TEAM}}` placeholder the controller must fill, alongside the existing `{{PROJECT}}` etc.).

- [ ] **Step 1: Generalize the "running inside herdr" line**

Current (`codex-dispatch-prompt.md:7`):

```markdown
You are the implementer for one task of a larger plan, running as a Codex agent inside herdr. Work only on this task, inside `{{PROJECT}}`.
```

Replace with:

```markdown
You are the implementer for one task of a larger plan, running as a Codex agent inside a multiplexer pane. Work only on this task, inside `{{PROJECT}}`.
```

- [ ] **Step 2: Add the agmsg completion-message requirement to the Report section**

Current (`codex-dispatch-prompt.md:32-41`):

```markdown
## Report

The task is complete only when you have done both, in this order:

1. Write your full report to `{{REPORT_ABSOLUTE_PATH}}`, starting with a first line exactly `STATUS: <one of DONE, DONE_WITH_CONCERNS, NEEDS_CONTEXT, BLOCKED>`, followed by: commit hashes with messages, tests run (command and output), self-review notes, concerns and open questions.
2. Stop and wait. The controller detects completion from herdr and reads your report.

**On redispatch, OVERWRITE the report file — do not append.** The controller uses the first `STATUS:` line as the completion signal, and a stale `STATUS: BLOCKED` from a previous round would fire the completion detector on this round's redispatch before you finish. Rewrite the whole file with the new round's final status on line 1.

If NEEDS_CONTEXT or BLOCKED: put your questions or blocker details in the report file, set the STATUS line accordingly, then stop. The controller will send answers as a new prompt in this same session — you keep your context. Do not tear anything down. Your BLOCKED verdict is welcomed — plan defects are the controller's job to rule on, not yours to work around.
```

Replace with:

```markdown
## Report

The task is complete only when you have done all three, in this order:

1. Write your full report to `{{REPORT_ABSOLUTE_PATH}}`, starting with a first line exactly `STATUS: <one of DONE, DONE_WITH_CONCERNS, NEEDS_CONTEXT, BLOCKED>`, followed by: commit hashes with messages, tests run (command and output), self-review notes, concerns and open questions.
2. Send your completion signal via agmsg — this is how the controller knows you're done, do not skip it even if you think no one is listening:

   ```sh
   ~/.agents/skills/agmsg/scripts/send.sh {{TEAM}} codex claude "STATUS: <same status as line 1 of your report> <one-sentence summary>"
   ```

3. Stop and wait. The controller reads your agmsg message and your report.

**On redispatch, OVERWRITE the report file — do not append.** The controller uses the first `STATUS:` line as the source of truth for what happened, and a stale `STATUS: BLOCKED` from a previous round would be misread on this round if left in place. Rewrite the whole file with the new round's final status on line 1. Send the agmsg completion message (step 2) every time, including on redispatch — the controller may be waiting on it even when the report file's `STATUS:` line can't be trusted as a signal.

If NEEDS_CONTEXT or BLOCKED: put your questions or blocker details in the report file, set the STATUS line accordingly, send the agmsg message (step 2) with the same status, then stop. The controller will send answers as a new agmsg message or a new prompt in this same session — you keep your context. Do not tear anything down. Your BLOCKED verdict is welcomed — plan defects are the controller's job to rule on, not yours to work around.
```

- [ ] **Step 3: Add `{{TEAM}}` to the controller fill-in instructions**

Current (`codex-dispatch-prompt.md:3`):

```markdown
Controller instructions: fill every `{{...}}`, write the result to `task-N-dispatch.md` next to the task brief. On redispatch, append a `## Redispatch N` section to the same file instead of rewriting it. Everything below the rule is the dispatch content.
```

This line already says "fill every `{{...}}`", which covers the new `{{TEAM}}` placeholder without further wording changes — no edit needed here, but note it explicitly so the next step's verification checks for it.

- [ ] **Step 4: Verify no unresolved herdr references remain in the file**

```sh
grep -n "herdr" .claude/skills/codex-driven-development/codex-dispatch-prompt.md
```

Expected: no output (empty). If any line prints, it was missed — go back and generalize it.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/codex-driven-development/codex-dispatch-prompt.md
git commit -s -m "refactor(codex-driven-development): add agmsg completion signal to dispatch prompt template"
```

---

### Task 7: Update the project CLAUDE.md Plan Execution wording

**Files:**
- Modify: `.claude/CLAUDE.md`

**Interfaces:** none (standalone doc fix).

- [ ] **Step 1: Replace the stale herdr-only description**

Current (`.claude/CLAUDE.md`, under `### Plan Execution`):

```markdown
1. codex-driven-development（実装を Codex に委譲してトークン使用量を分散。herdr session 内であることが前提）
```

Replace with:

```markdown
1. codex-driven-development（実装を Codex に委譲してトークン使用量を分散。対応する multiplexer（herdr/Orca）のセッション内であることが前提）
```

- [ ] **Step 2: Verify no other file in the repo references the old wording**

```sh
cd /Users/takanokenichi/GitHub/panicboat/dotfiles/.claude/worktrees/feat-cdd-multiplexer-support
grep -rn "herdr session 内であることが前提" . --include="*.md" 2>/dev/null
```

Expected: no output (empty) — confirms the only occurrence was the one just fixed.

- [ ] **Step 3: Commit**

```bash
git add .claude/CLAUDE.md
git commit -s -m "docs: update Plan Execution wording for multiplexer-generalized codex-driven-development"
```

---

## Final Verification

After all 7 tasks are committed, run this end-to-end sanity check before opening a PR:

- [ ] **Step 1: Confirm no stray herdr-only wording remains outside the herdr-specific rows of `multiplexer-adapters.md`**

```sh
cd /Users/takanokenichi/GitHub/panicboat/dotfiles/.claude/worktrees/feat-cdd-multiplexer-support
grep -n "herdr" .claude/skills/codex-driven-development/SKILL.md
```

Expected: every remaining hit is either inside a `herdr の場合` branch, a Failure Modes/Red Flags row that is genuinely herdr-specific, or a reference to `multiplexer-adapters.md` — no hit implies herdr is the *only* supported multiplexer.

- [ ] **Step 2: Confirm the plan's spec is fully covered**

Re-read `docs/superpowers/specs/2026-09-03-codex-driven-development-multiplexer-design.md` section by section and confirm each maps to a task above:
- Multiplexer Adapter Contract → Task 1
- Prerequisites, Setup → Task 2
- Dispatch → Task 3
- Redispatch, Await → Task 4
- Teardown, Failure Modes → Task 5
- (dispatch prompt changes implied by Dispatch/Await) → Task 6
- (CLAUDE.md drift) → Task 7 (not in spec explicitly — found during this plan's own self-review; covered anyway since it directly follows from the spec's goal)

- [ ] **Step 3: Push and open a draft PR**

```bash
git push -u origin feat/cdd-multiplexer-support
gh pr create --draft --title "Generalize codex-driven-development to a multiplexer adapter + agmsg communication" --body "$(cat <<'EOF'
## Summary
- Generalizes codex-driven-development's herdr-only prerequisite into a multiplexer adapter contract (herdr + Orca verified)
- Moves Redispatch/Await off TUI text injection onto agmsg's Codex monitor bridge, with a TUI-injection fallback when the bridge doesn't arm

## Test plan
- [ ] Dry-run Setup/Dispatch/Redispatch/Await against a real herdr session with a small throwaway task
- [ ] Dry-run the same against a real Orca session
- [ ] Confirm fallback mode still works when agmsg delivery mode is left `off`

Spec: docs/superpowers/specs/2026-09-03-codex-driven-development-multiplexer-design.md
EOF
)"
```

Note: pushing and opening the PR requires explicit user confirmation before running — do not run Step 3 without asking first, per this repository's git safety conventions.
