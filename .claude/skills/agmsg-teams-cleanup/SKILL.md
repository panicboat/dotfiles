---
name: agmsg-teams-cleanup
description: agmsg の全 team と全 messages を一括で cleanup する。user が明示指示したときのみ動く。承認後、全 team を member 全 leave で解散して team dir を消し、messages.db の全 row を削除する。個別 team を残す UI は持たない brute 用途。
---

# agmsg-teams-cleanup

## When to use

agmsg の全 team と全 messages を一気に消したい時に user が明示的に呼び出す。個別 team を残す・特定 message だけ残す選択肢は持たない — brute-force cleanup 専用。自動 trigger は無し。

## Prerequisites

開始前に以下を確認する。ひとつでも欠けていれば、欠けている項目を報告して skill の実行を中断する。

1. `command -v sqlite3` が成功する
2. `~/.agents/skills/agmsg/scripts/` が存在する

利用する外部依存:

- `~/.agents/skills/agmsg/scripts/team.sh <team>` — team の member 一覧を取得
- `~/.agents/skills/agmsg/scripts/leave.sh <team> <agent_id>` — 1 member を team から除去。最後の member 除去時に team dir 自動削除
- `~/.agents/skills/agmsg/teams/` — team dir が並ぶ
- `~/.agents/skills/agmsg/db/messages.db` — SQLite。`messages(team, from_agent, to_agent, body, created_at, read_at)` テーブルに DELETE を直接発行

## Workflow

### Step 1. 対象一覧の取得

- `~/.agents/skills/agmsg/teams/` 配下の dir 名を一覧化する。dir 自体が無い or 空なら team 0 件として扱う
- 各 team について `team.sh <team>` を実行し member 一覧を取得する
- DB が存在する場合、全体件数と team 別内訳を取得する（team dir が消えた orphan 分も含めた全内訳）:

  ```bash
  sqlite3 ~/.agents/skills/agmsg/db/messages.db \
    "SELECT team, COUNT(*) FROM messages GROUP BY team ORDER BY team;"
  sqlite3 ~/.agents/skills/agmsg/db/messages.db \
    "SELECT COUNT(*) FROM messages;"
  ```

  DB が存在しない場合は message 0 件として扱う

### Step 2. 一括承認

team dir と messages がいずれも 0 件なら「掃除対象なし」と報告して終了する。

そうでなければ AskUserQuestion で以下を 1 回にまとめて提示する:

- 削除対象の team 名一覧とそれぞれの member
- messages の総件数と team 別件数（生きた team のぶんと orphan の内訳）
- 「全部消す / キャンセル」の 2 択

user が承認したら Step 3 へ進む。拒否されたら skill を終了する。dry-run mode は無い（この提示自体が dry-run 相当）。

### Step 3. 全 team の leave 実行

- Step 1 で列挙した team ごとに、その team の member 全員を `leave.sh <team> <agent_id>` で除去する
- 最後の member 除去時に team dir が自動削除される
- 途中で失敗した場合はそこで停止し、「どこまで leave 済み・残り team + member・失敗理由」を報告する。Step 4 には進まない — team dir が中途半端に残った状態で messages を消すと状態が不整合になるため

### Step 4. Messages 全削除

- 承認済みかつ Step 3 が完走したら、messages を一括削除する:

  ```bash
  sqlite3 ~/.agents/skills/agmsg/db/messages.db \
    "DELETE FROM messages;"
  ```

- DB が存在しない場合はこの Step をスキップする
- team 名を SQL に埋め込まないため escape 不要（`DELETE FROM messages;` はパラメータなし）

### Step 5. 完了報告

以下を報告して終了する:

- 消した team 名の一覧と member 数の合計
- 削除した message 総件数（Step 4 実行前後の COUNT 差、あるいは Step 1 で取得した総件数）

## Safety

- 承認 point は 1 箇所（Step 2）。「何を消すか」を team 名・member・message 件数まで数値で提示してから聞く
- 承認前は DB / team dir に一切書き込まない
- 削除は不可逆。backup は取らない — user が明示指示した「全消し」であること、backup を残すのは skill の目的（残骸を消す）に反することが理由
- 個別 team を残す・特定 message だけ残す UI は持たない。それが必要なら agmsg 純正 script (`leave.sh` 等) を手で叩く

## Error handling

| 事象 | 対応 |
|---|---|
| `~/.agents/skills/agmsg/teams/` dir 自体が存在しない | team 0 件として Step 2 の承認 UI に反映（messages のみ削除対象） |
| `team.sh` が team not found を返す | Step 1 で取得したスナップショットと現状に乖離あり。停止して報告し、user に再 invoke を促す |
| `leave.sh` が途中失敗 | 停止して部分削除状態を報告。Step 4 には進まない |
| `messages.db` が存在しない | Step 4 をスキップして team leave のみ実行 |

## Verification (manual)

skill は SKILL.md 単体なので unit test は無い。以下の manual test で動作確認する。

1. **正常系**: テスト用 team を 2 つ以上作り、それぞれに member と messages を数件流したうえで skill を invoke する。全 team dir が消え messages が 0 件になることを確認する
2. **拒否系**: Step 2 で拒否した場合に DB / team dir が変わっていないことを確認する
3. **空系**: team dir が存在せず message も 0 件の状態で invoke し、「掃除対象なし」と報告して終了することを確認する
