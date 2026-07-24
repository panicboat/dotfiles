---
name: agmsg-driven-development
description: 実装 plan を実行するとき、implementer を agmsg 経由で spawn した Codex に委譲してトークン使用量を分散する。superpowers:subagent-driven-development の実行構造（タスクごとの実装 → タスクレビュー → 最終レビュー）は維持し、implementer 周りだけを置き換える。plan の実行方式として agmsg-driven-development が選択されたときに使用する。
---

# agmsg-Driven Development

superpowers:subagent-driven-development（以下 SDD）の実行構造を維持したまま、implementer を agmsg 経由の Codex に置き換えて plan を実行する。実装（最もトークンを消費する工程）を Codex に移し、Claude には意図の判断——plan 管理・task brief 作成・レビュー裁定——を残す。

## Prerequisites

開始前に以下を確認する。1〜2 が欠けていれば、欠けている項目を報告して SDD での実行を提案する。

1. `command -v codex` が成功する
2. `test -x ~/.agents/skills/agmsg/scripts/spawn.sh` が成功する
3. tmux 内である（`test -n "$TMUX"`）。tmux 外なら停止し、`claude` を tmux 内で起動し直すようユーザーに促す（`.zshrc` の `claude` ラッパーがこれを自動化する）。tmux 必須なのは、despawn が tmux の pane/window しか閉じられず、OS terminal 起動分は Teardown で掃除できないため（この制約回避のために OS terminal へフォールバックしない）

## Setup

完了条件: AGMSG・PROJECT・TEAM の 3 値が確定し、leader の join が成功していること。

1. Skill tool で superpowers:subagent-driven-development を読み込む。以後、Substitutions 節に挙げた項目以外はすべて SDD の指示に従う（Pre-Flight Plan Review・レビュー・progress ledger・File Handoffs・Red Flags を含む）。SDD の scripts（task-brief / review-package）は SDD 読み込み時に表示される base directory から解決する
2. 変数を確定する:
   - `AGMSG=~/.agents/skills/agmsg/scripts`
   - `PROJECT` = 作業 worktree の絶対パス
   - `TEAM` = `<リポジトリ名>-<ブランチ名の / を - に置換した値>`。リポジトリ名は `basename "$(dirname "$(git -C "$PROJECT" rev-parse --path-format=absolute --git-common-dir)")"` で得る（worktree でも main checkout の名前になる）
3. leader を join する: `AGMSG_RESOLVE_PROJECT=0 "$AGMSG/join.sh" "$TEAM" leader claude-code "$PROJECT"`
4. 以後のすべての agmsg スクリプト呼び出しに TEAM・agent 名・PROJECT を明示的に渡す。`whoami.sh` の自動解決を使わない

`AGMSG_RESOLVE_PROJECT=0` を外してはならない: agmsg の project 解決は SessionStart marker・登録済み ancestor・git common dir から「session が属する project」を推定するため、worktree からの join が main checkout に巻き戻され、並列 run の登録が衝突する。

## Substitutions

SDD の以下の項目だけを置き換える。表にない項目はすべて SDD のまま（task reviewer / final reviewer は SDD どおり Claude subagent）。

| SDD | 本 skill |
|---|---|
| Task tool で implementer subagent を dispatch | Dispatch 節の手順で Codex を spawn |
| implementer-prompt.md | 本 skill と同じディレクトリの codex-dispatch-prompt.md |
| implementer の返値による報告 | agmsg メッセージ + report file（Await 節） |
| 質問回答・追加 context・fix の再依頼 | Redispatch 節（despawn → dispatch file 更新 → 再 spawn） |
| implementer への Model Selection | Codex は既定モデル。必要時のみ `spawn.sh --model` |

## Dispatch

タスクごとに実行する。完了条件: spawn が成功し、Codex の pane が起動していること。

1. BASE commit を記録し、SDD の task-brief script で brief file を生成する
2. codex-dispatch-prompt.md の `{{...}}` をすべて埋め、brief と同じディレクトリの `task-N-dispatch.md` に書く
3. spawn する: `"$AGMSG/spawn.sh" codex implementer --project "$PROJECT" --team "$TEAM" --boot-prompt "Read <dispatch file の絶対パス> and follow it exactly."`
4. spawn が name 保持エラーで失敗したら `"$AGMSG/despawn.sh" "$TEAM" leader implementer --force` を実行して 1 回だけ再試行する。再失敗したらユーザーに報告して指示を待つ

## Await

完了条件: implementer の status を受信し、despawn が完了していること。

1. `"$AGMSG/watch-once.sh" "$PROJECT" claude-code --name leader --team "$TEAM" --timeout 3600` を background で実行し、終了を待つ
2. exit 0: `"$AGMSG/inbox.sh" "$TEAM" leader` で受信する
3. exit 2（timeout）: report file を確認する。status が書かれていればそれを受信内容として扱う。書かれていなければ tmux pane の状態をユーザーに報告して指示を待つ（勝手に再 spawn しない）
4. 受信後 `"$AGMSG/despawn.sh" "$TEAM" leader implementer --force` で pane を閉じる
5. status は SDD の Handling Implementer Status に従って処理する。DONE → SDD どおり review-package → task reviewer subagent

## Redispatch

NEEDS_CONTEXT・BLOCKED・レビュー指摘の fix はすべて再 spawn で行う。完了条件: 更新済み dispatch file で Dispatch 手順 3〜4 と Await が完了していること。

1. dispatch file の末尾に `## Redispatch N` 見出しで回答・追加 context・findings を追記する（fix の内容要件は SDD の fix dispatch に従う）
2. Dispatch 手順 3〜4 と Await を実行する

idle な Codex は後送メッセージを受信できない。`send.sh` で Codex に指示を送ってはならない——Codex への入力は spawn の boot-prompt だけ。

## Teardown

final review 完了後、または run を中断するときに実行する。完了条件: `team.sh` が team not found を返すこと。

1. `"$AGMSG/despawn.sh" "$TEAM" leader implementer --force`（despawn 済みによるエラーは想定内として続行する）
2. `"$AGMSG/leave.sh" "$TEAM" leader`（最後のメンバーが抜けた team は削除される）
3. `"$AGMSG/team.sh" "$TEAM"` がエラーになることを確認する

## Red Flags

SDD の Red Flags に加えて、以下をしてはならない。

- idle な Codex へ send.sh で指示を送る（届かない。Redispatch する）
- whoami.sh / pwd の自動解決に頼る（worktree が main checkout に巻き戻される）
- `AGMSG_RESOLVE_PROJECT=0` なしで join する
- implementer を despawn せずに次の spawn をする（name 衝突で拒否される）
- Teardown を飛ばして run を終える（team と登録が残る）
