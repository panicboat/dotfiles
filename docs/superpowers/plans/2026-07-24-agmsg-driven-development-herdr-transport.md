# agmsg-driven-development herdr Transport Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `agmsg-driven-development` skill の implementer 委譲を、agmsg（tmux spawn + SQLite messaging）から herdr（socket API）へ全面置換する。

**Architecture:** 差分参照型は維持。SKILL.md は superpowers:subagent-driven-development（SDD）を invoke し、implementer 周りだけを herdr の `pane split` / `agent start` / `agent prompt` / `agent wait` / `pane close` に置換。task/final reviewer は Claude subagent のまま。tmux 資産は全 revert し、ansible は herdr install に転換。

**Tech Stack:** Claude Code skill (Markdown), herdr 0.7.5 CLI (protocol 17), Codex CLI, jq, ansible (homebrew role)

**Spec:** `docs/superpowers/specs/2026-07-24-agmsg-driven-development-herdr-transport-design.md`

## Global Constraints

- skill 名は `agmsg-driven-development` 据え置き（rename しない）。description は herdr transport を明記
- herdr CLI は実機 VERIFIED 済み: `herdr pane split --current --direction right --cwd <PATH>` → 新 pane id は `.result.pane.pane_id`。`herdr agent start <NAME> --kind codex --pane <ID> --timeout <MS>`。`herdr agent prompt <TARGET> <TEXT>`。`herdr agent wait <TARGET> --until done --until blocked --timeout <MS>`（状態: idle/working/blocked/done/unknown）。`herdr pane close <PANE_ID>`。TARGET は pane id を使う（name も可）
- JSON parse は jq
- Codex への入力は `herdr agent prompt` のみ。完了検知は `herdr agent wait`。詳細報告は report file の STATUS 行が source of truth
- codex は herdr 組み込み integration。`herdr integration install codex` が `~/.codex/herdr-agent-state.sh` を入れて状態検出を有効化する（未導入では done/blocked を検出できない）
- コミットは `git commit -s`。`Co-Authored-By` 禁止。コミットメッセージは英語
- 無関係な変更（`.claude/settings.json`・`.codex/config.toml` の既存差分）をコミットに含めない

---

### Task 1: Rewrite SKILL.md and codex-dispatch-prompt.md for herdr

**Files:**
- Modify (full rewrite): `.claude/skills/agmsg-driven-development/SKILL.md`
- Modify (full rewrite): `.claude/skills/agmsg-driven-development/codex-dispatch-prompt.md`

**Interfaces:**
- Consumes: 実機 VERIFIED の herdr CLI（Global Constraints）
- Produces: SKILL.md の Dispatch 節が同ディレクトリの `codex-dispatch-prompt.md` を参照。dispatch template の placeholder は `{{PROJECT}}` `{{ONE_LINE_TASK_CONTEXT}}` `{{INTERFACES_OR_NONE}}` `{{BRIEF_ABSOLUTE_PATH}}` `{{REPORT_ABSOLUTE_PATH}}` の 5 つ（agmsg 版の `{{TEAM}}` は削除）

- [ ] **Step 1: SKILL.md を全面書き換え**

`.claude/skills/agmsg-driven-development/SKILL.md` を以下の内容で上書きする:

````markdown
---
name: agmsg-driven-development
description: 実装 plan を実行するとき、implementer を herdr 経由で起動した Codex に委譲してトークン使用量を分散する。superpowers:subagent-driven-development の実行構造（タスクごとの実装 → タスクレビュー → 最終レビュー）は維持し、implementer 周りだけを置き換える。plan の実行方式として agmsg-driven-development が選択されたときに使用する。
---

# agmsg-Driven Development

superpowers:subagent-driven-development（以下 SDD）の実行構造を維持したまま、implementer を herdr 経由の Codex に置き換えて plan を実行する。実装（最もトークンを消費する工程）を Codex に移し、Claude には意図の判断——plan 管理・task brief 作成・レビュー裁定——を残す。skill 名の "agmsg" は agent-message-driven の概念ラベルで、transport の実体は herdr。

## Prerequisites

開始前に以下を確認する。ひとつでも欠けていれば、欠けている項目を報告して SDD での実行を提案する。

1. `command -v herdr` が成功する
2. herdr session 内である（`herdr pane current` が成功する）。session 外なら停止し、herdr を起動してその中で claude を動かすようユーザーに促す
3. codex integration が入っている（`herdr integration status | grep '^codex:'` が `installed` を含む）。未導入なら `herdr integration install codex` の実行を促す。これが無いと herdr は Codex の done/blocked を検出できない

## Setup

完了条件: PROJECT が確定していること。

1. Skill tool で superpowers:subagent-driven-development を読み込む。以後、Substitutions 節に挙げた項目以外はすべて SDD の指示に従う（Pre-Flight Plan Review・レビュー・progress ledger・File Handoffs・Red Flags を含む）。SDD の scripts（task-brief / review-package）は SDD 読み込み時に表示される base directory から解決する
2. `PROJECT` = 作業 worktree の絶対パスを確定する

## Substitutions

SDD の以下の項目だけを置き換える。表にない項目はすべて SDD のまま（task reviewer / final reviewer は SDD どおり Claude subagent）。

| SDD | 本 skill |
|---|---|
| Task tool で implementer subagent を dispatch | Dispatch 節の手順で Codex を herdr agent として起動 |
| implementer-prompt.md | 本 skill と同じディレクトリの codex-dispatch-prompt.md |
| implementer の返値による報告 | report file + herdr agent state（Await 節） |
| 質問回答・追加 context・fix の再依頼 | 生きた codex への `herdr agent prompt`（Redispatch 節） |
| implementer への Model Selection | Codex は既定モデル |

## Dispatch

タスクごとに実行する。完了条件: agent start が成功し、boot prompt を投入したこと。

1. BASE commit を記録し、SDD の task-brief script で brief file を生成する
2. codex-dispatch-prompt.md の `{{...}}` をすべて埋め、brief と同じディレクトリの `task-N-dispatch.md` に書く
3. Codex 用の pane を作る（controller の pane を分割、cwd を worktree に）:
   `PANE=$(herdr pane split --current --direction right --cwd "$PROJECT" | jq -r '.result.pane.pane_id')`
4. その pane で Codex を起動する:
   `herdr agent start implementer --kind codex --pane "$PANE" --timeout 120000`
   失敗したら `herdr pane close "$PANE"` で掃除して 1 回だけ再試行する。再失敗はユーザーに報告して指示を待つ
5. boot prompt を投入する:
   `herdr agent prompt "$PANE" "Read <dispatch file の絶対パス> and follow it exactly."`

## Await

完了条件: Codex の停止を検知し、report の STATUS を読んだこと。

1. `herdr agent wait "$PANE" --until done --until blocked --timeout 3600000` でブロックする
2. report file の STATUS 行（DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED）を読む。herdr state は「いつ読むか」、STATUS は「何が起きたか」の source of truth
3. timeout（wait が非ゼロ終了）なら report file を確認する。STATUS があればそれを採用。無ければ `herdr agent read "$PANE"` で pane 出力を採取してユーザーに報告し、指示を待つ（勝手に再起動しない）
4. STATUS は SDD の Handling Implementer Status に従って処理する。DONE → SDD どおり review-package → task reviewer subagent

## Redispatch

NEEDS_CONTEXT・BLOCKED・レビュー指摘の fix は、生きた Codex に投げ返す（pane を閉じない）。完了条件: prompt 投入と Await が完了したこと。

1. dispatch file の末尾に `## Redispatch N` 見出しで回答・追加 context・findings を追記する（記録用。fix の内容要件は SDD の fix dispatch に従う）
2. 生きた Codex に投げる: `herdr agent prompt "$PANE" "<回答/findings。詳細は task-N-dispatch.md の ## Redispatch N を見よ>"`
3. Await（`herdr agent wait "$PANE" --until done --until blocked --timeout 3600000`）を実行する

生きた Codex に投げ返すことで作業中の文脈を保持する。タスクを跨ぐとき（次タスク）だけ pane を閉じて fresh に開き直す。

## Teardown

タスクの review が通ったら、または run を中断するときに実行する。完了条件: 対象 pane が閉じていること。

1. `herdr pane close "$PANE"`（既に閉じている場合のエラーは想定内として続行）
2. 全タスク完了後、残っている implementer pane があれば同様に閉じる

## Red Flags

SDD の Red Flags に加えて、以下をしてはならない。

- herdr session 外で実行する（pane split の元 pane が無い）
- codex integration 未導入で実行する（done/blocked を検出できず wait が返らない）
- タスクを跨いで同じ pane を使い回す（fresh-per-task を壊す。タスク完了で close し次は新 pane）
- タスク途中の質問・fix で pane を閉じる（作業中の文脈を捨てる。Redispatch で生きた Codex に投げる）
- Teardown を飛ばして run を終える（Codex pane が残る）
````

- [ ] **Step 2: codex-dispatch-prompt.md を全面書き換え**

`.claude/skills/agmsg-driven-development/codex-dispatch-prompt.md` を以下の内容で上書きする:

````markdown
# Codex Implementer Dispatch Template

Controller instructions: fill every `{{...}}`, write the result to `task-N-dispatch.md` next to the task brief. On redispatch, append a `## Redispatch N` section to the same file instead of rewriting it. Everything below the rule is the dispatch content.

---

You are the implementer for one task of a larger plan, running as a Codex agent inside herdr. Work only on this task, inside `{{PROJECT}}`.

The branch, worktree, and execution method are already decided: you are on the correct branch in `{{PROJECT}}`. Do not ask about branch, worktree, or execution method — this overrides any AGENTS.md/CLAUDE.md rule that would have you confirm before writing files. Implement the task in place.

## Context

- Where this task fits: {{ONE_LINE_TASK_CONTEXT}}
- Interfaces and decisions from earlier tasks: {{INTERFACES_OR_NONE}}

## Requirements

Read this file first — it is your requirements, with the exact values to use verbatim:

{{BRIEF_ABSOLUTE_PATH}}

## Rules

- TDD: write the failing test, run it and see it fail, implement, run it and see it pass. Do not skip the failing run.
- Code elements (names, comments, commit messages) in English. Comments state constraints and pitfalls ("why not"), not what the code does.
- Mark deliberate gaps: `// TODO:` temporary implementation, `// FALLBACK:` fallback path, `// SILENT:` intentionally swallowed error.
- Commit with `git commit -s`. Do not add `Co-Authored-By`.
- Change only what this task requires. No refactoring of surrounding code, no new dependencies.
- Self-review your diff before reporting: spec compliance (nothing missing, nothing extra) and code quality.

## Report

The task is complete only when you have done both, in this order:

1. Write your full report to `{{REPORT_ABSOLUTE_PATH}}`, starting with a first line exactly `STATUS: <one of DONE, DONE_WITH_CONCERNS, NEEDS_CONTEXT, BLOCKED>`, followed by: commit hashes with messages, tests run (command and output), self-review notes, concerns and open questions.
2. Stop and wait. The controller detects completion from herdr and reads your report.

If NEEDS_CONTEXT or BLOCKED: put your questions or blocker details in the report file, set the STATUS line accordingly, then stop. The controller will send answers as a new prompt in this same session — you keep your context. Do not tear anything down.
````

- [ ] **Step 3: 検証**

実行:
```bash
grep -c '^## ' .claude/skills/agmsg-driven-development/SKILL.md
grep -o '{{[A-Z_]*}}' .claude/skills/agmsg-driven-development/codex-dispatch-prompt.md | sort -u
grep -c 'tmux\|despawn\|watch-once\|\.agents/skills/agmsg\|send\.sh\|inbox\.sh' .claude/skills/agmsg-driven-development/SKILL.md
```
期待: `## ` 見出しが 8（Prerequisites / Setup / Substitutions / Dispatch / Await / Redispatch / Teardown / Red Flags）。placeholder が `{{BRIEF_ABSOLUTE_PATH}}` `{{INTERFACES_OR_NONE}}` `{{ONE_LINE_TASK_CONTEXT}}` `{{PROJECT}}` `{{REPORT_ABSOLUTE_PATH}}` の 5 種。3 つ目の grep（tmux / despawn / watch-once / agmsg スクリプト参照の残存）が 0。skill 名の "agmsg" は据え置きなので検出対象に含めない

- [ ] **Step 4: コミット**

```bash
git add .claude/skills/agmsg-driven-development/SKILL.md .claude/skills/agmsg-driven-development/codex-dispatch-prompt.md
git commit -s -m "refactor(skills): switch agmsg-driven-development transport to herdr

Replace agmsg (tmux spawn + SQLite team messaging) with herdr's socket
API: pane split + agent start launch Codex, agent prompt drives it,
agent wait detects completion, pane close tears it down. Live-agent
prompt keeps in-task context, so questions and fixes no longer destroy
and respawn the implementer. The skill name is retained."
```

---

### Task 2: Remove tmux artifacts and the tmux claude wrapper (dotfiles)

**Files:**
- Delete: `.config/tmux/tmux.conf`
- Modify: `.zshrc`（tmux 版 `claude()` ラッパーを削除）

**Interfaces:**
- Consumes: なし
- Produces: なし（後続タスクへの引き継ぎなし）

herdr 版の `claude()` 自動起動ラッパーは追加しない。herdr に初期コマンド起動の CLI が無い（`herdr` は TUI を起動/attach するのみ）ため、透過的な wrapper は作れない。代わりに SKILL.md の Prerequisites #2 が「herdr session 内か」を検出して案内する。

- [ ] **Step 1: tmux.conf を削除**

```bash
git rm .config/tmux/tmux.conf
```

- [ ] **Step 2: .zshrc から tmux 版 claude() を削除**

`.zshrc` の以下のブロックを削除する（`codex()` 関数と `brew-update()` 関数の間にある）:

```zsh
# agmsg-driven-development requires tmux: despawn only closes tmux panes, so
# Codex must be spawned inside tmux. Launch claude inside tmux when possible.
function claude() {
  if [[ -n "$TMUX" ]] || (( ! $+commands[tmux] )); then
    command claude "$@"
  else
    tmux new-session command claude "$@"
  fi
}
```

削除後、`.zshrc` に `tmux` の文字列が残っていないことを確認する。

- [ ] **Step 3: 検証**

```bash
test ! -e .config/tmux/tmux.conf && echo "tmux.conf removed"
grep -c 'tmux' .zshrc
```
期待: `tmux.conf removed`。`.zshrc` の `tmux` grep が 0

- [ ] **Step 4: 手元の symlink を撤去（環境・コミットなし）**

```bash
rm -f ~/.config/tmux/tmux.conf
rmdir ~/.config/tmux 2>/dev/null || true
test ! -e ~/.config/tmux/tmux.conf && echo "symlink removed"
```

- [ ] **Step 5: コミット**

```bash
git add .config/tmux/tmux.conf .zshrc
git commit -s -m "revert(tmux): drop tmux config and claude wrapper

The herdr transport does not use tmux. Remove the tmux.conf and the
tmux-launching claude wrapper; the skill's Prerequisites detects the
herdr session instead."
```

---

### Task 3: Switch ansible from tmux install to herdr install

**Files:**
- Modify: `~/GitHub/panicboat/ansible/roles/homebrew/tasks/main.yaml`（別リポジトリ。ブランチ `feat/install-tmux`）

**Interfaces:**
- Consumes: なし
- Produces: なし

このタスクは ansible リポジトリ（`~/GitHub/panicboat/ansible`、ブランチ `feat/install-tmux`）で作業する。PR #30 を「tmux install」から「herdr install」へ転換する。

- [ ] **Step 1: install リストの tmux を herdr に置き換える**

`roles/homebrew/tasks/main.yaml` の install リストの以下の行:
```yaml
      - tmux                    # Terminal multiplexer (required by agmsg-driven-development for spawn/despawn)
```
を削除し、alphabetical 位置（`helm` の後、`helmfile` の前）に以下を挿入する:
```yaml
      - herdr                   # Agent multiplexer (required by agmsg-driven-development to spawn/drive Codex)
```

- [ ] **Step 2: uninstall リストに tmux を戻す**

`uninstall homebrew packages` タスクの `name:` リストを、`gemini-cli` の前に `tmux` を加えて以下にする:
```yaml
    name:
      - tmux
      - gemini-cli
```

- [ ] **Step 3: 検証**

```bash
cd ~/GitHub/panicboat/ansible
grep -n 'herdr' roles/homebrew/tasks/main.yaml
grep -A4 'uninstall homebrew packages' roles/homebrew/tasks/main.yaml | grep -c tmux
grep -c '      - tmux ' roles/homebrew/tasks/main.yaml
```
期待: install リストに herdr が 1 行。uninstall ブロックに tmux が 1。install リスト側の `- tmux ` 行は 0

- [ ] **Step 4: コミット・プッシュ・PR タイトル更新**

```bash
cd ~/GitHub/panicboat/ansible
git commit -s -am "feat(homebrew): install herdr instead of tmux

agmsg-driven-development now spawns and drives Codex through herdr's
socket API, not tmux. Install herdr and return tmux to the uninstall
list."
git push
gh pr edit 30 --title "Install herdr instead of tmux"
```

---

### Task 4: Local environment cleanup (no commit)

**Files:** なし（手元環境のみ）

**Interfaces:**
- Consumes: なし
- Produces: 検証用に手動導入した tmux の除去

- [ ] **Step 1: 検証用 tmux を uninstall**

```bash
brew uninstall tmux 2>&1 | tail -2 || true
command -v tmux >/dev/null && echo "STILL PRESENT" || echo "tmux removed"
```
期待: `tmux removed`

- [ ] **Step 2: herdr テストサーバ／ソケットの残骸を除去**

```bash
pkill -f 'herdr server' 2>/dev/null || true
rm -rf /tmp/hd.sock /tmp/hd-client.sock /tmp/hd-cfg /tmp/hd-server.log 2>/dev/null || true
echo "herdr test residue cleaned"
```

- [ ] **Step 3: codex integration を導入し footprint を確認**

```bash
herdr integration install codex 2>&1 | tail -3
herdr integration status | grep '^codex:'
cd ~/GitHub/panicboat/dotfiles && git status --short .codex/
test -f ~/.codex/herdr-agent-state.sh && echo "hook installed"
```
期待: codex が `installed`。`~/.codex/herdr-agent-state.sh` が存在。`git status --short .codex/` に新たな差分が出た場合は、それが `.codex/config.toml`（dotfiles への symlink）への hook 登録かを確認し、追跡すべき設定なら別コミットとして dotfiles に取り込む（不要な差分なら revert する）。判断がつかなければユーザーに確認する

---

### Task 5: E2E verification — single run (interactive, user present)

**Files:**
- Create: `~/tmp/herdr-dd-e2e/`（使い捨て検証リポジトリ）

**Interfaces:**
- Consumes: Task 1〜4 のすべて
- Produces: Success Criteria の VERIFIED 判定（Task 6 の前提）

前提: herdr を起動し、その pane 内で claude を動かすこと。`command -v codex` と `command -v herdr` が成功し、`herdr integration status` で codex が installed であること。

- [ ] **Step 1: 検証リポジトリとミニ plan を作る**

```bash
mkdir -p ~/tmp/herdr-dd-e2e && cd ~/tmp/herdr-dd-e2e
git init -b main && git commit --allow-empty -s -m "chore: init"
mkdir -p docs/superpowers/plans
```
`~/tmp/herdr-dd-e2e/docs/superpowers/plans/2026-07-24-greet.md` に以下を書く:
```markdown
# Greet Script Implementation Plan

**Goal:** `greet.sh` が `hello <name>` を出力する。

## Global Constraints

- Bash のみ。依存追加なし

### Task 1: greet.sh

**Files:**
- Create: `greet.sh`
- Test: `test.sh`

- [ ] **Step 1:** `test.sh` を書く: `./greet.sh world` の出力が `hello world` と一致しなければ exit 1 する比較を含める。実行して失敗を確認（greet.sh 未作成のため）
- [ ] **Step 2:** `greet.sh` を実装して `chmod +x` する
- [ ] **Step 3:** `./test.sh` が exit 0 することを確認
- [ ] **Step 4:** `git add greet.sh test.sh && git commit -s -m "feat: add greet script"`
```

- [ ] **Step 2: skill を実行して 1 サイクル観察**

herdr の pane 内で新しい Claude Code セッションを `~/tmp/herdr-dd-e2e` から開始し、「`docs/superpowers/plans/2026-07-24-greet.md` を agmsg-driven-development で実行して」と依頼する。次を観察する:
- Prerequisites が herdr session と codex integration を検出して通過する
- `herdr pane split` で Codex pane が開き、`agent start` で Codex が起動する
- `agent wait` が done を検出し、report file の STATUS が読まれる
- レビュー指摘があれば、`agent prompt` で**同じ pane の生きた Codex** に fix が投げ返される（pane が閉じられない）ことを確認する
- タスク完了で `pane close` される

- [ ] **Step 3: TARGET 解決と addressing の確認**

Codex 起動中に別シェルで次を実行し、agent が pane id で addressable なことを確認する:
```bash
herdr agent list
herdr agent get "<Codex の pane id>"
```
期待: agent list に Codex が現れ、`agent get <pane_id>` が not_found を返さない

- [ ] **Step 4: 結果検証**

```bash
cd ~/tmp/herdr-dd-e2e
git log --format='%h %s %(trailers:key=Signed-off-by)' -3
./test.sh && echo PASS
herdr pane list | jq '[.result.panes[]? | select(.pane_id|startswith("w"))] | length'
```
期待: implementer の signoff 付きコミットが存在。`PASS`。残存 implementer pane が無い。spawn → 実装 → 完了検知 → review → close の一周と、途中の agent prompt 再投入が人手の介入なしで通ったことを VERIFIED として記録する

---

### Task 6: E2E verification — parallel worktrees (interactive, user present)

**Files:**
- Modify: `~/tmp/herdr-dd-e2e/`（worktree 2 本を追加）

**Interfaces:**
- Consumes: Task 5 の検証リポジトリと結果
- Produces: 並列分離の VERIFIED 判定

- [ ] **Step 1: worktree を 2 本作り、各々にミニ plan を置く**

```bash
cd ~/tmp/herdr-dd-e2e
git worktree add -b feat/a .claude/worktrees/feat-a main
git worktree add -b feat/b .claude/worktrees/feat-b main
mkdir -p .claude/worktrees/feat-a/docs/superpowers/plans .claude/worktrees/feat-b/docs/superpowers/plans
```
feat-a には `greet-a.sh`/`test-a.sh`（出力 `hello-a <name>`）、feat-b には `greet-b.sh`/`test-b.sh`（出力 `hello-b <name>`）を対象にした Task 5 Step 1 と同型のミニ plan を各 `docs/superpowers/plans/` に置く（ファイル名衝突を避ける）。

- [ ] **Step 2: 2 セッションを別々の herdr session で並行実行**

各 worktree から、別々の herdr session（例: `herdr --session a` と `herdr --session b`）の pane 内で Claude Code を開始し、各ミニ plan を同時に実行させる。

- [ ] **Step 3: 分離の検証**

両 run の実行中に、各 herdr session で `herdr pane list` / `herdr agent list` を確認する。
期待: 各 session の Codex pane が相手 run に現れない。pane id は session スコープで衝突しない。両 run とも signoff 付きコミット + テスト PASS で完了し、Codex pane が残らない（Success Criteria の並列分離を VERIFIED として記録）

- [ ] **Step 4: 後片付け**

```bash
rm -rf ~/tmp/herdr-dd-e2e
```
