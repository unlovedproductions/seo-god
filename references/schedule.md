# Schedule — run the loop daily, and notice when it did not run

Goal: the daily loop in `references/act.md` runs without the user, and a run that did **not**
happen becomes visible the next time they open Cursor. Those are two separate jobs. The
second one is the point of this phase: an unattended job nobody checks is worth nothing.

Everything happens in the USER's project directory — the current working directory. Never
install anything into the skill folder, and never edit the scripts that live there.

## 0. Ask first — this is the fork, and the two answers are not equivalent

Ask this, then wait:

> Do you want the daily run on an **OS-native scheduler** (Task Scheduler, launchd or cron —
> this machine, only while it is on; needs Cursor Agent CLI), or as a **Cursor Automation**
> (cloud agent on a cron; needs this project on GitHub; **cannot** reach OpenSEO on
> `127.0.0.1`, so it works from repo-visible data only)?

| | OS-native | Cursor Automation (cloud) |
| --- | --- | --- |
| Needs | machine on at the chosen time; `cursor-agent` logged in; pwsh 7 on Windows | GitHub repo + Cursor Automations / Cloud Agents |
| Crawl + fresh snapshot via OpenSEO | **yes** (local Docker) | **no** — committed snapshots only |
| Search Console | yes (in the container) | no |
| Edit + `build_cmd` | yes | yes, in cloud checkout |
| Commits | never | yes — readout / marker / edits |
| Machine off all day | nothing runs; next session warns | still runs in the cloud |

- **Unsure** → OS-native if the machine is usually on at the chosen time (only path that measures
  anything new). Cursor Automation if the machine is often asleep or they want zero local cron.
- **Neither** → `schedule.mode: "none"`, leave `phases.schedule` as found; `/seo-god act` by hand.
- **Both** → pick one primary writer. Two writers fighting over the same readout is a merge mess.

Then ask for the time: **24-hour `HH:MM`, local, default `05:00`.**

## 1. Both paths — checks before you install anything

1. **`phases.setup` is `"done"`.** Otherwise `references/setup.md` first.
2. **`.seo-god/` is in the project `.gitignore`.** Add it if missing (OS path writes there).
3. **OS path only:** `cursor-agent --version` or `cursor agent --version` works, and
   `cursor agent login` has been done once. Installers warn rather than refuse if the CLI is
   missing; runs then record `ok:false, "cursor-agent not found"` until fixed.
4. **Cloud path only:** repo is on GitHub (or GitLab) and the user can open Cursor Automations.

`openseo.status` need not be `"running"` to install. The loop degrades (`references/act.md`).

## 2. The OS-native path

### 2.1 What gets installed

The runner (`scripts/daily-run.ps1`, `scripts/daily-run.sh`) lives in **this skill**. The
installer **copies it into `<project>/scripts/`** and the scheduler runs that copy.

| | |
| --- | --- |
| runs | `<project>/scripts/daily-run.(ps1\|sh)` daily at local time |
| working directory | **project root** (must contain `seo-god.json`) |
| what the runner does | probes OpenSEO, runs `cursor-agent -p "/seo-god daily" --print --force --trust`, writes `.seo-god/last-run.json` |
| never | commit, or write into the skill folder |

| Flag | Why |
| --- | --- |
| `--add-dir <skill root>` | so the agent can read `references/*.md` outside the project |
| `--print --force --trust` | headless: stdout + auto-approve shell for curl/git/`build_cmd` |

Default skill dir: `~/.cursor/skills/seo-god` (Windows: `%USERPROFILE%\.cursor\skills\seo-god`).

### 2.2 Windows

```
pwsh -NoProfile -File "<skill>\scripts\install-schedule.ps1" -Time 05:00 -ProjectDir "<project>"
```

Requires **PowerShell 7** (`pwsh`). Refuses to schedule onto 5.1. From 5.1 you can still *launch*
the installer so it prints the install pointer:

```
powershell.exe -NoProfile -File "<skill>\scripts\install-schedule.ps1" -Time 05:00 -ProjectDir "<project>"
```

Task name: **SEO-GOD Daily**. The runner itself prepends common Cursor Agent install dirs to
`PATH` (Task Scheduler often starts minimal), then resolves `cursor-agent` or `cursor agent`.

Uninstall: `Unregister-ScheduledTask -TaskName "SEO-GOD Daily" -Confirm:$false`.

### 2.3 macOS

```
bash "<skill>/scripts/install-schedule.sh" 05:00 "<project>"
```

Writes `~/Library/LaunchAgents/com.seo-god.daily.plist`, bakes installer-shell `PATH` into the
agent so `cursor-agent` resolves. Uninstall: `launchctl bootout gui/$(id -u)/com.seo-god.daily`
then `rm` the plist.

### 2.4 Linux

```
bash "<skill>/scripts/install-schedule.sh" 05:00 "<project>"
```

Crontab line (with `--skill-dir`):

```
M H * * * cd '<project>' && flock -n .seo-god/run.lock bash scripts/daily-run.sh --skill-dir '<skill>' >> .seo-god/cron.log 2>&1
```

Put a `PATH=` line at the top of the crontab that includes `cursor-agent` (and `pnpm` if
`build_cmd` needs it). Re-run the installer from a shell where `cursor-agent --version` works.

Uninstall: `crontab -e`, delete the `scripts/daily-run.sh` line.

### 2.5 Dry run (no agent session)

```
SEO_GOD_DRY_RUN=1 bash scripts/daily-run.sh --skill-dir <skill root>
$env:SEO_GOD_DRY_RUN=1; pwsh -NoProfile -File scripts\daily-run.ps1 -SkillDir <skill root>
```

Expect `DRY: Cursor agent CLI found` and `references/act.md readable — yes`. Do **not** use
`Start-ScheduledTask` / `launchctl start` as a "test" — that starts a real unattended run.

### 2.6 What the scheduler will not do

| | Windows | macOS | Linux |
| --- | --- | --- | --- |
| asleep | `WakeToRun` if allowed | coalesces on wake | no catch-up |
| powered off | `StartWhenAvailable` later | day skipped | day skipped |
| logged out | task needs logged-on user | agents need login | cron still runs |
| hang | killed at 2h | no OS limit | optional `timeout 2h` |

## 3. Missed-run self-check

`.seo-god/last-run.json` is written **only** by the OS runner:
`{"ts":"<UTC ISO 8601>","ok":true|false,"notes":"<short>"}`.

SKILL.md: if `schedule.mode` ≠ `"none"` and the marker at `schedule.marker` is missing,
unparseable, >48h old, or `ok:false` → warn first, then continue. Hard kills leave yesterday's
marker; the warning appears after 48h when they next open Cursor.

## 4. Cursor Automation (cloud) path

### 4.1 Limits — say before they choose it

The Automation runs a **Cursor Cloud Agent** with the GitHub repo checked out. **It cannot
reach OpenSEO on `127.0.0.1`.** No live crawl, no fresh GSC pull from the container. It only
sees committed `seo-god.json`, snapshots, readouts, and source.

**Stale snapshots ⇒ useless cloud runs.** If nobody commits MEASURE snapshots from a machine
that can reach OpenSEO, the Automation honestly reports "nothing new" forever. Prefer OS-native
when the laptop is usually awake at the chosen hour.

### 4.2 Prompt (verbatim — fill `<SITE_URL>` only)

```
You are the SEO monitor for <SITE_URL>. You run once a day, unattended, in this repository.
Nobody is watching: ask no questions and stop for nothing.

Where you are: a Cursor Cloud Agent / Automation with this repository checked out. You CANNOT
reach the OpenSEO container on the owner's machine (127.0.0.1). Do not crawl, do not claim a
new Search Console pull, and do not invent snapshot numbers.

1. Read seo-god.json at the repository root. If missing, unparseable, or version is not 1,
   write a readout saying exactly that and stop.
2. Find the newest snapshot and the newest one before it under dist/seo/snapshots/ or
   seo/snapshots/. Those two files are your only measurements. No snapshot: write a readout
   that nothing has been measured yet, and stop.
3. If the newest snapshot is not from today, say so, name its date, label the comparison stale.
4. Review in order: regressions first, then quick wins (positions 4-15), then at most ONE new
   page. If the seo-god skill is available, follow references/act.md for thresholds and edit
   rules. If not, do the read-only half only. One act.md clause does NOT apply: "never commit"
   — you MUST commit (step 9); that is how cloud delivers output. Nothing else is relaxed.
5. Honesty first. Null / available:false / measured:false = NOT MEASURED. No invented stats,
   quotes, or testimonials. Empty successful runs are fine: say so and stop.
6. If you edit, run build_cmd from seo-god.json before the first edit and after the last;
   revert failures. No build_cmd → no edits.
7. Write readout to dist/seo/readouts/<YYYY-MM-DD>.md or seo/readouts/ (match snapshot dir):
   at most 15 lines.
8. Write seo/last-run.json as exactly
   {"ts":"<UTC ISO 8601>","ok":true,"notes":"<short>"} (ok:false only if incomplete).
9. Commit the readout, seo/last-run.json, and any page edits — nothing under .seo-god/. Stop.

No credentials in this prompt. If a step needs the owner's machine or a secret you lack, skip
it and name it in the readout.
```

Same prompt lives in `references/cloud-prompt.md` for copy-paste.

### 4.3 Creating the Automation

You (the agent in Cursor) create it via the Automations editor handoff — do **not** send the
user to claude.ai:

1. Fill `<SITE_URL>` from `seo-god.json`.
2. Prefill a Cursor Automation: cron trigger for their `HH:MM` (document timezone caveat —
   Automations cron has no separate TZ field; confirm in the editor), `gitConfig` for this
   repo + default branch, prompt from 4.2, no MCP required for the free path.
3. Show a short draft table → get approval → open Automations with `open_automation` and the
   prefill. User finishes save in the UI.
4. After they confirm it is saved: set state per section 7 (`mode: "cloud"`, marker
   `seo/last-run.json`).

If Automations handoff is unavailable, tell them: Cursor → Automations → New → Schedule →
paste 4.2 → connect this GitHub repo → save.

### 4.4 Cloud marker

`.seo-god/last-run.json` is gitignored and never exists in cloud. Set:

- `schedule.marker` → `"seo/last-run.json"`
- commit that file from the Automation (step 8)

Local `/seo-god` only sees it after `git pull`. Independent check: GitHub commit history.

Switching back to OS: set `schedule.marker` back to `".seo-god/last-run.json"`.

## 5. AI visibility is not part of the daily loop

Daily = `cursor-agent -p "/seo-god daily"` → `references/act.md` only.

Monthly attended: `/seo-god ai-visibility`. Optional headless OS entry (hours away from daily):

```
cursor-agent -p "/seo-god ai-visibility" --print --force --trust --add-dir "<skill root>"
```

## 6. Maintenance

| Path | Safe to delete? |
| --- | --- |
| `.seo-god/backup/…` | yes when old |
| `.seo-god/cron.log`, `.seo-god/launchd.log` | yes |
| `.seo-god/run.lock` | leave |
| `.seo-god/last-run.json` | **no** (OS deadman) |
| `seo/last-run.json` | **no** (cloud deadman) |
| `dist/seo/snapshots/`, readouts | **no** |

## 7. Write state

- `schedule.mode` — `"os"` or `"cloud"`
- `schedule.time_local` — registered `HH:MM`
- `schedule.marker` — `".seo-god/last-run.json"` (OS) or `"seo/last-run.json"` (cloud)
- `phases.schedule` — `"done"` only after installer exit 0 **or** user confirms Automation saved

Never write the run marker from this phase file.

## 8. Hand back

- what was registered and next fire time
- OS: loop never commits; cloud: Automation commits readout + marker
- missed-run warning behavior
- uninstall (OS) or Automations UI disable (cloud)
- AI-visibility monthly note if that phase is done

## 9. Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `last run: never` after install | expected | wait or `/seo-god act` |
| `cursor-agent not found` | PATH / CLI missing | install Cursor Agent; `cursor agent login`; Linux: crontab `PATH=`; Windows: runner PATH bootstrap + reinstall |
| `seo-god.json not found…` | wrong working directory | re-run installer from project root |
| `failed during <step>` | runner died | scheduler log / Task Scheduler history |
| `skill dir not found…` | skill moved | re-run installer |
| cloud marker missing/stale | no pull / Automation idle | `git pull`; check Automations runs + GitHub commits |

**Read `schedule.mode` before debugging.** Cloud has no local cron/task/log.
