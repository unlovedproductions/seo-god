# SEO-GOD — shareable agentic SEO skill (design)

2026-08-01 · Approved decisions from brainstorm with Aria

## Goal

A public Claude Code skill Aria's audience installs in one line. It turns Claude Code into an
agentic SEO operator for THEIR site using OpenSEO + the methods proven on a production site:
audit → measure → act → AI visibility → scheduled daily runs. Free path works end to end;
paid services are optional power-ups. Distributed as a public GitHub repo; a companion setup
guide lives on the author's site.

## Audience assumptions (decision: free-first)

- Has: a website (any stack; repo access preferred), Claude Code, willingness to install Docker.
- Does NOT have (must never be required): DataForSEO key, LLM API keys, GSC service accounts,
  claude.ai routine access, a specific OS.
- Skill must run on Windows / macOS / Linux. All OS-specific work (scheduler, paths) is branched.

## Architecture (decision: orchestrator + phase references)

```
seo-god/                      (public repo == the skill folder)
  SKILL.md                    thin orchestrator: state detection + routing only
  references/
    setup.md                  OpenSEO boot (Docker, local_noauth), site registration
    audit.md                  crawl + issue triage + verified fixes
    measure.md                GSC connect walkthrough, snapshots, diff, regression-first review
    act.md                    the daily agentic loop (fix regressions, quick wins, answer-first content)
    ai-visibility.md          locked prompt set, citation probing, "be the answer" playbook
    schedule.md               OS-native scheduler OR cloud routine (asks the user)
    power-ups.md              optional: DataForSEO (budget-capped), LLM keys, Telegram digest
  scripts/
    daily-run.(ps1|sh)        probe OpenSEO /api/health → claude -p "/seo-god daily" → run marker
    install-schedule.(ps1|sh) Task Scheduler / launchd / cron creation, hardened
  README.md                   audience-facing; built with beautify-github-readme
```

- `SKILL.md` reads `seo-god.json` in the user's project (created on first run): site URL,
  OpenSEO status, GSC status, chosen schedule mode, completed phases. Nothing in state →
  first-time setup; partial → resume; complete → phase menu / daily loop. Re-invocations
  always know where the user left off.
- Each reference file is self-contained and loaded only when its phase runs (progressive
  disclosure — keeps per-run context small).

## The five phases

1. **SETUP** (free): boot OpenSEO via Docker, register the user's site over MCP, and create
   `seo-god.json` in their project root. Every first run does this pass before any of the rest,
   and every later phase gates on `phases.setup` being `"done"`.
2. **AUDIT** (free): crawl with the local OpenSEO container (AUTH_MODE=local_noauth, embedded SQLite; its
   in-container cron never fires — host drives it, learned in production). Crawl the user's
   site, triage issues by impact, fix what lives in their repo (titles, metas, broken
   links, thin content) with verified edits and the user's own build/typecheck as the gate.
3. **MEASURE** (free): walk the user through GSC OAuth connect (every gotcha documented);
   degrade gracefully to OpenSEO rank tracking + crawl deltas if they skip it. Daily
   snapshot to `dist/seo/snapshots/<date>.json` in their repo; run-over-run diff; review
   order is regression-first (regressions > quick wins pos 4-15 > new queries) — the
   production REVIEW step, genericized.
4. **AI VISIBILITY** (free core, paid upgrade): lock a 10-prompt set for the user's niche on
   first run (never edited afterward — comparability). Free-path probing = Claude Code's
   WebSearch tool per prompt, scoring whether the user's domain appears in results/answers;
   report a search-visibility score on the locked prompt set (results-page proxy) vs named
   competitors + the "be the answer" playbook (answer-first pages, directories, consistent
   naming). LLM API keys upgrade probing to multi-model measurement (ask each model directly,
   metric-v2 style).
5. **SCHEDULE** (decision: skill ASKS the user which mode):
   - **OS-native**: `install-schedule` creates Task Scheduler / launchd / cron for
     `daily-run` — hardened from day one: wake-from-sleep, catch-up on missed starts, run
     on battery, execution time limit (the 0x800710E0 lesson), plus a "did it actually run"
     self-check that surfaces missed runs the next time the user opens Claude Code.
   - **Cloud routine**: for users with claude.ai routine access + a GitHub repo — a
     genericized version of the production monitor prompt (consume snapshot, act, readout);
     points at the schedule plugin flow. Cloud can't reach their local OpenSEO — the skill
     says so plainly and scopes the routine to repo-visible data.

**ACT** (free) — **the daily loop, and deliberately not a phase.** It carries no entry in
`phases`, is available on demand once setup is done, and is what the schedule actually runs: read
today's diff, fix regressions first, chase quick wins, produce answer-first content (40-70w TL;DR
up top, question-shaped FAQs, numbered steps) for the gaps the data shows. Hard honesty laws (see
Safety rails).

## Power-ups (offered contextually, never required)

- **DataForSEO** (~$50 min top-up): real volume/CPC/difficulty + backlinks. Ships with the
  production budget-guard pattern MANDATORY: per-run spend cap, balance floor auto-disable,
  spend ledger. No uncapped API loops, ever.
- **LLM API keys**: multi-model AI-citation measurement (metric-v2 style).
- **Telegram digest**: bot-token + pairing walkthrough (generalized from a production bot
  setup); daily run ends with a plain-text digest.

## Safety rails (non-negotiable, encoded in every phase file)

- Secrets: env file created by the skill, gitignored at creation, never printed, never
  committed. No secrets in schedule definitions or routine prompts beyond what the platform
  isolates.
- Data honesty: missing/uncovered data reported as missing — never zero-filled, never
  extrapolated. Partial coverage labeled.
- SEO ethics: no bought links, no fake reviews, no auto-posting to social/forums, no
  fabricated claims on generated pages. Directory submissions are owner-driven.
- Money: any paid API call path is budget-capped before the first call.
- Scheduled jobs ship with their own failure visibility (self-check or deadman-style note).

## README + branding

- README.md built with the **beautify-github-readme** skill (Aria requirement): hero,
  badges, section headers, cohesive visual story. Install = one line. A proof section states
  the provenance and points at the in-repo smoke and eval reports — no outbound product links.
- In-skill instruction text stays neutral/technical (it's for Claude, not the audience).
  The companion setup guide on the author's site carries the author's voice instead — launch
  collateral, out of scope for the skill build.

## Out of scope v1

Directory/link-kit module, DataForSEO-required features beyond the capped power-up,
multi-site management, Windows-service style always-on daemons, SERP scraping of Google
(fragile + gray; the audience version measures via GSC/OpenSEO/AI probing instead).

## Success criteria

- Fresh machine (any OS) with Docker + Claude Code: `/seo-god` reaches a completed AUDIT on
  a real site in one sitting with zero paid keys.
- Daily scheduled run produces a snapshot + diff + readout without human input; a missed
  run is visible the next session.
- AI-visibility report produces a stable search-visibility score on the locked prompt set
  (results-page proxy) — never reported as a citation rate.
- No path exists where the skill spends money without an explicit user-set cap.

## Implementation notes

- Scaffold with **skill-creator** (structure, description tuning, evals); README via
  **beautify-github-readme**; repo under Aria's GitHub (public).
- Genericize from the production engine by REWRITING, not copying — the original production
  engine is a separate private codebase; only its patterns and lessons transfer.
- Next step after spec approval: **writing-plans** skill for the implementation plan.
