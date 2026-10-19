---
name: handoff
description: 情報が失われやすい圧縮の代わりに新しいセッションで作業を続けられるよう、タスクの状態を .pi/handoff.md に保存する。コンテキストが埋まってきたときやサブタスクが終わったときに使う。
---
# 引き継ぎ

`.pi/handoff.md` を**40行以内**で書く:

```markdown
## Goal
## Done            (with file paths)
## Decisions       (and why; include constraints from the user)
## Next steps      (ordered and concrete)
## Key refs        (file:line, exact commands, failing test names)
## Dead ends       (what was tried and why it failed, so nobody redoes it)
```

そのあと、ユーザーに1行で伝える: *「引き継ぎを保存しました。新しいセッション(`/new`)を開始し、`/skill:resume` を実行してください。」*

ユーザーがこのセッションに留まりたい場合は、代わりに次を提案する:
`/compact Keep: goal, decisions, next steps, file:line refs. Drop: tool output, file contents, resolved errors.`
