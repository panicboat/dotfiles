---
name: agmsg-role-workflow
description: agmsg で役割ベースに協業するチームの運用プロトコル。連絡と herdr での起こし方・書き換え担当の限定・レビューと承認の流れを、役割名や役割構成によらず定める。あわせて自分の役割定義の引き方を示す。agmsg で自分に名前(役割)が割り当てられたチームで作業し、その役割に従って動くときに使用する。
---

# Role-based Team Collaboration

自分の役割は agmsg に登録した名前(identity)で決まる。参加・起こし方・チーム操作は agmsg skill に従う。agmsg が持つのは名前だけなので、役割の意味はチーム側の定義から引く。

## Resolving your role

1. 自分の agmsg identity 名を確認する(`actas` 中ならその名前)
2. チームの役割定義を読み、自分の名前に一致する役割を採用する。定義の置き場所はチームで決める(例: `.claude/team-roles.md`)。team は複数プロジェクトにまたがりうるので、全メンバーが読める単一の場所を参照先にする
3. 一致する定義がなければ、人間に確認してから作業を始める

## Role definition schema

チームは各役割を次のフィールドで定義する。

- `name`: agmsg の identity 名
- `responsibility`: 責任範囲
- `writes`: 成果物を書き換えるか(yes / no)
- `reports-to`: 判断を仰ぐ先の役割。最上位は `none`(= requirements owner)
- `reviews`: (任意) レビュー対象の役割名。レビュー役だけが持つ

## Protocol

役割構成によらず全員が従う。ここでは役割名ではなく上記フィールドで相手を指す。

- 連絡はすべて agmsg で行う。相手にメッセージを送ったら、「agmsgの受信箱を確認して」と入力して起こす。相手が working(作業中)や blocked(入力待ち)のときは、何も打ち込まずに待つ
- ハンドオフ(依頼・完了報告・承認報告など宛先が切り替わる連絡)は、直接の宛先に加えて requirements owner(`reports-to: none` の役割)にも一報する
- 成果物を書き換えるのは `writes: yes` の役割だけ。複数いるときは担当範囲を分け、書き込みが重ならないようにする。`writes: no` の役割は agmsg でフィードバックを返すにとどめる
- `writes: yes` の役割は、変更を終えたら `reviews` に自分を指定している役割にレビューを依頼する
- `reviews` を持つ役割は、指摘をすべて agmsg で対象の writer に返す。writer は指摘に対応して再依頼し、レビュー役が指摘なし(承認)とするまで繰り返す。承認判断はレビュー役が行う
- 承認後、requirements owner が最終検収し、仕様レベルの判断を行う。仕様・要件の疑問は各役割の `reports-to`(最終的に requirements owner)へエスカレーションする
