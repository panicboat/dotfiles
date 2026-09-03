---
name: codex-driven-development
description: 実装 plan を実行するとき、implementer を multiplexer pane 上の Codex に委譲してトークン使用量を分散する。superpowers:subagent-driven-development の実行構造（タスクごとの実装 → タスクレビュー → 最終レビュー）は維持し、implementer 周りだけを置き換える。動作条件は対応する multiplexer（herdr/Orca）のセッション内で実行していること・agmsg がインストールされていることで、満たさなければ何も起動せず SDD での実行を提案する。plan の実行方式として codex-driven-development が選択されたときに使用する。
---

# Codex-Driven Development

superpowers:subagent-driven-development（以下 SDD）の実行構造を維持したまま、implementer だけを multiplexer pane 上の Codex に置き換えて plan を実行する。実装（最もトークンを消費する工程）を Codex に移し、Claude には意図の判断——plan 管理・task brief 作成・レビュー裁定——を残す。pane の生成・破棄には `multiplexer-adapters.md` に定義された adapter 契約を使う。生きた Codex への追加指示（Redispatch）と完了検知（Await）は agmsg の Codex monitor bridge を使い、bridge が使えない場合のみ multiplexer 固有の TUI 操作にフォールバックする。

## Prerequisites

開始前に以下を確認する。ひとつでも欠けていれば、欠けている項目を報告して SDD での実行を提案する。

1. 使える multiplexer が最低1つある。`multiplexer-adapters.md` の `detect()` 手順を herdr → Orca の順に試す。**両方使えると判定された場合**は、現在の Claude Code セッション自身が動いている pane を提供している方を選ぶ（作業中の環境と同じツールで pane を割る方が自然で、確認コストも要らない）。判定できなければユーザーに選ばせる
2. agmsg がインストールされている（`~/.agents/skills/agmsg` が存在する）。無ければ agmsg のインストールをユーザーに促し、SDD での実行を提案する
3. Codex CLI があり、`~/.agents/skills/agmsg/scripts/drivers/types/codex/codex-shim.sh` が存在する（`codex` コマンドが shim 経由で起動する実配線は非対話スクリプトから確証できないため、ここでは弱いシグナルとして扱う。実際に機能しているかは Dispatch 節の bridge armed 確認で確定させる）
4. herdr を選んだ場合のみ: herdr session 内である（`herdr pane current` が成功する）。session 外なら herdr を起動してその中で claude を動かすようユーザーに促す。`protocol_mismatch` なら server 再起動が要り、エラーメッセージが socket path 付きの `herdr server stop` を示すのでユーザーに提示する。**server 再起動は既存 pane のプロセスを落とす**ため、勝手に実行しない

## Setup

完了条件: `PROJECT`・`TEAM`・agmsg の両 identity が確定していること。

1. Skill tool で superpowers:subagent-driven-development を読み込む。以後、Substitutions 節に挙げた項目以外はすべて SDD の指示に従う（Pre-Flight Plan Review・レビュー・progress ledger・File Handoffs・Red Flags を含む）。SDD の scripts（task-brief / review-package）は SDD 読み込み時に表示される base directory から解決する
2. `PROJECT` = 作業対象ディレクトリの絶対パスを確定する（多くの場合 worktree だが、単一ブランチでの作業等 worktree を使わないケースもあり、`PROJECT` はそのどちらでもよい）
3. `TEAM` を `PROJECT` から導出する（例: `cdd-$(basename "$PROJECT")`。既存の `AGENT="impl-$(basename "$PROJECT")"` と同じ命名思想。`PROJECT` のパスから決定的に導出できればよい）
4. 以下を idempotent に実行する（既に実行済みでも成功扱い）:

   ```sh
   ~/.agents/skills/agmsg/scripts/join.sh "$TEAM" claude claude-code "$PROJECT"
   ~/.agents/skills/agmsg/scripts/join.sh "$TEAM" codex codex "$PROJECT"
   ~/.agents/skills/agmsg/scripts/delivery.sh set monitor codex "$PROJECT"
   ```

5. Claude 自身の delivery mode を確認し、`monitor` でなければ Monitor tool を起動する:

   ```sh
   ~/.agents/skills/agmsg/scripts/delivery.sh status claude-code "$PROJECT"
   ```

   `mode: monitor` でなければ `~/.agents/skills/agmsg/scripts/delivery.sh set monitor claude-code "$PROJECT"` を実行し、出力される `AGMSG-DIRECTIVE` の指示に従って Monitor tool を起動する
6. `TEAM` は plan 実行全体を通して使い回す（後述 Run Teardown まで解体しない）。同一 `PROJECT` に対する再実行は既存 team に join するだけで、新規 team は作らない

## Substitutions

SDD の以下の項目だけを置き換える。表にない項目はすべて SDD のまま（task reviewer / final reviewer は SDD どおり Claude subagent）。

| SDD | 本 skill |
|---|---|
| Task tool で implementer subagent を dispatch | Codex を multiplexer pane 上の agent として起動（Dispatch 節、`multiplexer-adapters.md`） |
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
2. codex-dispatch-prompt.md の `{{...}}`（`{{TEAM}}` を含む。Task 6 でテンプレート自体を multiplexer 名を含まない汎用の文言に更新済み）をすべて埋め、brief と同じディレクトリの `task-N-dispatch.md` に書く
3. `multiplexer-adapters.md` の選ばれた adapter の `create_pane(cwd=$PROJECT)` を実行する。**`PANE` が取れたことを確認してから進む**——取れないまま進むと以降の全コマンドが空文字列を target にして無関係なエラーを出す:

   ```sh
   PANE="$(<adapter の create_pane コマンドの出力から pane id / handle を抽出>)"
   case "$PANE" in ""|null) echo "CREATE_PANE_FAILED"; exit 1;; esac
   ```

4. adapter の `run(pane_id, argv)` で **dispatch prompt を argv に載せて** Codex を起動する。agent 名/pane 名はサーバー全体で一意でなければならないため worktree 名から導出する（herdr の場合。Orca は pane 単位で衝突しないため不要）:

   ```sh
   AGENT="impl-$(basename "$PROJECT")"
   BOOT="Read $PROJECT/path/to/task-N-dispatch.md and follow it exactly."   # 絶対パスに置き換える
   ```

   `multiplexer-adapters.md` の `run` の行に従って `codex "$BOOT"` を起動する。**prompt が起動時に確定するので TUI への投入競合が無い**。起動直後にモーダルが出ても prompt はキューされ、モーダルを閉じた時点で自動投入される
5. 起動直後の一度きりの対話ダイアログ（`Do you trust the contents of this directory?` / `Hooks need review` / update 確認）が出たら、adapter の `read(pane_id)` で内容を判定し、`send_text`/`send_keys` で応答する。**trust 系（directory trust・hooks trust）はユーザー承認を得てから**応答する。自動承認しない
6. **bridge armed 確認**: 起動から一定時間（30秒を目安）、以下を数秒おきにポーリングする:

   ```sh
   ~/.agents/skills/agmsg/scripts/delivery.sh status codex "$PROJECT"
   ```

   - `Codex bridge: $TEAM/codex alive (pid ...)` が出たら → 以降このバッチは **push mode**（Redispatch/Await 節を参照）。bridge は Codex スレッドの初回 turn 完了後にのみ arm するため、これは旧版の `agent_status` idle→working/done 判定より強い証跡になっている（受理だけでなく処理完了まで確認済み）。boot prompt の受信確認を別途行う必要はない
   - タイムアウトしても出なければ、fallback mode に切り替える前に **boot prompt の受信確認**を行う（bridge が arm しない = 初回 turn 完了の証跡が無いため、fallback へ切り替える前に「そもそも prompt が届いたか」を別手段で確認する）。adapter ごとに手段が異なる:
     - **herdr**: `agent_status` が `idle` を抜けたかをポーリングする（`agent start` 直後は `idle` を通るため単発チェックでは判定できない）:

       ```sh
       for i in $(seq 1 20); do
         ST=$(herdr agent get "$PANE" | jq -r '.result.agent.agent_status')
         case "$ST" in working|done|blocked) break;; esac
         sleep 3
       done
       echo "status=$ST"
       ```

       - `working` / `done` — 受信確認できた
       - `blocked` — モーダルで入力待ち。Failure Modes の該当行で解消してから受信確認できたものとして扱う
       - `idle` のまま枯渇 — `tail -1 ~/.codex/history.jsonl` の末尾が今の boot prompt かを見る。一致すれば届いており Codex が遅いだけで受信確認できたとみなす。不一致なら届いていない
     - **Orca**: herdr の `agent_status` に相当する検証済みの状態フィールドが無い（`multiplexer-adapters.md` 参照）。代わりに `read(pane_id)`（`orca terminal read --terminal "$PANE" --json` → `result.terminal.tail`）で boot prompt のテキストが composer / 入力欄に未送信のまま残っていないかを確認する。**これはベストエフォートのテキスト検査であり、herdr の `agent_status` のような証明された signal ではない**——テキストが消えていても Codex 側が処理を始めたことの確証にはならない点に注意する。テキストが残っていなければ受信確認できたとみなす
   - 受信確認できたら、以降このバッチは **fallback mode**（TUI 注入 + adapter の `read`/herdr の `agent_status` ポーリングに切り替える）。ユーザーには push mode が使えなかった旨を報告する。受信確認も取れない場合は Dispatch 自体が失敗している可能性があるため、先に進まずユーザーに報告する

## Await

完了条件: Codex の完了通知を受け取り、report の STATUS を読んだこと。モードは Dispatch 節末尾で決まった push mode / fallback mode に従う。

**push mode**:

1. Claude 側の Monitor が Setup 節で有効化済みなので、Codex が dispatch prompt の指示どおり `send.sh` で送る `STATUS: <...>` 付きメッセージは非同期の task-notification として届く。届くまでブロッキングで待つ必要はない——他の作業を進めてよい
2. ただし「打ち切り線の無い待機」は禁止（Red Flags 参照）。通知が `WAIT_BUDGET`（1200秒を目安）内に届かない場合の安全網として、以下を軽くポーリングする:

   ```sh
   ~/.agents/skills/agmsg/scripts/inbox.sh "$TEAM" claude
   # 何も届いていなければ bridge がまだ生きているか確認する
   ~/.agents/skills/agmsg/scripts/delivery.sh status codex "$PROJECT"
   ```

   `inbox.sh` に STATUS 付きメッセージが見つかったら通知を受け取ったのと同じ扱いにする。`delivery.sh status` で bridge が落ちていたら（`not running` に変わっていたら）fallback mode に切り替える
3. 通知または `inbox.sh` で受け取った `STATUS:` 行（DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED）を読む。report file には実装内容の詳細（commit hashes、テスト結果、self-review メモ）が書かれているので、STATUS 受領後に report file を読んで内容を確認する
4. STATUS は SDD の Handling Implementer Status に従って処理する。DONE → SDD どおり review-package → task reviewer subagent

**fallback mode**（現行どおり）:

1. report file の `STATUS:` を第一信号として待つ。補助信号は adapter によって異なる（下記参照）。`WAIT_BUDGET` は打ち切り線:

   ```sh
   REPORT="/abs/path/to/task-N-report.md"   # 実際の絶対パスに置き換える
   WAIT_BUDGET=1200   # 秒
   DEADLINE=$(( $(date +%s) + WAIT_BUDGET ))
   OUTCOME=timeout
   while :; do
     grep -q '^STATUS:' "$REPORT" 2>/dev/null && { OUTCOME=report; break; }
     # <adapter ごとの補助信号チェック。下記 herdr/Orca 参照>
     [ "$(date +%s)" -ge "$DEADLINE" ] && break
     sleep 5
   done
   echo "OUTCOME=$OUTCOME"
   ```

   完了状態に `idle` を含めない。`idle` は初回 prompt を処理する前にも通る状態で、完了と区別できない。turn の完了は integration が `done` として報告する

   - **herdr**: ループのコメント行を以下に差し替えて `agent_status` を補助信号にする:

     ```sh
     ST=$(herdr agent get "$PANE" 2>/dev/null | jq -r '.result.agent.agent_status')
     case "$ST" in done|blocked) OUTCOME="state:$ST"; break;; esac
     ```

   - **Orca**: herdr の `agent_status` に相当する検証済みの状態フィールドが無い（`multiplexer-adapters.md` 参照）。代わりに `read(pane_id)`（`orca terminal read --terminal "$PANE" --json` → `result.terminal.tail`）の出力をループの都度確認し、承認待ちモーダルの文言が残っていないか見る。**これはベストエフォートのテキスト検査であり、herdr の `agent_status` のような証明された signal ではない**——テキストが残っていても実行中モーダルとは限らない点に注意する

2. `OUTCOME=state:blocked`（herdr のみ）なら実行途中の承認要求。Failure Modes に従って解消し、ループに戻る
3. `OUTCOME=report` なら STATUS 行（DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED）を読む
4. `OUTCOME=timeout` なら停止ではなくチェックポイントとして扱う（Failure Modes 参照）
5. STATUS は SDD の Handling Implementer Status に従って処理する

**report file を第一信号にする理由**: `STATUS:` 行は dispatch prompt が Codex に「最後に書け」と指示している本 skill 自身の契約であり、herdr の state machine から独立している。`herdr agent wait` は使わない——`--until` の集合を間違えると無言で永久にブロックし、停止と正常な待機の区別が最も付きにくい形の失敗になる（打ち切り線の無い待機は Red Flags でも禁止）。

### `STATUS:` が信号として使えない場合の代替信号

push mode・fallback mode いずれでも、以下の場面では report file の `STATUS:` を素朴に信じると誤検知する:

- **redispatch 直後**: 前ラウンドの `STATUS: BLOCKED` (等) が report 先頭に残っており、Codex が上書きする前に「report あり」で即抜ける
- **Codex が上書きし忘れる**: dispatch/redispatch のメッセージに「上書きしろ」と書いてあっても、実際には append することがある

このどちらかが疑わしい場面（= 全ての redispatch）では、**Codex の出力に依存しない信号**に切り替える:

- **commit 数** — バッチが期待する commit 数 (`N`) を事前に決めておき、`git rev-list --count $BASE..HEAD >= N` を確認する。fix round の場合は `git rev-list --count $FIX_BASE..HEAD >= 1` で足りる
- **round 見出しの新規追加** — dispatch prompt に「`## Fix round N` 見出しを report に追記しろ」と書き、`grep -q "^## Fix round $N" "$REPORT"` を確認する（この場合は overwrite ではなく append を要求）

commit 数ベースが最も堅牢（Codex の書き方に依存しない）。push mode でも、STATUS 通知を受け取った後にこれらで裏取りしてよい。

## Redispatch

NEEDS_CONTEXT・BLOCKED・レビュー指摘の fix は、生きた Codex に投げ返す（pane を閉じない）。完了条件: 投入を確認し、Await が完了したこと。モードは Dispatch 節末尾で決まった push mode / fallback mode に従う。

1. dispatch file の末尾に `## Redispatch N` 見出しで回答・追加 context・findings を追記する（記録用。fix の内容要件は SDD の fix dispatch に従う）
2. **push mode**: agmsg で送るだけでよい。

   ```sh
   ~/.agents/skills/agmsg/scripts/send.sh "$TEAM" claude codex "<回答/findings。詳細は task-N-dispatch.md の ## Redispatch N を見よ。完了したら report file を上書きして STATUS を送ること>"
   ```

   ビジー中の Codex に送っても実行中のターンを中断せず、完了後に次のターンとして安全にキューされることを実地確認済み。**送信するメッセージ本文に必ず「report file を上書きすること」を再度書く**——dispatch prompt にも同じ規約があるが、redispatch 経由で思い出させないと append されてしまい、次の Await が前ラウンドの STATUS で誤検知する

3. **fallback mode**: 現行どおり multiplexer adapter の `send_text`/`send_keys` で TUI に投入する:

   ```sh
   # herdr の場合
   herdr pane send-text "$PANE" "<回答/findings>"
   sleep 2
   herdr pane send-keys "$PANE" Enter
   # Orca の場合は send_text と send_keys(Enter) を分離して2回送る（multiplexer-adapters.md 参照）
   ```

   `herdr agent prompt` は使わない。`--wait --until working` を付けても、起動直後の一過性の `working` を拾って投入せずに成功を返すことがある（`--help` の "It does not track turns"）。**投入されたことを確認する**（`tail -1 ~/.codex/history.jsonl` の行数が増え、末尾が今の prompt であること）
4. Await を実行する（次節）。fallback mode の場合、report file には前ラウンドの `STATUS:` が既にあり第一信号が誤検知するため、「Await」節末尾の「`STATUS:` が信号として使えない場合の代替信号」を参照して commit 数か round 見出しに切り替える

生きた Codex に投げ返すことで作業中の文脈を保持する。バッチ境界を跨ぐとき（次バッチ）だけ pane を閉じて fresh に開き直す（「Batching Strategy」参照）。バッチ内の fix round では常に同じ pane を live で使う。

## Teardown

2つの異なるライフサイクルに分かれる。pane の寿命と `TEAM`/identity の寿命は一致しない——`TEAM` は plan 実行全体で使い回すため、バッチごとに解体しない。

**Pane Teardown**（タスク/バッチの review が通ったら都度実行）
1. adapter の `close_pane(pane_id)` で対象 pane を閉じる（既に閉じている場合のエラーは想定内として続行）
2. `TEAM`/identity は解体しない。次のバッチも同じ `TEAM` に join したまま新しい pane を作る

**Run Teardown**（plan 実行全体が完了した最後に1回、または run を中断するときに実行）
1. 残っている implementer pane がないか確認し、あれば同様に `close_pane` で閉じる
2. 以下で agmsg の identity を解除する:

   ```sh
   ~/.agents/skills/agmsg/scripts/reset.sh "$PROJECT" codex codex
   ~/.agents/skills/agmsg/scripts/reset.sh "$PROJECT" claude-code claude
   ```

## Failure Modes

| 症状 | 原因 | 一手 |
|---|---|---|
| `agent_status` が `blocked` のまま | Codex がモーダルを表示して入力待ち | `herdr agent read "$PANE" --source visible --lines 40` で種類を判定。`Do you trust the contents of this directory?` はユーザー承認を得て `send-keys Enter`、`⚠ N hooks need review` は承認を得て `send-keys t` → `escape`。どちらも承認は永続。閉じれば argv の prompt が自動投入されるので投入し直さない |
| `agent read` が空文字列 | default の `--source recent` はモーダル表示中に空を返す | `--source visible` を付け直す。空を「画面が読めない」と解釈しない |
| `agent start` が `agent_pane_busy` | split 直後の pane の shell がまだ idle 判定されていない | 数秒おいてリトライする（`multiplexer-adapters.md` の herdr `run` 行のリトライロジック参照） |
| `agent start` が `agent_name_taken` | 同名 agent が herdr server 全体に既存 | 待っても解消しない。error message が保持側の `pane_id` と `cwd` を示すので、前 run の残骸なら閉じ、並行 run なら `AGENT` に suffix を足して 1 度だけやり直す |
| Await が `WAIT_BUDGET` 超過 | 停止とは限らない | `git log` / `git status` / report file で実際の到達点を確かめ、ユーザーに報告して指示を待つ。**pane を作り直さない**——作業は完了・commit 済みのことがある |
| Redispatch 後の Await が即完了 | report file に前ラウンドの `STATUS:` が残っている | 第一信号を Codex 出力に依存しないものに切り替える（Await 節末尾「`STATUS:` が信号として使えない場合の代替信号」参照）。最堅牢は commit 数。round 見出しでも可 |
| 想定 commit 数が積まれない | Codex が (a) 依存不足で BLOCKED、(b) plan の裁定待ち、(c) モーダル入力待ち | `git log`, `git status`, report file, `herdr agent read --source visible` で到達点を確認。install / package add で回避を Codex に指示しない（環境不備は controller の裁定事項）— plan の validation 手段そのものを差し替える |
| herdr がエラーを返すのに jq が空を返す | herdr 停止 / protocol mismatch | ループは必ず上限で打ち切り、生出力をユーザーに見せる。`until` で無限に回さない |
| `join.sh`/`whoami.sh` で登録した project が、渡した path と違う path で登録される（`delivery.sh status` がその path では "no identities registered" や `mode: off` を返す） | agmsg の `agmsg_resolve_project` が、git worktree の cwd を「既に登録済みの git-common メインリポジトリ」へ自動的に解決する（`join.sh`/`whoami.sh` はこの解決を経由するが `delivery.sh` は経由しない — path 解決の非対称性） | `whoami.sh "$PROJECT" codex`（または `claude-code`）の出力の `project=` フィールドで実際に登録された path を確認し、以降の `delivery.sh` 呼び出しはその path に対して行う。この非対称性は agmsg 側の既知の挙動であり、Setup/Dispatch の手順自体は変更不要（idempotent に再実行すれば正しい path で解決される） |
| bridge が `WAIT_BUDGET` 内に arm しない | Codex CLI バージョン非互換、agmsg app-server 起動失敗等（BETA機能） | fallback mode に切り替えて続行する。ユーザーには push mode が使えなかった旨を報告する |
| 同一 `PROJECT` で2つの生きた Codex pane が同時に存在する | agmsg の identity 衝突で bridge/thread が競合し、片方の bridge しか arm されない | 現行設計では 1 pane = 1 バッチが前提のため通常発生しない。並行バッチを将来サポートする場合は別途設計が必要 |
| `.codex/hooks.json` が git 管理下に出現する | `delivery.sh set monitor` の副作用でプロジェクトの working tree に書き出される | `.git/info/exclude` に `/.codex/hooks.json` を追加する（Setup 実行時に未対応なら確認する） |
| Orca で `send_text`+`send_keys` を同時送信すると `agent_prompt_blocked` になる | Orca 側のエージェント自動化ガード（詳細な発火条件は未解明） | text と enter を分離して2回に分けて送る（`multiplexer-adapters.md` 参照） |

## Red Flags

SDD の Red Flags に加えて、以下をしてはならない。

- 使える multiplexer が無い状態で実行する（pane を作る元 pane が無い）
- agmsg 未導入で実行する（push mode が使えず、常に fallback mode に落ちる）
- `herdr agent start` の出力を捨てる（起動失敗に気づけない）
- 完了検知を `agent_status` だけに頼る（初回 dispatch は `STATUS:`、redispatch は commit 数か round 見出し。Await 節参照）
- 打ち切り線の無い待機に入る（ハングと正常な待機が区別できず、復旧手順が発火しない）
- バッチ境界を跨いで同じ pane を使い回す（fresh-per-batch を壊す。バッチ完了で close し次バッチは新 pane。「Batching Strategy」参照）
- タスク途中の質問・fix で pane を閉じる（作業中の文脈を捨てる。Redispatch で生きた Codex に投げる）
- redispatch 時に「report を上書きしろ」の再念押しを省く（毎回入れる。stale STATUS 誤検知が確実に起きる）
- 実行依存の validation を dispatch 前に潰さない（Dispatch 節冒頭「Dispatch 前チェック」参照）
- 環境不備（bundle 未導入・cred 未設定等）を Codex に install / setup で埋めさせる（依存を追加するかは controller の裁定事項）
- Teardown を飛ばして run を終える（Codex pane が残る）
