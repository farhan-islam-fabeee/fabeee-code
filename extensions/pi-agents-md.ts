import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

// pi reads AGENTS.md / CLAUDE.md from the project folder and its parents, the same files other
// harnesses read. This extension makes pi use <project>/.pi/AGENTS.md instead: it drops those
// project files from the context and adds .pi/AGENTS.md. pi's own global file in ~/.pi/agent stays.
export default function (pi: ExtensionAPI) {
  const file = join(dirname(fileURLToPath(import.meta.url)), "..", "AGENTS.md");
  const agentDir = resolve(process.env.PI_CODING_AGENT_DIR || join(homedir(), ".pi", "agent"));
  pi.on("before_agent_start", (event) => {
    const files = event.systemPromptOptions.contextFiles;
    for (let i = files.length - 1; i >= 0; i--) {
      if (!resolve(files[i].path).startsWith(agentDir + sep)) files.splice(i, 1);
    }
    if (existsSync(file)) files.push({ path: file, content: readFileSync(file, "utf8") });
  });
}
