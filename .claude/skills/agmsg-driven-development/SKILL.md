---
name: agmsg-driven-development
description: 実装 plan を実行するとき、implementer を herdr 経由で起動した Codex に委譲してトークン使用量を分散する。superpowers:subagent-driven-development の実行構造（タスクごとの実装 → タスクレビュー → 最終レビュー）は維持し、implementer 周りだけを置き換える。plan の実行方式として agmsg-driven-development が選択されたときに使用する。
---

# agmsg-Driven Development

superpowers:subagent-driven-development（以下 SDD）の実行構造を維持したまま、implementer を herdr 経由の Codex に置き換えて plan を実行する。実装（最もトークンを消費する工程）を Codex に移し、Claude には意図の判断——plan 管理・task brief 作成・レビュー裁定——を残す。skill 名の "agmsg" は agent-message-driven の概念ラベルで、transport の実体は herdr。

## Prerequisites

開始前に以下を確認する。ひとつでも欠けていれば、欠けている項目を報告して SDD での実行を提案する。

1. `command -v herdr` が成功する
2. herdr session 内である（`herdr pane current` が成功する）。失敗したら**エラーの中身を読んでから対処を決める**。session 外なら herdr を起動してその中で claude を動かすようユーザーに促す。`protocol_mismatch`（client と server の version 差）なら herdr server の再起動が要り、エラーメッセージが実行すべき `herdr server stop` コマンドを socket path 付きで示すので、それをユーザーに提示する。**server 再起動は既存 pane のプロセスを落とす**ため、勝手に実行せず確認を取る
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
3. Codex 用の pane を作る（controller の pane を分割、cwd を worktree に）。**`PANE` が取れたことを確認してから進む**。取れないまま進むと以降の全コマンドが空文字列を target にして無関係なエラーを出す:

   ```sh
   PANE=$(herdr pane split --current --direction right --cwd "$PROJECT" | jq -r '.result.pane.pane_id')
   case "$PANE" in ""|null) echo "SPLIT_FAILED"; exit 1;; esac
   ```

4. その pane で Codex を起動する。**agent 名は herdr server 全体で一意**でなければならず、他プロジェクトの run が同じ名前を使っていると `agent_name_taken` で失敗するため、worktree 名から導出する:

   ```sh
   AGENT="impl-$(basename "$PROJECT")"
   ```

   split 直後の pane はまだ shell が idle と認識されておらず `agent start` が `agent_pane_busy` を返すため、成功するまでリトライする。ただし**リトライで解消する失敗としない失敗を分ける**:

   ```sh
   for i in $(seq 1 20); do
     OUT=$(herdr agent start "$AGENT" --kind codex --pane "$PANE" --timeout 120000 2>&1)
     printf '%s' "$OUT" | grep -q '"error"' || break
     # 名前衝突は待っても解消しない。即座に抜けて名前を変える
     printf '%s' "$OUT" | grep -q 'agent_name_taken' && break
     sleep 2
   done
   printf '%s' "$OUT" | grep -q '"error"' && { echo "START_FAILED"; printf '%s\n' "$OUT"; exit 1; }
   ```

   `agent_name_taken` なら `AGENT` に suffix を足して 1 度だけやり直す。それ以外でリトライが枯渇したらユーザーに報告して指示を待つ

5. agent が pane に登録され、かつ TUI が入力を受け付けるまで待つ。登録前に prompt を投げると `agent_not_found` になり、登録直後でも TUI が未応答なら prompt は捨てられる。**この 2 つは別の条件**なので両方待つ:

   ```sh
   REGISTERED=no
   for i in $(seq 1 15); do
     [ "$(herdr pane list | jq -r --arg p "$PANE" '.result.panes[]?|select(.pane_id==$p)|.agent' 2>/dev/null)" = "codex" ] \
       && { REGISTERED=yes; break; }
     sleep 2
   done
   [ "$REGISTERED" = "no" ] && { echo "NOT_REGISTERED"; herdr pane list; exit 1; }
   sleep 5   # 登録は TUI の準備完了を意味しない
   ```

   **上限を切る。** `herdr` 自体が落ちている・protocol mismatch を起こしている場合、エラー応答でも jq は空を返すだけなので、`until` で回すと永久にハングする。枯渇したら `herdr pane list` の生出力をユーザーに見せて指示を待つ

6. boot prompt を投入する。**`--wait` を必ず付ける**:

   ```sh
   herdr agent prompt "$PANE" "Read <dispatch file の絶対パス> and follow it exactly." \
     --wait --until working --timeout 15000
   ```

   `--wait` なしだと、agent が prompt を受け取れない状態でも成功が返り、投入されないまま待ちに入る。`--until working` を付けるので、成功して返った時点で投入は確定している。

   Await 節が `herdr agent wait` を禁じているのと矛盾しないのは、**`--timeout` で上限を切っているから**。無言で永久にブロックする失敗形にはならず、超過すれば `timeout` が返る。

   `agent_prompt_stalled` が返ったら投入は失敗している。**そのときだけ**手順 7 で原因を特定してから、手順 6 をやり直す。

7. **（手順 6 が `agent_prompt_stalled` を返した場合のみ）** 原因を特定する。まず投入の有無を切り分ける:

   ```sh
   tail -1 ~/.codex/history.jsonl
   ```

   Codex は受け取った prompt をここに追記する。末尾に今の prompt が無ければ**投入されていない**。原因の第一候補は Codex の **hook trust modal**（`⚠ N hooks need review before it can run` / `Press t to trust all`）で、表示中は入力を一切受け付けず prompt は黙って捨てられる。次で確認する:

   ```sh
   herdr agent read "$PANE" --source visible --lines 40
   ```

   **`--source visible` は必須。** default の `recent` は modal 表示中に空文字列を返すため、モーダルの存在に気付けない。
   モーダルがあれば `herdr agent send-keys "$PANE" t`（全 hook を信頼、実行前に user の確認を取る）→ `escape` で閉じ、入力プロンプト `›` が出たことを確認してから手順 6 をやり直す。承認は永続するので同一マシンで一度きり。

手順 5 の待機と手順 6 の `--wait` を省くと、`agent prompt` は成功を返すのに Codex は何もしない。`agent_status` は `idle` のままで、report file も commit も生成されない。「`agent start` が成功したから prompt を投げてよい」という読み方が原因。

## Await

完了条件: Codex の停止を検知し、report の STATUS を読んだこと。

1. report file の出現を第一の完了信号として待つ。herdr state は補助信号、`WAIT_BUDGET` は打ち切り線:
   ```sh
   REPORT="/abs/path/to/task-N-report.md"   # 実際の絶対パスに置き換える
   WAIT_BUDGET=1200   # 秒。超えたら諦めるのではなく、状況を見てユーザーに報告する
   DEADLINE=$(( $(date +%s) + WAIT_BUDGET ))
   OUTCOME=timeout
   while :; do
     grep -q '^STATUS:' "$REPORT" 2>/dev/null && { OUTCOME=report; break; }
     ST=$(herdr agent get "$PANE" 2>/dev/null | jq -r '.result.agent.agent_status')
     case "$ST" in done|blocked|idle) OUTCOME="state:$ST"; break;; esac
     [ "$(date +%s)" -ge "$DEADLINE" ] && break
     sleep 5
   done
   echo "OUTCOME=$OUTCOME"
   ```
   `idle` を完了と見なせるのは、Dispatch 手順 6 の `--wait --until working` で `working` への遷移を確認済みだから。あの確認を飛ばすとこのループは即座に「完了」と誤判定する
2. report file の STATUS 行（DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED）を読む。STATUS が「何が起きたか」の source of truth
3. `OUTCOME=timeout` なら停止ではなくチェックポイントとして扱う。report file、`git log`、`git status` を見て、実際にどこまで進んでいるかを確かめてからユーザーに報告し、指示を待つ（勝手に再起動しない）
4. STATUS は SDD の Handling Implementer Status に従って処理する。DONE → SDD どおり review-package → task reviewer subagent

**report file を第一信号にする理由**: `STATUS:` 行は dispatch prompt が Codex に「最後に書け」と指示している本 skill 自身の契約であり、herdr の state machine から独立している。herdr state を第一信号にすると、初回 prompt と Redispatch で遷移が違うといった癖に依存し、まだ観測していない同種の癖でも同じ形で止まる。`herdr agent wait` は使わない——`--until` の集合を間違えると無言で永久にブロックし、それが停止と正常な待機の区別を最も難しくする形の失敗になる。

**`WAIT_BUDGET` を有限にする理由**: 打ち切り線が無い（あるいは 60 分のように長すぎる）と、手順 3 の復旧手順が実行されないままになる。ハングと正常な待機が観測上区別できず、ユーザーから見ても「進んでいるのか止まっているのか分からない」状態が続く。長いタスクで足りなければ延ばしてよいが、無効化はしない。

## Redispatch

NEEDS_CONTEXT・BLOCKED・レビュー指摘の fix は、生きた Codex に投げ返す（pane を閉じない）。完了条件: prompt 投入と Await が完了したこと。

1. dispatch file の末尾に `## Redispatch N` 見出しで回答・追加 context・findings を追記する（記録用。fix の内容要件は SDD の fix dispatch に従う）
2. 生きた Codex に投げる。Dispatch 手順 6 と同様 `--wait` を必ず付ける: `herdr agent prompt "$PANE" "<回答/findings。詳細は task-N-dispatch.md の ## Redispatch N を見よ>" --wait --until working --timeout 15000`
3. Await を実行する。Redispatch では report file に既に前ラウンドの `STATUS:` 行があるため、Await 手順 1 のループはそのままでは即座に完了と誤判定する。ループに入る前に、この fix round で追記される見出し（例 `## Fix round N`）の出現を待つ条件に差し替える:
   ```sh
   grep -q '^## Fix round N' "$REPORT" 2>/dev/null && { OUTCOME=report; break; }
   ```

生きた Codex に投げ返すことで作業中の文脈を保持する。タスクを跨ぐとき（次タスク）だけ pane を閉じて fresh に開き直す。

## Teardown

タスクの review が通ったら、または run を中断するときに実行する。完了条件: 対象 pane が閉じていること。

1. `herdr pane close "$PANE"`（既に閉じている場合のエラーは想定内として続行）
2. 全タスク完了後、`herdr pane list` で残っている implementer pane を確認し、あれば同様に `herdr pane close <PANE_ID>` で閉じる

## Red Flags

SDD の Red Flags に加えて、以下をしてはならない。

- herdr session 外で実行する（pane split の元 pane が無い）
- codex integration 未導入で実行する（`agent_status` が更新されず、Await の補助信号が機能しない）
- `herdr agent start` の出力を捨てる（起動失敗に気づけない。Codex は自己更新を検出すると "Please restart Codex" と表示して終了することがあり、その場合 prompt は死んだプロセスに投入される）
- `agent start` の成功をもって prompt を投げてよいと見なす（登録も TUI 準備も終わっていない。手順 5 で両方待つ）
- `--wait` なしで `herdr agent prompt` を使う（投入されなくても成功が返る。`--until working` まで確認して 1 セット）
- 画面確認を `--source visible` なしで行う（default の `recent` は modal 表示中に空を返す。空だからといって「画面が読めない」と結論しない）
- prompt が届かないときに pane を作り直す（hook trust modal は pane を作り直しても再発する。まず `--source visible` で画面を見る）
- 完了検知を herdr state だけに頼る（初回 prompt と Redispatch で遷移が違う。report file の `STATUS:` を第一信号にする）
- 打ち切り線の無い、あるいは数十分に及ぶ待機に入る（ハングと正常な待機が区別できなくなり、Await 手順 3 の復旧手順も発火しない）
- 待機が返らないことを理由に pane を作り直す（`git log` を見る前に文脈を捨てている。作業は終わって commit 済みのことがある）
- Redispatch の待機で前ラウンドの `STATUS:` 行を完了信号として拾う（即座に誤判定する。その round で追記される見出しを待つ）
- タスクを跨いで同じ pane を使い回す（fresh-per-task を壊す。タスク完了で close し次は新 pane）
- タスク途中の質問・fix で pane を閉じる（作業中の文脈を捨てる。Redispatch で生きた Codex に投げる）
- Teardown を飛ばして run を終える（Codex pane が残る）
