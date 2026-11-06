@../AGENTS.md

## Scope

Claude Code 固有のツール運用ルールだけを書く。汎用的な開発規範は AGENTS.md に書く。
このファイルのルールは skill の既定動作・既定の提案より優先する。

## Choices

ユーザーに選択肢から選ばせるとき（本ファイルの各確認・skill が提示する選択肢を含む）は、テキストで列挙せず AskUserQuestion tool を使う。

## Workflow

git リポジトリ内のファイル（docs・plan を含む）に書き込む前に、進め方をユーザーに選ばせる。git リポジトリでなければ確認しない。

1. worktree を使って進める
2. worktree を使わず新規ブランチを作成して進める
3. 現在のブランチ（実際のブランチ名を表示する）で進める

例外: 作業対象の worktree / ブランチを指定されて dispatch された実装担当は、確認せずそのブランチで作業する。実行方式も問い直さない。

## Superpowers

### Artifacts

skill が生成する spec / plan の扱いを、Commit と Issue の 2 点について Workflow の確認と同時に選ばせる。

#### Commit

1. commit する: skill 既定の保存先に従う
2. commit しない: `.superpowers/` 以下に保存し、`/.superpowers/` を `.git/info/exclude` に追加する

#### Issue

1. 新規 Issue を作成して書き出す
2. 既存 Issue に書き出す（Issue 番号をユーザーが指定）
3. 書き出さない

会話・ブランチ名・PR 本文から対象 Issue が 1 件に定まる場合は、2 を「既存 Issue #<番号> に書き出す」と番号を埋めて提示する。

書き出す場合は、spec の全文と plan のチェックリストを 1 つの Issue に次の順で書き出す。

1. spec がユーザーのレビューで確定したら、新規 Issue なら spec 全文を本文にして作成し、既存 Issue なら spec 全文をコメントとして追加する
2. plan が確定したら、plan から下の規則でチェックリストを作り、同じ Issue にコメントとして追加する
3. plan 実行中にチェックリストの項目の完了を確認したら、該当項目にチェックを付ける
4. 書き出し後に spec / plan を改訂したら、spec は本文・コメントを改訂後の全文で更新し、plan のコメントは改訂後の plan から下の規則で作り直して更新する

plan のチェックリストは次の規則で作る。

- plan の Task ごとに `- [ ] Task N: <見出し>` を書く
- plan に前提の Task が書かれた Task には、子項目に `- 前提: Task N` を書く
- 環境ごとに順に進める Task には、環境ごとに子のチェック項目 `- [ ] <環境>` を進める順に書く
- 人の操作を含む Task には、人の操作ごとに子のチェック項目 `- [ ] 人の操作: <内容>` を書く。環境ごとの人の操作は、その環境の項目の下に書く
- Commit で「commit しない」を選んだ場合は、plan 全文を `<details>` で折りたたんでチェックリストの後に添える。「commit する」を選んだ場合は plan 全文を書き出さない

### Plan Execution

実装 plan の実行前に、実行方式をユーザーに選ばせる。

1. codex-driven-development（実装を Codex に委譲してトークン使用量を分散。herdr/Orca のセッション内が前提）
2. subagent-driven-development（Claude subagent で実行）
3. executing-plans（このセッションでインライン実行）

### codex-driven-development

同一セッション内で複数 worktree に並行実行する場合、2 つ目以降の worktree にも Monitor tool で watch.sh を個別に起動する: `~/.agents/skills/agmsg/scripts/watch.sh <session_id に一意なサフィックスを付けたもの> <project_path> claude-code`

## agmsg

fujibee/agmsg 純正 skill（`agmsg:agmsg`）に適用する。カスタム skill（`agmsg-teams-cleanup` 等）には適用しない。

### Team Selection

セッションで初めて agmsg を使う前に、team の扱いをユーザーに選ばせる。選択肢の提示前にコマンドを実行しない。

1. 新規 team を作成する: team 名と agent 名をユーザーが指定する
2. 既存 team に join する: `~/.agents/skills/agmsg/scripts/whoami.sh "$(pwd)"` の `available_teams` から team を選ばせ、`~/.agents/skills/agmsg/scripts/team.sh <team>` の参加 agent 名と衝突しない agent 名を決めさせる
3. 現在登録済みの identity のまま使う: `~/.agents/skills/agmsg/scripts/whoami.sh "$(pwd)"` の出力を提示する

### Delivery Mode

Team Selection で 1 または 2 を選んだら、delivery mode をユーザーに聞かず `monitor` に設定する。

1. `~/.agents/skills/agmsg/scripts/delivery.sh set monitor claude-code "$(pwd)"` を実行する
2. 出力の `AGMSG-DIRECTIVE` ブロックに書かれた command で Monitor tool を invoke する
