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
