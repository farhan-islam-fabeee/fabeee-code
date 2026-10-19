// JSON and project helpers for setup.sh. Values come from argv and PK_* env vars so
// nothing needs shell quoting. Writes back up the original file once per run.
//
//   upsert-provider <models.json>            provider + optional model from PK_* env
//   has-provider <models.json> <id>          exit 0 if the provider exists
//   list-models <baseUrl>                    GET <baseUrl>/models (key in FABEEE_CODE_KEY), one id per line
//   json-get <file> <dotted.path>            print a value, exit 1 if missing
//   apply-settings <settings.json> preview|write   pi settings from PK_* env
//   key-refs <models.json>                   print "<provider>\t<apiKey>" for each provider with a key
//   merge-mcp <mcp.json> <kit mcp.json> <server...>  add the named servers if missing
//   detect-check <dir>                       suggest a fast check command
//   agents-template <dir> <check>            print a starter project AGENTS.md
import fs from "node:fs";
import path from "node:path";

const DRY = process.env.FABEEE_CODE_DRY_RUN === "1";
const STAMP = process.env.FABEEE_CODE_STAMP || String(Date.now());
const env = (name, fallback = "") => process.env[name] ?? fallback;

// Messages printed to the user, in the language setup.sh chose (FABEEE_CODE_LANG).
const MESSAGES = {
  en: { unchanged: "unchanged", dryWrite: "[dry-run] would write", backup: "backup", wrote: "wrote",
        noChanges: "(no changes)", unset: "(unset)", keptMcp: "kept existing MCP server", addedMcp: "added MCP server" },
  ja: { unchanged: "変更なし", dryWrite: "[ドライラン] 書き込む内容", backup: "バックアップ", wrote: "書き込みました",
        noChanges: "（変更なし）", unset: "（未設定）", keptMcp: "既存の MCP サーバーを維持", addedMcp: "MCP サーバーを追加" },
  ko: { unchanged: "변경 없음", dryWrite: "[드라이 런] 쓸 내용", backup: "백업", wrote: "저장함",
        noChanges: "(변경 없음)", unset: "(설정 안 됨)", keptMcp: "기존 MCP 서버 유지", addedMcp: "MCP 서버 추가" },
  bn: { unchanged: "অপরিবর্তিত", dryWrite: "[ড্রাই রান] যা লেখা হবে", backup: "ব্যাকআপ", wrote: "লেখা হয়েছে",
        noChanges: "(কোনো পরিবর্তন নেই)", unset: "(সেট করা নেই)", keptMcp: "বিদ্যমান MCP সার্ভার রাখা হয়েছে", addedMcp: "MCP সার্ভার যোগ করা হয়েছে" },
};
const msg = (key) => (MESSAGES[env("FABEEE_CODE_LANG")] || MESSAGES.en)[key];

const isObj = (v) => v !== null && typeof v === "object" && !Array.isArray(v);

function readJson(file) {
  if (!fs.existsSync(file)) return {};
  const text = fs.readFileSync(file, "utf8").trim();
  return text ? JSON.parse(text) : {};
}

function writeJson(file, data) {
  const text = JSON.stringify(data, null, 2) + "\n";
  if (fs.existsSync(file) && fs.readFileSync(file, "utf8") === text) {
    console.log(`  ${msg("unchanged")}: ${file}`);
    return;
  }
  if (DRY) {
    console.log(`  ${msg("dryWrite")}: ${file}\n${text}`);
    return;
  }
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const backup = `${file}.backup-${STAMP}`;
  // Only the first write in a run backs up, so the backup is always the pre-setup file.
  if (fs.existsSync(file) && !fs.existsSync(backup)) {
    fs.copyFileSync(file, backup);
    console.log(`  ${msg("backup")}: ${backup}`);
  }
  fs.writeFileSync(file, text);
  console.log(`  ${msg("wrote")}: ${file}`);
}

function deepMerge(target, src) {
  const out = isObj(target) ? { ...target } : {};
  for (const [k, v] of Object.entries(src)) {
    out[k] = isObj(v) && isObj(out[k]) ? deepMerge(out[k], v) : v;
  }
  return out;
}

function withSchema(obj, schema) {
  return obj.$schema ? obj : { $schema: schema, ...obj };
}

function upsertProvider(file) {
  const id = env("PK_ID");
  if (!id) throw new Error("PK_ID is required");
  const data = withSchema(readJson(file), "https://pi.dev/schemas/models.schema.json");
  data.providers = data.providers || {};
  const provider = { ...(data.providers[id] || {}) };
  if (env("PK_BASE_URL")) {
    provider.baseUrl = env("PK_BASE_URL");
    provider.api = env("PK_API", "openai-completions");
  }
  if (env("PK_API_KEY")) provider.apiKey = env("PK_API_KEY");

  const modelId = env("PK_MODEL_ID");
  if (modelId) {
    const [input, output, cacheRead, cacheWrite] = env("PK_COST", "0,0,0,0").split(",").map(Number);
    const model = {
      id: modelId,
      name: env("PK_MODEL_NAME", modelId),
      reasoning: env("PK_REASONING") === "true",
      input: env("PK_IMAGES") === "1" ? ["text", "image"] : ["text"],
      contextWindow: Number(env("PK_CONTEXT", "32768")),
      maxTokens: Number(env("PK_MAX_TOKENS", "8192")),
      cost: { input, output, cacheRead, cacheWrite },
    };
    const ttl = Number(env("PK_CACHE_TTL", "0"));
    if (ttl > 0) model.promptCache = { short: ttl };
    const models = (provider.models || []).filter((m) => m.id !== modelId);
    provider.models = [...models, model];
  }
  data.providers[id] = provider;
  writeJson(file, data);
}

async function listModels(baseUrl) {
  const headers = {};
  if (env("FABEEE_CODE_KEY")) headers.Authorization = `Bearer ${env("FABEEE_CODE_KEY")}`;
  const res = await fetch(`${baseUrl.replace(/\/$/, "")}/models`, { headers, signal: AbortSignal.timeout(5000) });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const body = await res.json();
  const ids = (body.data || body.models || []).map((m) => m.id || m.name).filter(Boolean);
  if (!ids.length) throw new Error("no models listed");
  console.log(ids.join("\n"));
}

function jsonGet(file, dotted) {
  let v = readJson(file);
  for (const key of dotted.split(".")) v = isObj(v) ? v[key] : undefined;
  if (v === undefined || v === null) process.exit(1);
  console.log(typeof v === "object" ? JSON.stringify(v) : String(v));
}

function settingsPatch() {
  const patch = {};
  const def = env("PK_DEFAULT");
  if (def) {
    const i = def.indexOf("/");
    patch.defaultProvider = def.slice(0, i);
    patch.defaultModel = def.slice(i + 1);
  }
  Object.assign(patch, {
    defaultThinkingLevel: "low",
    defaultTools: ["read", "bash", "edit", "write", "+codemode"],
    codemode: { mode: "on", inlineBudget: 1500 },
    retry: { enabled: true, maxRetries: 2, provider: { maxRetries: 0 } },
    showCacheMissNotices: true,
  });
  const enabled = env("PK_ENABLED_MODELS");
  if (enabled) patch.enabledModels = enabled.split(",");
  const local = env("PK_LOCAL_MODEL");
  if (local) {
    const ctx = Number(env("PK_LOCAL_CTX", "32768"));
    patch.httpIdleTimeoutMs = 600000;
    patch.compaction = {
      enabled: true,
      modelOverrides: {
        [local]: {
          reserveTokens: Math.min(16384, Math.floor(ctx / 4)),
          keepRecentTokens: Math.min(20000, Math.floor(ctx * 0.3)),
        },
      },
    };
  }
  return patch;
}

function flatten(obj, prefix = "") {
  return Object.entries(obj).flatMap(([k, v]) =>
    isObj(v) ? flatten(v, `${prefix}${k}.`) : [[`${prefix}${k}`, JSON.stringify(v)]]);
}

function applySettings(file, mode) {
  const current = readJson(file);
  const next = withSchema(deepMerge(current, settingsPatch()), "https://pi.dev/schemas/settings.schema.json");
  if (mode === "preview") {
    const before = new Map(flatten(current));
    const changes = flatten(next).filter(([k, v]) => k !== "$schema" && before.get(k) !== v);
    if (!changes.length) console.log(`  ${msg("noChanges")}`);
    for (const [k, v] of changes) console.log(`  ${k}: ${before.get(k) ?? msg("unset")} -> ${v}`);
    return;
  }
  writeJson(file, next);
}

function keyRefs(file) {
  for (const [id, p] of Object.entries(readJson(file).providers || {})) {
    if (p.apiKey) console.log(`${id}\t${p.apiKey}`);
  }
}

function mergeMcp(file, kitFile, names) {
  const data = readJson(file);
  const kit = readJson(kitFile).mcpServers || {};
  data.mcpServers = data.mcpServers || {};
  for (const name of names) {
    if (data.mcpServers[name]) console.log(`  ${msg("keptMcp")}: ${name}`);
    else if (kit[name]) {
      data.mcpServers[name] = kit[name];
      console.log(`  ${msg("addedMcp")}: ${name}`);
    }
  }
  writeJson(file, data);
}

function onPath(bin) {
  return (process.env.PATH || "").split(":").some((dir) => {
    try {
      fs.accessSync(path.join(dir, bin), fs.constants.X_OK);
      return true;
    } catch {
      return false;
    }
  });
}

function nodeProject(dir) {
  const file = path.join(dir, "package.json");
  if (!fs.existsSync(file)) return null;
  const scripts = readJson(file).scripts || {};
  const has = (f) => fs.existsSync(path.join(dir, f));
  const pm = has("pnpm-lock.yaml") ? "pnpm" : has("yarn.lock") ? "yarn" : has("bun.lock") || has("bun.lockb") ? "bun" : "npm";
  const run = (s) => ({ npm: `npm run -s ${s}`, pnpm: `pnpm -s run ${s}`, yarn: `yarn -s ${s}`, bun: `bun run ${s}` })[pm];
  return { scripts, pm, run, tsconfig: has("tsconfig.json") };
}

function detectCheck(dir) {
  const has = (f) => fs.existsSync(path.join(dir, f));
  const js = nodeProject(dir);
  if (js) {
    const type = ["typecheck", "type-check", "check-types", "tsc", "check"].find((s) => js.scripts[s]);
    const parts = [];
    if (type) parts.push(js.run(type));
    else if (js.tsconfig) parts.push("npx tsc --noEmit");
    if (js.scripts.lint) parts.push(js.run("lint"));
    return parts.join(" && ");
  }
  if (has("Cargo.toml")) return "cargo check -q";
  if (has("go.mod")) return "go vet ./...";
  if (has("pyproject.toml") || has("setup.py") || has("requirements.txt")) {
    const parts = [];
    if (onPath("ruff")) parts.push("ruff check .");
    if (onPath("mypy") && (has("mypy.ini") || /\[tool\.mypy\]/.test(has("pyproject.toml") ? fs.readFileSync(path.join(dir, "pyproject.toml"), "utf8") : ""))) parts.push("mypy .");
    return parts.length ? parts.join(" && ") : "python3 -m compileall -q .";
  }
  return "";
}

function agentsTemplate(dir, check) {
  const has = (f) => fs.existsSync(path.join(dir, f));
  const cmds = [];
  if (check) cmds.push(`- Fast check: \`${check}\``);
  const js = nodeProject(dir);
  if (js) {
    for (const s of ["test", "build", "dev", "start"]) if (js.scripts[s]) cmds.push(`- ${s}: \`${js.run(s)}\``);
  } else if (has("Cargo.toml")) {
    cmds.push("- test: `cargo test`", "- build: `cargo build`", "- run: `cargo run`");
  } else if (has("go.mod")) {
    cmds.push("- test: `go test ./...`", "- build: `go build ./...`");
  } else if (has("pyproject.toml") || has("requirements.txt")) {
    cmds.push(`- test: \`${onPath("pytest") ? "pytest -q" : "TODO"}\``);
  }
  if (!cmds.some((c) => c.startsWith("- test"))) cmds.push("- test (single file): TODO");
  console.log(`# ${path.basename(dir)}

## Commands
${cmds.join("\n")}

## Layout
TODO: one line per top-level directory. Run \`/skill:project-map\` to generate \`.pi/MAP.md\`.

## Conventions
TODO: naming, error handling, where tests live, anything the agent keeps getting wrong.
`);
}

const [cmd, ...args] = process.argv.slice(2);
try {
  switch (cmd) {
    case "upsert-provider": upsertProvider(args[0]); break;
    case "has-provider": process.exit(readJson(args[0]).providers?.[args[1]] ? 0 : 1);
    case "list-models": await listModels(args[0]); break;
    case "json-get": jsonGet(args[0], args[1]); break;
    case "apply-settings": applySettings(args[0], args[1]); break;
    case "key-refs": keyRefs(args[0]); break;
    case "merge-mcp": mergeMcp(args[0], args[1], args.slice(2)); break;
    case "detect-check": console.log(detectCheck(args[0])); break;
    case "agents-template": agentsTemplate(args[0], args[1] || ""); break;
    default: throw new Error(`unknown command: ${cmd}`);
  }
} catch (err) {
  console.error(`pi-config: ${err.message}`);
  process.exit(1);
}
