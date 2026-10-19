---
name: docs-lookup
description: Look up current library APIs through Context7 instead of guessing. Use before writing code against an unfamiliar or version-sensitive API.
---
# Docs lookup

1. **Check notes first.** If `.pi/notes/<library>.md` exists and its version matches, use it and skip Context7.
2. **Find the installed version** (`npm ls <pkg> --depth=0`, `pip show <pkg>`, or the manifest). Don't read lockfiles.
3. **Query narrowly.** Resolve the library id once, then query one specific topic (for example "middleware" or "useQuery options"). Ask for the smallest token budget the tool allows that answers the question, about 2000.
4. **Save what you rely on** to `.pi/notes/<library>.md`: 30 lines or fewer, with the version on the first line. Next time you need it, read that file instead of calling Context7 again.
