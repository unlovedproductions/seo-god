#!/usr/bin/env bash
# SEO-GOD daily runner — macOS / Linux (and Git Bash, where `claude` resolves on PATH).
#
# Run it FROM THE PROJECT ROOT: the directory that holds seo-god.json. The
# scheduler entry created by references/schedule.md sets that working directory.
#
# It probes the local OpenSEO container, hands the run to Claude Code
# (`/seo-god daily`), and ALWAYS leaves a run marker at .seo-god/last-run.json —
# the file SKILL.md's missed-run self-check reads:
#   {"ts":"<UTC ISO 8601>","ok":true|false,"notes":"<short>"}
# The marker is this script's alone; references/act.md never writes it.
#
# Requires: bash, the `claude` CLI. `curl` and `node` are optional — they serve
# only the readiness probe (node reads openseo.url out of seo-god.json), so a
# machine without them still runs the loop and says so in the marker notes.
#
# SEO_GOD_DRY_RUN=1 prints what would happen, writes an ok:true "dry-run"
# marker, and exits 0 — no network call, no Claude Code session.
#
# There is no per-run timeout here on purpose: the OS scheduler owns the
# execution time limit (references/schedule.md sets it).
set -euo pipefail

DRY="${SEO_GOD_DRY_RUN:-0}"
MARKER=".seo-god/last-run.json"
STEP="startup"
SUFFIX=""

mkdir -p .seo-god
# The snapshot directory is deliberately NOT pre-created here: measure.md
# section 5.1 resolves it per run and falls back to seo/snapshots/ when dist/ is
# gitignored, so an empty dist/seo/snapshots would point at the wrong history.

note() {
  printf '{"ts":"%s","ok":%s,"notes":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" > "$MARKER"
}
# Any unhandled failure — including a non-zero exit from claude — lands here.
trap 'note false "failed during $STEP (line $LINENO)"' ERR
# A scheduler that hits its execution-time limit kills the run mid-flight. Without
# this the marker would still hold the PREVIOUS run's ok:true and SKILL.md's
# self-check would never see the miss. Clearing ERR on the way out keeps this note
# from being overwritten by the killed command's own failure.
trap 'note false "interrupted during $STEP"; trap - ERR; exit 143' INT TERM
# Deliberate stops clear the trap first so the intended note is the one kept.
die() { trap - ERR; note false "$1"; exit 1; }

STEP="reading seo-god.json"
if [ ! -f seo-god.json ]; then
  echo "error: seo-god.json not found in $(pwd) — run this from the project root" >&2
  die "seo-god.json not found in the working directory"
fi

OPENSEO_URL=""
if command -v node >/dev/null 2>&1; then
  # The try/catch keeps node's status 0 for malformed JSON or a missing key: an
  # unreadable URL costs the probe, never the run.
  OPENSEO_URL="$(node -e 'try{const s=JSON.parse(require("fs").readFileSync("seo-god.json","utf8"));process.stdout.write(String((s.openseo&&s.openseo.url)||""))}catch(e){}')" || OPENSEO_URL=""
  [ -n "$OPENSEO_URL" ] || SUFFIX="openseo.url unreadable, probe skipped"
else
  SUFFIX="node not found, probe skipped"
fi
OPENSEO_URL="${OPENSEO_URL%/}"

if [ "$DRY" = "1" ]; then
  echo "DRY: cwd $(pwd)"
  echo "DRY: would GET ${OPENSEO_URL:-<unknown>}/api/health (max 120s, non-fatal)"
  echo 'DRY: would run claude -p "/seo-god daily" --permission-mode acceptEdits --max-turns 80'
  if command -v claude >/dev/null 2>&1; then
    echo "DRY: claude CLI found"
  else
    echo "DRY: claude CLI NOT on PATH — a real run would stop here"
  fi
  [ -z "$SUFFIX" ] || echo "DRY: note — $SUFFIX"
  echo "DRY: would write $MARKER"
  note true "dry-run"
  exit 0
fi

STEP="claude CLI check"
if ! command -v claude >/dev/null 2>&1; then
  echo "error: claude CLI not found on PATH" >&2
  die "claude CLI not found"
fi

# Readiness probe, not a cron trigger. OpenSEO has NO cron/refresh endpoint to
# hit: its only scheduled work is the Cloudflare Workers `scheduled()` export in
# src/server.ts, driven by the "*/15 * * * *" cron in wrangler.jsonc — which is
# unreachable over HTTP and absent from the self-hosted Docker mode this skill
# uses (docker-entrypoint.sh ends in `vite preview`, a plain Node server). Their
# own preflight says so: "Rank-tracking schedules do not run in Docker mode"
# (src/lib/selfhost-preflight.ts). The agentic step below drives every crawl,
# rank and GSC read itself over MCP, so all this step buys is knowing the
# container answered first. /api/health is unauthenticated by design
# (src/routes/api/health.ts — the Docker HEALTHCHECK probes it).
STEP="OpenSEO health probe"
if [ -n "$OPENSEO_URL" ]; then
  if ! command -v curl >/dev/null 2>&1; then
    SUFFIX="curl not found, probe skipped"
    echo "warn: curl not found — skipping the OpenSEO readiness probe" >&2
  elif ! curl -fsS -m 120 -o /dev/null "$OPENSEO_URL/api/health"; then
    SUFFIX="openseo unreachable"
    echo "warn: OpenSEO health probe failed — continuing (act.md degrades)" >&2
  fi
fi

STEP="claude -p /seo-god daily"
# MSYS2_ARG_CONV_EXCL is the Git Bash trap: MSYS rewrites any argument that looks
# like an absolute POSIX path before handing it to a native .exe, so the prompt
# would reach claude.exe as "C:/Program Files/Git/seo-god daily" — a real 80-turn
# acceptEdits session on a garbage prompt, ending in an ok:true marker. Scoped to
# this one prefix, and ignored outright by macOS and Linux shells.
MSYS2_ARG_CONV_EXCL='/seo-god' claude -p "/seo-god daily" --permission-mode acceptEdits --max-turns 80

if [ -n "$SUFFIX" ]; then
  note true "completed ($SUFFIX)"
else
  note true "completed"
fi
