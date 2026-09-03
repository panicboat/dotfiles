# Multiplexer Adapter Contract

codex-driven-development が pane 生成・破棄・起動直後の対話ダイアログ処理・状態確認に要求する最小インターフェースと、対応 multiplexer ごとの具体コマンド。Redispatch の定常運用は agmsg（`../../../../.agents/skills/agmsg` 相当。実際のパスは `~/.agents/skills/agmsg`）に移るため、ここでの TUI 操作は「起動直後の一度きりの対話ダイアログ処理」と「agmsg bridge が arm しなかった場合の fallback mode」にのみ使う。

## Contract

| 操作 | 用途 |
|---|---|
| `detect()` | この multiplexer が現在の環境で使えるか |
| `create_pane(cwd) -> pane_id` | 新しい pane を指定 cwd で作る |
| `run(pane_id, argv)` | pane で `codex "<prompt>"` を実行する（Dispatch の初回投入。bridge が arm する前なので agmsg 経由にはできない） |
| `send_text(pane_id, text)` / `send_keys(pane_id, keys)` | 起動直後の対話ダイアログ処理、および fallback mode での Redispatch |
| `read(pane_id)` | pane の可視テキストを読む（対話ダイアログの種類判定、fallback mode の状態確認） |
| `close_pane(pane_id)` | pane を閉じる |
| `receipt_check(pane_id) -> received｜not_received` | boot prompt が実際に届いた（処理が始まった）かを確認する。agmsg bridge が arm しなかった場合の fallback 判断に使う |
| `poll_state(pane_id) -> working｜done｜blocked｜unknown` | pane の実行状態を確認する。fallback mode の Await ポーリングの補助信号に使う |

adapter の選択は SKILL.md の Prerequisites 節で行う。以降の節は選ばれた adapter に応じて、この2つの表のうち片方だけを見ればよい。

## herdr

Claude Code 自身が herdr pane の中で動いている（`herdr pane current` が成功する）ことが前提。

| 契約操作 | コマンド |
|---|---|
| `detect()` | `command -v herdr` が成功し、かつ `herdr pane current` が成功する |
| `create_pane(cwd)` | `herdr pane split --current --direction right --cwd "<cwd>" \| jq -r '.result.pane.pane_id'`（既存 SKILL.md の Dispatch 節が使っていたのと同じフィールドパス） |
| `run(pane_id, argv)` | `herdr agent start <name> --kind codex --pane <pane_id> --timeout <ms> -- "<prompt>"`（pane 選択と codex 起動が一体。`<name>` はサーバー全体で一意にする必要があり、`impl-$(basename "$PROJECT")` のように `PROJECT` から導出する）。split 直後の pane は shell がまだ idle 判定されておらず `agent_pane_busy` を返すことがあるため、`agent_name_taken`（待っても解消しない）以外のエラーは最大10回・2秒間隔でリトライし、それでも解消しなければ失敗として報告する: `for i in $(seq 1 10); do OUT=$(herdr agent start <name> --kind codex --pane <pane_id> --timeout <ms> -- "<prompt>" 2>&1); printf '%s' "$OUT" \| grep -q '"error"' \|\| break; printf '%s' "$OUT" \| grep -q 'agent_name_taken' && break; sleep 2; done; printf '%s' "$OUT" \| grep -q '"error"' && { echo "START_FAILED"; printf '%s\n' "$OUT"; exit 1; }` |
| `send_text(pane_id, text)` | `herdr pane send-text <pane_id> "<text>"` |
| `send_keys(pane_id, keys)` | `herdr pane send-keys <pane_id> <keys>`（例: `Enter`） |
| `read(pane_id)` | `herdr agent read <pane_id> --source visible --lines <N>` |
| `close_pane(pane_id)` | `herdr pane close <pane_id>` |
| `receipt_check(pane_id)` | `agent_status` が `idle` を抜けたかをポーリングする（`agent start` 直後は `idle` を通るため単発チェックでは判定できない）: `for i in $(seq 1 20); do ST=$(herdr agent get <pane_id> \| jq -r '.result.agent.agent_status'); case "$ST" in working\|done\|blocked) break;; esac; sleep 3; done`。`working`/`done`/`blocked` のいずれかで抜ければ `received`。`idle` のまま枯渇したら `tail -1 ~/.codex/history.jsonl` の末尾が対象の boot prompt と一致するかを見る——一致すれば `received`（Codex が遅いだけ）、不一致なら `not_received` |
| `poll_state(pane_id)` | `herdr agent get <pane_id> \| jq -r '.result.agent.agent_status'` の結果をそのまま `working`/`done`/`blocked` として使う。`idle` は初回 prompt を処理する前にも通る状態で完了と区別できないため `unknown` として返す |

## Orca

Claude Code 自身が Orca 管理下の pane で動いていることが前提。Orca には herdr の `pane current` に相当する「自分がどの pane か」を直接返すコマンドが無いため、`orca terminal list --json` を実行し、`worktreePath` が現在の作業ディレクトリと一致し `agentIdentity` が `claude` である要素の `handle` を自分の pane として扱う。**既知の未解決 gap**: cwd が git worktree のサブディレクトリの場合、この方法は 0 件しかマッチしない（実地確認済み）。Orca は `worktreePath` として git worktree のパスではなくメインリポジトリのパスを返すため。codex-driven-development は worktree 上での実行を通常運用とするため、この検出方法は現状そのままでは使えない。

| 契約操作 | コマンド |
|---|---|
| `detect()` | `command -v orca` が成功し、`orca status --json` の `result.runtime.reachable` が `true` |
| `create_pane(cwd)` | 自分の pane の handle が分かれば `orca terminal split --terminal <own_handle> --direction horizontal --cwd "<cwd>"` → `result.split.handle`。分からなければ `orca terminal create --worktree "path:<cwd>"` → `result.terminal.handle`（**`result.handle` ではない**）。**`split` の `ok:false`/timeout エラーは信頼できない場合がある** — エラー応答を返した呼び出しがバックエンドでは非同期に成功し、pane が実際には作られていたケースを実地確認済み。エラー時は即 retry せず `orca terminal list` で実際に作成されていないか確認してから判断すること（さもないと pane の重複作成や、作られた pane の孤児化につながる） |
| `run(pane_id, argv)` | pane 作成時に `--command "codex \"<prompt>\""` を渡して同時に起動する（`create_pane` 呼び出しと同時に行う） |
| `send_text(pane_id, text)` | `orca terminal send --terminal <pane_id> --text "<text>"`（**`--enter` と同時指定しない** — 同時指定は `agent_prompt_blocked` で拒否されるケースを実地確認済み） |
| `send_keys(pane_id, "Enter")` | `orca terminal send --terminal <pane_id> --enter`（`send_text` とは別呼び出しにする） |
| `read(pane_id)` | `orca terminal read --terminal <pane_id> --json` → `result.terminal.tail`（ANSI 制御文字混じりの生テキストが返るため、パース時は考慮する） |
| `close_pane(pane_id)` | `orca terminal close --terminal <pane_id>`。**既知の未解決 gap**: `orca terminal create` で作成した pane が `orca terminal list` に一度も現れず、その handle で `close_pane` を呼ぶと `tab_not_found` で失敗するケースを実地確認済み。原因未特定 |
| `receipt_check(pane_id)` | `read(pane_id)`（`orca terminal read --terminal <pane_id> --json` → `result.terminal.tail`）で boot prompt のテキストが composer / 入力欄に未送信のまま残っていないかを確認する。残っていなければ `received`。**ベストエフォート**——herdr の `agent_status` のような証明された signal ではなく、テキストが消えていても Codex 側が処理を始めた確証にはならない |
| `poll_state(pane_id)` | `read(pane_id)` の `result.terminal.tail` が既知の対話ダイアログ文言（`Do you trust the contents of this directory?` / `Hooks need review`）を含めば `blocked`。それ以外は常に `unknown`（herdr の `agent_status` に相当する検証済みの状態フィールドが無いため、`working`/`done` の判別はしない） |

## bridge armed 確認（multiplexer 非依存）

どちらの adapter を使う場合も、Dispatch 後に以下で agmsg の Codex monitor bridge が arm したかを確認する:

```sh
~/.agents/skills/agmsg/scripts/delivery.sh status codex "$PROJECT"
```

出力に `Codex bridge: <team>/<agent> alive (pid <pid>)` の行が含まれれば armed。含まれなければ（例: `Codex bridge: <team>/<agent> not running`）、fallback mode に切り替える。
