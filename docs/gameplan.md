# Game plan: a local coding agent on pi

**Machine:** M5 Pro, 24 GB unified memory
**Harness:** pi 1.2.0 (`/opt/homebrew/bin/pi`)
**Inference:** oMLX on `127.0.0.1:8000`, serving `Qwen3.8-27B-4bit`

> **Note (2026-10-20):** `scripts/setup.sh` now writes this whole setup into the project (`.pi/models.json`, `.pi/settings.json`, `.pi/mcp.json`, `.pi/extensions/`, `.pi/skills/`, `.pi/AGENTS.md`) so a team shares it through git. The phases below still describe the settings themselves; where they say `~/.pi/agent/…`, the setup script uses the project's `.pi/…` instead.

## The one idea that drives every choice

On Apple Silicon, **prefill (reading the prompt) is the bottleneck, not decode.** Every token of system prompt, tool definitions, skill list and tool output costs prefill time on every turn. oMLX's paged SSD KV cache hides most of that cost, but only while the **prompt prefix stays byte-identical** from turn to turn.

So the rules are:

1. **Keep the prompt surface small and stable.** Use few tools, short skill descriptions, MCP tools loaded on demand (deferred or codemode), and no extensions that rewrite the system prompt every turn.
2. **Get quality from deterministic tools, not extra LLM passes.** LSP diagnostics, linters, type checkers and targeted tests are almost free. LLM reviewers are expensive, so run them on demand and only on the diff.
3. **Change one thing at a time and measure** (Phase 6).

---

## Phase 0: Fix the current config first (highest value, about 10 min)

Your configs disagree with each other:

| Setting | Value | Problem |
|---|---|---|
| pi `models.json` → `contextWindow` | **262144** | oMLX `sampling.max_context_window` is **32768**. pi thinks it has 8× more room than it does, so auto-compaction never fires before the server truncates or errors. |
| pi `models.json` → `maxTokens` | 32768 | This equals the whole real window, which leaves no room for input. |
| pi `models.json` → `reasoning` | false | If Qwen3.8 is a hybrid thinking model, this turns off pi's thinking levels (`low` to execute, `high` to plan). |
| oMLX `sampling.temperature` | 1.0 | This is too hot for reliable tool calls. Set sampling per model in pi instead. |
| oMLX `scheduler.chunked_prefill` / `memory.prefill_memory_guard` | false / false | On 24 GB, a long prefill can push the machine into swap, and swap is the worst slowdown there is. |

**0.1 Pick the real context size.** At 4-bit, a 27B model's weights take about 15–16 GB. Start at **32768**. If `memory_pressure` stays green during a long session, try **49152** in oMLX. Then set pi to the **same number**.

**0.2 Replace `~/.pi/agent/models.json`** (generic template: [`config/models.local.example.json`](../config/models.local.example.json); the oMLX-specific version is below) (pi already keeps `.bak` copies, and you should make one too):

```json
{
  "$schema": "https://pi.dev/schemas/models.schema.json",
  "providers": {
    "omlx": {
      "baseUrl": "http://127.0.0.1:8000/v1",
      "api": "openai-completions",
      "apiKey": "${OMLX_API_KEY}",
      "authHeader": true,
      "models": [
        {
          "id": "Qwen3.8-27B-4bit",
          "name": "Qwen3.8 27B (local)",
          "reasoning": true,
          "input": ["text", "image"],
          "contextWindow": 32768,
          "maxTokens": 8192,
          "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
          "promptCache": { "short": 3600, "long": 86400 },
          "samplingParamsByThinkingLevel": {
            "off":  { "temperature": 0.7, "top_p": 0.8,  "top_k": 20 },
            "low":  { "temperature": 0.6, "top_p": 0.95, "top_k": 20 },
            "high": { "temperature": 0.6, "top_p": 0.95, "top_k": 20 }
          }
        }
      ]
    }
  }
}
```

> Verify the sampling key names against the `$schema` (your editor will flag them). The values are Qwen's published defaults for thinking and non-thinking modes. Keep `reasoning: false` if the model has no thinking mode.

**0.3 Change these in the oMLX dashboard:**
- `scheduler.chunked_prefill`: **true**
- `memory.prefill_memory_guard`: **true**
- `scheduler.max_concurrent_requests`: **8 → 2**. Each concurrent request needs its own KV cache, and two is the most 24 GB can hold for parallel subagents.
- Keep `cache.enabled: true` and `hot_cache_only: false`. The SSD cache is what makes multi-turn agent loops fast.

**0.4 Optional, and you must run it yourself because it is a system setting:** macOS caps GPU-wired memory at roughly two-thirds of RAM. If larger contexts OOM, look up `iogpu.wired_limit_mb` for your macOS version and raise it a little, for example to about 19000 MB, leaving at least 5 GB for the OS.

---

## Phase 1: Core `~/.pi/agent/settings.json`

Ready-made: [`config/settings.json`](../config/settings.json).

```json
{
  "$schema": "https://pi.dev/schemas/settings.schema.json",
  "defaultProvider": "omlx",
  "defaultModel": "Qwen3.8-27B-4bit",
  "defaultThinkingLevel": "low",
  "defaultTools": ["read", "bash", "edit", "write", "+codemode"],
  "codemode": { "mode": "on", "inlineBudget": 1500 },
  "compaction": {
    "enabled": true,
    "modelOverrides": {
      "omlx/Qwen3.8-27B-4bit": { "reserveTokens": 8192, "keepRecentTokens": 10000 }
    }
  },
  "retry": { "enabled": true, "maxRetries": 2, "provider": { "maxRetries": 0 } },
  "httpIdleTimeoutMs": 600000,
  "showCacheMissNotices": true,
  "enableInstallTelemetry": false
}
```

Why these values:
- **`defaultThinkingLevel: "low"`**: execute fast, then switch to `high` only for planning or hard bugs. You can also pin a level per model with `modelThinkingLevels`.
- **`+codemode`**: lets the model batch several tool calls into one script and filter large outputs *before* they enter context. That means fewer turns and less prefill.
- **`inlineBudget: 1500`**: halves the tokens spent listing tools inline (the default is 3000).
- **Compaction overrides**: the defaults (16k reserve plus 20k kept) would trigger almost immediately in a 32k window.
- **`httpIdleTimeoutMs: 600000`**: a cold prefill of a long local context can exceed the 5-minute default.
- **`showCacheMissNotices: true`**: turn this on while tuning so you can *see* when something busts the prefix cache. Turn it off later.

Restore keys you already had (like `lastChangelogVersion`) when you merge this in.

---

## Phase 2: Extensions (pi packages)

Install globally with `pi install npm:<name>`. Add `-l` for a project-only install. Try a package for one run with `pi -e npm:<name>`. **Every package runs code, so read its source before installing.**

### Tier A: always on (quality from deterministic tools, low overhead)

| Package | Why | Speed cost |
|---|---|---|
| **`pi-lens`** | Runs LSP diagnostics, linters, formatters and type checks on every edit. It also adds AST search/replace, a *read guard* (blocks edits to files the agent hasn't read) and a git guard. This is the biggest single quality lever for a local model. | Low on decode. Configure it to report **errors only, not style warnings**, so diagnostics don't flood context. LSP clients idle-evict. |
| **`cc-safety-net`** | Blocks `rm -rf`, `git reset --hard`, force-push, and reads of `.env`/SSH/AWS secrets. It parses commands, so wrapping or reordering doesn't hide them. | About zero. No dependencies, and no LLM involvement. |
| **`@ssk_dev/rpiv-todo-lean`** | A live todo list that survives compaction. Local models lose the thread after compaction, and this anchors them. It's a trimmed wrapper around `@juicesharp/rpiv-todo` with the same engine, and its tool description is about 250 tokens instead of about 900. Don't install both. | Tiny. |
| **`pi-rtk-optimizer`** | Compresses tool output in pure TypeScript with zero dependencies: summarizes test runs, keeps only build errors and warnings, condenses git status/log/diff, aggregates linter output, and groups grep/rg hits by file. Hard truncation at 12,000 characters. **Read compaction is off by default, so leave it off**: pi's `edit` needs exact file text. It also rewrites commands into quieter forms through the external `rtk` program; without it, it warns at startup ("rtk binary unavailable"), so setup installs `rtk` (`brew install rtk`, or the official script) whenever the core tier is installed. `rtk init` isn't needed for pi. There's no saved copy of the raw output, so rerun into a log file when you need the whole thing. *Replaces `pi-token-killer`, which no longer installs on Node 26: it pins `better-sqlite3` 11.x, which has no Node 26 build and doesn't compile against Node 26's V8. It also still uses pi's pre-rename package names (last release April 2026).* | Negative. It *removes* tokens with no LLM call. Check `/rtk stats`. |

### Tier B: on demand (LLM passes, only when you invoke them)

| Package | Use |
|---|---|
| **`@narumitw/pi-plan-mode`** | A read-only `/plan`. Plan at `high` thinking, then exit and execute at `low`. This is cheaper than thinking hard on every turn. |
| **`pi-simplify`** | `/simplify` reviews **only the changed lines** (`git diff`) for clarity and consistency, one file at a time, and runs tests. Use `/simplify --ref=main` before a PR. |
| **`pi-subagents`** | Use `scout` for read-only recon in a *child* context, so exploration noise never enters the main context. Use `reviewer` for a final diff review. **Cap concurrency at 2** to match oMLX. On a single local GPU, parallel agents compete for compute: the win is context isolation, not wall-clock speed. Leave the watchdog reviewer **off**. |

### Tier C: speed, measure before keeping

| Package | Notes |
|---|---|
| **`pi-cache-optimizer`** | Compresses the skill list and removes session-overview churn from the prompt, which helps keep the prefix stable. Its author doesn't claim gains for local servers, so check `/cache-optimizer doctor` plus your cache-miss notices with and without it. |

### Tier D: token and compaction packages (from a pi.dev search on 2026-10-15)

Selection rule for a local 27B: **no extra LLM calls** (each one is a slow local turn) and **no rewriting the prompt on every turn** (that defeats oMLX's prefix cache).

| Package | What it does | Verdict |
|---|---|---|
| **`@sting8k/pi-vcc`** | Replaces pi's compaction with an **algorithmic** one that makes no model calls. It keeps goal, files and changes, commits, outstanding context, user preferences, and about 120 lines of recent transcript. `vcc_recall` searches the raw session for anything compacted away. Config: `~/.pi/agent/pi-vcc-config.json`. | **Add.** Compaction goes from a long 27B summarization turn to near-instant. |
| **`pi-prefix-stabilizer`** | Keeps the system prompt byte-identical: it pins volatile package paths, sorts tool schemas, and warns when the leading text changes. | **Add** (small, no deps). Load it before other prompt-touching extensions. It only helps if oMLX's cache is keyed on prefix content, so confirm with cache-miss notices. |
| **`pi-caveman`** at **`/caveman lite`** | Appends terse-output rules to the system prompt (once, so the prompt stays stable). It doesn't touch reasoning, tool calls or file writes, and it switches itself off for security warnings and irreversible actions. | **Add, Lite level only.** Output is decode, the slowest thing on a local model. Full and Ultra may hurt the clarity of explanations. |
| **`pi-hashline-edit-pro`** | Read output gets 4-character line anchors, and edits target anchors instead of repeating the old text. Stale anchors are rejected, and the post-edit diff returns fresh anchors so no re-read is needed. It replaces the built-in `read`, `edit` and `grep`. | **A/B test.** Edits need far fewer output tokens, but reads cost about 2 extra tokens per line, and it may clash with pi-lens's read guard and pi-rtk-optimizer's read compaction (keep it off). |
| **`context-fold`** | Deterministic: past about 45% context, it folds stale tool results into digests in batches (cache-aware). Originals stay recallable through `recall_folded` and `unfold`. | **Watch.** The design fits well, but the README says it may be retired. |
| **`@pi-unipi/compactor`** | Zero-LLM compaction plus recall plus multi-language sandbox tools. | Alternative to pi-vcc. Its sandbox overlaps codemode, so it's heavier. |
| **`pi-context-view`** | Shows what's in your context, including hidden prompt parts. | **Add while tuning**, then remove. |

**Rejected after reading their pages:**
- **`pi-observational-memory`** and **`billion-context(-pi)`**: they run background or in-band LLM calls on the session model.
- **`pi-jev-lens`**: its classifier is an external API (TypeSafe key), so tool output would leave your machine.
- **`toolflow`**: overlaps pi-rtk-optimizer, its read cache has an unclear staleness risk, and its per-stage tool pruning changes the tool list, which busts the prefix cache.
- **`pi-fovea`**: injects a repo map on every prompt, which means more input and a changing prefix. Probe covers search.
- **`pi-context-diet`** (local only): built around cloud cache TTLs, and its `always` mode rewrites history every turn. **On cloud providers it becomes a good fit.** See Phase 7.
- **`pi-token-killer`**: fails to install on Node 26 (native `better-sqlite3` 11.x) and is unmaintained; replaced by `pi-rtk-optimizer`. **`@bacnh85/pi-rtk`** needs the external `rtk` binary for everything.

### Skip for now

- **`pi-mcp-adapter` / `pi-mcp-extension`**: pi 1.2 has **built-in MCP** with codemode/deferred exposure, so these are redundant.
- **`billion-context`**: a proxy that replaces old message ranges with summaries, and the main model decides when to compress. On a local 27B, that means extra slow model turns, and the rewritten history invalidates oMLX's prefix cache. The `handoff` skill (Phase 3) gets most of the benefit for free.
- **`pi-rtk`** (mcowger): unpublished from npm in September 2026. Don't run two output filters at once in any case.
- **`context-mode`** isn't skipped: it's an optional A/B alternative in Phase 4. It keeps tool output out of context rather than rewriting history.
- **`pi-web-access`**: only add it if you actually need web research. Context (Phase 4) covers library docs.

### Phase 2b: one small custom extension, a quality gate

Source: [`extensions/quality-gate.ts`](../extensions/quality-gate.ts). Install it with `scripts/install.sh extension`, which copies it to `~/.pi/agent/extensions/`. When the agent says it's done, it runs the project's *fast* check. On failure, it feeds the error back once or twice instead of letting a broken change stand. This catches most "it said done but it doesn't compile" failures for the cost of one shell command.

```ts
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { execSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";

// The project declares its fast check in .pi/check (one shell line),
// e.g. `npm run -s typecheck && npm run -s lint`.
const MAX_RETRIES = 2;

export default function (pi: ExtensionAPI) {
  let retries = 0;

  pi.on("before_agent_start", async () => { retries = 0; });

  pi.on("agent_end", async (_event, ctx) => {
    const file = ".pi/check";
    if (!existsSync(file) || retries >= MAX_RETRIES) return;
    const cmd = readFileSync(file, "utf8").trim();
    try {
      execSync(cmd, { stdio: "pipe", timeout: 120_000 });
    } catch (err: any) {
      retries++;
      const out = String(err.stdout ?? "") + String(err.stderr ?? "");
      pi.sendMessage(
        `Quality gate failed (\`${cmd}\`). Fix these, then stop:\n\n` + out.slice(-3000),
        { triggerTurn: true },
      );
    }
  });
}
```

> This is a sketch against the documented event names. `before_agent_start` may also fire on the gate's own re-trigger, so test whether the counter resets there. Check `sendMessage`'s exact signature in `extensions/types.ts`, and test it with `pi --extension ./quality-gate.ts` before installing.

---

## Phase 3: Skills (progressive disclosure, cheap by design)

Only each skill's **name + description** sit in the prompt. The body loads when needed, so skills are the cheapest way to add know-how. Keep descriptions to **one short sentence** (each one is prefill on every turn).

Location: setup installs them in the project's `.pi/skills/` (pi-only; `~/.pi/agent/skills/` is pi's global folder). pi also reads `~/.agents/skills/` and `.agents/skills/`. This is the Agent Skills standard, so the same skills also work in other spec-compliant agents.

### 3a. Token and compaction skills (ready-made in [`skills/`](../skills/))

These target the four places tokens go: **reading code, command output, multi-step lookups, and re-explaining state after compaction.**

| Skill | Saves tokens by | Invocation |
|---|---|---|
| [`lean-read`](../skills/lean-read/SKILL.md) | Locating before reading: Probe `search_code` (filesOnly first, `maxTokens` 3000, deduped `session`), `rg`/`fd` (bundled in `~/.pi/agent/bin`), then `extract_code file:line` or `read` with offset/limit. It never re-reads a file already in context and never opens lockfiles or generated files. | auto |
| [`quiet-shell`](../skills/quiet-shell/SKILL.md) | Quiet flags, `diff --stat` before a full diff, and long output sent to a log file and then grepped or tailed. Tests stay scoped to the touched files. | auto |
| [`batch-tools`](../skills/batch-tools/SKILL.md) | Doing 3+ lookups in one `codemode` script that returns a summary under 1500 tokens. That's one turn and one prefill instead of many. | auto |
| [`delegate-scout`](../skills/delegate-scout/SKILL.md) | Pushing broad exploration into a `scout` subagent that answers in 150 words or fewer, so its file reads never enter the main context. | auto |
| [`project-map`](../skills/project-map/SKILL.md) | Keeping a `.pi/MAP.md` of 60 lines or fewer (commands, layout, entry points, conventions, gotchas), so new sessions skip re-exploring. | auto |
| [`handoff`](../skills/handoff/SKILL.md) | Writing a `.pi/handoff.md` of 40 lines or fewer (goal, done, decisions, next steps, refs, dead ends) and moving to a **fresh session** instead of compacting. Its fallback is a focused `/compact Keep: … Drop: …`. | auto |
| [`resume`](../skills/resume/SKILL.md) | Starting a new session from the handoff file and map only. | `/skill:resume` only |
| [`docs-lookup`](../skills/docs-lookup/SKILL.md) | Querying local docs (Context) for one narrow topic, DeepWiki only as a fallback, then caching what it relies on in `.pi/notes/<lib>.md` so it never looks up the same thing twice. | auto |

**Why handoff beats compaction on a local model:** pi's compaction makes the *main model* summarize the old messages. On a 27B at 32k, that's a long, slow turn. Repeated compactions also re-summarize earlier summaries, so detail is lost each time. A handoff file is written once, is exact, and a fresh session restarts from about 1.5k tokens.

Install:

```bash
./scripts/install.sh skills ~/path/to/project
```

This copies each skill into the project's `.pi/skills/` (pi loads it after you trust the project; commit it so the team gets it too). To use a skill in every project, run `/skills-global` in pi: it copies the skills you pick, or all of them, to `~/.pi/agent/skills/`. `scripts/install.sh context <project>` (run by setup) adds [`context/AGENTS.md`](../context/AGENTS.md) as a marked section of `.pi/AGENTS.md` and installs [`extensions/pi-agents-md.ts`](../extensions/pi-agents-md.ts), which makes pi read `.pi/AGENTS.md` instead of the root `AGENTS.md`/`CLAUDE.md` that other harnesses use. Re-running replaces only that section. Comments, commit messages, design docs and replies to the user are in Japanese unless told otherwise. Internal work, including the agent's own working files (`.pi/MAP.md`, `.pi/handoff.md`, `.pi/notes/`), uses terse English, which measured cheapest on every tokenizer tested (see [research](research.md)).

### 3b. Quality skills (write these next)

| Skill | What it tells the model | Invocation |
|---|---|---|
| `verify` | Check order: format → lint → typecheck → **targeted** tests for touched modules. Run the full suite only when asked. Paste just the failing lines. | auto |
| `bugfix-tdd` | Reproduce with a failing test first, fix, re-run that test, then re-run neighbors. | auto |
| `self-review` | Before saying "done", read your own `git diff` once against a checklist: unused code, error handling, naming consistent with the surrounding code, no debug leftovers. | auto |
| `commit` | Conventional commit message from the staged diff. | `disable-model-invocation: true`, so only `/skill:commit` |

Example, `.pi/skills/verify/SKILL.md`:

```markdown
---
name: verify
description: Run the project's checks in fast-to-slow order after editing code.
---
1. Find the commands in AGENTS.md (or package.json / Makefile / pyproject).
2. Run in order, stopping at the first failure: format, lint, typecheck,
   then only the tests covering files you changed.
3. Pipe long output through `tail -n 40` or `rg -n "error|FAIL"`.
4. Fix and re-run the failing step only. Full suite only if the user asks.
```

**Per project, write a short `.pi/AGENTS.md`** (about 30 lines): build/test/lint commands, layout, and conventions. For a local model this matters more than any package. Also create `.pi/check` with the one-line fast check for the quality gate.

---

## Phase 4: MCP servers (built into pi 1.2)

pi registers each MCP tool as `mcp__<server>__<tool>`. The **default exposure is `codemode`**, which means the tool is invisible to the prompt until a script searches for it. Keep it that way for most servers. Promote only the one or two tools you use constantly to `direct`.

| Server | Why it speeds things up | Exposure |
|---|---|---|
| **Probe** (local AST-aware code search) | Works like `rg`, but each hit is a **whole function or class** (tree-sitter), with hard token caps (`maxTokens`, `PROBE_MAX_TOKENS`), a `filesOnly` mode, and `session` dedupe across calls. `extract_code file:line` pulls one block instead of a whole file. It's fully local, with no embeddings or index to build. This is the main input-token saver, used by the `lean-read` skill. | `search_code` + `extract_code` `direct`; `query_code` deferred |
| **Context** ([Neuledge Context](https://github.com/neuledge/context), library docs) | A local model's knowledge is older and smaller than a frontier model's. Fetching the real API docs beats three rounds of hallucinate, fail, retry. Free and Apache-2.0, with no rate limits: each library's docs download once as a SQLite file and are searched locally, with results trimmed to a token budget. Replaced Context7, whose free tier is now metered. | `direct` (3 tools) |
| **DeepWiki** (optional backup) | Free, keyless docs and Q&A for any public GitHub repo, for libraries the Context registry lacks. Answers can be long. | `deferred` |
| **Serena** (LSP semantic code tools), *optional* | Symbol-level read/replace (`find_symbol`, `replace_symbol_body`) instead of reading whole files. Worth it on **large repos**. It overlaps with pi-lens's navigation tools, so add it only if pi-lens isn't enough. | `deferred` |
| **Playwright MCP**, *frontend projects only* | Lets the agent check its UI changes itself instead of you doing it. | `deferred`, project-level |

Install Probe globally once. Don't use `npx`, which re-resolves the package on every pi start and adds seconds to startup:

```bash
npm install -g @probelabs/probe@latest
```

Then use [`config/mcp.json`](../config/mcp.json) as `~/.pi/agent/mcp.json` (`scripts/install.sh mcp` copies it if you have none yet) (merge it if you already have servers there):

```json
{
  "mcpServers": {
    "probe": {
      "command": "probe",
      "args": ["mcp", "--timeout", "60"],
      "env": { "PROBE_MAX_TOKENS": "4000" },
      "exposure": "deferred",
      "toolExposure": { "search_code": "direct", "extract_code": "direct" },
      "description": "Local AST-aware code search that returns whole functions and classes, with token caps"
    },
    "context": {
      "command": "context",
      "args": ["serve"],
      "exposure": "direct",
      "description": "Local library docs (Neuledge Context): search_packages, download_package, get_docs"
    },
    "deepwiki": {
      "url": "https://mcp.deepwiki.com/mcp",
      "exposure": "deferred",
      "description": "Docs and Q&A for public GitHub repos (DeepWiki), for libraries the local docs don't cover"
    }
  }
}
```

The three direct tools add a few hundred tokens to the system prompt. That prefix never changes, so oMLX caches it after the first turn. Verify with `pi mcp list`.

**Optional A/B: `context-mode`** (`npm i -g context-mode` + `pi install npm:context-mode`, then add `"context-mode": { "command": "context-mode", "exposure": "deferred" }`). It runs commands in a sandbox where only their stdout enters context. Large outputs (logs, Playwright snapshots, fetched pages) are indexed in local SQLite FTS5 so the model can search them instead of reading them. It also logs edits, errors and decisions so state can be retrieved after a compaction. Its own benchmarks claim 94–99% reductions on large outputs. Try it on log-heavy or browser-heavy projects. **Run it *instead of* `pi-rtk-optimizer`, not alongside it**, because both reroute shell output. Drop it if the local model misuses its 11 tools. Check with `ctx stats`.

For Serena, install it with `uv tool install -p 3.13 serena-agent` and `serena init`. Take the exact MCP launch command from [Serena's client guide](https://oraios.github.io/serena/02-usage/030_clients.html), then add it to `.pi/mcp.json` in the large repos where you want it. Serena disables its own file and shell tools inside harnesses, so it won't duplicate pi's.

Put Playwright in a frontend project's `.pi/mcp.json` with `"exposure": "deferred"`. Project MCP config loads only after you grant project trust.

**Deliberately not added:**
- **Filesystem MCP**: duplicates pi's built-in read/edit/write.
- **GitHub MCP**: the `gh` CLI through bash costs zero prompt tokens.
- **Memory MCPs, and servers with dozens of tools**: the cost is prompt size and model confusion.
- **oMLX's own MCP/web-search integrations**: keep tools in one place (pi).

Run `pi mcp list` to check connections. `/mcp` shows errors, and `~/.pi/agent/mcp.log` has the logs.

---

## Phase 5 (optional): A second, small model for cheap work

If memory allows (check this after Phase 0), load a **small instruct model (about 3–4B, 4-bit, about 2.5 GB)** in oMLX next to the 27B. Then:

- **Route compaction to it** with a pi *virtual model*. A router extension (`pi.registerVirtualModel`) sends `request.reason === "direct"` (compaction and similar) to the small model, and returns `previous` for continuations so the main model's cache stays valid. Compacting 30k tokens on the 27B is slow, and on a 4B it's quick.
- **Point the `scout` subagent at it** for recon (see pi-subagents' models doc for per-role overrides).

Don't route normal coding turns between models. Each switch drops the prompt cache.

---

## Phase 6: Measure, then keep or drop

1. Pick **3 real tasks** from your work: a small bugfix, a multi-file feature, and a refactor.
2. Run each at baseline (Phase 0 + 1 only). Record **wall-clock time, number of turns, peak context tokens, compactions triggered, whether checks pass, and how many manual fixes you needed.** For token savings, also read `/rtk stats` (pi-rtk-optimizer) or `ctx stats` (context-mode).
3. Add **one** tier at a time (A → skills → MCP → B → C) and re-run. Keep what improves pass rate without costing more than about 15% time.
4. Watch the cache-miss notices. If a package causes misses every turn, it's rewriting the prefix: drop it or filter its resources:
   ```json
   { "packages": [{ "source": "npm:pi-lens", "skills": [] }] }
   ```
5. When it's stable, turn off `showCacheMissNotices` and pin package versions (`npm:pi-lens@x.y.z`) so an update doesn't silently change behavior.

---

## Phase 7: Cloud option (OpenRouter or any OpenAI-compatible API)

Everything in Phases 1–6 carries over: skills, MCP, pi-vcc, pi-rtk-optimizer and the quality gate. What changes is **what you're optimizing.** Locally, the cost is *time*, mostly prefill. In the cloud, the cost is *money*, and three facts dominate the bill:

1. **Every turn re-sends the whole context.** A 30-turn session at 80k context bills about 2.4M input tokens.
2. **Cached input is 4–10× cheaper.** OpenRouter lists cache reads at 0.1× the input price for DeepSeek, Anthropic and Alibaba Qwen, about 0.2× for Z.AI, and 0.25× for Moonshot, Grok and Gemini. **Cache hit rate is the single biggest cost lever.**
3. **Output tokens (including thinking) cost several times more than input.** Thinking level and reply length matter more than they did locally.

### 7.1 Pick a route

| Route | When | Setup |
|---|---|---|
| **OpenRouter** (built into pi) | One key, every model, easy to compare. | `/login openrouter` or `export OPENROUTER_API_KEY=...`. pi then lists only the models your key can use, **with prices**. |
| **Direct provider** (built in): DeepSeek, Z.ai, Moonshot, Groq, Cerebras, Fireworks, Together, Mistral, xAI, OpenAI, Anthropic, Gemini, Vercel AI Gateway | Your main model is settled. There's one backend, so the cache always hits the same servers and there's no router fee. | `export DEEPSEEK_API_KEY=...` (etc.) or `/login <provider>`. `pi --list-models deepseek` checks it. |
| **Flat-rate coding plans** (built in): ZAI Coding Plan, Kimi For Coding, Qwen Token Plan | Your monthly metered spend gets high. A subscription replaces per-token billing (token savings then stretch your quota instead). | `ZAI_API_KEY`, `KIMI_API_KEY`, `QWEN_TOKEN_PLAN_API_KEY` |
| **Any other OpenAI-compatible endpoint** | A provider pi doesn't ship. | Add it to `models.json` (7.3). |

**Choosing a model for cost:** prefer families with **automatic** caching and cheap reads (DeepSeek, GLM/Z.AI, Kimi/Moonshot, Grok). Anthropic reads are cheap too, but writes cost 1.25× (5-minute TTL) or 2× (1-hour TTL), and caching needs `cache_control`. Verify that pi's requests through OpenRouter actually hit the cache (7.5) before you rely on it. **Avoid `openrouter/auto`.** It can route each turn to a different model, which splits the cache, and pi shows its price as 0.

### 7.2 Switch per session, not per turn

Switching provider or model mid-session re-sends the entire context **uncached** to the new backend. Use the `handoff` skill as the switch point:

```bash
# local (default, from settings.json)
pi
```

```bash
# cloud for a hard task: start fresh, read the handoff
pi --model openrouter/<model-id>:low
```

Add shell aliases:

```bash
alias pic='pi --model openrouter/<model-id>:low'
```

```bash
alias pid='pi --model deepseek/<model-id>:low'
```

`--models "omlx/*,openrouter/<id>"` scopes model cycling to just these. To use the cloud by default in one repo, put `defaultProvider`/`defaultModel` in that repo's `.pi/settings.json`.

### 7.3 A custom OpenAI-compatible provider

Merge this into `~/.pi/agent/models.json` next to `omlx` (full file: [`config/models.cloud.example.json`](../config/models.cloud.example.json)). Costs are **USD per million tokens**, copied from the provider's pricing page. pi uses them for the footer and `/session` cost totals, and for cache-warming decisions.

```json
"mycloud": {
  "baseUrl": "https://api.example.com/v1",
  "api": "openai-completions",
  "apiKey": "${MYCLOUD_API_KEY}",
  "models": [
    {
      "id": "<model-id>",
      "name": "<Model> (mycloud)",
      "reasoning": true,
      "input": ["text"],
      "contextWindow": 131072,
      "maxTokens": 16384,
      "cost": { "input": 0.0, "output": 0.0, "cacheRead": 0.0, "cacheWrite": 0.0 },
      "promptCache": { "short": 300 }
    }
  ]
}
```

- Set `promptCache.short` to the provider's real cache TTL in seconds. Leave it out if the provider doesn't cache, which also turns cache warming off for it.
- **Don't add `compat` flags unless you've verified a difference** (pi's docs are explicit about this). If the endpoint rejects `prompt_cache_key` or `prompt_cache_retention`, run `/cache-optimizer doctor` and use the fix it suggests.

### 7.4 Cloud-specific settings and packages

| Change | Why it saves money |
|---|---|
| **Cap the effective context at about 100k**, even when the model offers 256k+, using the `handoff` skill when the footer passes it (or a per-model `contextWindow` override via `modelOverrides` in `models.json`; check the shape in the schema). | Each turn bills the whole context. A fresh session from a 1.5k-token handoff is far cheaper than turns 40–60 at 200k. |
| `"defaultThinkingLevel": "low"`. Use `:high` (e.g. `--model x:high`) only for planning. | Thinking is billed as output, the most expensive token type. |
| Keep `"cacheWarming": "streaming"` (the default). Use `"idle"` only if you often pause 5+ minutes mid-task with large contexts. | Warm-ups are billed requests. pi only warms when it estimates at least $0.05 avoided, but the cost adds up. |
| **`pi-cache-optimizer`**: Tier C becomes **add**. | Adds a per-session `prompt_cache_key` for OpenAI-compatible routes, keeps the skill list short, warns about proxies that split caches, and shows hit rate in the footer. |
| **`pi-context-diet`** (default `cold` mode, set `/context-diet ttl` to the provider's TTL): becomes **add**. | Once a long pause has already expired the cache, the next request is uncached anyway. It uses that moment to replace stale tool output with stubs, so the trim costs nothing extra. Don't use `always` mode. |
| `pi-vcc`, `pi-caveman` (Lite), `pi-rtk-optimizer`, `rpiv-todo-lean`, `pi-prefix-stabilizer` | All worth *more* in the cloud. A stock compaction is a paid call on the whole context, output costs several times more than input, and a stable prefix means cache hits. |
| Subagents: put `scout` on a **cheap model** (pi-subagents per-role overrides). | Exploration is read-heavy and doesn't need the big model. |

### 7.5 Guardrails and verification

- **Spending cap:** set a credit limit **per API key** in the OpenRouter (or provider) dashboard, and use a separate key for pi.
- **Privacy:** your code leaves the machine. In OpenRouter's privacy settings, exclude providers that train on or retain prompts, and check the direct provider's data policy before using it on work repos.
- **Cache hits:** keep `showCacheMissNotices: true` for the first few cloud sessions. On OpenRouter, open a generation on the Activity page and check `cached_tokens` and `cache_discount`. If `cached_tokens` stays at 0 after the second turn, something is changing the prefix (fix it before scaling up), or the model needs `cache_control` that isn't being sent.
- **Sticky routing:** OpenRouter keeps follow-ups on the same backend only after a cache hit, and drops the pin after 10 idle minutes. Pinning a fixed `provider.order` overrides that, so leave routing on default unless a specific backend is clearly cheaper.
- **Track it:** `/session` shows session totals. Repeat the Phase 6 test runs on the cloud model and record **$ per task** next to time and pass rate.

---

## Rollout checklist

- [ ] Phase 0: align context window (pi = oMLX), set maxTokens 8192, fix sampling, turn on chunked prefill and prefill memory guard, set concurrency to 2
- [ ] Phase 1: settings.json (thinking low, +codemode, compaction overrides, timeouts)
- [ ] Baseline run of 3 tasks
- [ ] Tier A: pi-lens (errors only), cc-safety-net, rpiv-todo-lean, pi-rtk-optimizer (read compaction off)
- [ ] Tier D: pi-vcc, pi-prefix-stabilizer, pi-caveman (lite), pi-context-view while tuning; A/B pi-hashline-edit-pro
- [ ] Token skills: copy `skills/` → `<project>/.pi/skills/` (lean-read, quiet-shell, batch-tools, delegate-scout, project-map, handoff, resume, docs-lookup); `/skills-global` copies any you want everywhere to `~/.pi/agent/skills/`
- [ ] Quality skills: verify, bugfix-tdd, self-review, commit + per-project AGENTS.md
- [ ] MCP: Probe (direct search/extract) + Context (direct, `npm i -g @neuledge/context`) + optional DeepWiki (deferred) via `config/mcp.json`; Serena only for large repos; Playwright only for frontend
- [ ] Per project: run `project-map` once; add `.pi/handoff.md` to `.gitignore`
- [ ] Optional A/B: context-mode instead of pi-rtk-optimizer on log- or browser-heavy projects (it uses native `better-sqlite3` 12.x, so check it installs on your Node version first)
- [ ] Tier B: plan-mode, pi-simplify, pi-subagents (concurrency 2, watchdog off)
- [ ] Quality-gate extension + `.pi/check` per project
- [ ] Tier C: pi-cache-optimizer, A/B tested
- [ ] Optional: small helper model for compaction and scout
- [ ] Pin versions
- [ ] Cloud (optional): separate key with a credit cap and privacy settings → `/login openrouter` (or a direct provider) → aliases → add pi-cache-optimizer and pi-context-diet → verify `cached_tokens` > 0 from turn 2 → Phase 6 runs with $ per task
