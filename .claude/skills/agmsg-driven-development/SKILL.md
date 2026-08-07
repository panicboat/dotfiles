---
name: agmsg-driven-development
description: 実装 plan を実行するとき、implementer を herdr 経由で起動した Codex に委譲してトークン使用量を分散する。superpowers:subagent-driven-development の実行構造（タスクごとの実装 → タスクレビュー → 最終レビュー）は維持し、implementer 周りだけを置き換える。plan の実行方式として agmsg-driven-development が選択されたときに使用する。
---

# agmsg-Driven Development

superpowers:subagent-driven-development（以下 SDD）の実行構造を維持したまま、implementer を herdr 経由の Codex に置き換えて plan を実行する。実装（最もトークンを消費する工程）を Codex に移し、Claude には意図の判断——plan 管理・task brief 作成・レビュー裁定——を残す。skill 名の "agmsg" は agent-message-driven の概念ラベルで、transport の実体は herdr。

## Prerequisites

開始前に以下を確認する。ひとつでも欠けていれば、欠けている項目を報告して SDD での実行を提案する。

1. `command -v herdr` が成功する
2. herdr session 内である（`herdr pane current` が成功する）。session 外なら停止し、herdr を起動してその中で claude を動かすようユーザーに促す
3. codex integration が入っている（`herdr integration status | grep '^codex:'` の行が `not installed` でない）。この status の語彙は `current (vN)` / `not installed` で、`installed` という文字列は出力されない。未導入なら `herdr integration install codex` の実行を促す。これが無いと herdr は Codex の done/blocked を検出できない

## Setup

完了条件: PROJECT が確定していること。

1. Skill tool で superpowers:subagent-driven-development を読み込む。以後、Substitutions 節に挙げた項目以外はすべて SDD の指示に従う（Pre-Flight Plan Review・レビュー・progress ledger・File Handoffs・Red Flags を含む）。SDD の scripts（task-brief / review-package）は SDD 読み込み時に表示される base directory から解決する
2. `PROJECT` = 作業 worktree の絶対パスを確定する

## Substitutions

SDD の以下の項目だけを置き換える。表にない項目はすべて SDD のまま（task reviewer / final reviewer は SDD どおり Claude subagent）。

| SDD | 本 skill |
|---|---|
| Task tool で implementer subagent を dispatch | Dispatch 節の手順で Codex を herdr agent として起動 |
| implementer-prompt.md | 本 skill と同じディレクトリの codex-dispatch-prompt.md |
| implementer の返値による報告 | report file + herdr agent state（Await 節） |
| 質問回答・追加 context・fix の再依頼 | 生きた codex への `herdr agent prompt`（Redispatch 節） |
| implementer への Model Selection | Codex は既定モデル |

## Dispatch

タスクごとに実行する。完了条件: `agent_status` が `working` に遷移したことを確認したこと。**agent start の成功と prompt の受理は完了条件ではない。**

1. BASE commit を記録し、SDD の task-brief script で brief file を生成する
2. codex-dispatch-prompt.md の `{{...}}` をすべて埋め、brief と同じディレクトリの `task-N-dispatch.md` に書く
3. Codex 用の pane を作る（controller の pane を分割、cwd を worktree に）:
   `PANE=$(herdr pane split --current --direction right --cwd "$PROJECT" | jq -r '.result.pane.pane_id')`
4. その pane で Codex を起動する。split 直後の pane はまだ shell が idle と認識されておらず `agent start` が `agent_pane_busy` を返すため、成功するまでリトライする:
   ```bash
   for i in $(seq 1 20); do
     OUT=$(herdr agent start implementer --kind codex --pane "$PANE" --timeout 120000 2>&1)
     printf '%s' "$OUT" | grep -q '"error"' || break
     sleep 2
   done
   printf '%s' "$OUT" | grep -q '"error"' && { echo "START_FAILED"; printf '%s\n' "$OUT"; exit 1; }
   ```
   リトライが枯渇したらユーザーに報告して指示を待つ
5. Codex の TUI が対話を受け付けるまで待ってから boot prompt を投入する:
   ```bash
   sleep 5
   herdr agent prompt "$PANE" "Read <dispatch file の絶対パス> and follow it exactly."
   ```
6. `agent_status` が `working` に遷移したことを確認する。遷移しなければ prompt は捨てられている:
   ```bash
   SAW=no
   for i in $(seq 1 30); do
     ST=$(herdr agent get "$PANE" 2>/dev/null | jq -r '.result.agent.agent_status')
     [ "$ST" = "working" ] && { SAW=yes; break; }
     sleep 2
   done
   [ "$SAW" = "no" ] && { echo "PROMPT_NOT_ACCEPTED"; exit 1; }
   ```
   `working` を見ずに Await へ進むと wait が永久にブロックする。ここで止まったらユーザーに報告する

手順 5 の settle と手順 6 の確認を省くと、`agent prompt` は成功を返すのに Codex は何もしない。`agent_status` は `idle` のままで、report file も commit も生成されない。「`agent start` が成功したから prompt を投げてよい」という読み方が原因。

## Await

完了条件: Codex の停止を検知し、report の STATUS を読んだこと。

1. `herdr agent wait "$PANE" --until done --until blocked --until idle --timeout 3600000` でブロックする。`--until idle` は必須。session への 2 回目以降の prompt（Redispatch）では、Codex は完了時に `done` を経由せず `working` → `idle` に戻るため、`--until done --until blocked` だけでは永久にブロックする
2. report file の STATUS 行（DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED）を読む。herdr state は「いつ読むか」、STATUS は「何が起きたか」の source of truth
3. timeout（wait が非ゼロ終了）なら report file を確認する。STATUS があればそれを採用。無ければ commit の有無（`git log`）と worktree の状態を見てユーザーに報告し、指示を待つ（勝手に再起動しない）
4. STATUS は SDD の Handling Implementer Status に従って処理する。DONE → SDD どおり review-package → task reviewer subagent

`herdr agent read` は環境によって空を返し、pane 出力による診断ができない。観測手段は `agent_status` の遷移と report file の 2 つだけと前提を置く。wait が返らないときに Codex が固まったと判断する前に、まず `git log` を見る——作業は終わって commit まで済んでいることがある。

## Redispatch

NEEDS_CONTEXT・BLOCKED・レビュー指摘の fix は、生きた Codex に投げ返す（pane を閉じない）。完了条件: prompt 投入と Await が完了したこと。

1. dispatch file の末尾に `## Redispatch N` 見出しで回答・追加 context・findings を追記する（記録用。fix の内容要件は SDD の fix dispatch に従う）
2. 生きた Codex に投げる: `herdr agent prompt "$PANE" "<回答/findings。詳細は task-N-dispatch.md の ## Redispatch N を見よ>"`
3. Dispatch 手順 6 と同じ方法で `agent_status` が `working` に遷移したことを確認する
4. Await（`herdr agent wait "$PANE" --until done --until blocked --until idle --timeout 3600000`）を実行する

生きた Codex に投げ返すことで作業中の文脈を保持する。タスクを跨ぐとき（次タスク）だけ pane を閉じて fresh に開き直す。

## Teardown

タスクの review が通ったら、または run を中断するときに実行する。完了条件: 対象 pane が閉じていること。

1. `herdr pane close "$PANE"`（既に閉じている場合のエラーは想定内として続行）
2. 全タスク完了後、`herdr pane list` で残っている implementer pane を確認し、あれば同様に `herdr pane close <PANE_ID>` で閉じる

## Red Flags

SDD の Red Flags に加えて、以下をしてはならない。

- herdr session 外で実行する（pane split の元 pane が無い）
- codex integration 未導入で実行する（done/blocked を検出できず wait が返らない）
- タスクを跨いで同じ pane を使い回す（fresh-per-task を壊す。タスク完了で close し次は新 pane）
- タスク途中の質問・fix で pane を閉じる（作業中の文脈を捨てる。Redispatch で生きた Codex に投げる）
- Teardown を飛ばして run を終える（Codex pane が残る）
- `agent start` の成功や `agent prompt` の成功をもって Codex が動き出したと見なす（どちらも成功を返したまま Codex が何もしていないことがある。`agent_status` が `working` になるまでが 1 セット）
- `agent wait` から `--until idle` を落とす（Redispatch で永久にブロックする）
- wait が返らないことを理由に pane を作り直す（`git log` を見る前に文脈を捨てている）
