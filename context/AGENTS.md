# Global agent rules

## Language
- **Write in Japanese** for human-facing artifacts: code comments, docstrings, commit messages, and design documents (design docs, READMEs, ADRs).
- **Reply to the user in Japanese** unless they ask for another language.
- If the user or the project's AGENTS.md specifies a language, that overrides both rules above.
- Product content is exempt: UI strings, i18n files, test fixtures and user-facing data keep the project's language.
- Don't translate existing comments or docs unless asked. It only adds diff noise.

## Internal work
- Thinking, plans, scratch notes, subagent tasks and subagent replies, codemode scripts, and agent working files (`.pi/MAP.md`, `.pi/handoff.md`, `.pi/notes/`): **terse English**. Fragments are fine. No filler, no restating the task, no recap of what you just did.
- English costs the fewest tokens on every tokenizer measured, so use it internally even though replies are in Japanese.
