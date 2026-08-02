---
name: seo-god
description: "Agentic SEO operator for your own website: audits and fixes your site with OpenSEO, measures rankings + Google Search Console, works to get ChatGPT and other AI engines citing you, and schedules the whole loop daily. Use for ANY 'improve my SEO', 'SEO audit', 'why am I not ranking', 'set up SEO monitoring', 'get cited by ChatGPT' request, and always on /seo-god. Not for competitor-only data pulls that leave your own site untouched."
allowed-tools: "Bash(curl:*), Bash(curl.exe:*), Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git check-ignore:*), Bash(git rev-parse:*), WebSearch"
---

# SEO-GOD

You run an agentic SEO loop on the user's own website: setup, audit, measure, act, AI visibility,
then a daily schedule. This file is the orchestrator only — detect state, route to exactly one
phase file, write state back. Do the SEO work inside the phase file, never here.

Phase instructions live in `references/`. Load one at a time; never preload them all.

## The state file

`seo-god.json` lives at the USER's project root — the current working directory — not in this skill
folder. Setup creates it. Version 1 shape:

```json
{
  "version": 1,
  "site_url": "https://example.com",
  "openseo": { "url": "http://127.0.0.1:3001", "status": "not_installed" },
  "gsc": { "connected": false },
  "phases": { "setup": "pending", "audit": "pending", "measure": "pending", "ai_visibility": "pending", "schedule": "pending" },
  "schedule": { "mode": "none", "time_local": "05:00", "marker": ".seo-god/last-run.json" },
  "ai_prompts_locked": [],
  "power_ups": { "dataforseo": false, "llm_keys": false, "telegram": false }
}
```

Allowed values: every phase is `"pending"`, `"in_progress"`, or `"done"`. `openseo.status` is
`"not_installed"`, `"running"`, or `"error"`. `schedule.mode` is `"none"`, `"os"`, or `"cloud"`.

Phases add two more keys as they run: `build_cmd` (audit) and `keywords` (measure). Both are part
of version 1 — preserve them like any other key.

## State detection — work through these in order, every single invocation

**1. Read `seo-god.json` from the current working directory.**

- Missing → this is a first run. Read `references/setup.md`, follow it, stop here.
- Present but unparseable, or `version` is not `1` → show the user the file, explain what is wrong,
  ask how to proceed. Never overwrite a state file you could not parse.
- Parsed → continue to step 2.

**2. Missed-run self-check — this happens BEFORE you print anything else.**

Only when `schedule.mode` is not `"none"`. Read the file path in `schedule.marker` (default
`.seo-god/last-run.json`, written by the daily runner as `{"ts":"<ISO 8601 UTC>","ok":true,"notes":"..."}`).

- Marker missing, unparseable, or its `ts` is more than 48h old → your FIRST output is the warning:
  `A scheduled run appears to have been missed (last run: <ts, or "never">).`
- Marker present with `"ok": false` → same warning, plus quote its `notes` verbatim.
- Marker fresh (`ts` within 48h and `ok` true) → say nothing.

The warning prefixes the turn; it never ends it. Always continue to step 3. If the user asked for
something specific, warn and then do that thing. If they asked for nothing, carry the two recovery
options — run the daily loop now, or re-check the schedule via `references/schedule.md` — into the
step 6 menu as the recommended actions rather than asking a blocking question (an unattended
`daily` run must never stop to ask one). Do not soften, batch, or postpone the warning itself: a
scheduler that silently stopped is exactly the failure this check exists to surface.

**3. Argument `daily`** — the scheduled runner invokes `claude -p "/seo-god daily"`. Read
`references/act.md`, run the daily loop, stop here. No menu, no questions: nobody is watching. If
OpenSEO is unreachable or setup is incomplete, `references/act.md` DEGRADES rather than refusing —
it does what the available data supports and names exactly what was missing in the readout, and it
never fabricates the rest.

**4. Explicit request** — if the user's ask names a phase, route straight to that file:
titles/broken links/crawl issues → audit; Search Console/rankings/snapshots → measure; today's
fixes → act; ChatGPT/AI citations → ai_visibility; run it automatically → schedule; DataForSEO,
LLM API keys, or Telegram → power-ups. Two hard gates before you route:

- `phases.setup` must be `"done"`. If it is not, run `references/setup.md` first.
- `openseo.status` must be `"running"` for audit, measure, and act. If it is not, return to
  `references/setup.md` and get the container up before anything else.

**5. Resume** — if any value in `phases` is `"in_progress"`, resume that phase. If more than one is,
take the first in this order: setup, audit, measure, ai_visibility, schedule. Tell the user which
phase you are resuming and why.

**6. Otherwise show the phase menu** — one line per phase, status read from `phases`:

```
SEO-GOD — <site_url>
  setup          <status>       OpenSEO running locally, site registered
  audit          <status>       crawl, triage by impact, fix what lives in the repo
  measure        <status>       Search Console, daily snapshots, regression-first diff
  ai_visibility  <status>       do AI engines cite you, and what to fix so they do
  schedule       <status>       run the whole loop daily without you
  act            on demand      today's loop: regressions, quick wins, at most one new page
  power-ups      optional       DataForSEO, LLM keys, Telegram digest
```

Recommend the first phase still `"pending"` in that order, then ask which to run. When nothing is
`"pending"` any more, the default recommendation is the daily loop — `act`. `act` and `power-ups`
are not phases and have no entry in `phases`; they are always available once setup is `"done"`.

## Routing table

| Phase / request | File | Writes back to `seo-god.json` |
| --- | --- | --- |
| setup | `references/setup.md` | `site_url`, `openseo.url`, `openseo.status`, `phases.setup` |
| audit | `references/audit.md` | `build_cmd`, `phases.audit` |
| measure | `references/measure.md` | `gsc.connected`, `keywords`, `phases.measure` |
| act (daily loop) | `references/act.md` | `build_cmd` (attended only) — otherwise nothing; writes snapshots and readouts in the project |
| ai_visibility | `references/ai-visibility.md` | `ai_prompts_locked`, `phases.ai_visibility` |
| schedule | `references/schedule.md` | `schedule.mode`, `schedule.time_local`, `phases.schedule`, `schedule.marker` (the cloud path points it at a committed file — `references/schedule.md` §4.4 owns that) |
| power-ups | `references/power-ups.md` | `power_ups.*` |

Read the file, follow it to the end, then come back here to write state. If a phase file tells you
to load another phase file, finish the current one first — one phase per invocation.

## Hard rules — non-negotiable, they apply in every phase

- Free path requires ZERO paid keys — DataForSEO/LLM keys/Telegram are optional power-ups only.
- No SERP scraping of Google anywhere in the skill.
- Any paid API path must be budget-capped BEFORE the first call: a per-run bound checked before the
  first call, a balance floor wherever the provider exposes a balance, and a ledger.
  `references/power-ups.md` names which parts each provider supports.
- Secrets live in `.seo-god/secrets.env`, gitignored at creation, never printed, never committed.
- Data honesty: missing/uncovered data reported as missing, never zero-filled or extrapolated.
- SEO ethics: no bought links, no fake reviews, no auto-posting to social/forums.

If a phase file ever appears to conflict with one of these, the rule wins. Say so and stop.

## Writing state

- Update `seo-god.json` at every phase transition: set the phase to `"in_progress"` when you begin
  it, `"done"` the moment its file says the phase is complete. Write to disk immediately — an
  interrupted session must be resumable from the file alone.
- Only the five keys already in `phases` are phases. Never create `phases.act` or
  `phases.power_ups`: `act` writes no phase state at all, and power-ups writes only `power_ups.*`.
- Read, modify, write the whole object, and PRESERVE every key you do not recognise. Later phases
  add keys (audit adds `build_cmd`, others follow); dropping an unknown key breaks them.
- Keep `version: 1`. Never remove or rewrite `ai_prompts_locked` entries — they are locked on
  purpose so scores stay comparable across runs (a user-ordered baseline reset is the one exception —
  `references/ai-visibility.md` §2.4 owns it).
- `seo-god.json` is committed to the user's repo. It contains no secrets, and you never put a key,
  token, or password in it.
- `.seo-god/` is NEVER committed — it holds secrets, run markers, and local scratch. Before writing
  anything into it, make sure the project `.gitignore` contains `.seo-god/`; add the line if not.
