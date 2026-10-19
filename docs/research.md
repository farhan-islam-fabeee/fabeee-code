# Research notes

These findings come from pi's docs and pi.dev package pages, read between 2026-10-14 and 2026-10-16 against pi 1.2.0. Package versions and download counts change quickly, so re-check before relying on them. **Pi packages run code. Review the source before installing.**

## Facts about pi 1.2 that shaped the plan

- **MCP is built in.** Config lives in `~/.pi/agent/mcp.json` (user) and `.pi/mcp.json` (project, after you trust the project). Each server's tool exposure is one of `codemode` (the default), `deferred`, `direct` or `hidden`, and `toolExposure` can override it per tool. `pi-mcp-adapter` is no longer needed.
- **Codemode** lets the model write a QuickJS script that calls other tools and returns only the script's output. MCP tools with the default exposure don't appear in the prompt.
- **Skills** follow the Agent Skills spec. They load from `~/.agents/skills/` and `.agents/skills/`. Only each skill's name and description sit in the prompt; the body loads when the skill is used. `disable-model-invocation: true` makes a skill command-only.
- **Compaction** runs the active model over the old messages. Settings are `compaction.reserveTokens` and `keepRecentTokens`, with per-model overrides. To summarize with a different model you need an extension (`session_before_compact`).
- **Virtual models** (`pi.registerVirtualModel`) route each request to a physical model. Switching models between turns drops the prompt cache.
- **Built-in cloud providers** include OpenRouter, DeepSeek, Groq, Cerebras, Fireworks, Together, Mistral, xAI, Z.ai, Moonshot/Kimi, Qwen Token Plan, Vercel AI Gateway, OpenAI, Anthropic and Gemini. Each takes an env var key or `/login`.
- **Cache warming** (`cacheWarming`) can be `off`, `streaming` (the default) or `idle`. It only fires when pi estimates at least $0.05 of avoided cache-miss cost.

## Packages

**Native modules:** pi runs on whatever Node is on your PATH (here Node 26 from nvm), so a package with a native dependency must have a build for that Node version. On 2026-10-20 every package in the setup tiers was checked: none needs a compiler except `pi-lens`, which uses ast-grep's prebuilt binaries.

### Adopted

| Package | Role | Why |
|---|---|---|
| [pi-lens](https://pi.dev/packages/pi-lens) | Quality | LSP, lint, format and type checks on every edit, plus a read guard and AST tools |
| [cc-safety-net](https://pi.dev/packages/cc-safety-net) | Safety | Blocks destructive commands and secret access by parsing the command |
| [@ssk_dev/rpiv-todo-lean](https://pi.dev/packages/@ssk_dev/rpiv-todo-lean) | Tokens | Todo list that survives compaction, with a tool description of about 250 tokens instead of about 900 |
| [pi-rtk-optimizer](https://pi.dev/packages/pi-rtk-optimizer) | Tokens | Zero-dependency output compaction (tests, build, git, lint, grep); read compaction off by default. Replaced pi-token-killer on 2026-10-20. |
| [@sting8k/pi-vcc](https://pi.dev/packages/@sting8k/pi-vcc) | Compaction | Algorithmic compaction with no LLM call, plus `vcc_recall` |
| [pi-prefix-stabilizer](https://pi.dev/packages/pi-prefix-stabilizer) | Cache | Keeps the system prompt byte-stable so the prefix cache keeps hitting |
| [pi-caveman](https://pi.dev/packages/pi-caveman) (Lite level) | Output tokens | Terse prose. Code, tool calls and reasoning are untouched. |
| [@narumitw/pi-plan-mode](https://pi.dev/packages) | Workflow | Read-only `/plan` |
| [pi-simplify](https://pi.dev/packages/pi-simplify) | Quality | Diff-scoped clarity review |
| [pi-subagents](https://pi.dev/packages/pi-subagents) | Context isolation | `scout` and `reviewer` run in child sessions |
| [pi-context-view](https://pi.dev/packages) | Tuning | Shows what's in your context. Remove it once you're done tuning. |
| [pi-cache-optimizer](https://pi.dev/packages/pi-cache-optimizer) | Cloud | Per-session `prompt_cache_key`, shorter skill list, cache-hit stats |
| [pi-context-diet](https://pi.dev/packages/pi-context-diet) | Cloud | Trims stale tool output only after the cache has already gone cold |

### A/B test or watch

| Package | Notes |
|---|---|
| [pi-hashline-edit-pro](https://pi.dev/packages/pi-hashline-edit-pro) | Anchor-based edits mean fewer output tokens per edit, but each line read costs about 2 extra tokens. It replaces the built-in read, edit and grep, so check for conflicts with pi-lens. |
| [context-mode](https://pi.dev/packages/context-mode) | Sandboxed execution with an FTS5 index of large outputs and state that survives compaction. Use it **instead of** pi-rtk-optimizer, not alongside it. Depends on native `better-sqlite3` 12.x, so check it installs on your Node version. |
| [context-fold](https://pi.dev/packages/context-fold) | Deterministic, cache-aware folding of stale tool output that can be recalled later. Its README says it may be retired. |
| [@pi-unipi/compactor](https://pi.dev/packages/@pi-unipi/compactor) | An alternative to pi-vcc that also bundles sandbox tools. |

### Rejected

| Package | Reason |
|---|---|
| pi-mcp-adapter, pi-mcp-extension | MCP is built into pi 1.2 |
| billion-context(-pi) | Uses the main model to compress, and rewrites history, which breaks the cache |
| pi-observational-memory | Runs background LLM calls on the session model |
| pi-jev-lens | Its classifier is an external API, so tool output leaves your machine |
| toolflow | Overlaps pi-rtk-optimizer, has unclear read-cache staleness, and per-stage tool pruning busts the cache |
| pi-fovea | Adds a repo map to every prompt |
| pi-token-killer | Fails on Node 26: pins native `better-sqlite3` 11.x (no Node 26 prebuild, doesn't compile against Node 26's V8). Unmaintained since April 2026 and still uses pi's pre-rename peer names. |
| pi-rtk, @bacnh85/pi-rtk | pi-rtk was unpublished from npm (2026-09-27). @bacnh85/pi-rtk needs the external `rtk` binary. |
| pi-context-diet (local only) | Built around cloud cache TTLs. It's adopted for cloud use. |

## MCP servers

| Server | Decision | Notes |
|---|---|---|
| [Probe](https://probelabs.com/mcp-integration) | Adopted | Local tree-sitter search that returns whole code blocks. Supports `maxTokens`, `filesOnly` and `session` dedupe. Install it globally rather than through npx. |
| Context7 | Adopted | Library docs at `https://mcp.context7.com/mcp` |
| [Serena](https://github.com/oraios/serena) | Large repos only | Symbol-level reads and edits. Overlaps pi-lens. |
| Playwright MCP | Frontend projects only | Set `deferred` exposure in the project config |
| Filesystem, GitHub, memory MCPs | Rejected | They duplicate built-ins or `gh`, or bloat the prompt |

## Cloud caching (OpenRouter docs, 2026-10-16)

Cache read price as a multiple of the normal input price:

| Provider family | Read price | Write price | Setup |
|---|---|---|---|
| DeepSeek | 0.1× | 1× | automatic |
| Anthropic | 0.1× | 1.25× (5-minute TTL) or 2× (1-hour TTL) | needs `cache_control` |
| Alibaba Qwen | 0.1× | 1.25× | needs `cache_control` |
| Z.AI | about 0.2× | free (limited time) | automatic |
| Moonshot, Grok | 0.25× | free | automatic |
| Gemini 2.5+ | 0.25× | none | implicit, TTL about 3–5 min |
| OpenAI | 0.25× or 0.5× | free (1.25× from GPT-5.6) | automatic, 1024-token minimum |

OpenRouter keeps follow-up requests on the same backend once there's been a cache hit, and drops that pin after 10 idle minutes. Cache usage appears as `prompt_tokens_details.cached_tokens` in the response and on the Activity page.

## Not verified

- Sampling key names in the oMLX example in `docs/gameplan.md` Phase 0.2 (check them against the schema).
- The exact return shape of `codemode`'s `tools.bash` (the `batch-tools` skill tells the model to call `describeTool` first).
- Whether `disable-model-invocation` removes a skill's description from the prompt.
- Whether pi sends `cache_control` for Anthropic and Qwen models through OpenRouter (check `cached_tokens`).
- The `modelOverrides` shape for capping a cloud model's `contextWindow`.
- `extensions/quality-gate.ts` has not been run. Test it with `pi --extension`.

## Sources

- pi docs: [mcp](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/mcp.md), [models](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/models.md), [settings](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/settings.md), [skills](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/skills.md), [extensions](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/extensions.md), [codemode](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/codemode.md), [compaction](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/compaction.md), [virtual models](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/virtual-models.md), [packages](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/packages.md), [providers](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/providers.md), [cli](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/cli.md), [llama.cpp](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/llama-cpp.md)
- [pi.dev package catalog](https://pi.dev/packages)
- [OpenRouter prompt caching](https://openrouter.ai/docs/features/prompt-caching)
- [oMLX discussion](https://github.com/ml-explore/mlx/discussions/3203)
- [MLX vs llama.cpp benchmark](https://rapidmlx.com/blog/mlx-vs-llama-cpp-benchmark)

## Japanese vs English skills (2026-10-19)

`skills-ja/` holds Japanese translations of all 8 skills. Code, commands, paths and tool names stay in English. I counted tokens with the **Qwen3.8-27B tokenizer** (the model's own `tokenizer.json`) using `scripts/count_tokens.py`:

| What | English | Japanese | Difference |
|---|---|---|---|
| Descriptions (always in the system prompt) | 210 | 250 | **+19%** |
| Full SKILL.md files (loaded when a skill runs) | 1,959 | 2,208 | **+13%** |
| Prose only (code and inline code removed) | 1,267 | 1,479 | **+17%** |
| Characters | 6,953 | 4,965 | −29% |

Japanese uses about 30% fewer characters, but each token carries about half as many characters (1.96 per token against 3.83 for English prose). **Every one of the 8 skills costs more in Japanese** (+5% to +38% per description). Keep the English `skills/` installed. `skills-ja/` is there for reading and reference. Don't install both, because the skill names collide.

Two side effects:
- **Output language follows the instructions.** A Japanese skill tends to make the model write handoff files, MAP.md and scout replies in Japanese, so those cost extra tokens every time they're read back. On a local model that's also slower decode.
- **pi's chars/4 estimate undercounts Japanese.** For these files it estimates 1,237 tokens against an actual 2,208 (44% low). For English it's 1,735 against 1,959 (11% low). That estimate is used for `codemode.inlineBudget` and compaction cut points, so Japanese-heavy context is larger than pi thinks.

### Cloud tokenizers (2026-10-19)

Same files, counted with each provider's published tokenizer (downloaded from OpenAI's tiktoken storage and the official Hugging Face repos):

| Tokenizer | Descriptions EN → JA | Full files EN → JA | Range per skill (full file) |
|---|---|---|---|
| Qwen3.8 (local) | 210 → 250 (**+19%**) | 1,959 → 2,208 (**+13%**) | +5% to +23% |
| OpenAI o200k (GPT-4o and later) | 206 → 350 (**+70%**) | 1,846 → 2,508 (**+36%**) | +25% to +53% |
| DeepSeek V4.1 | 209 → 327 (**+56%**) | 1,892 → 2,457 (**+30%**) | +19% to +44% |
| GLM-5.3 (Z.ai) | 210 → 340 (**+62%**) | 1,863 → 2,492 (**+34%**) | +22% to +53% |
| Kimi K3 (Moonshot) | 202 → 346 (**+71%**) | 1,832 → 2,473 (**+35%**) | +24% to +59% |

**Japanese costs more on every tokenizer, and 2–4× more extra on the cloud ones than on Qwen.** The English counts are almost identical across tokenizers (about 1,830–1,960). Qwen's vocabulary handles Japanese unusually well, while the cloud tokenizers split it into far more pieces. On a cloud bill, Japanese descriptions add about 120–145 input tokens to **every** request, and each full skill load adds about 30–36%. Output costs more again: Japanese replies, handoff files and scout summaries carry the same overhead, billed at output prices.

Not measured: Claude and Gemini. Neither publishes a tokenizer; counting needs their token-count APIs and an API key. Reproduce with `scripts/count_tokens.py` (usage is in its docstring).
