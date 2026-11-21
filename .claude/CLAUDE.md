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

1. 新規 Issue を作成して spec を転記する
2. 既存 Issue に転記する（Issue 番号をユーザーが指定）
3. 転記しない

会話・ブランチ名・PR 本文から対象 Issue が 1 件に定まる場合は、2 を「既存 Issue <URL> に転記する」と URL を埋めて提示する。

Issue には spec だけを転記し、plan は転記しない。転記する場合は次の順で行う。

1. spec のレビューをユーザーに依頼する前に、新規 Issue なら spec が解決する課題を本文にして作成する
2. 対象の Issue に spec 全文をコメントとして追加し、レビュー依頼にそのコメントの URL を添える
3. 転記後に spec を改訂したら、spec のコメントを改訂後の全文で更新する

### Plan Execution

実装 plan の実行前に、実行方式をユーザーに選ばせる。

1. delegated-development（実装を外部 CLI エージェントに委譲してトークン使用量を分散）
2. subagent-driven-development（Claude subagent で実行）
3. executing-plans（このセッションでインライン実行）

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
