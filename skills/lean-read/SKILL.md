---
name: lean-read
description: Find and read code with minimal tokens. Use before opening a file you haven't seen or when searching the codebase.
---
# Lean read

Goal: get the exact lines you need, not whole files.

1. **Map first.** If `.pi/MAP.md` exists, read it before exploring the tree.
2. **Locate before reading.**
   - Concept search: `mcp__probe__search_code` with `maxTokens: 3000`, `maxResults: 5`. For broad queries, run it with `filesOnly: true` first. Reuse one `session` id per task so the same blocks aren't returned twice.
   - Exact names: `rg -n --max-count 5 'name' <dir>`. Find files: `fd -e ts <pattern> --max-depth 4`.
   - Structural patterns: `mcp__probe__query_code` (ast-grep syntax) or pi-lens symbol search.
3. **Read narrowly.** Use `mcp__probe__extract_code` with `file:line`, or `read` with `offset`/`limit` (at most 150 lines). Read a whole file only if it's under about 200 lines or you're about to rewrite most of it.
4. **Never re-read** a file already in context unless it changed. You already know the content of your own edits.
5. **Never read** lockfiles, `dist/`, `build/`, `node_modules/`, minified or generated files, snapshots, or binary/data files. To peek, use `wc -l`, `head -n 20`, or `jq 'keys'`.
