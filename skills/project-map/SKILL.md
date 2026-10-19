---
name: project-map
description: Create or update .pi/MAP.md, a short codebase map that saves future sessions from re-exploring. Use when it's missing or the structure changed.
---
# Project map

Write `.pi/MAP.md` in **60 lines or fewer**, with no code:

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

- Build it with `lean-read`. Use `delegate-scout` for large repos.
- Update the file in place. When it grows past 60 lines, delete stale lines rather than adding more.
- Read commands from package.json, Makefile, pyproject and AGENTS.md. Don't guess them.
