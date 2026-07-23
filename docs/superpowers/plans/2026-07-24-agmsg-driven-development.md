# agmsg-Driven Development Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** superpowers:subagent-driven-development (SDD) の implementer を agmsg 経由の Codex に置き換える skill `agmsg-driven-development` を dotfiles に追加する。

**Architecture:** 差分参照型 skill。SKILL.md は SDD を invoke してプロセス全体に従い、implementer 周りだけを置換表で差し替える。Codex への入力は spawn の boot-prompt のみ、出力は agmsg メッセージ + report file のみという一方向規律。team は run（worktree）ごとに分離する。

**Tech Stack:** Claude Code skill (Markdown), agmsg scripts (`~/.agents/skills/agmsg/scripts/`), tmux, Codex CLI

**Spec:** `docs/superpowers/specs/2026-07-24-agmsg-driven-development-design.md`

## Global Constraints

- team 名 = `<リポジトリ名>-<branch-slug>`（slug = ブランチ名の `/` を `-` に置換）。identity は `leader`（controller）/ `implementer`（Codex）固定
- agmsg スクリプト呼び出しは常に TEAM・agent 名・PROJECT（worktree 絶対パス）を明示的に渡す。`join.sh` には `AGMSG_RESOLVE_PROJECT=0` を必ず付ける
- Codex への入力は `spawn.sh --boot-prompt` のみ。idle な Codex へ `send.sh` で送信してはならない
- SKILL.md は見出し英語・本文日本語。codex-dispatch-prompt.md は英語（agent 間プロトコル文書）
- コミットは `git commit -s`。`Co-Authored-By` 禁止。コミットメッセージは英語
- `.claude/settings.json` の変更（本作業と無関係な model 設定）をコミットに含めない

---

### Task 1: Skill files (SKILL.md + codex-dispatch-prompt.md)

**Files:**
- Create (overwrite the empty placeholder): `.claude/skills/agmsg-driven-development/SKILL.md`
- Create: `.claude/skills/agmsg-driven-development/codex-dispatch-prompt.md`

**Interfaces:**
- Consumes: なし（最初のタスク）
- Produces: SKILL.md の Dispatch 節が `codex-dispatch-prompt.md`（同一ディレクトリ・このファイル名）を参照する。template の placeholder 名は `{{TEAM}}` `{{PROJECT}}` `{{ONE_LINE_TASK_CONTEXT}}` `{{INTERFACES_OR_NONE}}` `{{BRIEF_ABSOLUTE_PATH}}` `{{REPORT_ABSOLUTE_PATH}}` の 6 つ。Task 3 の symlink がこの 2 ファイルを対象にする

- [x] **Step 1: SKILL.md を書く**

`.claude/skills/agmsg-driven-development/SKILL.md` に以下の内容を書く（0 バイトのプレースホルダを上書き）:

````markdown
---
name: agmsg-driven-development
description: 実装 plan を実行するとき、implementer を agmsg 経由で spawn した Codex に委譲してトークン使用量を分散する。superpowers:subagent-driven-development の実行構造（タスクごとの実装 → タスクレビュー → 最終レビュー）は維持し、implementer 周りだけを置き換える。plan の実行方式として agmsg-driven-development が選択されたときに使用する。
---

# agmsg-Driven Development

superpowers:subagent-driven-development（以下 SDD）の実行構造を維持したまま、implementer を agmsg 経由の Codex に置き換えて plan を実行する。実装（最もトークンを消費する工程）を Codex に移し、Claude には意図の判断——plan 管理・task brief 作成・レビュー裁定——を残す。

## Prerequisites

開始前に以下を確認する。ひとつでも欠けていれば、欠けている項目を報告して SDD での実行を提案する。

1. `command -v codex` が成功する
2. `test -x ~/.agents/skills/agmsg/scripts/spawn.sh` が成功する
3. tmux 内である（`test -n "$TMUX"`）。tmux 外の場合は OS terminal 起動になることをユーザーに伝え、続行の可否を確認する

## Setup

完了条件: AGMSG・PROJECT・TEAM の 3 値が確定し、leader の join が成功していること。

1. Skill tool で superpowers:subagent-driven-development を読み込む。以後、Substitutions 節に挙げた項目以外はすべて SDD の指示に従う（Pre-Flight Plan Review・レビュー・progress ledger・File Handoffs・Red Flags を含む）。SDD の scripts（task-brief / review-package）は SDD 読み込み時に表示される base directory から解決する
2. 変数を確定する:
   - `AGMSG=~/.agents/skills/agmsg/scripts`
   - `PROJECT` = 作業 worktree の絶対パス
   - `TEAM` = `<リポジトリ名>-<ブランチ名の / を - に置換した値>`。リポジトリ名は `basename "$(dirname "$(git -C "$PROJECT" rev-parse --path-format=absolute --git-common-dir)")"` で得る（worktree でも main checkout の名前になる）
3. leader を join する: `AGMSG_RESOLVE_PROJECT=0 "$AGMSG/join.sh" "$TEAM" leader claude-code "$PROJECT"`
4. 以後のすべての agmsg スクリプト呼び出しに TEAM・agent 名・PROJECT を明示的に渡す。`whoami.sh` の自動解決を使わない

`AGMSG_RESOLVE_PROJECT=0` を外してはならない: agmsg の project 解決は SessionStart marker・登録済み ancestor・git common dir から「session が属する project」を推定するため、worktree からの join が main checkout に巻き戻され、並列 run の登録が衝突する。

## Substitutions

SDD の以下の項目だけを置き換える。表にない項目はすべて SDD のまま（task reviewer / final reviewer は SDD どおり Claude subagent）。

| SDD | 本 skill |
|---|---|
| Task tool で implementer subagent を dispatch | Dispatch 節の手順で Codex を spawn |
| implementer-prompt.md | 本 skill と同じディレクトリの codex-dispatch-prompt.md |
| implementer の返値による報告 | agmsg メッセージ + report file（Await 節） |
| 質問回答・追加 context・fix の再依頼 | Redispatch 節（despawn → dispatch file 更新 → 再 spawn） |
| implementer への Model Selection | Codex は既定モデル。必要時のみ `spawn.sh --model` |

## Dispatch

タスクごとに実行する。完了条件: spawn が成功し、Codex の pane が起動していること。

1. BASE commit を記録し、SDD の task-brief script で brief file を生成する
2. codex-dispatch-prompt.md の `{{...}}` をすべて埋め、brief と同じディレクトリの `task-N-dispatch.md` に書く
3. spawn する: `"$AGMSG/spawn.sh" codex implementer --project "$PROJECT" --team "$TEAM" --boot-prompt "Read <dispatch file の絶対パス> and follow it exactly."`
4. spawn が name 保持エラーで失敗したら `"$AGMSG/despawn.sh" "$TEAM" leader implementer --force` を実行して 1 回だけ再試行する。再失敗したらユーザーに報告して指示を待つ

## Await

完了条件: implementer の status を受信し、despawn が完了していること。

1. `"$AGMSG/watch-once.sh" "$PROJECT" claude-code --name leader --team "$TEAM" --timeout 3600` を background で実行し、終了を待つ
2. exit 0: `"$AGMSG/inbox.sh" "$TEAM" leader` で受信する
3. exit 2（timeout）: report file を確認する。status が書かれていればそれを受信内容として扱う。書かれていなければ tmux pane の状態をユーザーに報告して指示を待つ（勝手に再 spawn しない）
4. 受信後 `"$AGMSG/despawn.sh" "$TEAM" leader implementer --force` で pane を閉じる
5. status は SDD の Handling Implementer Status に従って処理する。DONE → SDD どおり review-package → task reviewer subagent

## Redispatch

NEEDS_CONTEXT・BLOCKED・レビュー指摘の fix はすべて再 spawn で行う。完了条件: 更新済み dispatch file で Dispatch 手順 3〜4 と Await が完了していること。

1. dispatch file の末尾に `## Redispatch N` 見出しで回答・追加 context・findings を追記する（fix の内容要件は SDD の fix dispatch に従う）
2. Dispatch 手順 3〜4 と Await を実行する

idle な Codex は後送メッセージを受信できない。`send.sh` で Codex に指示を送ってはならない——Codex への入力は spawn の boot-prompt だけ。

## Teardown

final review 完了後、または run を中断するときに実行する。完了条件: `team.sh` が team not found を返すこと。

1. `"$AGMSG/despawn.sh" "$TEAM" leader implementer --force`（despawn 済みによるエラーは想定内として続行する）
2. `"$AGMSG/leave.sh" "$TEAM" leader`（最後のメンバーが抜けた team は削除される）
3. `"$AGMSG/team.sh" "$TEAM"` がエラーになることを確認する

## Red Flags

SDD の Red Flags に加えて、以下をしてはならない。

- idle な Codex へ send.sh で指示を送る（届かない。Redispatch する）
- whoami.sh / pwd の自動解決に頼る（worktree が main checkout に巻き戻される）
- `AGMSG_RESOLVE_PROJECT=0` なしで join する
- implementer を despawn せずに次の spawn をする（name 衝突で拒否される）
- Teardown を飛ばして run を終える（team と登録が残る）
````

- [x] **Step 2: codex-dispatch-prompt.md を書く**

`.claude/skills/agmsg-driven-development/codex-dispatch-prompt.md` に以下の内容を書く:

````markdown
# Codex Implementer Dispatch Template

Controller instructions: fill every `{{...}}`, write the result to `task-N-dispatch.md` next to the task brief. On redispatch, append a `## Redispatch N` section to the same file instead of rewriting it. Everything below the rule is the dispatch content.

---

You are the implementer for one task of a larger plan, running as agent `implementer` in team `{{TEAM}}`. Work only on this task, inside `{{PROJECT}}`.

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

The task is complete only when both steps below are done, in this order.

1. Write your full report to `{{REPORT_ABSOLUTE_PATH}}`: status, commit hashes with messages, tests run (command and output), self-review notes, concerns and open questions.
2. Send exactly one status message:

   `~/.agents/skills/agmsg/scripts/send.sh {{TEAM}} implementer leader "STATUS: <one line summary>"`

   where STATUS is one of DONE, DONE_WITH_CONCERNS, NEEDS_CONTEXT, BLOCKED.

If NEEDS_CONTEXT or BLOCKED: put your questions or blocker details in the report file, send the status, then stop. Answers arrive as an appended `## Redispatch` section of this dispatch file, read by a fresh session. Never wait for a reply in this session.
````

- [x] **Step 3: 検証**

実行:
```bash
grep -c '^## ' .claude/skills/agmsg-driven-development/SKILL.md
grep -o '{{[A-Z_]*}}' .claude/skills/agmsg-driven-development/codex-dispatch-prompt.md | sort -u
```
期待: SKILL.md の `## ` 見出しが 8（Prerequisites / Setup / Substitutions / Dispatch / Await / Redispatch / Teardown / Red Flags）。placeholder が `{{BRIEF_ABSOLUTE_PATH}}` `{{INTERFACES_OR_NONE}}` `{{ONE_LINE_TASK_CONTEXT}}` `{{PROJECT}}` `{{REPORT_ABSOLUTE_PATH}}` `{{TEAM}}` の 6 種のみ

- [x] **Step 4: コミット**

```bash
git add .claude/skills/agmsg-driven-development/SKILL.md .claude/skills/agmsg-driven-development/codex-dispatch-prompt.md
git commit -s -m "feat(skills): add agmsg-driven-development skill

Delta over superpowers:subagent-driven-development: keep the
per-task implement/review structure and swap only the implementer
for a Codex agent spawned via agmsg, distributing token usage
across providers. Codex input goes only through spawn boot-prompt
(idle Codex cannot receive messages); teams are isolated per
worktree run so parallel runs do not collide."
```

---

### Task 2: CLAUDE.md rule + role-protocol removal commit

**Files:**
- Modify: `.claude/CLAUDE.md`（Workflow 節に Plan Execution を追加。Team Collaboration 節の削除は作業ツリーに既に存在）
- Delete (already deleted in working tree, commit it): `.claude/skills/agmsg-role-protocol/SKILL.md`

**Interfaces:**
- Consumes: Task 1 の skill 名 `agmsg-driven-development`（ルール本文が参照）
- Produces: なし（最終タスクへの引き継ぎなし）

- [x] **Step 1: CLAUDE.md に Plan Execution 節を追加**

`.claude/CLAUDE.md` の `### Worktree Operations` ブロック末尾（`- 作業完了・マージ後は ...` の行）と `## Implementation` の間に以下を挿入する:

```markdown
### Plan Execution

- 実装 plan の実行を開始する前に、実行方式を以下から選択するようユーザーに確認する（skill 側の既定の提案より優先する）
  1. agmsg-driven-development（実装を Codex に委譲してトークン使用量を分散）
  2. subagent-driven-development（Claude subagent で実行）
  3. executing-plans（このセッションでインライン実行）
```

- [x] **Step 2: 検証**

実行: `grep -A 6 '^### Plan Execution' .claude/CLAUDE.md`
期待: 上記 6 行が表示される。`git diff .claude/CLAUDE.md` に Team Collaboration 節の削除と Plan Execution の追加だけが含まれる

- [x] **Step 3: コミット**

`.claude/settings.json` を含めないこと。

```bash
git add .claude/CLAUDE.md .claude/skills/agmsg-role-protocol/SKILL.md
git commit -s -m "feat(claude): require plan execution method choice, drop role-protocol

The resident-team protocol (agmsg-role-protocol + Team Collaboration
section) is replaced by the agmsg-driven-development skill: fresh
Codex per task keeps per-task context clean, which the resident team
could not. superpowers is a plugin, so the execution-method choice is
forced from CLAUDE.md (which outranks skills) instead of editing the
writing-plans handoff."
git status --short
```

期待: `git status --short` の出力が ` M .claude/settings.json` と未追跡の一時ファイルのみ

---

### Task 3: Symlink installation and stale symlink cleanup（環境設定・コミットなし）

**Files:**
- Create: `~/.claude/skills/agmsg-driven-development/`（ディレクトリ実体 + ファイル単位 symlink）
- Remove: `~/.claude/skills/agmsg-role-protocol/`, `~/.agents/skills/agmsg-role-protocol/`（削除済み skill への残骸）

**Interfaces:**
- Consumes: Task 1 の 2 ファイル（symlink 対象）
- Produces: `~/.claude/skills/agmsg-driven-development/` が全プロジェクトから user skill として解決可能になる（Task 4 の前提）

- [x] **Step 1: 残骸の確認と削除**

実行（削除前に中身を確認する）:
```bash
/bin/ls -la ~/.claude/skills/agmsg-role-protocol/ ~/.agents/skills/agmsg-role-protocol/
```
期待: dotfiles の削除済みパスを指す broken symlink（または旧ファイル）のみ。それ以外が見つかったらユーザーに報告して判断を仰ぐ。確認後:
```bash
rm -rf ~/.claude/skills/agmsg-role-protocol ~/.agents/skills/agmsg-role-protocol
```

- [x] **Step 2: symlink 設置**

```bash
mkdir -p ~/.claude/skills/agmsg-driven-development
ln -s /Users/takanokenichi/GitHub/panicboat/dotfiles/.claude/skills/agmsg-driven-development/SKILL.md ~/.claude/skills/agmsg-driven-development/SKILL.md
ln -s /Users/takanokenichi/GitHub/panicboat/dotfiles/.claude/skills/agmsg-driven-development/codex-dispatch-prompt.md ~/.claude/skills/agmsg-driven-development/codex-dispatch-prompt.md
```

- [x] **Step 3: 検証**

実行: `/bin/ls -laL ~/.claude/skills/agmsg-driven-development/`
期待: SKILL.md と codex-dispatch-prompt.md が実体サイズで表示される（broken symlink ならここでエラーになる）。あわせて `head -3 ~/.claude/skills/agmsg-driven-development/SKILL.md` が frontmatter を返す

注: `~/.claude` 側 symlink の恒久化（ansible playbook への反映）は別リポジトリ github.com/panicboat/ansible の作業であり本 plan の対象外

---

### Task 4: E2E verification — single run（ユーザー同席・対話的）

**Files:**
- Create: `~/tmp/agmsg-dd-e2e/`（使い捨て検証リポジトリ）

**Interfaces:**
- Consumes: Task 1〜3 のすべて（skill が user skill として解決されること）
- Produces: Success Criteria 1・2 の VERIFIED 判定（Task 5 の前提）

前提: tmux セッション内で実行すること。`command -v codex` が成功すること。

- [x] **Step 1: 検証リポジトリを作る**

```bash
mkdir -p ~/tmp/agmsg-dd-e2e && cd ~/tmp/agmsg-dd-e2e
git init -b main && git commit --allow-empty -s -m "chore: init"
mkdir -p docs/superpowers/plans
```

- [x] **Step 2: ミニ plan を書く**

`~/tmp/agmsg-dd-e2e/docs/superpowers/plans/2026-07-24-greet.md` に以下を書く:

```markdown
# Greet Script Implementation Plan

**Goal:** `greet.sh` が `hello <name>` を出力する。

## Global Constraints

- Bash のみ。依存追加なし

### Task 1: greet.sh

**Files:**
- Create: `greet.sh`
- Test: `test.sh`

- [x] **Step 1:** `test.sh` を書く: `./greet.sh world` の出力が `hello world` と一致しなければ exit 1 する比較を含める。実行して失敗を確認（greet.sh 未作成のため）
- [x] **Step 2:** `greet.sh` を実装して `chmod +x` する
- [x] **Step 3:** `./test.sh` が exit 0 することを確認
- [x] **Step 4:** `git add greet.sh test.sh && git commit -s -m "feat: add greet script"`
```

- [x] **Step 3: skill を実行して 1 サイクル観察**

tmux 内で `~/tmp/agmsg-dd-e2e` から新しい Claude Code セッションを開始し、「`docs/superpowers/plans/2026-07-24-greet.md` を agmsg-driven-development で実行して」と依頼する。CLAUDE.md の Plan Execution ルールによる実行方式の確認が出ること（Success Criteria 2）も観察する。

- [x] **Step 4: 結果検証**

実行（e2e リポジトリで）:
```bash
git log --format='%h %s %(trailers:key=Signed-off-by)' -3
./test.sh && echo PASS
~/.agents/skills/agmsg/scripts/team.sh agmsg-dd-e2e-main 2>&1
```
期待: implementer の signoff 付きコミットが存在する。`PASS`。team.sh は team not found エラー（Teardown 完了）。spawn → 実装 → agmsg 報告 → review → despawn が人手の介入なしで一周したことを観察で確認し、結果を VERIFIED として記録する

---

### Task 5: E2E verification — parallel worktrees（ユーザー同席・対話的）

**Files:**
- Modify: `~/tmp/agmsg-dd-e2e/`（worktree 2 本を追加）

**Interfaces:**
- Consumes: Task 4 の検証リポジトリと結果
- Produces: Success Criteria 3・4 の VERIFIED 判定

- [x] **Step 1: worktree を 2 本作る**

```bash
cd ~/tmp/agmsg-dd-e2e
git worktree add -b feat/a .claude/worktrees/feat-a main
git worktree add -b feat/b .claude/worktrees/feat-b main
```

各 worktree の `docs/superpowers/plans/` に Task 4 Step 2 と同型のミニ plan を置く（feat/a は `greet-a.sh`、feat/b は `greet-b.sh` を対象にし、ファイル名衝突を避ける）。

- [x] **Step 2: 2 セッション並行実行**

tmux 内で各 worktree から Claude Code セッションを 1 つずつ開始し、同時に agmsg-driven-development で各 plan を実行させる。

- [x] **Step 3: 分離の検証**

実行（両 run の実行中〜完了後）:
```bash
/bin/ls ~/.agents/skills/agmsg/teams/
~/.agents/skills/agmsg/scripts/history.sh agmsg-dd-e2e-feat-a leader
~/.agents/skills/agmsg/scripts/history.sh agmsg-dd-e2e-feat-b leader
```
期待: 実行中は `agmsg-dd-e2e-feat-a` と `agmsg-dd-e2e-feat-b` の 2 team が並存し、spawn の name 衝突が起きない。各 history に相手 run のメッセージが混ざらない。両 run の Teardown 後は teams が空に戻る（Success Criteria 3・4 を VERIFIED として記録）

- [x] **Step 4: 後片付け**

```bash
rm -rf ~/tmp/agmsg-dd-e2e
```
