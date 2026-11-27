---
name: issue-status-report
description: Use when asked to summarize, report, or post the current status or progress of a GitHub Issue as a comment — e.g. 「Issue に現状をまとめて」「進捗を Issue に書いて」「全体像と現在地」「次に何をすればいいか」「何が残っているか」 — especially for multi-PR or multi-environment rollouts tracked in one Issue.
---

# Issue Status Report

Issue を読んだ人が「全体像と現在地」「次にやること」「残っていること」を 1 回で把握できるコメントを作り、承認を得てから投稿する。

## Workflow

完了条件: ユーザーが承認した本文が対象の Issue にコメントとして投稿され、それより前のレポートがすべて `OUTDATED` として隠されていること。

1. Issue の本文と全コメントを読む: `gh issue view <N> -R <owner/repo> --json title,body,comments`
2. 関連 PR を洗い出す。
   - 本文・コメント中の PR の URL と `<owner/repo>#<N>` 表記
   - Issue を参照した PR: `gh api repos/<owner>/<repo>/issues/<N>/timeline --paginate --jq '.[] | select(.event=="cross-referenced") | .source.issue | select(.pull_request) | .html_url'`
3. 段階を決める。設計・spec のコメントに Rollout や手順があればその順に、なければ Issue 本文の「進め方」の順に並べる。マージ後の適用・確認・後片付け（旧設定の削除など）も段階として数える。
4. 各 PR の状態を取る: `gh pr view <N> -R <owner/repo> --json state,isDraft,mergedAt,reviewDecision,statusCheckRollup,title`
5. 実環境の状態（クラスタ・クラウド・監視）を確かめられる手段があれば確かめる。確かめられなかったものは「未確認」として本文に書く。
6. [Output Contract](#output-contract) どおりに下書きを書く。下書きと、手順 11 の 1 つ目のコマンドの出力（隠す過去レポートの URL）をユーザーに見せて承認を得る。
7. 投稿の直前に手順 4 をもう一度実行し、状態が変わっていれば下書きを直す。
8. 下書きに別 owner の Issue・PR の参照がないことを確かめる。出力が `[]` でなければ、該当の参照を下書きから消して、もう一度確かめる。

   ```sh
   python3 -c 'import re,sys; print(sorted({m for m in re.findall(r"(?:github\.com/|\b)([\w.-]+)/[\w.-]+(?:#|/(?:issues|pull)/)\d+", open(sys.argv[2]).read()) if m != sys.argv[1]}))' <owner> <file>
   ```

9. `gh issue comment <N> -R <owner/repo> --body-file <file>` で新しいコメントとして投稿する。
10. 描画された本文に、リンクになっていない参照がないことを確かめる。出力が `[]` なら手順 11 に進み、そうでなければ該当の参照を `owner/repo#番号` に直してコメントを編集し、もう一度確かめる。

   ```sh
   gh api repos/<owner>/<repo>/issues/comments/<comment_id> -H "Accept: application/vnd.github.html+json" --jq .body_html \
     | python3 -c 'import re,sys; h=re.sub(r"<a[^>]*>.*?</a>","",sys.stdin.read()); print(sorted(set(re.findall(r"[\w./-]*#\d+", re.sub(r"<[^>]+>"," ",h)))))'
   ```

11. 過去のレポートを隠す。
    1. 隠れていないレポートの node ID と URL を出す（1 行目が `## 全体像と現在地（` のコメント。投稿者は問わない）。

       ```sh
       gh api graphql --paginate -F owner=<owner> -F repo=<repo> -F number=<N> -f query='
         query($owner: String!, $repo: String!, $number: Int!, $endCursor: String) {
           repository(owner: $owner, name: $repo) { issue(number: $number) {
             comments(first: 100, after: $endCursor) {
               nodes { id url isMinimized body }
               pageInfo { hasNextPage endCursor }
           } } }
         }' --jq '.data.repository.issue.comments.nodes[] | select(.isMinimized | not) | select(.body | startswith("## 全体像と現在地（")) | [.id, .url] | @tsv'
       ```

    2. 手順 9 で投稿したコメント以外の行ごとに、node ID を `OUTDATED` として隠す。

       ```sh
       gh api graphql -F id=<node_id> -f query='mutation($id: ID!) { minimizeComment(input: {subjectId: $id, classifier: OUTDATED}) { minimizedComment { isMinimized } } }'
       ```

    3. 1 をもう一度実行する。出力が手順 9 で投稿したコメントの 1 行だけなら完了として URL を報告する。2 でエラーになったコメントが残っていれば、その URL とエラーを報告に書く。

## Output Contract

本文は次の雛形の節をこの順に持ち、1 行目は `## 全体像と現在地（YYYY年M月D日（曜）HH:MM JST 時点）` にする。見出しは雛形のまま使う（この skill に限り日本語）。本文は 1 文ごとに改行する。
Issue・PR の参照は、毎回 `owner/repo#番号` の完全な形で書く。同じリポジトリの参照が続いても省略せず、範囲（〜）でもまとめない。省略形の `#番号` は、コメントを書く Issue と同じリポジトリの Issue・PR にだけ使う（GitHub は `#番号` をコメントのあるリポジトリの番号として解釈する）。

```markdown
## 全体像と現在地（YYYY年M月D日（曜）HH:MM JST 時点）

<現在地を 1〜2 文>
背景と設計は [設計コメント](<URL>) にあります。

| # | 段階 | PR | 状態 |
|---|---|---|---|
| 1 | <段階> | <owner/repo#番号>、<owner/repo#番号> | <状態> |

- 確認したもの: <対象>（<手段>）
- 確認していないもの: <対象>

## 次にやること

1. <何をする>（担当: <名前。分からなければ「未定」>）。<完了条件>で完了とする。

## 残っていること

- <作業>
  - 待っているもの: <PR・作業・判断>

## 決まっていないこと

<決まっていない判断があるときだけこの節を置く>

## 関連

- <関連リンク>
```

各節の書き方は次のとおり。

### `## 全体像と現在地`

1. 時点は見出しの括弧の中だけに書く。
2. 見出しの次の行から、現在地を 1〜2 文で書く（例: 「staging と edge には適用済みで、動作確認が終わっていません。」）。
3. 背景と設計は、設計・spec のコメントへのリンク 1 行にする。
4. 段階の表: `| # | 段階 | PR | 状態 |`
   - PR のセルには、`owner/repo#番号`、`未作成`、`-`（PR を作らない段階）のどれかだけを書く。
   - 状態のセルには、次の値のどれか 1 つだけを書く。前回のレポートのセルに補足があっても引き継がない。

     | 値 | 付ける段階 |
     |---|---|
     | `✅ 完了` | 終わった段階 |
     | `👉 現在地` | 今手を動かすべき段階。並行して進められる段階が複数あれば、それぞれに付ける |
     | `⏳ 進行中` | レビュー中・CI 待ちなど、手を離れて結果を待っている段階 |
     | `⏸️ <段階の番号か owner/repo#番号> の<完了・適用・マージ>待ち` | 前の段階や PR を待っている段階 |
     | `未着手` | 待つものはないが、まだ手を付けていない段階 |

   - 一部だけ終わった段階は、終わった分と残りの分を別の行にし、それぞれに状態の値を付ける。`#` は行ごとに上から通し番号を振る。
   - 「次にやること」の項目が扱う PR の状態（Draft・承認など）や plan の内容は、その項目の下の階層に書く。
5. 表の下に根拠を 2 項目の箇条書きで書く: 確認したもの（対象と手段。`gh pr view`、kubectl、Datadog など）と、確認していないもの。確認していないものがなければ「なし」と書く。

### `## 次にやること`

今すぐ着手できる作業だけを、実行する順に番号付きで並べる。
各項目は「何をする・担当・何で完了とみなすか」を 1 文で書き、補足は下の階層に置く。担当が分からないときは「担当: 未定」と書く。

### `## 残っていること`

「次にやること」より後の作業と、何かを待っている作業を並べる。
各項目の下の階層に、待っているもの（PR のマージ、他チームの作業、判断など）を書く。

### `## 決まっていないこと`

決まっていない判断があるときだけ置く。各項目に、選択肢と判断の基準を下の階層で書く。

### `## 関連`

関連する Issue・PR・お知らせのリンク。段階の表に出したものは繰り返さない。

## Common Mistakes

| 症状 | 直し方 |
|---|---|
| PR の一覧だけで、マージ後の適用・確認・削除が見えない | 手順 3 のとおり、マージ後の作業も段階の表の行にする |
| 今すぐやる作業と、待ちの作業が同じ節にある | 着手できるものは「次にやること」、待っているものは「残っていること」に置く |
| 「本番の設定はまだ変わっていない」など、確かめていない推論を断定している | 「確認していないもの」に書くか、確かめてから書く |
| 背景・問題・方針を設計コメントから書き写している | 設計コメントへのリンク 1 行にする |
| 下書きの後に PR がマージされ、投稿時に古くなっている | 手順 7 で投稿の直前に取り直す |
| 同じリポジトリの PR を `owner/repo#1、#2` や `#1〜#3` と省略し、2 つ目以降がリンクにならない | 1 つずつ `owner/repo#番号` で書く。手順 10 で確かめる |
| 状態・PR のセルに括弧の補足（Draft・承認済み・plan の件数・一部の進み具合）がある | セルは決めた値だけにする。一部だけ終わった段階は行を分け、PR の状態は「次にやること」の下の階層に書く |
| 別 owner の Issue・PR を関連などに書いている | 消す。手順 8 で投稿前に確かめる |
| 過去のレポートが隠れずに並び、どれが最新か分からない | 手順 11 で、投稿したコメント以外のレポートを `OUTDATED` として隠す |
| 時点が日付だけ | 見出しの括弧に時刻（JST）まで書く。同じ日に状況が変わることがある |
