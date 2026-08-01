#!/usr/bin/env bash
# SEO-GOD schedule installer — macOS (launchd) and Linux (cron).
#
#   bash install-schedule.sh                      # 05:00, project = current directory
#   bash install-schedule.sh 05:30
#   bash install-schedule.sh 05:30 /path/to/project
#
# Windows is not handled here: use install-schedule.ps1.
#
# The runner is COPIED into <project>/scripts/ first and the scheduler entry runs that copy,
# so updating or moving the skill folder never breaks a live schedule. Both branches are
# idempotent: re-running replaces the agent / the crontab line in place, never duplicates it.
#
# Every entry runs the runner with the PROJECT ROOT as its working directory, because the
# runner hard-fails unless seo-god.json is in the current directory.
#
# Uninstall:
#   macOS  launchctl unload ~/Library/LaunchAgents/com.seo-god.daily.plist && rm ~/Library/LaunchAgents/com.seo-god.daily.plist
#   Linux  crontab -e, then delete the scripts/daily-run.sh line
#
# references/schedule.md documents the 48h missed-run check and what each scheduler does NOT do.
set -euo pipefail

TIME="${1:-05:00}"
PROJECT_DIR="${2:-$PWD}"
LABEL="com.seo-god.daily"

die() { echo "install-schedule: $1" >&2; exit 1; }

# --- 1. Validate the arguments -------------------------------------------------------------
[[ "$TIME" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] ||
  die "invalid time '$TIME' - use 24-hour HH:MM, e.g. 05:00 or 23:30"
# 10# forces base 10: without it "08" is an invalid octal literal and the install dies.
HOUR=$((10#${TIME%%:*}))
MIN=$((10#${TIME##*:}))

[ -d "$PROJECT_DIR" ] || die "no such directory: $PROJECT_DIR"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
[ -f "$PROJECT_DIR/seo-god.json" ] ||
  die "no seo-god.json in $PROJECT_DIR - pass the project root as the second argument, or run /seo-god there first"

# --- 2. Pick the scheduler, and refuse BEFORE touching the project -------------------------
# Every refusal belongs here: an unsupported OS or a missing tool must not leave a copied
# runner and a new .seo-god directory behind in someone's repository.
OS="$(uname -s)"
case "$OS" in
  Darwin)
    TARGET="launchd"
    ;;
  Linux)
    TARGET="cron"
    command -v crontab >/dev/null 2>&1 ||
      die "crontab is not installed - install cron (Debian/Ubuntu: sudo apt-get install cron; Fedora: sudo dnf install cronie), or run scripts/daily-run.sh from a systemd timer with WorkingDirectory=$PROJECT_DIR"
    command -v flock >/dev/null 2>&1 ||
      die "flock is not installed (it ships in util-linux) - install it and re-run; the cron line uses it so two runs can never overlap in one repo"
    ;;
  MINGW* | MSYS* | CYGWIN*)
    die "this is Windows - use install-schedule.ps1 instead (a POSIX shell cannot register a Task Scheduler entry)"
    ;;
  *)
    die "unsupported OS '$OS' - schedule '$PROJECT_DIR/scripts/daily-run.sh' with your own scheduler: run it daily with the working directory set to $PROJECT_DIR"
    ;;
esac

# --- 3. Copy the runner into the project ---------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/daily-run.sh"
[ -f "$SRC" ] ||
  die "daily-run.sh is not next to this installer ($SCRIPT_DIR) - run the copy that ships in the skill's scripts folder"
DEST="$PROJECT_DIR/scripts/daily-run.sh"
mkdir -p "$PROJECT_DIR/scripts"
# .seo-god has to exist BEFORE the first scheduled run: cron's >> redirection and launchd's
# StandardOutPath both open a file inside it, neither creates a missing directory, and the
# entry would fail before the runner could write a marker to say so.
mkdir -p "$PROJECT_DIR/.seo-god"

RUNNER_NOTE="copied"
if [ -e "$DEST" ] && [ "$SRC" -ef "$DEST" ]; then
  # The project root IS the skill folder: source and destination are one file.
  RUNNER_NOTE="already in place"
else
  cp "$SRC" "$DEST"
fi
chmod +x "$DEST" 2>/dev/null || true
# Verify the copy BEFORE registering anything: an entry pointed at a missing file fails daily.
[ -f "$DEST" ] || die "the runner did not land at $DEST - nothing was scheduled"

command -v claude >/dev/null 2>&1 ||
  echo "warn: the claude CLI is not on PATH here - until it is, every run records ok:false, 'claude CLI not found'" >&2

if [ "$((10#$(date +%H%M)))" -lt "$((HOUR * 100 + MIN))" ]; then
  WHEN="today at $TIME"
else
  WHEN="tomorrow at $TIME"
fi

report_tail() {
  echo "  marker:      $PROJECT_DIR/.seo-god/last-run.json - /seo-god warns you when it goes 48h stale"
  echo "  dry run it:  (cd '$PROJECT_DIR' && SEO_GOD_DRY_RUN=1 bash scripts/daily-run.sh)   # starts no Claude session"
}

# --- 4. Install the entry ------------------------------------------------------------------
case "$TARGET" in
  launchd)
    PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
    mkdir -p "$HOME/Library/LaunchAgents"

    # A path can legally contain & or <, which would produce a plist launchd refuses to read.
    xml_escape() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
    P="$(xml_escape "$PROJECT_DIR")"
    # launchd agents start with a minimal PATH that almost never contains the claude CLI, so
    # the PATH you install with is baked in. Re-run this installer if claude ever moves.
    PATH_VALUE="$(xml_escape "$PATH")"

    # Unload first: launchd keeps serving the OLD definition of an already-loaded label, so a
    # re-install with a new time would appear to do nothing.
    if [ -f "$PLIST" ]; then launchctl unload "$PLIST" >/dev/null 2>&1 || true; fi

    # RunAtLoad is explicitly false: installing must never start a real run while the user is
    # sitting there watching.
    cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$P/scripts/daily-run.sh</string>
  </array>
  <key>WorkingDirectory</key>
  <string>$P</string>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>$HOUR</integer>
    <key>Minute</key>
    <integer>$MIN</integer>
  </dict>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>$PATH_VALUE</string>
  </dict>
  <key>StandardOutPath</key>
  <string>$P/.seo-god/launchd.log</string>
  <key>StandardErrorPath</key>
  <string>$P/.seo-god/launchd.log</string>
  <key>RunAtLoad</key>
  <false/>
</dict>
</plist>
PLIST_EOF

    if ! launchctl load -w "$PLIST" >/dev/null 2>&1; then
      # Recent macOS sometimes refuses `load` for a freshly written agent; bootstrap into the
      # GUI domain is the modern equivalent.
      launchctl bootstrap "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 ||
        die "launchctl refused the agent - run: launchctl load -w \"$PLIST\" and read the error it prints"
    fi
    launchctl list 2>/dev/null | grep -q "$LABEL" ||
      echo "warn: $LABEL is not in \`launchctl list\` - check the plist before trusting the schedule" >&2

    echo ""
    echo "Installed the SEO-GOD daily loop - every day at $TIME local time. Runner $RUNNER_NOTE."
    echo "  entry:       launchd agent $LABEL  ($PLIST)"
    echo "  runs:        /bin/bash $DEST"
    echo "  working dir: $PROJECT_DIR  (seo-god.json must stay here)"
    echo "  next run:    $WHEN"
    echo "  asleep then: launchd runs it when the Mac wakes (several missed times coalesce into one run)"
    echo "  powered off: the day is skipped. \`sudo pmset repeat wakeorpoweron MTWRFSU $TIME:00\` wakes it if you want that"
    echo "  log:         $PROJECT_DIR/.seo-god/launchd.log  (stdout+stderr; safe to delete)"
    report_tail
    echo "  uninstall:   launchctl unload '$PLIST' && rm '$PLIST'"
    ;;

  cron)
    LINE="$MIN $HOUR * * * cd $PROJECT_DIR && flock -n .seo-god/run.lock bash scripts/daily-run.sh >> .seo-god/cron.log 2>&1"
    TMP="$(mktemp)"
    trap 'rm -f "$TMP"' EXIT
    # Drop any previous seo-god line first, whatever project or time it named, so a re-install
    # replaces the schedule instead of adding a second daily run. Everything else in the
    # crontab is passed through untouched.
    crontab -l 2>/dev/null | grep -v -e 'scripts/daily-run\.sh' -e '\.seo-god/run\.lock' > "$TMP" || true
    printf '%s\n' "$LINE" >> "$TMP"
    crontab "$TMP"
    crontab -l 2>/dev/null | grep -Fqx "$LINE" ||
      die "the crontab line did not stick - run 'crontab -l' and add it by hand: $LINE"

    echo ""
    echo "Installed the SEO-GOD daily loop - every day at $TIME local time. Runner $RUNNER_NOTE."
    echo "  entry:       crontab line for $(id -un)"
    echo "               $LINE"
    echo "  working dir: $PROJECT_DIR  (seo-god.json must stay here)"
    echo "  next run:    $WHEN"
    echo "  asleep/off:  cron does not catch up - a machine that is off at $TIME skips that day"
    echo "  overlap:     flock -n skips a run while yesterday's is somehow still going"
    echo "  log:         $PROJECT_DIR/.seo-god/cron.log  (stdout+stderr; safe to delete)"
    report_tail
    echo "  uninstall:   crontab -e, delete the scripts/daily-run.sh line"
    ;;

esac

echo ""
echo "Nothing about this commits to your repository, and the loop never commits either."
exit 0
