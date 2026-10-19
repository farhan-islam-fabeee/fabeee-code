import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { cpSync, existsSync, mkdirSync, readdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

// /skills-global [name ...]: copy skills from this project's .agents/skills/ to ~/.agents/skills/
// so they are available in every project. With no names, pick one (or all) from a list.
const ALL = "All skills";

export default function (pi: ExtensionAPI) {
  pi.registerCommand("skills-global", {
    description: "Copy project skills (.agents/skills) to ~/.agents/skills",
    handler: async (args, ctx) => {
      const from = join(ctx.cwd, ".agents", "skills");
      const to = join(homedir(), ".agents", "skills");
      const available = existsSync(from)
        ? readdirSync(from, { withFileTypes: true })
            .filter((d) => d.isDirectory() && existsSync(join(from, d.name, "SKILL.md")))
            .map((d) => d.name)
        : [];
      if (!available.length) {
        ctx.ui.notify(`No skills in ${from}`, "warning");
        return;
      }

      let names = args.trim().split(/\s+/).filter(Boolean);
      if (!names.length) {
        const pick = await ctx.ui.select("Copy which skill to ~/.agents/skills?", [ALL, ...available]);
        if (!pick) return;
        names = pick === ALL ? available : [pick];
      }
      const unknown = names.filter((n) => !available.includes(n));
      if (unknown.length) {
        ctx.ui.notify(`Not in this project: ${unknown.join(", ")}. Available: ${available.join(", ")}`, "error");
        return;
      }

      const existing = names.filter((n) => existsSync(join(to, n)));
      if (existing.length && !(await ctx.ui.confirm("Overwrite global skills?", existing.join(", ")))) return;

      mkdirSync(to, { recursive: true });
      for (const n of names) cpSync(join(from, n), join(to, n), { recursive: true, force: true });
      ctx.ui.notify(`Copied to ${to}: ${names.join(", ")}`, "info");
    },
  });
}
