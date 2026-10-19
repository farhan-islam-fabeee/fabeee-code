---
name: quiet-shell
description: シェルコマンドを出力が短くなるように実行する。ビルド、テスト、インストール、git、ログのコマンドすべてで使う。
---
# 静かなシェル

- **静音フラグ:** `npm i --silent`、`pip install -q`、`cargo build -q`、`pytest -q --no-header -rf`、`go test ./pkg/...`。JS のテストランナーでは dot 形式かサマリー形式のレポーターを使う。
- **Git:** まず `git status -sb` と `git --no-pager diff --stat`。そのあと必要なファイルだけ `git --no-pager diff -U1 -- <file>` を実行する。履歴は `git log --oneline -n 10`。
- **長い出力・量が読めない出力:** ファイルに書き出し、必要な部分だけを見る。
  ```bash
  cmd > "${TMPDIR:-/tmp}/pi-out.log" 2>&1; echo "exit $?"
  tail -n 30 "${TMPDIR:-/tmp}/pi-out.log"
  rg -n "error|FAIL|panic|Traceback" "${TMPDIR:-/tmp}/pi-out.log" | head -n 20
  ```
- **範囲を絞る:** テスト、リンター、型チェックは、触ったファイルやパッケージに限定する。フルスイートは頼まれたときだけ実行する。
- **禁止:** `ls -R`、`find /`、`-L 2` なしの `tree`、大きなファイルへの `cat`。代わりに `fd --max-depth 2` を使う。
- 結果の末尾に生出力の保存先パス(token-killer の tee ファイル)があれば、必要な部分だけをそこから読む。
