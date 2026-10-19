---
name: handoff
description: Save task state to .pi/handoff.md so work continues in a fresh session instead of a lossy compaction. Use when context is getting full or a subtask is done.
---
# Handoff

Write `.pi/handoff.md` in **40 lines or fewer**:

```markdown
## Goal
## Done            (with file paths)
## Decisions       (and why; include constraints from the user)
## Next steps      (ordered and concrete)
## Key refs        (file:line, exact commands, failing test names)
## Dead ends       (what was tried and why it failed, so nobody redoes it)
```

Then tell the user in one line, in your reply language, that the handoff is saved and they should start a new session (`/new`) and run `/skill:resume`.

If the user would rather stay in this session, suggest this instead:
`/compact Keep: goal, decisions, next steps, file:line refs. Drop: tool output, file contents, resolved errors.`
