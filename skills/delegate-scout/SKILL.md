---
name: delegate-scout
description: Hand broad exploration to a scout subagent so its reading never enters this context. Use when a question spans more than about five files.
---
# Delegate to scout

1. Call the `subagent` tool with the `scout` agent. Give it one question per call, plus the directories to search.
2. End every task with: *"Answer in at most 150 words: the key files with file:line, how they connect, and open questions. No code dumps."*
3. Run at most 2 scouts at once.
4. Trust the summary. Open only the 1–3 `file:line` refs you're about to edit, using `lean-read`.
