**English** | [日本語](README.md)

# fabeee-code

A setup kit for running the [pi](https://pi.dev) coding agent on a **local model** (oMLX on Apple Silicon), with an optional **cloud** route (OpenRouter or any OpenAI-compatible API). It's tuned for **code quality at minimal token cost**. Locally that cost is time; in the cloud it's money.

It was tuned for pi 1.2.0, an M5 Pro with 24 GB, and oMLX serving `Qwen3.8-27B-4bit`. Adjust the model ID, context size and memory figures for your machine.

## Layout

```
bootstrap.sh                one-liner entry point: downloads/updates the kit in ~/.fabeee-code, then runs setup.sh here
docs/gameplan.md            the full plan: phases 0–7, rationale, rollout checklist
docs/research.md            package and MCP findings (adopted / A-B / rejected), cache pricing, open questions
skills/                     8 token- and compaction-saving skills (Agent Skills format)
context/AGENTS.md           agent rules added as a section of the project's AGENTS.md: Japanese for comments, docs and replies; terse English internally
skills-ja/                  Japanese translations, kept for reference (they cost 13–71% more tokens depending on the model; see docs/research.md)
config/models.local.example.json  template for a local OpenAI-compatible server (oMLX, Ollama, LM Studio, …)
config/settings.json        pi settings: low thinking, codemode, compaction sized for 32k
config/mcp.json             Probe (local code search) + Context7 (docs)
config/models.cloud.example.json  template for any OpenAI-compatible cloud provider
extensions/quality-gate.ts  runs the project's fast check when the agent finishes and feeds failures back
extensions/skills-global.ts /skills-global pi command: copies chosen project skills to ~/.pi/agent/skills
extensions/pi-agents-md.ts  makes pi read .pi/AGENTS.md instead of the root AGENTS.md/CLAUDE.md other harnesses use
extensions/project-models.ts registers the providers in a project's .pi/models.json (pi only reads models.json globally)
scripts/setup.sh            guided setup, run from a project folder: writes the whole pi setup into the project
scripts/lib/pi-config.mjs   JSON/project helper used by setup.sh (backs up every file it changes)
scripts/lib/i18n.sh         message loader; catalogs in scripts/lib/lang/{en,ja,ko,bn}.txt
scripts/lib/check-i18n.mjs  checks the catalogs have the same keys and placeholders (run after editing messages)
scripts/install.sh          installs skills, the extension, MCP config and package tiers
scripts/count_tokens.py     compares token counts of skills/ vs skills-ja/ across tokenizers (HF tokenizer.json, OpenAI o200k, Kimi)
```

## Quick start

Run this one-liner from inside the project you want to work on:

```bash
curl -fsSL https://raw.githubusercontent.com/farhan-islam-fabeee/fabeee-code/main/bootstrap.sh | bash
```

It downloads the kit to `~/.fabeee-code` (or updates it on later runs), then starts the guided setup in the current folder. Pass setup options after `bash -s --`, for example `curl -fsSL … | bash -s -- --lang=ja --dry-run`. `FABEEE_CODE_HOME` changes where the kit is kept, and `FABEEE_CODE_REF` pins a branch or tag.

To read the script before running it:

```bash
curl -fsSL https://raw.githubusercontent.com/farhan-islam-fabeee/fabeee-code/main/bootstrap.sh -o bootstrap.sh
```

```bash
less bootstrap.sh && bash bootstrap.sh
```

If you've cloned the repo, you can also run `scripts/setup.sh` from your project folder directly.

It first asks for a display language: English, 日本語, 한국어 or বাংলা. Your system locale sets the default, and `--lang=ja` (or `FABEEE_CODE_LANG=ja`) skips the question.

**Everything is written into the project**, so you commit it once and the whole team gets the same setup. Nothing goes into `~/.pi/agent` except what pi itself needs on each machine.

| In the project (commit it) | Per person (never committed) |
|---|---|
| `.pi/models.json`: model providers, loaded by `.pi/extensions/project-models.ts` | API keys: macOS Keychain, an environment variable, or pi's `/login`. `.pi/models.json` only holds a reference such as `${VAR}` or `!security …` |
| `.pi/settings.json`: default model, thinking level, codemode, compaction, packages | pi itself |
| `.pi/mcp.json`: Probe and Context7 | the `probe` and `rtk` programs (setup installs `rtk` with Homebrew when `pi-rtk-optimizer` is used) |
| `.pi/extensions/`: quality gate, `/skills-global`, `.pi/AGENTS.md` loader, provider loader | `.pi/npm/` (downloaded packages) and `.pi/handoff.md`, both added to `.gitignore` |
| `.pi/skills/`, `.pi/AGENTS.md`, `.pi/check` | |

pi loads `.pi/` only after you trust the project, so answer yes to its trust prompt on first start.

In a project that's already set up (for example after a teammate committed it), setup offers **"Use it"**: it only prepares your machine (pi, your own API keys, `probe`, `rtk`) and leaves the project as it is. pi installs the project's packages on first start.

Otherwise it walks through 7 steps and asks before each change:

1. **Project:** confirms the folder.
2. **pi:** installs pi if it's missing (the official installer or npm), makes sure your shell can find it, and checks the version.
3. **Models:** choose local, cloud or both, saved to `.pi/models.json`.
   - **Local:** oMLX, Ollama, LM Studio, a llama.cpp router, or any OpenAI-compatible server. The script lists the server's models and asks for the context window the server *actually* serves (for oMLX it reads `~/.omlx/settings.json`).
   - **Cloud:** OpenRouter, DeepSeek, Z.ai, Moonshot, the other providers built into pi, or a custom OpenAI-compatible endpoint with prices and cache lifetime.
   - **API keys:** the macOS Keychain (pi runs `security` on each request), an environment variable, or pi's own `/login`. There's no plain-text option, because the file is shared.
4. **Settings:** writes `.pi/settings.json` (low thinking by default, codemode, compaction sized to the local window) with the project's default model.
5. **Kit:** installs the skills into `.pi/skills/`, the `/skills-global` command, the quality gate, and the Probe and Context7 MCP servers in `.pi/mcp.json`.
6. **Packages:** offers each package tier separately and installs with `pi install -l`, so they're declared in `.pi/settings.json`. Every package runs code, so each tier asks first.
7. **Project files:** sets up git, `.pi/check` (detected from package.json, Cargo, Go or Python), a starter `.pi/AGENTS.md` if there's none, the agent-rules section in `.pi/AGENTS.md` (replaced on re-runs, the rest of the file untouched), and `.gitignore`. pi reads `.pi/AGENTS.md` instead of the root `AGENTS.md`/`CLAUDE.md`, which other harnesses use; setup never edits those.

Every config file it changes is backed up first (`<file>.backup-<timestamp>`), and it's safe to re-run. `--dry-run` asks the same questions but writes nothing.

To install pieces by hand instead, `./scripts/install.sh all <project>` installs the skills, rules, extensions and MCP config into that project, and `./scripts/install.sh packages <tier> <project>` installs one tier (`core`, `tokens`, `ondemand`, `tuning`, `cloud`, `ab`). [config/models.local.example.json](config/models.local.example.json) and [config/settings.json](config/settings.json) are examples you can copy into a project's `.pi/` (gameplan Phase 0–1).

## Skills

Skills are installed per project in `.pi/skills/`. To make one available everywhere, run `/skills-global` in pi and pick it (or all of them); it's copied to `~/.pi/agent/skills/`. `/skills-global handoff resume` copies those two directly.

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

`scripts/setup.sh` has been tested end to end in throwaway folders against a mock model server, in all four languages. The skills and the quality gate haven't been run inside pi yet, and several config details still need checking against pi's schemas. [docs/research.md](docs/research.md) lists them under "Not verified".
