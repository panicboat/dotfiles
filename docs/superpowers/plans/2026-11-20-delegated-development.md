# delegated-development Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `codex-driven-development` skill を、`codex exec` を adapter スクリプト経由で 1 ターンずつ起動する `delegated-development` skill に置き換える。

**Architecture:** SKILL.md は SDD の implementer だけを置き換える手順書で、CLI 固有の処理は `adapters/<cli>.sh` の subcommand（`detect`/`run`/`resume`/`session_id`/`last_message`）に閉じる。打ち切りは `bound.pl` が子孫プロセスまで止めて終了コード 142 に正規化する。Claude は adapter を Bash `run_in_background` で起動し、終了通知で report file を読む。

**Tech Stack:** bash（macOS 標準）、perl（`/usr/bin/perl`）、Markdown。テストは素の bash。

**Spec:** `docs/superpowers/specs/2026-11-20-delegated-development-design.md`

## Global Constraints

- skill のディレクトリは `.claude/skills/delegated-development/`
- 新しい依存を足さない: jq・bats・coreutils `timeout` を使わない（出力解析は grep / sed）
- `WAIT_BUDGET` は環境変数、既定 1800（秒）
- 打ち切りの終了コードは 142
- コード要素（変数名・関数名・コメント・コミットメッセージ）は英語、Markdown の見出しは英語・本文は日本語
- コメントは 1 行、Why not（制約・落とし穴）だけを書く
- コミットは `git commit -s`、`Co-Authored-By` を付けない、Conventional Commits の type を付ける
- Codex を起動するときの許可・sandbox フラグは CLI 引数で指定しない（`~/.codex/config.toml` に任せる）。model も指定しない
- SDD の参照先は superpowers 7.0.2 の subagent-driven-development（task-brief / review-package / sdd-workspace scripts、`### 2. Handle the report`、`references/handling-reports.md`）

## Review Focus

1. prompt に空白・改行・`"`・`$`・`'` を含む → codex に 1 つの argv としてそのまま届く（Task 2 のテスト `prompt_is_passed_verbatim`）
2. `<out>` のパスに空白を含む（worktree や `.superpowers/sdd/...` 配下）→ 出力ファイルが正しい場所に書かれ `session_id` が読める（Task 2 のテスト `out_path_with_spaces`）
3. 呼び出し側の stdin が開いたパイプ → codex に届かず `</dev/null` になる（codex は非 TTY の開いた stdin で待ち続ける: openai/codex#20919）（Task 2 のテスト `stdin_is_detached`）
4. codex が `thread.started` を出す前に失敗 → `session_id` が空文字で成功せず非 0 で終わる（Task 2 のテスト `session_id_missing_fails`）
5. 打ち切られた子が自分の子プロセス（テスト実行等）を別プロセスグループで起動している → 孤児が残らない（Task 1 のテスト `timeout_kills_detached_descendants`）

---

### Task 1: bound.pl

**Files:**
- Create: `.claude/skills/delegated-development/bound.pl`
- Create: `.claude/skills/delegated-development/tests/assert.sh`
- Test: `.claude/skills/delegated-development/tests/bound.test.sh`

**Interfaces:**
- Produces: `bound.pl <seconds> <command> [args...]` — command を子プロセスとして起動する。時間内に終われば子の終了コード（シグナル終了は 128+signo）。時間切れなら子と全子孫に TERM、2 秒後に KILL して終了コード 142。`<seconds>` が正の整数でない・command が無い場合は stderr に usage を出して終了コード 2
- Produces: `tests/assert.sh` — `source` して使う。`assert_eq <name> <expected> <actual>`（PASS/FAIL と name を 1 行出力）、末尾で呼ぶ `finish`（失敗が 1 件でもあれば終了コード 1、件数を出力）

- [ ] **Step 1: `tests/assert.sh` と失敗するテストを書く**

`tests/bound.test.sh` は `source "$(dirname "$0")/assert.sh"` し、`BOUND="$(dirname "$0")/../bound.pl"` を使う。テスト:

```bash
# exit_code_is_propagated
"$BOUND" 5 sh -c 'exit 7'; assert_eq exit_code_is_propagated 7 "$?"
# success_returns_zero
"$BOUND" 5 true; assert_eq success_returns_zero 0 "$?"
# argv_is_passed_verbatim
out="$("$BOUND" 5 printf '%s|' 'a b' '$HOME' "it's")"; assert_eq argv_is_passed_verbatim 'a b|$HOME|it'"'"'s|' "$out"
# timeout_returns_142
"$BOUND" 1 sleep 30; assert_eq timeout_returns_142 142 "$?"
# timeout_kills_detached_descendants: grandchild in its own process group must not survive
marker="bound-test-$$-$RANDOM"
"$BOUND" 1 perl -e 'if (!fork) { setpgrp(0,0); exec "perl", "-e", "sleep 300", $ARGV[0] } sleep 300' "$marker"
sleep 3; ! pgrep -f "$marker" >/dev/null; assert_eq timeout_kills_detached_descendants 0 "$?"
# usage_error_returns_2
"$BOUND" abc true 2>/dev/null; assert_eq usage_error_returns_2 2 "$?"
"$BOUND" 5 2>/dev/null; assert_eq usage_error_without_command 2 "$?"
finish
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `bash .claude/skills/delegated-development/tests/bound.test.sh`
Expected: `bound.pl` が無いため全件 FAIL、終了コード 1

- [ ] **Step 3: `bound.pl` を実装する**

子を fork + exec し、`alarm` で時間切れを検知する。時間切れ時は `pgrep -P <pid>` を再帰的に辿って子孫を列挙し、子孫と子に TERM → 2 秒 sleep → KILL を送って `exit 142`。codex はツールコマンドを別プロセスグループで起動するため、プロセスグループ kill では足りない（spec Constraints）。`chmod +x`。

- [ ] **Step 4: テストが通ることを確認する**

Run: `bash .claude/skills/delegated-development/tests/bound.test.sh`
Expected: 全件 PASS、終了コード 0。続けて `pgrep -f bound-test-` が何も出さない

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/delegated-development/bound.pl .claude/skills/delegated-development/tests/
git commit -s -m "feat(skills): add bound.pl timeout wrapper for delegated-development"
```

### Task 2: codex adapter

**Files:**
- Create: `.claude/skills/delegated-development/adapters/codex.sh`
- Test: `.claude/skills/delegated-development/tests/codex.test.sh`

**Interfaces:**
- Consumes: Task 1 の `bound.pl`（`adapters/codex.sh` からの相対パス `../bound.pl`）、`tests/assert.sh`
- Produces: `adapters/codex.sh <subcommand> ...`
  - `detect` — `codex` が PATH にあれば 0
  - `run <out> <prompt>` — `bound.pl "$WAIT_BUDGET" codex exec --json -o "<out>.last" "<prompt>" </dev/null >"<out>.jsonl"`。終了コード: 0 成功 / 142 打ち切り / その他は codex の終了コード
  - `resume <session_id> <out> <prompt>` — `codex exec resume "<session_id>" --json -o "<out>.last" "<prompt>"` を同じ条件で
  - `session_id <out>` — `<out>.jsonl` の最初の `"type":"thread.started"` 行の `thread_id` を stdout に出す。無ければ終了コード 1
  - `last_message <out>` — `<out>.last` を stdout に出す。無い・空なら終了コード 1
  - 引数不足・未知の subcommand は stderr に usage、終了コード 2
  - `WAIT_BUDGET` 未設定なら 1800

- [ ] **Step 1: 失敗するテストを書く**

`tests/codex.test.sh` は一時ディレクトリに stub `codex` を作り PATH の先頭に置く。stub は受け取った argv を 1 行 1 引数で `$STUB_DIR/argv` に、stdin の内容を `$STUB_DIR/stdin` に書き、`-o` の次の引数のファイルに `stub final message` を書き、stdout に `{"type":"thread.started","thread_id":"stub-thread-1"}` を出して `${STUB_EXIT:-0}` で終わる。`STUB_SLEEP` があれば先に sleep、`STUB_NO_THREAD=1` なら thread.started を出さない。テスト:

```bash
# run_builds_exec_argv
"$ADAPTER" run "$T/out" "hello"; assert_eq run_exit 0 "$?"
assert_eq run_builds_exec_argv "$(printf 'exec\n--json\n-o\n%s\nhello' "$T/out.last")" "$(cat "$STUB_DIR/argv")"
# resume_builds_resume_argv
"$ADAPTER" resume stub-thread-1 "$T/out2" "fix it"
assert_eq resume_builds_resume_argv "$(printf 'exec\nresume\nstub-thread-1\n--json\n-o\n%s\nfix it' "$T/out2.last")" "$(cat "$STUB_DIR/argv")"
# session_id_reads_thread_started
assert_eq session_id_reads_thread_started stub-thread-1 "$("$ADAPTER" session_id "$T/out")"
# last_message_reads_last_file
assert_eq last_message_reads_last_file "stub final message" "$("$ADAPTER" last_message "$T/out")"
# prompt_is_passed_verbatim
p=$'line1\nsay "hi" $HOME it\'s'; "$ADAPTER" run "$T/out3" "$p"; assert_eq prompt_is_passed_verbatim "$p" "$(tail -n 2 "$STUB_DIR/argv")"
# out_path_with_spaces
mkdir -p "$T/with space"; "$ADAPTER" run "$T/with space/out" x; assert_eq out_path_with_spaces stub-thread-1 "$("$ADAPTER" session_id "$T/with space/out")"
# stdin_is_detached
echo SHOULD-NOT-ARRIVE | "$ADAPTER" run "$T/out4" x; assert_eq stdin_is_detached "" "$(cat "$STUB_DIR/stdin")"
# failure_exit_is_propagated
STUB_EXIT=3 "$ADAPTER" run "$T/out5" x; assert_eq failure_exit_is_propagated 3 "$?"
# timeout_returns_142
STUB_SLEEP=30 WAIT_BUDGET=1 "$ADAPTER" run "$T/out6" x; assert_eq timeout_returns_142 142 "$?"
# session_id_missing_fails
STUB_NO_THREAD=1 "$ADAPTER" run "$T/out7" x; "$ADAPTER" session_id "$T/out7" >/dev/null; assert_eq session_id_missing_fails 1 "$?"
# last_message_missing_fails
"$ADAPTER" last_message "$T/nonexistent"; assert_eq last_message_missing_fails 1 "$?"
# detect_finds_codex / detect_without_codex
"$ADAPTER" detect; assert_eq detect_finds_codex 0 "$?"
PATH=/usr/bin:/bin "$ADAPTER" detect; assert_eq detect_without_codex 1 "$?"
# usage_errors_return_2
"$ADAPTER" run "$T/out8" 2>/dev/null; assert_eq run_missing_prompt 2 "$?"
"$ADAPTER" bogus 2>/dev/null; assert_eq unknown_subcommand 2 "$?"
finish
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `bash .claude/skills/delegated-development/tests/codex.test.sh`
Expected: `adapters/codex.sh` が無いため FAIL、終了コード 1

- [ ] **Step 3: `adapters/codex.sh` を実装する**

`bound.pl` は `"$(dirname "$0")/../bound.pl"` で解決する（`~/.claude/skills/delegated-development/adapters/` はディレクトリ symlink なので `dirname "$0"` 基準で同じ skill 内の `bound.pl` に届く）。stdin の切り離しは openai/codex#20919（開いた非 TTY stdin で `codex exec` が待ち続ける）の回避であることを 1 行コメントで残す。`chmod +x`。

- [ ] **Step 4: テストが通ることを確認する**

Run: `bash .claude/skills/delegated-development/tests/codex.test.sh && bash .claude/skills/delegated-development/tests/bound.test.sh && shellcheck .claude/skills/delegated-development/adapters/codex.sh .claude/skills/delegated-development/tests/*.sh`
Expected: 両テスト全件 PASS、shellcheck の指摘なし

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/delegated-development/adapters/ .claude/skills/delegated-development/tests/codex.test.sh
git commit -s -m "feat(skills): add codex adapter for delegated-development"
```

### Task 3: skill documents

**Files:**
- Create: `.claude/skills/delegated-development/SKILL.md`
- Create: `.claude/skills/delegated-development/implementer-adapters.md`
- Create: `.claude/skills/delegated-development/dispatch-prompt.md`
- Reference (read only): `.claude/skills/codex-driven-development/SKILL.md`, `.claude/skills/codex-driven-development/codex-dispatch-prompt.md`

**Interfaces:**
- Consumes: Task 1・2 の `bound.pl`・`adapters/codex.sh` の subcommand と終了コード
- Produces: skill 名 `delegated-development`（frontmatter `name`）。Task 4 の CLAUDE.md がこの名前で参照する

- [ ] **Step 1: `SKILL.md` を書く**

frontmatter の `description` は「実装 plan を実行するとき、implementer を外部 CLI エージェント（adapter: 現在は Codex）に非対話モードで委譲してトークン使用量を分散する。superpowers:subagent-driven-development の実行構造は維持し implementer 周りだけを置き換える。plan の実行方式として delegated-development が選択されたときに使用する。」の趣旨で書く。本文の節は spec の Design 節に従う: Prerequisites / Setup / Substitutions / Batching Strategy / Dispatch / Await / Redispatch / Abort / Failure Modes / Red Flags。

- Prerequisites・Setup・Substitutions・Dispatch・Await・Redispatch・Abort・Failure Modes・Red Flags は spec の該当節の内容をそのまま手順化する。adapter は `<skill base directory>/adapters/<cli>.sh` で呼ぶ
- spec の「SDD の Handling Implementer Status」は SDD 7.0.2 の `### 2. Handle the report`（DONE 以外は `references/handling-reports.md`）を指す
- Batching Strategy と「Dispatch 前チェック」は現行 `codex-driven-development/SKILL.md` の節を移し、「pane」を「Codex セッション（`run` で始め、バッチ内の fix は `resume`）」に読み替える。バッチ境界では新規 `run` にする
- report file は SDD の命名（brief `task-N-brief.md` → report `task-N-report.md`）、adapter の `<out>` は同じディレクトリの `task-N-round-K`

- [ ] **Step 2: `implementer-adapters.md` を書く**

spec の Adapter Contract（subcommand 表と終了コードの約束）と Adding an Adapter（5 条件と、追加時に `adapters/<cli>.sh`・`tests/<cli>.test.sh`・表 1 行を足すこと）を載せる。規約確認の表は CLI 1 つにつき 1 行（CLI・確認バージョン・確認日・判定・参照 URL）:

| CLI | version | checked | 判定 | 参照 |
|---|---|---|---|---|
| codex | 0.169.0 | 2026-11-20 | 採用（公式 docs がスクリプト / CI 用途を案内） | https://developers.openai.com/codex/noninteractive |
| agy | 1.5.12 | 2026-11-20 | 不採用（Terms Section 6: third party tools / products not provided by us） | https://antigravity.google/terms , https://geminicli.com/docs/resources/faq/ |

- [ ] **Step 3: `dispatch-prompt.md` を書く**

現行 `codex-dispatch-prompt.md` をコピーし、spec の dispatch-prompt.md 節の 4 点（「running non-interactively」への変更、Report step 2・3 を「report file を書いたら終了する」に置換、OVERWRITE 段落の削除、`{{TEAM}}` の削除）だけを変える。NEEDS_CONTEXT / BLOCKED 時の「同じセッションに続きが届く」旨は「controller が同じセッションを resume して回答を送る」に書き換える。

- [ ] **Step 4: 文書を検証する**

Run:
```bash
D=.claude/skills/delegated-development
grep -nE 'agmsg|herdr|Orca|multiplexer|send\.sh|\{\{TEAM\}\}' "$D"/*.md
grep -c 'adapters/' "$D/SKILL.md"
grep -oE '\{\{[A-Z_]+\}\}' "$D/dispatch-prompt.md" | sort -u
```
Expected: 1 つ目は出力なし。2 つ目は 1 以上。3 つ目は `{{BRIEF_ABSOLUTE_PATH}} {{INTERFACES_OR_NONE}} {{ONE_LINE_TASK_CONTEXT}} {{PROJECT}} {{REPORT_ABSOLUTE_PATH}}` だけ

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/delegated-development/*.md
git commit -s -m "feat(skills): add delegated-development skill documents"
```

### Task 4: replace codex-driven-development

**Files:**
- Delete: `.claude/skills/codex-driven-development/`（SKILL.md・codex-dispatch-prompt.md・multiplexer-adapters.md）
- Modify: `.claude/CLAUDE.md`（`### Plan Execution` の選択肢 1、`### codex-driven-development` 節）

**Interfaces:**
- Consumes: Task 3 の skill 名 `delegated-development`

- [ ] **Step 1: 旧 skill を削除する**

`git rm -r .claude/skills/codex-driven-development`

- [ ] **Step 2: `.claude/CLAUDE.md` を書き換える**

`### Plan Execution` の選択肢 1 を `1. delegated-development（実装を外部 CLI エージェントに委譲してトークン使用量を分散）` にする。`### codex-driven-development` 見出しとその本文（watch.sh の並行 worktree 手順）を削除する。`## agmsg` 節は変えない。

- [ ] **Step 3: 参照が残っていないことを確認する**

Run: `git grep -nE 'codex-driven-development|multiplexer-adapters|codex-dispatch-prompt' -- ':!docs/superpowers/'`
Expected: 出力なし

- [ ] **Step 4: Commit**

```bash
git add -A .claude/
git commit -s -m "refactor(skills): replace codex-driven-development with delegated-development"
```

### Task 5: end-to-end check and installation

controller が実行する（実装 CLI に dispatch しない）。リポジトリ外を変更するステップはユーザーの承認を得てから行う。

**Files:**
- 変更なし（リポジトリ外の `~/.claude/skills/` と一時ディレクトリだけ）

- [ ] **Step 1: 実 codex で run → resume を通す**

一時ディレクトリに git repo と worktree を作り、worktree に `cd` して実行する:
```bash
A=<worktree>/.claude/skills/delegated-development/adapters/codex.sh
"$A" run "$T/round-0" "Create hello.txt containing hi and commit it with git commit -s -m 'test: add hello'. Reply DONE."; echo "exit=$?"
ID="$("$A" session_id "$T/round-0")"; echo "$ID"
"$A" resume "$ID" "$T/round-1" "Append a second line 'there' to hello.txt and commit it. Reply DONE."; echo "exit=$?"
git log --oneline
```
Expected: 両方 `exit=0`、`ID` が UUID、`git log` に 2 commit

- [ ] **Step 2: 実 codex で打ち切りを確かめる**

Run: `WAIT_BUDGET=20 "$A" run "$T/round-2" "Run the shell command: sleep 120. Then reply DONE."; echo "exit=$?"; sleep 3; pgrep -fl 'sleep 120' || echo no-orphan`
Expected: `exit=142`、`no-orphan`

- [ ] **Step 3: `~/.claude/skills/` の symlink を付け替える（ユーザー承認後）**

```bash
S=~/.claude/skills/delegated-development; R=<main checkout>/.claude/skills/delegated-development
mkdir -p "$S"
for f in SKILL.md implementer-adapters.md dispatch-prompt.md bound.pl; do ln -s "$R/$f" "$S/$f"; done
ln -s "$R/adapters" "$S/adapters"
rm -r ~/.claude/skills/codex-driven-development
```
`R` は main checkout（`~/GitHub/panicboat/dotfiles`）のパスにする。PR が main に merge されるまで `R` 側のファイルは存在しないため、このステップは merge 後に行う。
Expected: `/bin/ls -la ~/.claude/skills/delegated-development` で 5 つの symlink が解決できる

- [ ] **Step 4: 一時ディレクトリを削除する**
