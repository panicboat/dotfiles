# Implementer Adapters

## Adapter Contract

各 adapter は `adapters/<cli>.sh` という実行可能スクリプトで、次の subcommand を実装する。
SKILL.md は subcommand だけを呼び、CLI 固有のフラグ・出力形式を知らない。

| subcommand | 動作 | 終了コード / 出力 |
|---|---|---|
| `detect` | CLI が使えるか | 使えれば 0 |
| `run <out> <prompt>` | `cd` 済みの作業ディレクトリで新規セッションを 1 ターン実行し、生出力を `<out>.*` に書く | 0: 成功 / 142: 打ち切り / その他: 失敗 |
| `resume <session_id> <out> <prompt>` | 同じセッションで 1 ターン実行 | `run` と同じ |
| `session_id <out>` | `<out>.*` から再開用 ID を stdout に出す | 取れなければ非 0 |
| `last_message <out>` | `<out>.*` から最終応答を stdout に出す | 取れなければ非 0 |

- どの subcommand も、作業対象ディレクトリ（`PROJECT`）へ `cd` した shell から呼ばれる
- 打ち切り線は adapter の責務で、`run` / `resume` は環境変数 `WAIT_BUDGET`（既定 1800 秒）で必ず終わる。CLI 固有の打ち切り表現は終了コード 142 に正規化する
- CLI 自身に子孫プロセスまで止める打ち切りが無ければ、`bound.pl <seconds> <command> [args...]` で包む。`bound.pl` は時間切れで子孫プロセスを再帰的に TERM → KILL して 142 で終わり、時間内なら子の終了コードを返す
- 出力の解析は jq を使わず grep / sed で行う（新しい依存を足さない）

## Adding an Adapter

CLI を adapter に加える前に、次をすべて満たすことを確かめる。

1. 利用規約が、別の AI エージェント（Claude Code）から非対話モードで無人・反復起動することを禁じていない
2. 非対話モードで 1 ターン実行し、終了コードで成否が分かる
3. 再開用のセッション ID を機械的に取り出せ、その ID で文脈を保ったまま再開できる
4. worktree 内で `git commit -s` まで完了できる
5. 打ち切りで子孫プロセスが残らない（CLI 自身の timeout か `bound.pl`）

満たしたら次の 3 つを追加する。満たさない CLI は表に「不採用」の行だけを追加する。

- `adapters/<cli>.sh`（Adapter Contract を実装する）
- `tests/<cli>.test.sh`（PATH 先頭に置いた stub CLI で引数の組み立て・`session_id` 抽出・終了コードの正規化を検証する）
- 下の Terms Check の表に 1 行

## Terms Check

CLI 1 つにつき 1 行。

| CLI | version | checked | 判定 | 参照 |
|---|---|---|---|---|
| codex | 0.169.0 | 2026-11-20 | 採用（公式 docs がスクリプト / CI 用途を案内） | https://developers.openai.com/codex/noninteractive |
| agy | 1.5.12 | 2026-11-20 | 不採用（Terms Section 6: third party tools / products not provided by us） | https://antigravity.google/terms , https://geminicli.com/docs/resources/faq/ |

`agy` は条件 2〜5 を満たす（`-p --output-format json` の `conversation_id`、`--conversation` での再開、worktree での commit、`--print-timeout` 時の子プロセス終了と終了コード 3）が、条件 1 を満たさない。
Antigravity Terms Section 6 が "using third party software, tools, or services to access the Service" と "using the Service in connection with products not provided by us" を停止・解約事由とし、Gemini CLI FAQ が Claude Code を名指しして第三者ツールからの OAuth 利用を "direct violation" としている。
