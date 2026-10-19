---
name: docs-lookup
description: 推測せず、ローカルのドキュメント（Context MCP）で最新のライブラリ API を調べる。不慣れな API やバージョン依存の API に対してコードを書く前に使う。
---
# ドキュメント参照

1. **まずメモを確認する。** `.pi/notes/<library>.md` があり、バージョンが一致していればそれを使って終了する。
2. **インストール済みのバージョンを調べる**（`npm ls <pkg> --depth=0`、`pip show <pkg>`、またはマニフェスト）。ロックファイルは読まない。
3. **ローカルのドキュメントを調べる。** `mcp__context__get_docs` にライブラリとトピックを1つ渡す。トピックはすべて一致が必要なキーワードなので短くする（例: `middleware`、`useQuery options`）。
4. **まだローカルにない場合:** `mcp__context__search_packages` のあと、該当バージョンを `mcp__context__download_package` で取得する。ダウンロードは1回だけで、以降の検索はローカルで行う。
5. **レジストリになく、公開 GitHub リポジトリの場合:** `deepwiki` サーバーが設定されていれば、`tool_search` でそのツールを見つけ、狭い質問を1つする。
6. **頼りにする内容を保存する。** `.pi/notes/<library>.md` に30行以内で書き、1行目にバージョンを記す。
