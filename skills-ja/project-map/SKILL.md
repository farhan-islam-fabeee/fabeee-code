---
name: project-map
description: 今後のセッションが再探索しなくて済むよう、短いコードベースマップ .pi/MAP.md を作成・更新する。ファイルがないときや構成が変わったときに使う。
---
# プロジェクトマップ

`.pi/MAP.md` を**60行以内**、コードなしで書く:

```markdown
# <project>: <one-line purpose>
## Commands
build / test (single file) / lint / typecheck / run
## Layout
<dir>/: <one-line responsibility>
## Entry points
<file>: <what starts here>
## Key modules
<file>: <responsibility>
## Conventions
naming, error handling, test location, formatting
## Gotchas
things that broke before, non-obvious constraints
```

- 作成には `lean-read` を使う。大きなリポジトリでは `delegate-scout` を使う。
- ファイルはその場で更新する。60行を超えたら、行を足すのではなく古くなった行を消す。
- コマンドは package.json、Makefile、pyproject、AGENTS.md から読み取る。推測しない。
