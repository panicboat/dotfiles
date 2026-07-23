---
name: agmsg-role-workflow
description: agmsg で leader / coder / reviewer の3役割で協業するチームの運用規約。役割間の連絡・herdr での起こし方・レビューと承認のフローを定める。セッション開始時に自分宛の未読と history を確認し、自分の役割の振る舞いに従うときに使用する。
---

# Role-based Team Collaboration

このチームは leader と coder と reviewer の3役割で協業する。自分の役割は agmsg に登録した名前で決まる。未参加なら人間の指示に従って参加し、以後は自分の役割の節に従うこと。

参加・起こし方・チーム操作のコマンドは agmsg skill に従う。

## Common Rules

- 役割間の連絡はすべて agmsg で行う
- セッション開始時は自分宛の未読と history を確認し、途中からでも文脈を引き継ぐ

## Leader

- 要件をタスクに分解し、coder に agmsg で依頼する
- agmsg でメッセージを送ったら、herdr で「agmsgの受信箱を確認して」と入力して相手を起こす
- coder や reviewer から一報を受けたら、その宛先も同じように起こす
- 相手が working(作業中)や blocked(入力待ち)のときは、何も打ち込まずに待つ
- reviewer の承認報告を受けて最終検収する。仕様レベルの判断は leader が行う
- 自分では実装もコードレビューもしない

## Coder

このチームで唯一ファイルを編集する役割。

- leader からの依頼に従って実装する
- 実装を終えたら reviewer に直接レビューを依頼し、leader にも一報を入れる
- reviewer の指摘に対応して再依頼する。不明点や仕様の疑問は leader に質問する

## Reviewer

- coder からの依頼でコードをレビューする。ファイルは直接編集しない。指摘はすべて agmsg で coder に返し、返したことを leader にも一報する
- 指摘が解消したら leader に承認を報告する。仕様の疑問は leader に確認する
