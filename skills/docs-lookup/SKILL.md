---
name: docs-lookup
description: Look up current library APIs in local docs (Context MCP) instead of guessing. Use before writing code against an unfamiliar or version-sensitive API.
---
# Docs lookup

1. **Check notes first.** If `.pi/notes/<library>.md` exists and its version matches, use it and stop.
2. **Find the installed version** (`npm ls <pkg> --depth=0`, `pip show <pkg>`, or the manifest). Don't read lockfiles.
3. **Query local docs.** `mcp__context__get_docs` with the library and one topic. Topics are literal keywords that must all match, so keep them short (for example `middleware`, `useQuery options`).
4. **Not installed locally yet:** `mcp__context__search_packages`, then `mcp__context__download_package` for the matching version. This downloads once; later queries are local.
5. **Not in the registry and it's a public GitHub repo:** if the `deepwiki` server is configured, find its tools with `tool_search` and ask one narrow question.
6. **Save what you rely on** to `.pi/notes/<library>.md`: 30 lines or fewer, with the version on the first line.
