# pi-agent-kit

A setup kit for running the [pi](https://pi.dev) coding agent on a **local model** (oMLX on Apple Silicon), with an optional **cloud** route (OpenRouter or any OpenAI-compatible API). It's tuned for **code quality at minimal token cost**. Locally that cost is time; in the cloud it's money.

It was tuned for pi 1.2.0, an M5 Pro with 24 GB, and oMLX serving `Qwen3.8-27B-4bit`. Adjust the model ID, context size and memory figures for your machine.

## Layout

```
docs/gameplan.md            the full plan: phases 0–7, rationale, rollout checklist
docs/research.md            package and MCP findings (adopted / A-B / rejected), cache pricing, open questions
skills/                     8 token- and compaction-saving skills (Agent Skills format)
context/AGENTS.md           global rules installed with the skills: English for repo artifacts and replies, terse English internally
skills-ja/                  Japanese translations, kept for reference (they cost 13–71% more tokens depending on the model; see docs/research.md)
config/models.local.json    oMLX provider: context window matched to the server, sampling per thinking level
config/settings.json        pi settings: low thinking, codemode, compaction sized for 32k
config/mcp.json             Probe (local code search) + Context7 (docs)
config/models.cloud.example.json  template for any OpenAI-compatible cloud provider
extensions/quality-gate.ts  runs the project's fast check when the agent finishes and feeds failures back
scripts/install.sh          installs skills, the extension, MCP config and package tiers
scripts/count_tokens.py     compares token counts of skills/ vs skills-ja/ across tokenizers (HF tokenizer.json, OpenAI o200k, Kimi)
```

## Quick start

1. **Fix the model config first.** Read [docs/gameplan.md](docs/gameplan.md), Phase 0. Merge [config/models.local.json](config/models.local.json) and [config/settings.json](config/settings.json) into `~/.pi/agent/` by hand (the script never overwrites these), and set `OMLX_API_KEY` to your oMLX key.
2. **Install the skills (with the global `AGENTS.md`), the extension and the MCP config:**
   ```bash
   ./scripts/install.sh all
   ```
   ```bash
   npm install -g @probelabs/probe@latest
   ```
3. **Install packages one tier at a time**, measuring as you go (gameplan Phase 6):
   ```bash
   ./scripts/install.sh packages core
   ```
   The other tiers are `tokens`, `ondemand`, `tuning`, `cloud` and `ab`. Prefix any command with `DRY_RUN=1` to preview it.
4. **Per project:** write a short `AGENTS.md`, put a one-line fast check in `.pi/check` (for the quality gate), run the `project-map` skill once, and add `.pi/handoff.md` to `.gitignore`.

## Skills

| Skill | Saves tokens by |
|---|---|
| [lean-read](skills/lean-read/SKILL.md) | Searching (Probe, `rg`, `fd`) before reading, reading line ranges only, never re-reading |
| [quiet-shell](skills/quiet-shell/SKILL.md) | Using quiet flags, `--stat` before a full diff, and logging long output to a file then grepping it |
| [batch-tools](skills/batch-tools/SKILL.md) | Doing 3+ lookups in one codemode script that returns a short summary |
| [delegate-scout](skills/delegate-scout/SKILL.md) | Sending broad exploration to a `scout` subagent that replies in 150 words or fewer |
| [project-map](skills/project-map/SKILL.md) | Keeping a `.pi/MAP.md` of 60 lines or fewer so new sessions skip re-exploring |
| [handoff](skills/handoff/SKILL.md) | Saving state to `.pi/handoff.md` and starting a fresh session instead of compacting |
| [resume](skills/resume/SKILL.md) | Starting a session from the handoff file and map (`/skill:resume`) |
| [docs-lookup](skills/docs-lookup/SKILL.md) | Querying Context7 narrowly and caching the answer in `.pi/notes/` |

## Status

This is a plan plus starter files, and none of it has been run end to end yet. The skills and quality gate haven't been run inside pi, and several config details still need checking against pi's schemas. [docs/research.md](docs/research.md) lists them under "Not verified".
