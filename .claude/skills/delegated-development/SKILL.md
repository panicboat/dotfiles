---
name: delegated-development
description: 実装 plan を実行するとき、implementer を外部 CLI エージェント（adapter: 現在は Codex）に非対話モードで委譲してトークン使用量を分散する。superpowers:subagent-driven-development の実行構造（タスクごとの実装 → タスクレビュー → 最終レビュー）は維持し、implementer 周りだけを置き換える。plan の実行方式として delegated-development が選択されたときに使用する。
---

# Delegated Development

superpowers:subagent-driven-development（以下 SDD）の実行構造を維持したまま、implementer だけを外部 CLI エージェントに置き換えて plan を実行する。
implementer は CLI の非対話モードで 1 ターンずつ起動し、プロセス終了を完了信号にする。
CLI ごとの差（起動・再開・結果の取り出し・打ち切り）は `adapters/<cli>.sh` に閉じており、本 skill は adapter の subcommand だけを呼ぶ。adapter の契約は `implementer-adapters.md` にある。

以下、`SKILL_DIR` は Skill tool がこの skill の読み込み時に表示する base directory の絶対パスを指す。
Bash の変数は呼び出しを跨いで残らないため、コマンドには `SKILL_DIR`・`PROJECT`・`OUT` 等の値を絶対パスで埋めて書く。
adapter に渡す prompt は英単語で始める（adapter は prompt を位置引数で CLI に渡すため、`-` で始まると CLI のフラグとして解釈される）。

## Prerequisites

完了条件: 今回の run の implementer CLI（以下 `<cli>`）が 1 つ決まっていること。

1. 使える CLI を列挙する:

   ```sh
   for a in "$SKILL_DIR"/adapters/*.sh; do "$a" detect && basename "$a" .sh; done
   ```

2. 0 個なら、どの CLI も使えないことを報告して SDD での実行を提案し、終了する
3. 1 個ならそれを `<cli>` にする。2 個以上なら AskUserQuestion で `<cli>` を選ばせる。`<cli>` は run 全体で 1 つとし、タスクごとに変えない

## Setup

完了条件: SDD が読み込まれ、`PROJECT` が確定していること。

1. Skill tool で superpowers:subagent-driven-development を読み込む。以後、Substitutions 節に挙げた項目以外はすべて SDD の指示に従う（workspace・ledger・Pre-Flight・task review・fix loop・final review を含む）。SDD の scripts（sdd-workspace / task-brief / review-package）は SDD 読み込み時に表示される base directory から解決する
2. `PROJECT` = 作業対象ディレクトリの絶対パスを確定する（worktree でも単一ブランチの checkout でもよい）。`PROJECT` は adapter を起動する前の `cd` 先としてだけ使う

## Substitutions

SDD の以下の項目だけを置き換える。表にない項目はすべて SDD のまま（task reviewer / final reviewer は SDD どおり Claude subagent）。

| SDD | 本 skill |
|---|---|
| Task tool で implementer subagent を dispatch（`### 1. Dispatch the implementer`） | `adapters/<cli>.sh run` を Bash `run_in_background` で起動する（Dispatch 節） |
| implementer-prompt.md | 本 skill と同じディレクトリの dispatch-prompt.md |
| implementer の返値による報告（`### 2. Handle the report`） | 終了通知を受けて report file の `STATUS:` 行を読む（Await 節） |
| implementer の agent identity の記録（fix loop の round 1-3 で resume する相手） | `adapters/<cli>.sh session_id` で取り出した session id の記録 |
| 質問回答・追加 context・fix の再依頼（re-dispatch・fix loop の resume） | `adapters/<cli>.sh resume` を Bash `run_in_background` で起動する（Redispatch 節） |
| implementer への Model Selection | CLI の既定モデル。SDD が上位モデルへの切り替えを指示する箇所（`references/handling-reports.md` の BLOCKED 2・`references/fix-loop.md` の round 4-5）も、モデルを変えずに Redispatch で行う |

## Batching Strategy

SDD の `references/batching.md`（Batch small same-shape work）を、本 skill では **バッチ = 1 セッション** で運用する。
セッションは `run` で始め、バッチ内の質問回答・fix は同じセッションへの `resume` で行う。
fresh-per-task を強制すると、機械的な rename / config 更新の連続タスクでも毎回新規セッションが dispatch file・brief・周辺コードを読み直すことになる。

**バッチにする判断**:

- 5 task 全部が同じ shape の機械的置換 → 1 バッチ
- 前半 3 task が構造移動、後半 4 task が新レイアウトへの config 追随 → 2 バッチ（構造と追随でセッションを分ける）
- タスクごとに fresh judgement が要る（テスト設計・API 決定）→ 1 task = 1 セッション

**バッチ dispatch の要件**:

- `task-1-3-dispatch.md` / `task-4-7-dispatch.md` のように **バッチを 1 ファイル** にまとめる。中で「brief 1〜3 を順に読んで実装。各 brief = 1 commit」と明示する
- **順序依存を明記する** — バッチ内で「必ず順に実行」なのか「並行可」なのか
- **タスク間の中間状態を明記する** — 各タスクの中間状態でも repository が機能する必要があるか（proto の 2 段変更のような設計は Global Constraints に書く）
- **report file はバッチで 1 つ**（`task-1-3-report.md`）。adapter の `<out>` も `task-1-3-round-K` とバッチ単位で命名する

**バッチ境界**: 次のバッチは新規 `run` で始める（fresh-per-batch）。前のバッチの session id を resume しない。

バッチにしない場合は 1 task = 1 セッションで、Dispatch / Await / Redispatch はどちらでも同じ手順で成立する。

## Dispatch

タスク（またはバッチ）ごとに実行する。完了条件: adapter の `run` が background task として起動し、その task id を記録したこと。

**Dispatch 前チェック: plan の validation が実行に依存していないか。** plan / brief の Step に `bundle exec`, `pnpm run`, `bin/codegen`, `pytest`, `npm test`, `docker build`, `terraform plan` 等の**実行を伴う検証**がある場合、fresh worktree では対応する依存（`bundle install`, `node_modules`, gem native extension, docker daemon, cloud creds）が未整備のことが多く、implementer は BLOCKED になる。dispatch 前に:

- 検証が本当に実行を要求しているか読み直す（`bin/codegen` の存在確認と実行は別物）
- 実行必須なら controller が依存を先に整えるか、`test -d`, `grep -n`, `bash -n` 等の**構造検証に差し替えた指示**を dispatch に書く
- 差し替えたら「実際に走らせるかは開発者に任せる」ことを report / plan の Validation セクションに **既知の限界として明記**させる

これを飛ばすと implementer が BLOCKED を上げ、Redispatch で controller が差し替えを裁定することになる。

1. BASE commit（`git rev-parse HEAD`）を記録し、SDD の task-brief script で brief file を生成する
2. dispatch-prompt.md の `{{...}}` をすべて埋め、brief と同じディレクトリに `task-N-dispatch.md` として書く。report file は SDD の命名（brief `task-N-brief.md` → report `task-N-report.md`）で同じディレクトリに置く
3. タスクの起動番号 `K` を 0 にし、`OUT` を brief と同じディレクトリの `task-N-round-0`（絶対パス）にする
4. 次を Bash `run_in_background` で起動し、返ってきた background task id を記録する:

   ```sh
   cd "$PROJECT" && "$SKILL_DIR/adapters/<cli>.sh" run "$OUT" "Read <task-N-dispatch.md の絶対パス> and follow it exactly."
   ```

## Await

`run` / `resume` を起動するたびに実行する。完了条件: report file の `STATUS:` を読んで SDD の report 処理に渡したか、Failure Modes に進んだこと。

1. background task の終了通知を待つ。待つ間は他の作業をしてよい。adapter は `WAIT_BUDGET`（既定 1800 秒）で必ず終わるため、通知はその時間内に届く
2. 終了したのが `run` なら `"$SKILL_DIR/adapters/<cli>.sh" session_id "$OUT"` で session id を取り出し、ledger に記録する（`resume` は同じ session id を使い続ける）。取れなければ Failure Modes の「`session_id` が取れない」に従う
3. 通知の終了コードが 142（打ち切り）なら:
   - そのタスクで 1 回目の打ち切りなら、Redispatch の 1・3・4・5 を実行する（2 の追記はしない）。prompt は `The previous turn was stopped by a timeout. Check git log, git status, and <rename 後の report の絶対パス> (if it exists) to find where you stopped, continue the task, write the report file, and exit.` にする
   - 同じタスクで 2 回目の打ち切りなら Failure Modes に従う
4. 終了コードが 0 でも 142 でもないなら Failure Modes に従う
5. 終了コードが 0 なら report file の 1 行目の `STATUS:` を読む。`STATUS:` が無ければ Failure Modes に従う
6. STATUS は SDD の `### 2. Handle the report` に従って処理する（DONE → review-package → task reviewer。それ以外 → `references/handling-reports.md`）。NEEDS_CONTEXT・BLOCKED への回答と task review の fix は Redispatch で送る

## Redispatch

NEEDS_CONTEXT・BLOCKED への回答、追加 context、レビュー指摘の fix を、記録した session id の同じセッションに送る。完了条件: Await が完了したこと。

1. `K` を 1 増やす。`K` はタスクごとの起動番号で、Dispatch の `run` が 0、以後 `resume`（Await 3 の打ち切り後の resume を含む）のたびに 1 増える
2. `task-N-dispatch.md` 末尾に `## Redispatch K` 見出しを追記し、回答・追加 context・findings を書く（fix の内容要件は SDD の `references/fix-loop.md` に従う）
3. report file があれば `task-N-report.round-<K-1>.md` に rename する。これで Await が読む `STATUS:` は今ラウンドの report のものだけになる
4. `OUT` を `task-N-round-K`（絶対パス）にし、次を Bash `run_in_background` で起動して background task id を記録する。`OUT` は起動のたびに新しい値にする（再利用すると前ラウンドの `<out>.last` が残る）:

   ```sh
   cd "$PROJECT" && "$SKILL_DIR/adapters/<cli>.sh" resume "<session id>" "$OUT" "Read the '## Redispatch <K>' section of <task-N-dispatch.md の絶対パス>, address it, write the report file, and exit."
   ```

5. Await を実行する

## Abort

run を中断するときに実行する。完了条件: 実行中の background task が無いこと。

1. 実行中の background task があれば TaskStop で止める（adapter が子孫プロセスまで止める）
2. CLI 側のセッション履歴は削除しない

## Failure Modes

| 症状 | 一手 |
|---|---|
| すべての adapter の `detect` が非 0 | 報告して SDD を提案する |
| 終了コード 0 だが report に `STATUS:` が無い | `git log $BASE..HEAD`・`git status`・`"$SKILL_DIR/adapters/<cli>.sh" last_message "$OUT"` で到達点を確かめてユーザーに報告する。作業が commit 済みのことがあるので作り直さない |
| 同じタスクで 2 回目の打ち切り（終了コード 142） | 同上 |
| 終了コードが 0 でも 142 でもない | background task の出力（stderr）と `$OUT.*` の末尾をユーザーに見せる（認証切れ・CLI 更新等） |
| `session_id` が取れない | resume できないので、以後の Redispatch は 1〜3 の後に 4 の代わりに新規 `run` で行う。prompt は `Read <task-N-dispatch.md の絶対パス> and follow it exactly, including every Redispatch section.` にし、終了後に Await 2 で session id を取り直す |
| 環境不備で BLOCKED | controller が依存を整えるか validation を構造検証に差し替え（Dispatch 前チェック参照）、Redispatch で伝える。implementer に install / setup させない |

## Red Flags

SDD の Red Flags に加えて、以下をしてはならない。

- adapter を介さずに CLI を直接起動する（打ち切り線と終了コードの正規化が外れる）
- adapter を Bash の前景で起動する（前景は 10 分上限で切られる）
- バッチ境界を跨いで同じセッションを resume する（fresh-per-batch を壊す）
- タスク途中の質問・fix を新規 `run` で行う（session id があるなら `resume` で文脈を保つ）
- 実行依存の validation を dispatch 前に潰さない（Dispatch 前チェック参照）
- 環境不備を implementer に install / setup で埋めさせる（依存を追加するかは controller の裁定事項）
