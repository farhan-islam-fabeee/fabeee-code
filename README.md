# pi-agent-kit

A setup kit for running the [pi](https://pi.dev) coding agent on a **local model** (oMLX on Apple Silicon), with an optional **cloud** route (OpenRouter or any OpenAI-compatible API). It's tuned for **code quality at minimal token cost**. Locally that cost is time; in the cloud it's money.

It was tuned for pi 1.2.0, an M5 Pro with 24 GB, and oMLX serving `Qwen3.8-27B-4bit`. Adjust the model ID, context size and memory figures for your machine.

## Layout

```
docs/gameplan.md            the full plan: phases 0–7, rationale, rollout checklist
docs/research.md            package and MCP findings (adopted / A-B / rejected), cache pricing, open questions
skills/                     8 token- and compaction-saving skills (Agent Skills format)
context/AGENTS.md           global rules installed with the skills: Japanese for comments, docs and replies; terse English internally
skills-ja/                  Japanese translations, kept for reference (they cost 13–71% more tokens depending on the model; see docs/research.md)
config/models.local.json    oMLX provider: context window matched to the server, sampling per thinking level
config/settings.json        pi settings: low thinking, codemode, compaction sized for 32k
config/mcp.json             Probe (local code search) + Context7 (docs)
config/models.cloud.example.json  template for any OpenAI-compatible cloud provider
extensions/quality-gate.ts  runs the project's fast check when the agent finishes and feeds failures back
scripts/setup.sh            guided setup, run from a project folder: installs pi, configures local/cloud, installs the kit, prepares the project
scripts/lib/pi-config.mjs   JSON/project helper used by setup.sh (backs up every file it changes)
scripts/lib/i18n.sh         message loader; catalogs in scripts/lib/lang/{en,ja,ko,bn}.txt
scripts/lib/check-i18n.mjs  checks the catalogs have the same keys and placeholders (run after editing messages)
scripts/install.sh          installs skills, the extension, MCP config and package tiers
scripts/count_tokens.py     compares token counts of skills/ vs skills-ja/ across tokenizers (HF tokenizer.json, OpenAI o200k, Kimi)
```

## Quick start

Run the guided setup from inside the project you want to work on:

```bash
cd ~/path/to/your-project
```

```bash
~/Development/pi-agent-kit/scripts/setup.sh
```

It first asks for a display language: English, 日本語, 한국어 or বাংলা. Your system locale sets the default, and `--lang=ja` (or `PI_KIT_LANG=ja`) skips the question. Then it walks through 7 steps and asks before each change:

1. **Project:** confirms the folder.
2. **pi:** installs pi if it's missing (the official installer or npm) and checks the version.
3. **Models:** choose local, cloud or both.
   - **Local:** oMLX, Ollama, LM Studio, a llama.cpp router, or any OpenAI-compatible server. The script lists the server's models and asks for the context window the server *actually* serves (for oMLX it reads `~/.omlx/settings.json`).
   - **Cloud:** OpenRouter, DeepSeek, Z.ai, Moonshot, the other providers built into pi, or a custom OpenAI-compatible endpoint with prices and cache lifetime.
   - **API keys:** store them in the macOS Keychain (pi runs `security` on each request), in an environment variable, with pi's own `/login`, or, for a local server only, as plain text.
4. **Settings:** writes pi's settings (low thinking by default, codemode, compaction sized to the local window), sets the default model (globally or for this project only), and can add `pil`/`pic` shell aliases.
5. **Kit:** installs the skills, the global `AGENTS.md`, the quality gate, and the Probe and Context7 MCP servers.
6. **Packages:** offers each package tier separately. Every package runs code, so each one asks first.
7. **Project files:** sets up git, `.pi/check` (detected from package.json, Cargo, Go or Python), a starter `AGENTS.md`, and `.gitignore`.

Every pi config file it changes is backed up first (`<file>.backup-<timestamp>`), and it's safe to re-run. `--dry-run` asks the same questions but writes nothing.

To install pieces by hand instead, `./scripts/install.sh all` installs the skills, `AGENTS.md`, the extension and the MCP config, and `./scripts/install.sh packages <tier>` installs one tier (`core`, `tokens`, `ondemand`, `tuning`, `cloud`, `ab`). Merge [config/models.local.json](config/models.local.json) and [config/settings.json](config/settings.json) into `~/.pi/agent/` yourself (gameplan Phase 0–1).

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
