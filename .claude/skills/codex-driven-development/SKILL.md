---
name: codex-driven-development
description: 実装 plan を実行するとき、implementer を herdr pane 上の Codex に委譲してトークン使用量を分散する。superpowers:subagent-driven-development の実行構造（タスクごとの実装 → タスクレビュー → 最終レビュー）は維持し、implementer 周りだけを置き換える。動作条件は herdr session 内で実行していること・codex integration が導入済みであることで、満たさなければ何も起動せず SDD での実行を提案する。plan の実行方式として codex-driven-development が選択されたときに使用する。
---

# Codex-Driven Development

superpowers:subagent-driven-development（以下 SDD）の実行構造を維持したまま、implementer だけを herdr pane 上の Codex に置き換えて plan を実行する。実装（最もトークンを消費する工程）を Codex に移し、Claude には意図の判断——plan 管理・task brief 作成・レビュー裁定——を残す。

## Prerequisites

開始前に以下を確認する。ひとつでも欠けていれば、欠けている項目を報告して SDD での実行を提案する。

1. `command -v herdr` が成功する
2. herdr session 内である（`herdr pane current` が成功する）。session 外なら herdr を起動してその中で claude を動かすようユーザーに促す。`protocol_mismatch` なら server 再起動が要り、エラーメッセージが socket path 付きの `herdr server stop` を示すのでユーザーに提示する。**server 再起動は既存 pane のプロセスを落とす**ため、勝手に実行しない
3. codex integration が入っている（`herdr integration status | grep '^codex:'` の行が `not installed` でない。語彙は `current (vN)` / `not installed` で、`installed` という文字列は出力されない）。未導入なら `herdr integration install codex` を促す。これが無いと `agent_status` が更新されず Await の補助信号が死ぬ

## Setup

完了条件: PROJECT が確定していること。

1. Skill tool で superpowers:subagent-driven-development を読み込む。以後、Substitutions 節に挙げた項目以外はすべて SDD の指示に従う（Pre-Flight Plan Review・レビュー・progress ledger・File Handoffs・Red Flags を含む）。SDD の scripts（task-brief / review-package）は SDD 読み込み時に表示される base directory から解決する
2. `PROJECT` = 作業 worktree の絶対パスを確定する

## Substitutions

SDD の以下の項目だけを置き換える。表にない項目はすべて SDD のまま（task reviewer / final reviewer は SDD どおり Claude subagent）。

| SDD | 本 skill |
|---|---|
| Task tool で implementer subagent を dispatch | Codex を herdr agent として起動（Dispatch 節） |
| implementer-prompt.md | 本 skill と同じディレクトリの codex-dispatch-prompt.md |
| implementer の返値による報告 | report file の `STATUS:` 行 + `agent_status`（Await 節） |
| 質問回答・追加 context・fix の再依頼 | 生きた Codex への `send-text` + `send-keys`（Redispatch 節） |
| implementer への Model Selection | Codex は既定モデル |

## Batching Strategy

SDD の "Batch small same-shape work" が Codex 版では **バッチ = 1 pane** で運用される。fresh-per-task を強制すると、機械的な rename / config 更新の連続タスクでも毎回 pane split → agent start → pane close が要り冗長になる（実運用で 5 task の rename に pane を 5 個消費した反省）。

**バッチにする判断**:

- 5 task 全部が同じ shape の機械的置換 → 1 バッチ
- 前半 3 task が構造移動、後半 4 task が新レイアウトへの config 追随 → 2 バッチ (構造と追随で pane を分ける)
- タスクごとに fresh judgement が要る (テスト設計・API 決定) → 従来どおり 1 task = 1 pane

**バッチ dispatch の要件**:

- `task-1-3-dispatch.md` / `task-4-7-dispatch.md` のように **バッチを 1 ファイル**にまとめる。中で「brief 1〜3 を順に読んで実装。各 brief = 1 commit」と明示する
- **順序依存を明記** — バッチ内で「必ず順に実行」なのか「並行可」なのか
- **タスク間の中間状態** — 各タスクの中間状態でも repository が機能する必要があるか (proto の 2 段変更のような設計は Global Constraints に書く)
- **report file はバッチで 1 つ** (`task-1-3-report.md`) — Codex がバッチの STATUS を最後に上書きする

**バッチ間の pane 切り替え**: バッチが終わったら pane を close し、次バッチは新 pane で開く。fresh-per-batch。中で fix round が走る間は同じ pane を live で使う (Redispatch 節どおり)。

**バッチにしないと決めたら**: SDD どおり 1 task = 1 pane。この Skill の Dispatch/Await/Teardown はどちらでも成立する。

## Dispatch

タスクごとに実行する。完了条件: `agent start` が成功し、`agent_status` が `blocked` でないこと。

**Dispatch 前チェック: plan の validation が実行に依存していないか。** plan/brief の Step に `bundle exec`, `pnpm run`, `bin/codegen`, `pytest`, `npm test`, `docker build`, `terraform plan` 等の**実行を伴う検証**がある場合、fresh worktree では対応する依存 (`bundle install`, `node_modules`, gem native extension, docker daemon, cloud creds) が高確率で未整備で、Codex は BLOCKED になる。dispatch 前に:

- 検証が本当に実行を要求しているか読み直す (`bin/codegen` の存在確認と実行は別物)
- 実行必須なら controller が依存を先に整えるか、`test -d`, `grep -n`, `bash -n` 等の**構造検証に差し替えた指示**を Codex に渡す
- 差し替えなら「実際に走らせるかは開発者に任せる」ことを report / plan の Validation セクションに **既知の限界として明記**する

これを飛ばすと Codex が BLOCKED を上げ、redispatch で controller が結局差し替えを裁定することになる（実運用でほぼ毎回発生）。事前に潰す方が早い。

1. BASE commit を記録し、SDD の task-brief script で brief file を生成する
2. codex-dispatch-prompt.md の `{{...}}` をすべて埋め、brief と同じディレクトリの `task-N-dispatch.md` に書く
3. Codex 用の pane を作る（controller の pane を分割、cwd を worktree に）。**`PANE` が取れたことを確認してから進む**——取れないまま進むと以降の全コマンドが空文字列を target にして無関係なエラーを出す:

   ```sh
   PANE=$(herdr pane split --current --direction right --cwd "$PROJECT" | jq -r '.result.pane.pane_id')
   case "$PANE" in ""|null) echo "SPLIT_FAILED"; exit 1;; esac
   ```

4. **dispatch prompt を argv に載せて** Codex を起動する。agent 名は herdr server 全体で一意でなければならないため worktree 名から導出する:

   ```sh
   AGENT="impl-$(basename "$PROJECT")"
   BOOT="Read $PROJECT/path/to/task-N-dispatch.md and follow it exactly."   # 絶対パスに置き換える
   for i in $(seq 1 10); do
     OUT=$(herdr agent start "$AGENT" --kind codex --pane "$PANE" --timeout 120000 -- "$BOOT" 2>&1)
     printf '%s' "$OUT" | grep -q '"error"' || break
     printf '%s' "$OUT" | grep -q 'agent_name_taken' && break   # 待っても解消しない
     sleep 2
   done
   printf '%s' "$OUT" | grep -q '"error"' && { echo "START_FAILED"; printf '%s\n' "$OUT"; exit 1; }
   ```

   `--` 以降は codex の positional PROMPT にそのまま渡る（`codex [OPTIONS] [PROMPT]`）。**prompt が起動時に確定するので TUI への投入競合が無い**。起動直後にモーダルが出ても prompt はキューされ、モーダルを閉じた時点で自動投入される。リトライは `agent_pane_busy`（split 直後の shell がまだ idle 判定されていない）向けで、`agent_name_taken` は待っても解消しないので即座に抜けて `AGENT` に suffix を足して 1 度だけやり直す。それ以外でリトライが枯渇したらユーザーに報告して指示を待つ

5. prompt が処理に入ったことを確認する。`agent start` 直後は `idle`（まだ処理を始めていない）を通るため**単発チェックでは判定できない**。遷移するまでポーリングする:

   ```sh
   for i in $(seq 1 20); do
     ST=$(herdr agent get "$PANE" | jq -r '.result.agent.agent_status')
     case "$ST" in working|done|blocked) break;; esac
     sleep 3
   done
   echo "status=$ST"
   ```

   - `working` / `done` — prompt は届いている。Await へ進む
   - `blocked` — モーダルで入力待ち。Failure Modes の該当行で解消する
   - `idle` のまま枯渇 — `tail -1 ~/.codex/history.jsonl` の末尾が今の boot prompt かを見る。一致すれば届いており Codex が遅いだけ、不一致なら届いていない

## Await

完了条件: Codex の停止を検知し、report の STATUS を読んだこと。

1. report file の `STATUS:` を第一信号、`agent_status` を補助信号として待つ。`WAIT_BUDGET` は打ち切り線:

   ```sh
   REPORT="/abs/path/to/task-N-report.md"   # 実際の絶対パスに置き換える
   WAIT_BUDGET=1200   # 秒
   DEADLINE=$(( $(date +%s) + WAIT_BUDGET ))
   OUTCOME=timeout
   while :; do
     grep -q '^STATUS:' "$REPORT" 2>/dev/null && { OUTCOME=report; break; }
     ST=$(herdr agent get "$PANE" 2>/dev/null | jq -r '.result.agent.agent_status')
     case "$ST" in done|blocked) OUTCOME="state:$ST"; break;; esac
     [ "$(date +%s)" -ge "$DEADLINE" ] && break
     sleep 5
   done
   echo "OUTCOME=$OUTCOME"
   ```

   完了状態に `idle` を含めない。`idle` は初回 prompt を処理する前にも通る状態で、完了と区別できない。turn の完了は integration が `done` として報告する
2. `OUTCOME=state:blocked` なら実行途中の承認要求。Failure Modes に従って解消し、ループに戻る
3. `OUTCOME=report` なら STATUS 行（DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED）を読む。STATUS が「何が起きたか」の source of truth
4. `OUTCOME=timeout` なら停止ではなくチェックポイントとして扱う（Failure Modes 参照）
5. STATUS は SDD の Handling Implementer Status に従って処理する。DONE → SDD どおり review-package → task reviewer subagent

**report file を第一信号にする理由**: `STATUS:` 行は dispatch prompt が Codex に「最後に書け」と指示している本 skill 自身の契約であり、herdr の state machine から独立している。`herdr agent wait` は使わない——`--until` の集合を間違えると無言で永久にブロックし、停止と正常な待機の区別が最も付きにくい形の失敗になる。

### `STATUS:` が信号として使えない場合の代替信号

初回 dispatch は `STATUS:` で問題ないが、以下の場面では `STATUS:` を第一信号にすると誤検知する。実運用で頻出:

- **redispatch 直後**: 前ラウンドの `STATUS: BLOCKED` (等) が report 先頭に残っており、Codex が上書きする前にループが「report あり」で即抜ける。ゼロ秒完了 → 実際は未着手というパターン
- **Codex が上書きし忘れる**: dispatch prompt に「上書きしろ」と書いてあっても、実際には append することがある。この場合 STATUS 行は「先頭のもの」しか読まれず、常に前ラウンドの結果として解釈される

このどちらかが疑わしい場面（= 全ての redispatch）では、**Codex の出力に依存しない信号**に切り替える。有力な選択肢:

- **commit 数** — バッチが期待する commit 数 (`N`) を事前に決めておき、`git rev-list --count $BASE..HEAD >= N` を第一信号にする。fix round の場合は `git rev-list --count $FIX_BASE..HEAD >= 1` (fix の追加コミット) で足りる
- **round 見出しの新規追加** — dispatch prompt に「`## Fix round N` 見出しを report に追記しろ」と書き、`grep -q "^## Fix round $N" "$REPORT"` を第一信号にする（この場合は overwrite ではなく append を要求）

どちらを使うかは round ごとに controller が選ぶ。commit 数ベースが最も堅牢（Codex の書き方に依存しない）。切り替えたときは `agent_status=blocked` の補助信号は残す（Codex が実行中モーダルで止まったら拾いたいため）。

## Redispatch

NEEDS_CONTEXT・BLOCKED・レビュー指摘の fix は、生きた Codex に投げ返す（pane を閉じない）。完了条件: prompt 投入を確認し、Await が完了したこと。

1. dispatch file の末尾に `## Redispatch N` 見出しで回答・追加 context・findings を追記する（記録用。fix の内容要件は SDD の fix dispatch に従う）
2. 生きた Codex に投げる。既に起動済みなので argv は使えず、TUI への投入になる:

   ```sh
   herdr pane send-text "$PANE" "<回答/findings。詳細は task-N-dispatch.md の ## Redispatch N を見よ>"
   sleep 2
   herdr pane send-keys "$PANE" Enter
   ```

   `herdr agent prompt` を使わない。`--wait --until working` を付けても、起動直後の一過性の `working` を拾って投入せずに成功を返すことがある（`--help` の "It does not track turns"）

   **send-text に含める文言に必ず「report file を上書きすること」を再度書く。** dispatch prompt にも同じ規約があるが、redispatch 経由でその指示を Codex に思い出させないと append されてしまい、次の Await が前ラウンドの STATUS で誤検知する。毎回 1 行入れるコストで stale 誤検知を確実に潰せる
3. **投入されたことを確認する。** 手順 2 は成否を返さないので、これが唯一の判定手段:

   ```sh
   tail -1 ~/.codex/history.jsonl
   ```

   Codex は受け取った prompt をここに追記する。行数が増え、末尾が今の prompt であることを確認する
4. Await を実行する。ただし report file には前ラウンドの `STATUS:` が既にあり第一信号が誤検知する。「Await」節末尾の「`STATUS:` が信号として使えない場合の代替信号」を参照して、commit 数か round 見出しに切り替える。commit 数ベースの例:

   ```sh
   EXPECTED=<このラウンドで積むはずの累計 commit 数>
   while :; do
     N=$(cd "$PROJECT" && git rev-list --count "$BASE"..HEAD 2>/dev/null || echo 0)
     [ "$N" -ge "$EXPECTED" ] && { OUTCOME=commits; break; }
     ST=$(herdr agent get "$PANE" 2>/dev/null | jq -r '.result.agent.agent_status')
     case "$ST" in blocked) OUTCOME="state:blocked"; break;; esac
     [ "$(date +%s)" -ge "$DEADLINE" ] && break
     sleep 5
   done
   ```

生きた Codex に投げ返すことで作業中の文脈を保持する。バッチ境界を跨ぐとき（次バッチ）だけ pane を閉じて fresh に開き直す（「Batching Strategy」参照）。バッチ内の fix round では常に同じ pane を live で使う。

## Teardown

タスクの review が通ったら、または run を中断するときに実行する。完了条件: 対象 pane が閉じていること。

1. `herdr pane close "$PANE"`（既に閉じている場合のエラーは想定内として続行）
2. 全タスク完了後、`herdr pane list` で残っている implementer pane を確認し、あれば同様に `herdr pane close <PANE_ID>` で閉じる

## Failure Modes

| 症状 | 原因 | 一手 |
|---|---|---|
| `agent_status` が `blocked` のまま | Codex がモーダルを表示して入力待ち | `herdr agent read "$PANE" --source visible --lines 40` で種類を判定。`Do you trust the contents of this directory?` はユーザー承認を得て `send-keys Enter`、`⚠ N hooks need review` は承認を得て `send-keys t` → `escape`。どちらも承認は永続。閉じれば argv の prompt が自動投入されるので投入し直さない |
| `agent read` が空文字列 | default の `--source recent` はモーダル表示中に空を返す | `--source visible` を付け直す。空を「画面が読めない」と解釈しない |
| `agent start` が `agent_pane_busy` | split 直後の pane の shell がまだ idle 判定されていない | 数秒おいてリトライ（Dispatch 手順 4 のループ） |
| `agent start` が `agent_name_taken` | 同名 agent が herdr server 全体に既存 | 待っても解消しない。error message が保持側の `pane_id` と `cwd` を示すので、前 run の残骸なら閉じ、並行 run なら `AGENT` に suffix を足して 1 度だけやり直す |
| Await が `WAIT_BUDGET` 超過 | 停止とは限らない | `git log` / `git status` / report file で実際の到達点を確かめ、ユーザーに報告して指示を待つ。**pane を作り直さない**——作業は完了・commit 済みのことがある |
| Redispatch 後の Await が即完了 | report file に前ラウンドの `STATUS:` が残っている | 第一信号を Codex 出力に依存しないものに切り替える（Await 節末尾「`STATUS:` が信号として使えない場合の代替信号」参照）。最堅牢は commit 数。round 見出しでも可 |
| 想定 commit 数が積まれない | Codex が (a) 依存不足で BLOCKED、(b) plan の裁定待ち、(c) モーダル入力待ち | `git log`, `git status`, report file, `herdr agent read --source visible` で到達点を確認。install / package add で回避を Codex に指示しない（環境不備は controller の裁定事項）— plan の validation 手段そのものを差し替える |
| herdr がエラーを返すのに jq が空を返す | herdr 停止 / protocol mismatch | ループは必ず上限で打ち切り、生出力をユーザーに見せる。`until` で無限に回さない |

## Red Flags

SDD の Red Flags に加えて、以下をしてはならない。

- herdr session 外で実行する（pane split の元 pane が無い）
- codex integration 未導入で実行する（`agent_status` が更新されず Await の補助信号が死ぬ）
- `herdr agent start` の出力を捨てる（起動失敗に気づけない）
- 完了検知を `agent_status` だけに頼る（初回 dispatch は `STATUS:`、redispatch は commit 数か round 見出し。Await 節参照）
- 打ち切り線の無い待機に入る（ハングと正常な待機が区別できず、復旧手順が発火しない）
- バッチ境界を跨いで同じ pane を使い回す（fresh-per-batch を壊す。バッチ完了で close し次バッチは新 pane。「Batching Strategy」参照）
- タスク途中の質問・fix で pane を閉じる（作業中の文脈を捨てる。Redispatch で生きた Codex に投げる）
- redispatch 時に「report を上書きしろ」の再念押しを省く（毎回入れる。stale STATUS 誤検知が確実に起きる）
- 実行依存の validation を dispatch 前に潰さない（Dispatch 節冒頭「Dispatch 前チェック」参照）
- 環境不備（bundle 未導入・cred 未設定等）を Codex に install / setup で埋めさせる（依存を追加するかは controller の裁定事項）
- Teardown を飛ばして run を終える（Codex pane が残る）
