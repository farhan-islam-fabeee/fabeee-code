---
name: batch-tools
description: Combine three or more lookups or commands into one codemode script that returns only a short summary.
---
# Batch tools

Use this when you'd otherwise make several read, search or bash calls whose raw output you only need to skim.

1. If you haven't checked a tool's return shape this session, call `describeTool("<name>")` first.
2. Write **one** `codemode` script. Run independent calls together with `Promise.allSettled`.
3. **Filter inside the script.** Return counts, matching lines, `file:line` refs, or the first few lines. Never return raw dumps. Keep the returned text under about 1500 tokens.
4. If a call fails, report it in one line and keep the other results.

Shape:
```js
const targets = ["src/a.ts", "src/b.ts", "src/c.ts"];
const results = await Promise.allSettled(
  targets.map((f) => tools.bash({ command: `rg -n "^export " ${f} | head -n 15` })),
);
// Turn each result into a few lines, then return only that summary.
```
