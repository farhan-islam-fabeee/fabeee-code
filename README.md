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
context/AGENTS.md           プロジェクトの AGENTS.md に追加するエージェントルール: コメント・ドキュメント・応答は日本語、内部作業は簡潔な英語
skills-ja/                  スキルの日本語訳（参照用。モデルによってトークンが 13〜71% 増えます。docs/research.md を参照）
config/models.local.json    oMLX プロバイダー: コンテキストウィンドウをサーバーに合わせ、思考レベルごとにサンプリングを設定
config/settings.json        pi の設定: 思考レベル低め、codemode、32k 向けの圧縮設定
config/mcp.json             Probe（ローカルのコード検索）と Context7（ドキュメント）
config/models.cloud.example.json  OpenAI 互換クラウドプロバイダー用のテンプレート
extensions/quality-gate.ts  エージェントの作業終了時にプロジェクトの高速チェックを実行し、失敗を差し戻す
extensions/skills-global.ts pi の /skills-global コマンド: 選んだプロジェクトのスキルを ~/.agents/skills にコピー
extensions/agents-md-only.ts pi が AGENTS.md だけを読むようにする（CLAUDE.md をコンテキストから除外）
extensions/project-models.ts プロジェクトの .pi/models.json のプロバイダーを登録（pi は models.json をグローバルにしか読まないため）
scripts/setup.sh            対話式セットアップ（プロジェクトフォルダーで実行）: pi の設定一式をプロジェクトに書き込む
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

最初に表示言語（English、日本語、한국어、বাংলা）を尋ねます。既定値はシステムのロケールで決まり、`--lang=ja`（または `FABEEE_CODE_LANG=ja`）を指定すると質問を省略できます。

**設定はすべてプロジェクトに書き込みます。** 一度コミットすれば、チーム全員が同じセットアップを使えます。`~/.pi/agent` には、各マシンで pi 自体が必要とするもの以外は書き込みません。

| プロジェクトに置くもの（コミットする） | 個人ごと（コミットしない） |
|---|---|
| `.pi/models.json`: モデルのプロバイダー。`.pi/extensions/project-models.ts` が読み込みます | API キー: macOS キーチェーン、環境変数、または pi の `/login`。`.pi/models.json` には `${VAR}` や `!security …` のような参照だけを書きます |
| `.pi/settings.json`: デフォルトのモデル、思考レベル、codemode、圧縮、パッケージ | pi 本体 |
| `.pi/mcp.json`: Probe と Context7 | `probe` コマンド |
| `.pi/extensions/`: 品質ゲート、`/skills-global`、AGENTS.md 専用化、プロバイダー読み込み | `.pi/npm/`（ダウンロードしたパッケージ）と `.pi/handoff.md`。どちらも `.gitignore` に追加します |
| `.agents/skills/`、`AGENTS.md`、`.pi/check` | |

pi はプロジェクトを信頼したあとでのみ `.pi/` を読み込みます。初回起動時の信頼確認には「はい」と答えてください。

すでにセットアップ済みのプロジェクト（チームメンバーがコミットした場合など）では、**「これを使う」**を選べます。プロジェクトには手を加えず、このマシンだけを準備します（pi、自分の API キー、`probe`）。プロジェクトのパッケージは pi の初回起動時にインストールされます。

それ以外の場合は 7 つのステップを順に進め、変更の前には毎回確認します。

1. **プロジェクト:** 対象フォルダーを確認します。
2. **pi:** pi がなければインストールし（公式インストーラーまたは npm）、シェルから見つかるようにして、バージョンを確認します。
3. **モデル:** ローカル、クラウド、または両方を選び、`.pi/models.json` に保存します。
   - **ローカル:** oMLX、Ollama、LM Studio、llama.cpp ルーター、または任意の OpenAI 互換サーバー。サーバーのモデル一覧から選べます。コンテキストウィンドウは、サーバーが*実際に*扱える値を尋ねます（oMLX の場合は `~/.omlx/settings.json` から読み取ります）。
   - **クラウド:** OpenRouter、DeepSeek、Z.ai、Moonshot、pi に組み込まれたその他のプロバイダー、または料金とキャッシュ保持時間を指定したカスタムの OpenAI 互換エンドポイント。
   - **API キー:** macOS キーチェーン（pi がリクエストごとに `security` で読み取ります）、環境変数、または pi の `/login`。ファイルを共有するため、平文で保存する選択肢はありません。
4. **設定:** `.pi/settings.json`（思考レベルは低め、codemode、ローカルのウィンドウに合わせた圧縮）を、プロジェクトのデフォルトのモデルと一緒に書き込みます。
5. **キット:** スキルを `.agents/skills/` に、`/skills-global` コマンドと品質ゲートを、MCP サーバーの Probe と Context7 を `.pi/mcp.json` にインストールします。
6. **パッケージ:** パッケージ群ごとに確認し、`pi install -l` でインストールします（`.pi/settings.json` に記録されます）。パッケージはコードを実行するため、それぞれ事前に確認します。
7. **プロジェクトファイル:** git、`.pi/check`（package.json、Cargo、Go、Python から自動検出）、ひな形の `AGENTS.md`（なければ）、`AGENTS.md` へのエージェントルールのセクション（再実行時はそのセクションだけを置き換え、ほかの内容はそのまま）、`.gitignore` を用意します。pi は `AGENTS.md` だけを読みます。インストールされる拡張機能が `CLAUDE.md` をコンテキストから除外します。`CLAUDE.md` がある場合は警告しますが、ファイル自体は変更しません。

変更する設定ファイルは、事前にすべてバックアップします（`<file>.backup-<timestamp>`）。何度実行しても安全です。`--dry-run` を付けると、同じ質問をしたうえで何も書き込みません。

手動で個別にインストールする場合は、`./scripts/install.sh all <project>` でスキル、ルール、拡張機能、MCP 設定をそのプロジェクトに、`./scripts/install.sh packages <tier> <project>` でパッケージ群を 1 つ（`core`、`tokens`、`ondemand`、`tuning`、`cloud`、`ab`）インストールします。[config/models.local.json](config/models.local.json) と [config/settings.json](config/settings.json) は、プロジェクトの `.pi/` にコピーして使える例です（gameplan の Phase 0〜1）。

## スキル

スキルはプロジェクトごとに `.agents/skills/` へインストールします。すべてのプロジェクトで使いたいスキルは、pi で `/skills-global` を実行して選ぶと（すべて選ぶことも可能）、`~/.agents/skills/` にコピーされます。`/skills-global handoff resume` のように名前を指定して直接コピーすることもできます。

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
