---
name: lean-read
description: 最小限のトークンでコードを探して読む。未読のファイルを開く前や、コードベースを検索するときに使う。
---
# 省トークン読み込み

目的: ファイル全体ではなく、必要な行だけを取得する。

1. **まずマップを見る。** `.pi/MAP.md` があれば、ツリーを探索する前に読む。
2. **読む前に場所を特定する。**
   - 概念で検索: `mcp__probe__search_code` を `maxTokens: 3000`、`maxResults: 5` で使う。広いクエリでは先に `filesOnly: true` で実行する。同じブロックが二度返らないよう、タスクごとに同じ `session` id を使い回す。
   - 正確な名前: `rg -n --max-count 5 'name' <dir>`。ファイル検索: `fd -e ts <pattern> --max-depth 4`。
   - 構造パターン: `mcp__probe__query_code`(ast-grep 構文)または pi-lens のシンボル検索。
3. **狭く読む。** `mcp__probe__extract_code` に `file:line` を渡すか、`read` で `offset`/`limit` を指定する(最大150行)。ファイル全体を読むのは、約200行未満のときか、大部分を書き換える直前だけ。
4. **読み直さない。** コンテキストにあるファイルは、変更がない限り読み直さない。自分の編集内容はすでに把握している。
5. **読まないもの:** ロックファイル、`dist/`、`build/`、`node_modules/`、minify 済み・自動生成ファイル、スナップショット、バイナリ・データファイル。中身を覗くときは `wc -l`、`head -n 20`、`jq 'keys'` を使う。
