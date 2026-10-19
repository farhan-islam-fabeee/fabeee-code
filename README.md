[English](README.en.md) | **日本語**

# fabeee-code

コーディングエージェント [pi](https://pi.dev) を**ローカルモデル**（Apple Silicon 上の oMLX）で動かすためのセットアップキットです。必要に応じて**クラウド**（OpenRouter や任意の OpenAI 互換 API）も使えます。**最小限のトークンでコードの品質を上げる**ことを目指して調整しています。トークンのコストは、ローカルでは時間、クラウドでは料金です。

pi 1.2.0、M5 Pro（24 GB）、`Qwen3.8-27B-4bit` を動かす oMLX の環境で調整しました。モデル ID、コンテキストサイズ、メモリの数値はお使いのマシンに合わせて変更してください。

## 構成

```
bootstrap.sh                1 行インストールの入口: キットを ~/.fabeee-code に取得・更新し、現在のフォルダーで setup.sh を実行
docs/gameplan.md            計画の全体: Phase 0〜7、各判断の理由、導入チェックリスト
docs/research.md            パッケージと MCP の調査結果（採用・A/B テスト・不採用）、キャッシュ料金、未検証の点
skills/                     トークンと圧縮を節約する 8 つのスキル（Agent Skills 形式）
context/AGENTS.md           スキルと一緒にインストールするグローバルルール: コメント・ドキュメント・応答は日本語、内部作業は簡潔な英語
skills-ja/                  スキルの日本語訳（参照用。モデルによってトークンが 13〜71% 増えます。docs/research.md を参照）
config/models.local.json    oMLX プロバイダー: コンテキストウィンドウをサーバーに合わせ、思考レベルごとにサンプリングを設定
config/settings.json        pi の設定: 思考レベル低め、codemode、32k 向けの圧縮設定
config/mcp.json             Probe（ローカルのコード検索）と Context7（ドキュメント）
config/models.cloud.example.json  OpenAI 互換クラウドプロバイダー用のテンプレート
extensions/quality-gate.ts  エージェントの作業終了時にプロジェクトの高速チェックを実行し、失敗を差し戻す
scripts/setup.sh            対話式セットアップ（プロジェクトフォルダーで実行）: pi のインストール、ローカル/クラウドの設定、キットの導入、プロジェクトの準備
scripts/lib/pi-config.mjs   setup.sh が使う JSON/プロジェクト用ヘルパー（変更するファイルはすべてバックアップ）
scripts/lib/i18n.sh         メッセージの読み込み。カタログは scripts/lib/lang/{en,ja,ko,bn}.txt
scripts/lib/check-i18n.mjs  カタログのキーとプレースホルダーが揃っているかを確認（メッセージ編集後に実行）
scripts/install.sh          スキル、拡張機能、MCP 設定、パッケージ群をインストール
scripts/count_tokens.py     skills/ と skills-ja/ のトークン数を複数のトークナイザーで比較（HF tokenizer.json、OpenAI o200k、Kimi）
```

## クイックスタート

作業したいプロジェクトのフォルダーで、次の 1 行を実行します。

```bash
curl -fsSL https://raw.githubusercontent.com/farhan-islam-fabeee/fabeee-code/main/bootstrap.sh | bash
```

キットを `~/.fabeee-code` にダウンロードし（2 回目以降は更新）、現在のフォルダーで対話式セットアップを開始します。セットアップのオプションは `bash -s --` のあとに付けます。例: `curl -fsSL … | bash -s -- --lang=ja --dry-run`。`FABEEE_CODE_HOME` でキットの保存先を、`FABEEE_CODE_REF` でブランチやタグを指定できます。

実行前にスクリプトの中身を確認したい場合:

```bash
curl -fsSL https://raw.githubusercontent.com/farhan-islam-fabeee/fabeee-code/main/bootstrap.sh -o bootstrap.sh
```

```bash
less bootstrap.sh && bash bootstrap.sh
```

リポジトリをクローン済みなら、プロジェクトのフォルダーから `scripts/setup.sh` を直接実行することもできます。

最初に表示言語（English、日本語、한국어、বাংলা）を尋ねます。既定値はシステムのロケールで決まり、`--lang=ja`（または `FABEEE_CODE_LANG=ja`）を指定すると質問を省略できます。そのあと 7 つのステップを順に進め、変更の前には毎回確認します。

1. **プロジェクト:** 対象フォルダーを確認します。
2. **pi:** pi がなければインストールし（公式インストーラーまたは npm）、バージョンを確認します。
3. **モデル:** ローカル、クラウド、または両方を選びます。
   - **ローカル:** oMLX、Ollama、LM Studio、llama.cpp ルーター、または任意の OpenAI 互換サーバー。サーバーのモデル一覧から選べます。コンテキストウィンドウは、サーバーが*実際に*扱える値を尋ねます（oMLX の場合は `~/.omlx/settings.json` から読み取ります）。
   - **クラウド:** OpenRouter、DeepSeek、Z.ai、Moonshot、pi に組み込まれたその他のプロバイダー、または料金とキャッシュ保持時間を指定したカスタムの OpenAI 互換エンドポイント。
   - **API キー:** macOS キーチェーン（pi がリクエストごとに `security` で読み取ります）、環境変数、pi の `/login`、ローカルサーバーの場合のみ平文、から保存先を選べます。
4. **設定:** pi の設定（思考レベルは低め、codemode、ローカルのウィンドウに合わせた圧縮）を書き込み、デフォルトのモデル（全体またはこのプロジェクトのみ）を設定します。シェルのエイリアス `pil`/`pic` も追加できます。
5. **キット:** スキル、グローバルの `AGENTS.md`、品質ゲート、MCP サーバーの Probe と Context7 をインストールします。
6. **パッケージ:** パッケージ群ごとに確認しながらインストールします。パッケージはコードを実行するため、それぞれ事前に確認します。
7. **プロジェクトファイル:** git、`.pi/check`（package.json、Cargo、Go、Python から自動検出）、ひな形の `AGENTS.md`、`.gitignore` を用意します。

変更する pi の設定ファイルは、事前にすべてバックアップします（`<file>.backup-<timestamp>`）。何度実行しても安全です。`--dry-run` を付けると、同じ質問をしたうえで何も書き込みません。

手動で個別にインストールする場合は、`./scripts/install.sh all` でスキル、`AGENTS.md`、拡張機能、MCP 設定を、`./scripts/install.sh packages <tier>` でパッケージ群を 1 つ（`core`、`tokens`、`ondemand`、`tuning`、`cloud`、`ab`）インストールします。[config/models.local.json](config/models.local.json) と [config/settings.json](config/settings.json) は、ご自身で `~/.pi/agent/` に統合してください（gameplan の Phase 0〜1）。

## スキル

| スキル | トークンを節約する方法 |
|---|---|
| [lean-read](skills/lean-read/SKILL.md) | 読む前に検索する（Probe、`rg`、`fd`）。必要な行範囲だけを読み、同じファイルを読み直さない |
| [quiet-shell](skills/quiet-shell/SKILL.md) | 静音フラグを使い、差分全体の前に `--stat` を見る。長い出力はファイルに書き出してから絞り込む |
| [batch-tools](skills/batch-tools/SKILL.md) | 3 つ以上の検索を 1 つの codemode スクリプトにまとめ、短い要約だけを返す |
| [delegate-scout](skills/delegate-scout/SKILL.md) | 広い探索を `scout` サブエージェントに任せ、150 語以内で答えさせる |
| [project-map](skills/project-map/SKILL.md) | 60 行以内の `.pi/MAP.md` を保ち、新しいセッションで再探索しなくて済むようにする |
| [handoff](skills/handoff/SKILL.md) | 状態を `.pi/handoff.md` に保存し、圧縮の代わりに新しいセッションで続ける |
| [resume](skills/resume/SKILL.md) | 引き継ぎファイルとマップからセッションを再開する（`/skill:resume`） |
| [docs-lookup](skills/docs-lookup/SKILL.md) | Context7 に狭く問い合わせ、答えを `.pi/notes/` に保存して使い回す |

## 現状

`scripts/setup.sh` は、使い捨てのフォルダーとモックのモデルサーバーを使って、4 言語すべてで通しのテストを済ませています。スキルと品質ゲートはまだ pi の中で動かしていません。設定の細かい点にも、pi のスキーマとの照合が必要なものが残っています。未検証の点は [docs/research.md](docs/research.md) の「Not verified」にまとめています。

ドキュメント（`docs/` 以下）は現在英語のみです。
