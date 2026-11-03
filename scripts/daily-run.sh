#!/usr/bin/env bash
# SEO-GOD daily runner (Cursor fork) — macOS / Linux.
#
# Run it FROM THE PROJECT ROOT: the directory that holds seo-god.json.
#
# Probes the local OpenSEO container, hands the run to Cursor Agent
# (`/seo-god daily`), and ALWAYS leaves a run marker at .seo-god/last-run.json.
#
# Requires: bash, `cursor-agent` (or `cursor agent`) on PATH, logged in via
# `cursor agent login`. `curl` and `node` are optional for the OpenSEO probe.
#
# --skill-dir <path> points at this skill's folder. Without --add-dir on that
# path the agent cannot read references/*.md outside the project.
# Defaults to ${CURSOR_CONFIG_DIR:-$HOME/.cursor}/skills/seo-god.
#
# SEO_GOD_DRY_RUN=1 prints what would happen, writes ok:true "dry-run", exits 0.
set -euo pipefail

DRY="${SEO_GOD_DRY_RUN:-0}"
MARKER=".seo-god/last-run.json"
STEP="startup"
SUFFIX=""
SKILL_NOTE=""

SKILL_DIR="${CURSOR_CONFIG_DIR:-$HOME/.cursor}/skills/seo-god"
while [ $# -gt 0 ]; do
  case "$1" in
    --skill-dir) SKILL_DIR="${2:-}"; shift 2 ;;
    --skill-dir=*) SKILL_DIR="${1#--skill-dir=}"; shift ;;
    *) echo "warn: ignoring unknown argument: $1" >&2; shift ;;
  esac
done

resolve_agent() {
  if command -v cursor-agent >/dev/null 2>&1; then
    printf '%s' 'cursor-agent'
    return 0
  fi
  if command -v cursor >/dev/null 2>&1 && cursor agent --help >/dev/null 2>&1; then
    printf '%s' 'cursor agent'
    return 0
  fi
  return 1
}

mkdir -p .seo-god

note() {
  printf '{"ts":"%s","ok":%s,"notes":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" > "$MARKER"
}
notes_all() {
  if [ -n "$SUFFIX" ] && [ -n "$SKILL_NOTE" ]; then printf '%s; %s' "$SUFFIX" "$SKILL_NOTE"
  elif [ -n "$SUFFIX" ]; then printf '%s' "$SUFFIX"
  else printf '%s' "$SKILL_NOTE"
  fi
}
trap 'note false "failed during $STEP (line $LINENO)"' ERR
trap 'note false "interrupted during $STEP"; trap - ERR; exit 143' INT TERM
die() { trap - ERR; note false "$1"; exit 1; }

STEP="reading seo-god.json"
if [ ! -f seo-god.json ]; then
  echo "error: seo-god.json not found in $(pwd) — run this from the project root" >&2
  die "seo-god.json not found in the working directory"
fi

OPENSEO_URL=""
if command -v node >/dev/null 2>&1; then
  OPENSEO_URL="$(node -e 'try{const s=JSON.parse(require("fs").readFileSync("seo-god.json","utf8"));process.stdout.write(String((s.openseo&&s.openseo.url)||""))}catch(e){}')" || OPENSEO_URL=""
  [ -n "$OPENSEO_URL" ] || SUFFIX="openseo.url unreadable, probe skipped"
else
  SUFFIX="node not found, probe skipped"
fi
OPENSEO_URL="${OPENSEO_URL%/}"

STEP="resolving skill dir"
ADD_DIR_ARGS=()
SKILL_DIR_ABS=""
if [ -d "$SKILL_DIR" ]; then
  SKILL_DIR_ABS="$(cd "$SKILL_DIR" && pwd)"
  PROJECT_ABS="$(pwd)"
  if [ "${SKILL_DIR_ABS#"$PROJECT_ABS"/}" = "$SKILL_DIR_ABS" ] && [ "$SKILL_DIR_ABS" != "$PROJECT_ABS" ]; then
    ADD_DIR_ARGS=(--add-dir "$SKILL_DIR_ABS")
  fi
else
  SKILL_NOTE="skill dir not found, phase files unreadable"
  echo "warn: skill dir not found at $SKILL_DIR — the run cannot read references/*.md" >&2
fi

AGENT_BIN=""
if AGENT_BIN="$(resolve_agent)"; then
  :
else
  AGENT_BIN=""
fi

if [ "$DRY" = "1" ]; then
  echo "DRY: cwd $(pwd)"
  echo "DRY: would GET ${OPENSEO_URL:-<unknown>}/api/health (max 120s, non-fatal)"
  echo "DRY: skill dir ${SKILL_DIR_ABS:-$SKILL_DIR}"
  if [ -r "${SKILL_DIR_ABS:-$SKILL_DIR}/references/act.md" ]; then
    echo "DRY: references/act.md readable — yes"
  else
    echo "DRY: references/act.md readable — NO (the daily loop would run blind)"
  fi
  if [ ${#ADD_DIR_ARGS[@]} -gt 0 ]; then
    echo "DRY: would pass --add-dir \"$SKILL_DIR_ABS\""
  else
    echo "DRY: would pass no --add-dir (skill dir missing, or inside the project)"
  fi
  echo 'DRY: would run cursor-agent -p "/seo-god daily" --print --force --trust'
  if [ -n "$AGENT_BIN" ]; then
    echo "DRY: Cursor agent CLI found ($AGENT_BIN)"
  else
    echo "DRY: Cursor agent CLI NOT on PATH — a real run would stop here"
  fi
  [ -z "$SUFFIX" ] || echo "DRY: note — $SUFFIX"
  [ -z "$SKILL_NOTE" ] || echo "DRY: note — $SKILL_NOTE"
  echo "DRY: would write $MARKER"
  note true "dry-run"
  exit 0
fi

STEP="Cursor agent CLI check"
if [ -z "$AGENT_BIN" ]; then
  echo "error: cursor-agent not found on PATH (install via Cursor: cursor agent)" >&2
  die "cursor-agent not found"
fi

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

STEP="cursor-agent /seo-god daily"
if [ "$AGENT_BIN" = "cursor-agent" ]; then
  cursor-agent -p "/seo-god daily" \
    --print \
    --force \
    --trust \
    ${ADD_DIR_ARGS[@]+"${ADD_DIR_ARGS[@]}"}
else
  cursor agent -p "/seo-god daily" \
    --print \
    --force \
    --trust \
    ${ADD_DIR_ARGS[@]+"${ADD_DIR_ARGS[@]}"}
fi

NOTES="$(notes_all)"
if [ -n "$NOTES" ]; then
  note true "completed ($NOTES)"
else
  note true "completed"
fi
