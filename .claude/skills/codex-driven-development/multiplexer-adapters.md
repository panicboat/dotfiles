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
