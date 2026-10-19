---
name: batch-tools
description: 3つ以上の検索やコマンドを1つの codemode スクリプトにまとめ、短い要約だけを返す。
---
# ツールのまとめ実行

read、検索、bash を何度も呼ぶことになるが、生の出力はざっと見るだけでよい場合に使う。

1. このセッションでまだツールの戻り値の形を確認していなければ、先に `describeTool("<name>")` を呼ぶ。
2. `codemode` スクリプトを**1つだけ**書く。独立した呼び出しは `Promise.allSettled` でまとめて実行する。
3. **スクリプト内で絞り込む。** 件数、一致した行、`file:line` 参照、先頭の数行を返す。生のダンプは返さない。返すテキストは約1500トークン未満に収める。
4. 失敗した呼び出しは1行で報告し、他の結果は残す。

形:
```js
const targets = ["src/a.ts", "src/b.ts", "src/c.ts"];
const results = await Promise.allSettled(
  targets.map((f) => tools.bash({ command: `rg -n "^export " ${f} | head -n 15` })),
);
// 各結果を数行に変換し、その要約だけを返す。
```
