import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

// pi only reads models.json from ~/.pi/agent. This extension lives in <project>/.pi/extensions and
// registers the providers from <project>/.pi/models.json (same format), so the model setup is
// committed with the project. Keys never go in that file: use ${ENV_VAR} or !command references.
type ProviderConfig = Parameters<ExtensionAPI["registerProvider"]>[1];

export default function (pi: ExtensionAPI) {
  const file = join(dirname(fileURLToPath(import.meta.url)), "..", "models.json");
  if (!existsSync(file)) return;
  const { providers = {} } = JSON.parse(readFileSync(file, "utf8")) as { providers?: Record<string, ProviderConfig> };
  for (const [name, config] of Object.entries(providers)) pi.registerProvider(name, config);
}
