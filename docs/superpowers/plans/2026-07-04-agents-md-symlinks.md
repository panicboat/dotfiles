# AGENTS.md Symlinks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** codex と antigravity（gemini 系）がそれぞれ読むグローバル指示ファイルを、`.claude/CLAUDE.md` を実体とする相対シンボリックリンクとして追加する。

**Architecture:** `.claude/CLAUDE.md` を唯一の実体とし、`.codex/AGENTS.md` と `.gemini/AGENTS.md` をそこへの相対シンボリックリンクとして作成する。コード変更やビルドは発生せず、リポジトリ内のファイル構成変更のみ。

**Tech Stack:** git（シンボリックリンクの追跡、mode 120000）、POSIX `ln -s`

## Global Constraints

- シンボリックリンクは相対パスで作成する（クローン先パス依存を避けるため）
- `.claude/CLAUDE.md` の内容は変更しない
- `.codex/config.toml`、`.gemini/settings.json` は変更しない
- ansible repo 側の実配置ロジックはこのリポジトリの変更範囲外（対応しない）

---

### Task 1: Add AGENTS.md symlinks for codex and antigravity

**Files:**
- Create: `.codex/AGENTS.md` (symlink → `../.claude/CLAUDE.md`)
- Create: `.gemini/AGENTS.md` (symlink → `../.claude/CLAUDE.md`)

**Interfaces:**
- Consumes: `.claude/CLAUDE.md`（既存、変更しない実体ファイル）
- Produces: なし（後続タスクなし）

- [ ] **Step 1: `.codex/AGENTS.md` シンボリックリンクを作成する**

```bash
cd .codex && ln -s ../.claude/CLAUDE.md AGENTS.md && cd ..
```

- [ ] **Step 2: リンク先を確認する**

Run: `readlink .codex/AGENTS.md`
Expected: `../.claude/CLAUDE.md`

- [ ] **Step 3: `.gemini/AGENTS.md` シンボリックリンクを作成する**

```bash
cd .gemini && ln -s ../.claude/CLAUDE.md AGENTS.md && cd ..
```

- [ ] **Step 4: リンク先を確認する**

Run: `readlink .gemini/AGENTS.md`
Expected: `../.claude/CLAUDE.md`

- [ ] **Step 5: git がシンボリックリンクとして認識していることを確認する**

Run: `git add .codex/AGENTS.md .gemini/AGENTS.md && git ls-files -s .codex/AGENTS.md .gemini/AGENTS.md`
Expected: 両方とも mode `120000` で表示される

```
120000 <blob-sha> 0	.codex/AGENTS.md
120000 <blob-sha> 0	.gemini/AGENTS.md
```

- [ ] **Step 6: 内容が `.claude/CLAUDE.md` と一致することを確認する**

Run: `diff .codex/AGENTS.md .claude/CLAUDE.md && diff .gemini/AGENTS.md .claude/CLAUDE.md`
Expected: 差分なし（コマンドが何も出力せず終了コード 0）

- [ ] **Step 7: コミットする**

```bash
git commit -s -m "chore: add AGENTS.md symlinks for codex and antigravity"
```
