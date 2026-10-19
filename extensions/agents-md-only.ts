import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { basename } from "node:path";

// pi loads both AGENTS.md and CLAUDE.md as context files. Keep only the AGENTS.md family
// (AGENTS.md, AGENTS.override.md) so project rules live in one place.
export default function (pi: ExtensionAPI) {
  pi.on("before_agent_start", (event) => {
    const files = event.systemPromptOptions.contextFiles;
    for (let i = files.length - 1; i >= 0; i--) {
      if (basename(files[i].path).toLowerCase() === "claude.md") files.splice(i, 1);
    }
  });
}
