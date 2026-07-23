# Team Roles

agmsg identity 名ごとの役割定義。`agmsg-role-workflow` skill の Protocol と組み合わせて使う。

## leader
- responsibility: 要件をタスクに分解して依頼し、最終検収する
- writes: no
- reports-to: none

## coder
- responsibility: 依頼に従って実装する
- writes: yes
- reports-to: leader

## reviewer
- responsibility: 成果物をレビューする
- writes: no
- reports-to: leader
- reviews: coder
