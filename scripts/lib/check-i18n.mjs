// Checks the message catalogs: every key used by setup.sh/install.sh exists, every catalog has
// the same keys as en.txt, and each translation keeps the same number of %s placeholders.
//   node scripts/lib/check-i18n.mjs
import fs from "node:fs";
import path from "node:path";

const here = path.dirname(new URL(import.meta.url).pathname);
const scripts = ["../setup.sh", "../install.sh"].map((f) => path.join(here, f));
const langDir = path.join(here, "lang");

function parse(file) {
  const map = new Map();
  for (const line of fs.readFileSync(file, "utf8").split("\n")) {
    if (!line || line.startsWith("#")) continue;
    const i = line.indexOf("=");
    map.set(line.slice(0, i), line.slice(i + 1));
  }
  return map;
}

const placeholders = (s) => (s.replace(/%%/g, "").match(/%s/g) || []).length;
const used = new Set(scripts.flatMap((f) => [...fs.readFileSync(f, "utf8").matchAll(/(?:\$\(|[;{|&)]\s*|^\s*)(?:t|say) ([a-z][a-z0-9_]*)/gm)].map((m) => m[1])));
const en = parse(path.join(langDir, "en.txt"));
const problems = [];

for (const key of used) if (!en.has(key)) problems.push(`en: missing key used in scripts: ${key}`);
for (const key of en.keys()) if (!used.has(key)) problems.push(`en: unused key: ${key}`);

for (const file of fs.readdirSync(langDir).filter((f) => f.endsWith(".txt") && f !== "en.txt")) {
  const code = path.basename(file, ".txt");
  const cat = parse(path.join(langDir, file));
  for (const [key, text] of en) {
    if (!cat.has(key)) problems.push(`${code}: missing ${key}`);
    else if (placeholders(cat.get(key)) !== placeholders(text)) problems.push(`${code}: ${key} has ${placeholders(cat.get(key))} %s, en has ${placeholders(text)}`);
  }
  for (const key of cat.keys()) if (!en.has(key)) problems.push(`${code}: extra key ${key}`);
}

if (problems.length) {
  console.error(problems.join("\n"));
  process.exit(1);
}
console.log(`ok: ${used.size} keys, catalogs consistent`);
