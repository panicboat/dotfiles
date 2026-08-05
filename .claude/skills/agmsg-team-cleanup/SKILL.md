---
name: agmsg-team-cleanup
description: agmsg team の cleanup。user が明示指示したときに使う。指定 team の全 member を leave して team dir を消し、その team の messages を DB から削除する。追加で、team dir が存在しない orphan team の messages も除去できる。
---

# agmsg-team-cleanup

## When to use

主眼は team の cleanup（`~/.agents/skills/agmsg/teams/<team>/` を空にして dir ごと消す）。対象 team の messages 削除は従、team dir が存在しない orphan team の残存 messages 除去は付随処理として同じ invoke の末尾で行う。

自動 trigger は持たない。user が明示的に呼び出したときのみ動く。日常運用で team 登録は放置してよく、時間ベース・session ベースの自動解散はしない — `.claude/CLAUDE.md` から削除した Team Disband 節と同じ思想を skill 化したもの。

## Prerequisites

開始前に以下を確認する。ひとつでも欠けていれば、欠けている項目を報告して skill の実行を中断する。

1. `command -v sqlite3` が成功する
2. `~/.agents/skills/agmsg/scripts/` が存在する

利用する外部依存は以下のみ。skill 側で SQL を直接書くのは message の件数取得・purge（Step 3, 6, 7, 8）に限る:

- `whoami.sh <project_path>` — 現在の identity と `available_teams` を取得
- `team.sh <team>` — team の member 一覧を取得
- `leave.sh <team> <agent_id>` — 1 member を team から除去。最後の member 除去時に team dir 自動削除
- `~/.agents/skills/agmsg/db/messages.db` — SQLite。`messages(team, from_agent, to_agent, body, created_at, read_at)` テーブルに直接 SQL を発行
- `~/.agents/skills/agmsg/teams/` — team dir が並ぶディレクトリ。orphan 判定に使う

## Entry mode

Skill invoke 時に entry mode を分岐させる。

- **Mode A（team disband + orphan purge）**: user が team 名を指定した、あるいは `whoami.sh` の `available_teams` から user が選んだ場合。Workflow の全 Step（1〜9）を実行する。
- **Mode B（orphan purge のみ）**: user が「disband したい team は無い、orphan だけ掃除したい」と明示した場合。Step 1〜6 をスキップし、Step 7〜9 のみ実行する。

Entry 時に、team 名の有無を確認する:

1. user が最初から team 名を渡した → Mode A（Step 1 で team 名確定）
2. team 名なしで invoke された → `whoami.sh "$(pwd)"` で `available_teams` を取得する
   - `available_teams=none` の場合: Mode B で確定
   - 1 件以上の場合: AskUserQuestion で「解散する team を選ぶ / orphan のみ実行（Mode B）」を選ばせる

## Workflow: Mode A (team disband + orphan purge)

### Step 1. Team 特定

- user が team 名を渡していなければ、`whoami.sh "$(pwd)"` の `available_teams` を提示して選ばせる
- 選ばれた team 名を `TEAM` とする

### Step 2. Member 列挙

- `team.sh <TEAM>` を実行し member 一覧を取得する
- team が存在しない場合（`Team not found: <TEAM>` を exit 1 で返す）はここで報告して終了する。orphan purge（Step 7 以降）には進まない — team 名を誤った可能性が高いため、user に再確認させる

### Step 3. Message 件数取得

- 削除対象の message 件数を取得する:

```bash
sqlite3 ~/.agents/skills/agmsg/db/messages.db \
  ".param set :team '<TEAM>'" \
  "SELECT COUNT(*) FROM messages WHERE team=:team;"
```

- DB が存在しない場合は 0 件として扱う

### Step 4. 一括承認

AskUserQuestion で以下を 1 回にまとめて提示する:

- 対象 team 名
- Leave 対象の member 一覧
- 削除される messages の件数

user が承認したら Step 5 へ進む。拒否されたら skill を終了する。dry-run mode は持たない（この提示自体が dry-run 相当）。

### Step 5. Member leave 実行

- member ごとに `leave.sh <TEAM> <agent_id>` を実行する
- 最後の member 除去時に team dir が自動削除される（`leave.sh` の既存挙動）
- 途中で失敗した場合はそこで停止し、「どこまで leave 済み・残り member・失敗理由」を報告する。Step 6 には進まない（team dir が中途半端に残った状態で messages を消すのは不整合になるため）

### Step 6. Message purge

- 以下を実行し、削除件数を記録する:

```bash
sqlite3 ~/.agents/skills/agmsg/db/messages.db \
  ".param set :team '<TEAM>'" \
  "DELETE FROM messages WHERE team=:team;"
```

- DB が存在しない場合はこの Step をスキップする
- 完了後、Orphan messages purge（Step 7〜8）に進む

## Workflow: Mode B (orphan purge only)

Step 1〜6（team disband 部分）をすべてスキップし、Orphan messages purge（Step 7〜8）から開始する。

## Orphan messages purge (Step 7–8, both modes)

Mode A・Mode B のいずれからこの Step に到達した場合も、同じ手順で実行する。

### Step 7. Orphan messages 検出

- 残存 team 名を取得する:

```bash
sqlite3 ~/.agents/skills/agmsg/db/messages.db \
  "SELECT DISTINCT team FROM messages;"
```

- `~/.agents/skills/agmsg/teams/` 配下の dir 名と突き合わせ、team dir が存在しない team 名を orphan として抽出する
- 今回 Mode A で disband した team は Step 6 で削除済みのため orphan には含まれない
- 各 orphan team ごとに件数を取得する:

```bash
sqlite3 ~/.agents/skills/agmsg/db/messages.db \
  ".param set :team '<orphan>'" \
  "SELECT COUNT(*) FROM messages WHERE team=:team;"
```

- DB が存在しない場合は「orphan 検出対象なし」として Step 8 をスキップする

### Step 8. Orphan purge 承認 + 実行

- orphan が 0 件なら「orphan なし」と報告して終了する
- 1 件以上なら team 別 message 件数を提示し、AskUserQuestion で「全 orphan team を一括で purge するか」を承認させる（team 単位の選択削除はしない — user が「掃除」として明示指示した以上、残す理由がある team はそもそも orphan にならないため）
- 承認されたら orphan team ごとにループして発行し、削除件数を報告する:

```bash
for t in "${ORPHANS[@]}"; do
  sqlite3 ~/.agents/skills/agmsg/db/messages.db \
    ".param set :team '$t'" \
    "DELETE FROM messages WHERE team=:team;"
done
```

- 拒否されたら skip したことを報告して終了する

## Completion report

以下を報告して終了する:

- Mode A の場合: disband した team 名、leave した member 数、削除した message 数
- Mode A / B 共通: orphan purge の対象 team 名一覧と削除 message 数

## Safety

- 承認 point は 2 箇所（Step 4 の team disband 承認 / Step 8 の orphan purge 承認）。それぞれ「何を消すか」を数値で提示してから聞く
- 承認前は DB / team dir に一切書き込まない
- 削除は不可逆。backup は取らない — user が明示指示した削除であること、backup を残すのは skill の目的（残骸を消す）に反することが理由
- SQL は sqlite3 の parameter binding（`.param set`）を使い、team 名を string 展開しない — `~/.agents/skills/agmsg/scripts/history.sh` の `_agmsg_sqlesc` と同等の防御を維持する

## Error handling

| 事象 | 対応 |
|---|---|
| `whoami.sh` が `available_teams=none` を返す | Entry mode の分岐に従い Mode B で確定して継続 |
| `team.sh` が team not found を返す | 報告して終了。orphan purge には進まない |
| `leave.sh` が途中失敗 | 停止して部分削除状態を報告。Step 6〜8 には進まない |
| `messages.db` が存在しない | message 系 Step をスキップして Mode A の team disband のみ実行 |
| SQL の DELETE が 0 件 | 「該当なし」として通常フロー継続（エラー扱いしない） |

## Verification (manual)

skill は SKILL.md 単体なので unit test は無い。以下の manual test で動作確認する。

1. **正常系（Mode A）**: テスト用 team を `join.sh` で作成し member を 2 名登録、messages を数件流したうえで skill を invoke する。team dir が消え messages が消えることを確認する
2. **正常系（Mode B）**: `messages.db` に orphan team の row を直接 insert してから skill を invoke する。orphan purge のみ走ることを確認する
3. **拒否系**: Step 4 / Step 8 で拒否した場合に DB / team dir が変わっていないことを確認する
4. **失敗系**: 存在しない team 名を渡した場合に「team not found」で終了することを確認する
