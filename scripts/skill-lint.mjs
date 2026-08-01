#!/usr/bin/env node
// Structural + safety lint for the seo-god skill. Exit 1 on any violation.
import { readFileSync, readdirSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { execSync } from "node:child_process";

const self = fileURLToPath(import.meta.url);
const root = join(dirname(self), "..");
const fail = [];
const read = (p) => readFileSync(join(root, p), "utf8");

// 1. Forbidden strings (operator-specific data must never ship)
const FORBIDDEN = [
  /AAG[A-Za-z0-9_-]{20,}/,   // bot token shape
  /C:\\Users\\/,             // a local Windows path
  /DATAFORSEO_API_KEY=\S+/,  // a filled-in key
];

// Private guards stay OUT of the public repo: one regex per line, # comments allowed,
// loaded from the gitignored .seo-god/lint-extra.txt when a maintainer has one.
const extra = join(root, ".seo-god", "lint-extra.txt");
if (existsSync(extra)) {
  for (const line of readFileSync(extra, "utf8").split("\n")) {
    const src = line.trim();
    if (!src || src.startsWith("#")) continue;
    try { FORBIDDEN.push(new RegExp(src)); } catch { fail.push(`.seo-god/lint-extra.txt: bad regex ${src}`); }
  }
}

const scan = (dir) => {
  for (const e of readdirSync(join(root, dir), { withFileTypes: true })) {
    const rel = join(dir, e.name);
    if (e.isDirectory()) { if (!["node_modules", ".git", ".seo-god"].includes(e.name)) scan(rel); continue; }
    if (!/\.(md|mjs|sh|ps1|ya?ml|json)$/.test(e.name)) continue;
    if (join(root, rel) === self) continue; // the rule file itself is not a scan target
    const body = readFileSync(join(root, rel), "utf8");
    for (const rx of FORBIDDEN) if (rx.test(body)) fail.push(`${rel}: forbidden pattern ${rx}`);
  }
};
scan(".");

// 2. SKILL.md exists, <= 200 lines, and every references/*.md it names exists (and vice versa)
if (!existsSync(join(root, "SKILL.md"))) fail.push("SKILL.md missing");
else {
  const skill = read("SKILL.md");
  if (skill.split("\n").length > 200) fail.push("SKILL.md over 200 lines");
  const named = [...skill.matchAll(/references\/([a-z-]+\.md)/g)].map((m) => m[1]);
  const onDisk = existsSync(join(root, "references")) ? readdirSync(join(root, "references")).filter((f) => f.endsWith(".md")) : [];
  for (const n of new Set(named)) if (!onDisk.includes(n)) fail.push(`SKILL.md names missing file references/${n}`);
  for (const f of onDisk) if (!named.includes(f)) fail.push(`references/${f} never routed from SKILL.md`);
}

// 3. Shell scripts parse
for (const f of existsSync(join(root, "scripts")) ? readdirSync(join(root, "scripts")) : []) {
  try {
    if (f.endsWith(".sh")) execSync(`bash -n scripts/${f}`, { cwd: root });
    if (f.endsWith(".ps1")) execSync(`pwsh -NoProfile -Command "$errs=$null; [void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'scripts/${f}').Path,[ref]$null,[ref]$errs); if($errs.Count){exit 1}"`, { cwd: root });
  } catch { fail.push(`scripts/${f}: does not parse`); }
}

if (fail.length) { console.error(fail.join("\n")); process.exit(1); }
console.log("skill-lint: clean");
