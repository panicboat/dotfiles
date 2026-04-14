# .claude Directory Automation Design

## Overview

`.claude` ディレクトリ配下のすべての設定・定義ファイルを自動的に最適化する仕組みを構築する。
Claude Code の Remote Agent スケジューリング機能を活用し、Web のベストプラクティスを継続的に取り込む。

## Architecture

```
[手動: claude-optimize]  ─┐
[weekly cron schedule]  ──┴─→ Optimize Agent
                                    │
                          ┌─────────┼─────────────┐
                          ▼         ▼              ▼
                       Web 検索   現状読み取り    memory 参照
                      (各カテゴリ) (全ファイル)   (コンテキスト)
                          │         │
                          └────┬────┘
                               ▼
                          差分分析・変更ログ生成
                               │
                    ┌──────────┼──────────────────┐
                    ▼          ▼                   ▼
               CLAUDE.md   settings.json      commands/
               agents/     skills/            scripts/
               keybindings  MCP Servers        shell functions
                    │
                    └──→ git commit（変更ログ付き）
```

## Optimization Targets

| カテゴリ | 対象ファイル |
|----------|-------------|
| Instructions | `CLAUDE.md` |
| Settings | `settings.json`（hooks / MCP / permissions / env） |
| Commands | `.claude/commands/*.md` |
| Agents | `.claude/agents/*.md` |
| Skills | `.claude/skills/*.md` |
| Keybindings | `keybindings.json` |
| Scripts | `scripts/*.sh` |
| Shell functions | dotfiles の zsh/bash 設定 |
| Memory | 参照のみ（変更しない） |

## Components

### 1. Agent Prompt（`scripts/optimize-agent.md`）

エージェントへの指示書。以下のフェーズを順に実行する。

**Phase 1: Gather**
- カテゴリごとに Web 検索（例: "Claude Code CLAUDE.md best practices 2025"）
- `~/.claude/memory/` を参照してユーザーの好み・制約を把握

**Phase 2: Audit**
- 現状の全ファイルを読み取り
- ベストプラクティスとの差分を列挙

**Phase 3: Plan（変更ログ生成）**
- 変更内容・理由・カテゴリを記録
- 例: `[CLAUDE.md] Add: error handling annotation style (source: ...)`

**Phase 4: Execute**
- カテゴリ順に変更適用
- 既存ルール・スタイルとの一貫性を維持
- `CLAUDE.md` の既存ルールと矛盾する提案は破棄

**Phase 5: Commit**
- 変更ログを git commit メッセージに含めてコミット

### 2. Schedule（Claude Code schedule 機能）

`/schedule` コマンドで週1回のリモートエージェントを登録する。
プロンプトは `scripts/optimize-agent.md` を参照。

### 3. Manual Triggers

| 方法 | 実装場所 | 使い方 |
|------|---------|-------|
| スラッシュコマンド | `.claude/commands/optimize.md` | Claude Code 内で `/optimize` |
| シェル関数 | dotfiles の zsh 設定 | ターミナルから `claude-optimize` |

## Error Handling

| ケース | 対応 |
|--------|------|
| Web 検索失敗 | 該当カテゴリをスキップ・ログに記録してコミットは続行 |
| ファイル競合（未コミット変更あり） | 実行を中断・メッセージ出力して終了 |
| 既存スタイルと矛盾する提案 | `CLAUDE.md` の既存ルールを優先・提案を破棄 |
| git commit 失敗 | 変更を保持したまま終了・次回実行で再試行 |

## Testing

1. **初回実行検証** — 手動で `/optimize` を実行し、変更ログと diff を確認
2. **スケジュール検証** — 登録後に `/schedule run` で即時実行して動作確認
3. **冪等性確認** — 2回連続で実行して不要な変更が出ないことを確認
