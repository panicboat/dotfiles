# .claude Directory Automation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `.claude` ディレクトリ配下の全設定を Web のベストプラクティスを参照しながら自動最適化するエージェントを構築する。

**Architecture:** Agent プロンプトファイルを単一の source of truth として、Claude Code のスラッシュコマンド・シェル関数・スケジュールの3経路から同一ロジックを呼び出す。

**Tech Stack:** Claude Code CLI (`claude`), Claude Code schedule 機能, zsh

---

## File Structure

| Action | Path | 役割 |
|--------|------|------|
| CREATE | `.claude/scripts/optimize-agent.md` | エージェント指示書（source of truth） |
| CREATE | `.claude/commands/optimize.md` | `/optimize` スラッシュコマンド |
| MODIFY | `.zshrc` | `claude-optimize` シェル関数を追加 |
| SCHEDULE | Claude Code schedule | 週次リモートエージェントを登録 |

---

## Task 1: Create Agent Prompt

**Files:**
- Create: `.claude/scripts/optimize-agent.md`

- [ ] **Step 1: Create the agent prompt file**

`/Users/01054855/GitHub/panicboat/dotfiles/.claude/scripts/optimize-agent.md` を以下の内容で作成する。

```markdown
# .claude Optimization Agent

You are a Claude Code environment optimization agent. Improve the `.claude` configuration in this dotfiles repository by incorporating current best practices.

## Repository

Dotfiles path: `/Users/01054855/GitHub/panicboat/dotfiles`

## Phase 1: Gather Best Practices

Search the web for best practices for each category below:

1. `"Claude Code CLAUDE.md best practices" site:github.com` — instruction patterns
2. `"Claude Code settings.json hooks examples"` — useful PreToolUse / PostToolUse hooks
3. `"Claude Code custom slash commands examples" site:github.com` — command patterns
4. `"Claude Code custom agents subagents examples"` — agent patterns
5. `"Claude Code MCP servers useful 2025"` — MCP server recommendations
6. `"Claude Code keybindings productivity shortcuts"` — keyboard shortcuts
7. `"Claude Code zsh functions workflow"` — shell function patterns

## Phase 2: Audit Current State

Read all current files:

- `/Users/01054855/GitHub/panicboat/dotfiles/.claude/CLAUDE.md`
- `/Users/01054855/GitHub/panicboat/dotfiles/.claude/settings.json`
- `/Users/01054855/GitHub/panicboat/dotfiles/.zshrc`
- All files in `.claude/commands/` (if directory exists)
- All files in `.claude/agents/` (if directory exists)
- All files in `.claude/skills/` (if directory exists)
- `~/.claude/keybindings.json` (if exists)
- `~/.claude/memory/MEMORY.md` — for user preferences (reference only, do NOT modify)

Check for uncommitted changes first:
```bash
git -C /Users/01054855/GitHub/panicboat/dotfiles status --porcelain
```
If output is non-empty, abort with: "Uncommitted changes detected. Please commit or stash before running optimization."

## Phase 3: Plan Changes

Before making any changes, output a change log in this format:

```
CHANGE LOG:
[CATEGORY] ACTION: Description (source: URL or "community pattern")
```

Examples:
```
[settings.json] ADD: PostToolUse hook for automatic formatting (source: https://...)
[commands/] CREATE: /pr-review.md — PR review slash command (source: ...)
[CLAUDE.md] ADD: Instruction for commit scope format (source: community pattern)
[agents/] CREATE: /git-helper.md — Git workflow subagent (source: ...)
```

If no improvements are found for a category, skip it.

## Phase 4: Apply Changes

Apply each change:
- Preserve ALL existing rules in `CLAUDE.md` — additions only
- Follow existing JSON structure in `settings.json`
- Use lowercase kebab-case for new file names in `commands/` and `agents/`
- If a proposed change contradicts an existing rule in `CLAUDE.md`, skip the proposed change
- Do NOT add `Co-Authored-By` or `Signed-off-by` to any commit message
- Do NOT modify any files under `~/.claude/memory/`
- Do NOT touch plugin files under `~/.claude/plugins/`

## Phase 5: Commit

```bash
git -C /Users/01054855/GitHub/panicboat/dotfiles add -A
git -C /Users/01054855/GitHub/panicboat/dotfiles commit -m "$(cat <<'EOF'
Optimize .claude configuration

CHANGE LOG:
<paste change log here>
EOF
)"
```

If no changes were made, output "No improvements found. .claude is up to date." and exit without committing.
```

- [ ] **Step 2: Verify the file was created**

```bash
ls -la /Users/01054855/GitHub/panicboat/dotfiles/.claude/scripts/optimize-agent.md
```

Expected: ファイルが存在し 0 バイト超であること。

- [ ] **Step 3: Commit**

```bash
git -C /Users/01054855/GitHub/panicboat/dotfiles add .claude/scripts/optimize-agent.md
git -C /Users/01054855/GitHub/panicboat/dotfiles commit -m "Add optimize agent prompt"
```

---

## Task 2: Create Slash Command

**Files:**
- Create: `.claude/commands/optimize.md`

- [ ] **Step 1: Create the commands directory and slash command**

`/Users/01054855/GitHub/panicboat/dotfiles/.claude/commands/optimize.md` を以下の内容で作成する。

```markdown
Read the file at `/Users/01054855/GitHub/panicboat/dotfiles/.claude/scripts/optimize-agent.md` and execute all instructions in it exactly as written.
```

- [ ] **Step 2: Verify the file was created**

```bash
cat /Users/01054855/GitHub/panicboat/dotfiles/.claude/commands/optimize.md
```

Expected: 上記の1行が出力されること。

- [ ] **Step 3: Verify slash command is recognized by Claude Code**

Claude Code セッション内で `/optimize` と入力し、コマンドが補完候補に表示されることを確認する。

- [ ] **Step 4: Commit**

```bash
git -C /Users/01054855/GitHub/panicboat/dotfiles add .claude/commands/optimize.md
git -C /Users/01054855/GitHub/panicboat/dotfiles commit -m "Add /optimize slash command"
```

---

## Task 3: Add Shell Function

**Files:**
- Modify: `.zshrc` (関数セクション末尾に追記)

- [ ] **Step 1: Add `claude-optimize` function to `.zshrc`**

`.zshrc` の `function bedrock()` ブロックの後に以下を追記する。

```bash
function claude-optimize() {
  local prompt_file="$HOME/GitHub/panicboat/dotfiles/.claude/scripts/optimize-agent.md"
  if [[ ! -f "$prompt_file" ]]; then
    echo "Error: optimize-agent.md not found at $prompt_file" >&2
    return 1
  fi
  claude "$(cat "$prompt_file")"
}
```

- [ ] **Step 2: Verify syntax**

```bash
zsh -n /Users/01054855/GitHub/panicboat/dotfiles/.zshrc
```

Expected: エラーなし（出力なし）。

- [ ] **Step 3: Source and verify function is available**

```bash
source /Users/01054855/GitHub/panicboat/dotfiles/.zshrc && type claude-optimize
```

Expected:
```
claude-optimize is a shell function
```

- [ ] **Step 4: Commit**

```bash
git -C /Users/01054855/GitHub/panicboat/dotfiles add .zshrc
git -C /Users/01054855/GitHub/panicboat/dotfiles commit -m "Add claude-optimize shell function"
```

---

## Task 4: Register Schedule

**Prerequisites:** Task 1 完了済みであること。

- [ ] **Step 1: Register weekly schedule via Claude Code**

Claude Code セッション内で以下のスラッシュコマンドを実行する。

```
/schedule
```

スケジュール設定のプロンプトに対して以下を入力する：
- **Cron expression:** `0 9 * * 1`（毎週月曜 09:00）
- **Prompt:** `Read the file at /Users/01054855/GitHub/panicboat/dotfiles/.claude/scripts/optimize-agent.md and execute all instructions in it exactly as written.`

- [ ] **Step 2: Verify schedule is registered**

```
/schedule list
```

Expected: 上記のスケジュールが一覧に表示されること。

- [ ] **Step 3: Run schedule immediately to verify end-to-end behavior**

```
/schedule run <schedule-id>
```

Expected: エージェントが起動し、Web 検索 → Audit → 変更ログ出力 → (変更があれば) commit の順に実行されること。

- [ ] **Step 4: Verify idempotency**

Step 3 の実行後、再度 `/optimize` または `claude-optimize` を実行する。

Expected: "No improvements found. .claude is up to date." と出力され、新たな commit が作られないこと。
