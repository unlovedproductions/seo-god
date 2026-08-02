# Schedule — run the loop daily, and notice when it did not run

Goal: the daily loop in `references/act.md` runs without the user, and a run that did **not**
happen becomes visible the next time they open Claude Code. Those are two separate jobs. The
second one is the point of this phase: an unattended job nobody checks is worth nothing.

Everything happens in the USER's project directory — the current working directory. Never
install anything into the skill folder, and never edit the scripts that live there.

## 0. Ask first — this is the fork, and the two answers are not equivalent

Ask this, then wait:

> Do you want the daily run on an **OS-native scheduler** (Task Scheduler, launchd or cron — it
> runs on this machine, and only while this machine is on), or as a **Claude cloud routine**
> (needs claude.ai routine access and this project on GitHub; it cannot reach the OpenSEO
> container on your machine, so it works from repo-visible data only)?

| | OS-native | Cloud routine |
| --- | --- | --- |
| Needs | this machine on at the chosen time, the `claude` CLI on PATH, pwsh 7 on Windows | the project on GitHub + claude.ai routine access |
| Can crawl the site and capture today's snapshot | yes, through the local OpenSEO container | **no** — it reads snapshots already committed |
| Can read Search Console | yes (the connection lives in the container) | no |
| Can edit and verify with `build_cmd` | yes | yes, in its own checkout |
| Commits to the repo | never | yes — the readout is its only output channel |
| Machine off all day | nothing runs; the next session warns | irrelevant, it runs in the cloud |

- **Answer unclear, or the user is unsure** → OS-native. It needs nothing they do not already
  have, and it is the only path that can measure anything new. Say that is what you are doing.
- **They want neither** → leave `schedule.mode` at `"none"`, leave `phases.schedule` as you
  found it, and tell them `/seo-god act` runs the same loop by hand whenever they want. Never
  install a scheduler the user did not ask for.
- **They want both** → install OS-native now and say the cloud routine is redundant while it
  works; nothing breaks if they add one later, but two writers in one repo is a merge conflict
  waiting to happen.

Then ask for the time: **24-hour `HH:MM`, local, default `05:00`.** Guidance if they ask — pick
an hour the machine is on and nobody is building: the loop can edit files and run their build.

## 1. Both paths — three checks before you install anything

1. **`phases.setup` is `"done"`.** SKILL.md gates this phase on it; if you got here anyway,
   go back to `references/setup.md` first. There is nothing to schedule before setup.
2. **`.seo-god/` is in the project `.gitignore`.** Add the line if it is missing. The runner
   writes its marker and its logs there, and it must never be committed.
3. **The `claude` CLI answers** — `claude --version`. OS path only, and the installers warn
   rather than refuse, because a CLI that is missing today may be on PATH tomorrow. A scheduled
   run without it records `ok:false, "claude CLI not found"` every day until it is fixed.

`openseo.status` does not have to be `"running"` to install a schedule. The loop degrades on
its own (`references/act.md`), and the container is usually restarted by then anyway.

## 2. The OS-native path

### 2.1 What gets installed, on all three OSes

The runner (`scripts/daily-run.ps1`, `scripts/daily-run.sh`) lives in **this skill's** folder.
The installer **copies it into `<project>/scripts/` first and the scheduler entry runs the
project's copy** — so updating, moving or reinstalling the skill never breaks a live schedule.
That copy is an ordinary file in the user's repo: it holds nothing secret, and committing it is
fine and useful on a second machine.

Every entry, on every OS, has the same shape:

| | |
| --- | --- |
| runs | `<project>/scripts/daily-run.(ps1\|sh)`, once a day, at the chosen local time |
| working directory | **the project root** — the runner hard-fails with `ok:false` if `seo-god.json` is not in the current directory |
| what the runner does | probes OpenSEO, runs `claude -p "/seo-god daily"`, always writes `.seo-god/last-run.json` |
| what it never does | commit anything, or write any file in this skill's folder |

Both installers behave the same way: the time is a parameter (`HH:MM`, 24h, default `05:00`)
and is **validated before anything is registered**; every refusal happens **before** the project
is touched, so a failed install leaves no copied runner behind; the copy is **verified to exist
before** the entry is created; re-running replaces the entry in place (idempotent — never a
second daily run); and each one ends by echoing exactly what it registered, when it fires next,
and its own uninstall command.

**The two flags that make an unattended run work at all.** A headless `claude -p` is not a small
interactive session; it is a session with no human, no trust dialog, and a working directory that
holds only the project. Both installers therefore pass the skill's own path into the scheduler
entry, and the runner turns it into `--add-dir`:

| Flag | Why it exists | Where it comes from |
| --- | --- | --- |
| `--add-dir <skill root>` | a session can only read files inside its working directories, and this skill lives outside the project — without it `claude -p` can read **none** of `references/*.md` and the loop runs on SKILL.md's summary alone | the installer resolves it from its own location and writes it into the Task Scheduler argument / launchd `ProgramArguments` / cron line; the runner also accepts `--skill-dir` / `-SkillDir` by hand and defaults to `~/.claude/skills/seo-god` |
| `--allowedTools` | `acceptEdits` auto-approves Write/Edit and a fixed filesystem-command set and **nothing else**, so every `curl` (the whole OpenSEO MCP surface) and every `git` call is denied | the runner passes the same list SKILL.md's `allowed-tools` frontmatter declares: `curl`, `curl.exe`, and read-only `git status` / `diff` / `log` / `check-ignore` / `rev-parse` |

The absolute skill path lives in the machine-local scheduler entry only — never in the copied
runner — so the committed copy still works unchanged on a second machine. The runner adds
`--add-dir` only when that directory exists and sits outside the project; when it is missing the
run still happens and the marker says `skill dir not found, phase files unreadable`, so the failure
is visible instead of silent.

`git add`, `git commit` and `git push` are deliberately **not** granted. `references/act.md` and
`references/audit.md` forbid committing, and a permission grant must never contradict them.

**The build gate is the one thing the skill cannot pre-authorise.** `build_cmd` is an arbitrary
command for this project, so no static skill can allow it in advance. Show the user the one line to
add to **`~/.claude/settings.json`** (user scope — a project-scoped `.claude/settings.json` is
silently ignored in `-p` mode, because its rules only apply after a workspace-trust dialog that
never appears headlessly), under `permissions.allow`, using their own command:

```json
{ "permissions": { "allow": ["Bash(npm run build:*)"] } }
```

Say plainly why: without it the gate cannot run unattended, and `references/act.md`'s degrade table
then makes the run edit nothing and say so. **Never offer a blanket permission-bypass mode as the
fix** — not the skip-every-prompt permission mode, not the skip-all-permissions CLI flag. One
allow-entry naming one command is the whole ask; an unattended agent holding every permission in
the user's repository is not a trade this skill makes, and no file in this skill names such a mode
in a form anyone can paste.

**Say the override out loud, too:** `--permission-mode` beats `defaultMode` from any settings file,
so a user whose global default is more permissive still gets exactly this restricted set in
scheduled runs. That is intended.

You run the installer for the user's OS yourself, from their project root, and show them its
output as it stands — the last lines are the uninstall command and the dry-run command they will
want later. A non-zero exit means nothing was scheduled: relay the message verbatim, fix what it
names, and run it again.

### 2.2 Windows

`<skill>` below is the folder this `references/` directory lives in — you read this file from
there, so you have the path. Run it from the project root and `-ProjectDir` can be omitted:

```
pwsh -NoProfile -File "<skill>\scripts\install-schedule.ps1" -Time 05:00 -ProjectDir "<project>"
```

It registers the task **SEO-GOD Daily** targeting `pwsh.exe`, with `-WorkingDirectory` set to
the project root and every hardening flag on: `AllowStartIfOnBatteries`,
`DontStopIfGoingOnBatteries`, `StartWhenAvailable`, `WakeToRun`, `MultipleInstances IgnoreNew`,
and a 2-hour `ExecutionTimeLimit`. It then reads the task back and warns if a group policy
dropped any of them.

**It refuses to install onto Windows PowerShell 5.1** (no `pwsh` on PATH) and prints the
install pointer instead. The reason is not cosmetic: under 5.1, `$ErrorActionPreference='Stop'`
turns any stderr line a native command writes into a terminating error, so a run where `claude`
merely logged a warning would be recorded as a failed run.

On a machine with no `pwsh` at all, the command above cannot even start — so launch the
installer with Windows PowerShell and let it deliver its own refusal, which is why it is written
in 5.1-compatible syntax:

```
powershell.exe -NoProfile -File "<skill>\scripts\install-schedule.ps1" -Time 05:00 -ProjectDir "<project>"
```

Nothing is registered by that run: it prints the one-line install pointer, exits 1, and the
schedule waits until pwsh 7 is installed.

Uninstall: `Unregister-ScheduledTask -TaskName "SEO-GOD Daily" -Confirm:$false`.

### 2.3 macOS

```
bash "<skill>/scripts/install-schedule.sh" 05:00 "<project>"
```

It writes `~/Library/LaunchAgents/com.seo-god.daily.plist` — `ProgramArguments` of `/bin/bash`
plus the project's runner, `WorkingDirectory` at the project root, `StartCalendarInterval` from
the time you passed, stdout and stderr into `<project>/.seo-god/launchd.log`, and `RunAtLoad`
explicitly false so installing never starts a real run while the user is watching. Then it
unloads any previous copy of the label and `launchctl load -w`s the new one (with
`launchctl bootstrap gui/<uid>` as the fallback when a recent macOS refuses `load`).

One thing it bakes in on purpose: **`PATH`**. A launchd agent starts with a minimal `PATH` that
almost never contains the `claude` CLI, so the installer copies the `PATH` of the shell it was
run from into the agent's `EnvironmentVariables`. Run the installer from a shell where
`claude --version` works, and re-run it if the CLI ever moves.

Uninstall — **both steps**: `launchctl bootout gui/$(id -u)/com.seo-god.daily` (or the older
`launchctl unload <plist>`), then `rm ~/Library/LaunchAgents/com.seo-god.daily.plist`. Booting
the agent out only stops it for this login session; while the plist is still in
`~/Library/LaunchAgents`, launchd loads it again at the next login.

### 2.4 Linux

```
bash "<skill>/scripts/install-schedule.sh" 05:00 "<project>"
```

It installs one crontab line for the current user:

```
M H * * * cd '<project>' && flock -n .seo-god/run.lock bash scripts/daily-run.sh >> .seo-god/cron.log 2>&1
```

The single quotes around the path are load-bearing: cron hands the line to `/bin/sh`, so an
unquoted path with a space or an `&` in it would `cd` to the wrong place and treat the remainder
as separate commands — a schedule that installs cleanly, reports success, and never works. Two
characters cannot be made safe even quoted, so the installer refuses up front rather than
registering something broken: a `'` in the path (it would end the quoting) and a `%` (cron reads
the first unescaped `%` as a newline). Both refusals point at a systemd timer instead.

A previous seo-god line is removed first — matched on **both** markers together, the lock file
and the runner path, so a line carrying only one of them is the user's and is left alone. The
installer reports how many lines it replaced and how many it left untouched, and it refuses to
write at all if it could not first read the existing crontab. `flock -n` is why a run that
somehow overruns 24 hours cannot be joined by a second one. Missing `crontab` or `flock` is a
refusal too, naming the package to install (and the systemd-timer alternative) instead of
installing something half-wired.

cron starts with a minimal `PATH` too, and unlike the launchd branch this line does not carry
one. If the marker starts saying `claude CLI not found`, add `PATH=<the PATH where claude
works>` as the first line of `crontab -e`.

Uninstall: `crontab -e`, delete the `scripts/daily-run.sh` line.

### 2.5 Prove the plumbing without starting a Claude session

From the project root:

```
SEO_GOD_DRY_RUN=1 bash scripts/daily-run.sh --skill-dir <skill root>                  # macOS, Linux
$env:SEO_GOD_DRY_RUN=1; pwsh -NoProfile -File scripts\daily-run.ps1 -SkillDir <skill root>   # Windows (then Remove-Item Env:\SEO_GOD_DRY_RUN)
```

Both installers print this line with the real path already filled in — use theirs.

It prints what a real run would do and exits 0 without calling Claude Code at all.

**Read the `references/act.md readable` line before anything else.** The dry run prints the
resolved skill directory and whether the phase file can actually be read:

```
DRY: skill dir /home/me/.claude/skills/seo-god
DRY: references/act.md readable — yes
DRY: would pass --add-dir "/home/me/.claude/skills/seo-god"
```

A `NO` there means tomorrow's run reaches Claude Code with no phase file, and the daily loop runs
blind on SKILL.md's summary — the single most important thing this dry run proves. "The CLI is on
PATH" proves nothing by comparison. Fix the path and re-run the installer before you call the
schedule installed.

Two more things to be straight with the user about:

- **The dry run writes a real marker** (`ok:true`, `notes:"dry-run"`), so the missed-run check
  in section 3 stays quiet for 48h afterwards. It proves the plumbing — the working directory,
  the CLI on PATH, the skill directory, the marker path — and nothing about the loop itself.
- **Do not use `Start-ScheduledTask` / `launchctl start` as a test.** Those start a real
  unattended run: a Claude Code session with `--permission-mode acceptEdits` in the user's
  repository. If they want a run right now, `/seo-god act` does the same work attended, where
  they can see it.

The first real proof is tomorrow's readout in `dist/seo/readouts/` (or `seo/readouts/`).

### 2.6 What the scheduler will not do — say this plainly

| | Windows | macOS | Linux |
| --- | --- | --- | --- |
| asleep at the time | `WakeToRun` wakes it, if wake timers are allowed in the power plan | launchd runs it on wake; several missed times coalesce into one run | nothing; cron does not catch up |
| powered off at the time | `StartWhenAvailable` runs it once the machine is back | the day is skipped (`sudo pmset repeat wakeorpoweron …` can wake it) | the day is skipped |
| user logged out | the task runs only while the user is logged on | agents load at login, so a logged-out Mac runs nothing | cron runs regardless |
| on battery | runs, and does not stop when the charger is pulled | runs | runs |
| two runs at once | `IgnoreNew` drops the second | launchd never runs two instances of one label | `flock -n` drops the second |
| a run that hangs | killed at 2h (see section 3) | no limit — bounded only by the runner's `--max-turns 80` | same; prefix `timeout 2h` in the crontab line if a hard cap matters |

None of this is a service or a daemon. Nothing here keeps a machine awake, and nothing runs on
a machine that is off. That is exactly why section 3 exists.

## 3. The missed-run self-check — the deadman

`.seo-god/last-run.json` is written by the **runner**, and only by the runner:
`{"ts":"<UTC ISO 8601>","ok":true|false,"notes":"<short>"}`. Nothing in this file writes it,
neither installer writes it, and `references/act.md` does not write it. One writer, on purpose.

SKILL.md reads it at the top of **every** invocation once `schedule.mode` is not `"none"`:
missing, unparseable, or a `ts` more than 48h old → the first thing the user sees is
`A scheduled run appears to have been missed (last run: <ts, or "never">)`. `ok:false` → the
same warning plus the `notes` quoted verbatim. Fresh and `ok:true` → silence. 48h rather than
24h because one skipped day (a laptop that stayed shut) is ordinary life, and two in a row is a
broken schedule.

**The check tests the marker's AGE, not the presence of a recorded failure — and that is what
makes it a deadman.** The runner records its own failures, including a stop request (Ctrl+C, a
`TERM`, a stopped pipeline) as `interrupted during <step>`. What it cannot record is a hard
kill: Task Scheduler's "end the task if it runs longer than" is a `TerminateProcess`, not a
request, and so is a power cut, a forced reboot, or `kill -9`. No trap runs, no `finally` runs,
and **yesterday's marker is left sitting there**.

So a hard-killed run looks like this: nothing at all for up to two days, then a warning the
next time the user opens Claude Code, because the stale marker ages past 48h. State it plainly
when you hand back — a killed run shows up as a silent gap and then a warning, not as an error
at the time. The only alternative would be a second file written at start-up, and the marker
has exactly one writer for a reason.

The 2-hour limit on Windows is what makes that trade worth taking: a stuck agentic session gets
killed instead of running all day, burning tokens, and still holding the repo when tomorrow's
run fires. The cost of the limit is precisely the residual above.

When the warning does fire, the two recovery moves are: run the loop now (`/seo-god act`), or
come back here and re-check the schedule. Section 9 maps each marker message to its cause.

## 4. The cloud routine path

### 4.1 What it cannot do — say this before they choose it

The routine runs in Claude's cloud with the repository checked out. **It cannot reach the
OpenSEO container**: `references/setup.md` binds it to `127.0.0.1` on the user's machine, so
there is no crawl, no fresh snapshot, and no Search Console read from the cloud. It sees exactly
what is committed — `seo-god.json`, the snapshots and readouts under `dist/seo/` or `seo/`, and
the site's source.

The consequence is the part users miss: **the routine's diff is only as fresh as the last
snapshot somebody committed.** If nobody runs MEASURE locally (or from CI), the routine has
nothing new to read and its readouts will say so, day after day, honestly and uselessly. It
suits a project whose snapshots land in the repo some other way, or a user whose machine is
rarely on. If neither is true, recommend the OS path again before you set this up.

### 4.2 The routine prompt

Use this verbatim. Fill `<SITE_URL>` from `seo-god.json` and change nothing else — every clause
is load-bearing, and there are no credentials in it anywhere.

```
You are the SEO monitor for <SITE_URL>. You run once a day, unattended, in this repository.
Nobody is watching: ask no questions and stop for nothing.

Where you are: a Claude cloud routine with this repository checked out. You CANNOT reach the
OpenSEO container that produced the snapshots in this repo - it is bound to 127.0.0.1 on the
owner's machine. So you cannot crawl the site, capture a new snapshot, or read Search Console.
Never write as if you did.

1. Read seo-god.json at the repository root. If it is missing, unparseable, or its version is
   not 1, write a readout saying exactly that and stop.
2. Find the newest snapshot file and the newest one before it, under dist/seo/snapshots/ or
   seo/snapshots/ - whichever directory this repo actually has. Those two files are your only
   measurements. No snapshot at all: write a readout saying nothing has been measured yet, and
   stop.
3. If the newest snapshot is not from today, say so in the readout, name its date, and label
   the comparison stale. Today's numbers do not exist here and you never estimate them.
4. Review in this order, and never reorder it: regressions first (new error-severity crawl
   issues, rank drops, clicks down), then quick wins in positions 4 to 15, then at most ONE new
   page. If the seo-god skill is available in this environment, follow its references/act.md -
   it is the authority for every threshold and every edit rule. If it is not, do the read-only
   half: diff the two snapshots and write the readout. Never guess at a rule you cannot read.
   One clause of act.md does NOT apply to you: its "never commit the user's repository" rule is
   written for a run on the owner's own machine, where they review the diff themselves. You are
   not on their machine and a commit is your only way to deliver anything, so step 9 below
   governs commits and overrides that rule. Nothing else in act.md is relaxed.
5. Honesty outranks everything else here. Report only fields the snapshot carries: a null
   position, available:false or measured:false all mean NOT MEASURED - never zero, never
   "unranked", never a placeholder number. No invented statistics, prices, benchmarks, dates,
   quotes or testimonials on any page you write. If answering a query truthfully needs a fact
   you do not have, do not write the page. A run with nothing to do is a successful run: say so
   and stop.
6. If you edit anything, run the project's own build or typecheck command (build_cmd in
   seo-god.json) before the first edit and again after the last, and revert any change that
   does not pass. With no build_cmd in the file, make no edits at all.
7. Write the readout to dist/seo/readouts/<YYYY-MM-DD>.md (or seo/readouts/, matching the
   snapshot directory you used): at most 15 lines - what you did, why, the numbers, what is
   next.
8. Write seo/last-run.json as exactly {"ts":"<UTC ISO 8601, e.g. 2026-08-01T05:12:00Z>",
   "ok":true,"notes":"<short>"}, with ok:false only if you could not complete. This is the file
   the owner's local /seo-god reads to know you ran.
9. Commit the readout, seo/last-run.json and any page edits - nothing else, and nothing under
   .seo-god/ (it is gitignored and holds local secrets). Then stop.

There are no credentials in this prompt and you never need any. If a step seems to require an
API key, a token, or access to the owner's machine, skip it and name it in the readout.
```

### 4.3 Creating it

The user creates the routine themselves — nothing in this skill can create one for them:

- In Claude Code, the `schedule` flow creates cloud routines from a prompt and a daily time
  (`/schedule`, if their install has it). It is the shortest path when they already have it.
- Otherwise, claude.ai/code/routines: connect the GitHub repository, set the daily time in
  their timezone, paste the prompt from 4.2, save.

Tell them what to expect: the routine's output is a commit (or a pull request, if that is how
their routine is configured), so its history lives in the repo — which is also how they can see
at a glance whether it ran.

### 4.4 The cloud marker

The local marker in `.seo-god/last-run.json` can never exist on this path: the directory is
gitignored and the routine runs on a different machine. So on the cloud path — and only on the
cloud path — point the self-check at the committed file the routine writes:

- set `schedule.marker` to `"seo/last-run.json"` (step 8 of the prompt writes it),
- leave it at the repo root rather than under `dist/`, which a build can wipe.

Then SKILL.md's 48h check works exactly as designed, with one caveat to state plainly: it reads
the user's **local** copy, so it only sees the routine's marker after a `git pull`. A week
without pulling reads as a missed run — which is true of their checkout, if not of the routine.
Their independent check is the commit history on GitHub.

This redirection is why section 7 has you write `schedule.marker` **explicitly on both paths**: a
later switch back to an OS-native schedule has to point it back at `.seo-god/last-run.json`, or
the check would keep watching a file the local runner never touches.

## 5. AI visibility is not part of the daily loop

The scheduled run is `claude -p "/seo-god daily"`, which routes to `references/act.md` — and
that file never calls the AI-visibility phase. That is deliberate, not an oversight:
`references/ai-visibility.md` locks its ten-prompt set in a conversation with the user (its
section 2), and executing a playbook item is attended-only (its section 6.5), so an unattended
run there can only measure and report.

**Recommended cadence: monthly, attended — `/seo-god ai-visibility`.** Citation scores move
slowly against a locked prompt set; a daily number would be noise, and the useful half of that
phase (doing something about the score) needs somebody there. Put it on a calendar, not in a
scheduler.

If a user specifically wants the score history without attending, `references/ai-visibility.md`
section 0 already defines the headless path, so a second monthly entry works:

```
cd <project> && claude -p "/seo-god ai-visibility" \
  --permission-mode acceptEdits \
  --add-dir "<skill root>" \
  --allowedTools 'Bash(curl:*),Bash(curl.exe:*),Bash(git status:*),Bash(git diff:*),Bash(git log:*),Bash(git check-ignore:*),Bash(git rev-parse:*),WebSearch' \
  --max-turns 80
```

`--add-dir` is not optional here either — it has the identical wall the daily runner has, and
without it the session cannot read `references/ai-visibility.md` at all.

Warnings, all required: **schedule it hours away from the daily run** — two Claude sessions
in one repository will fight over the same files and the same build gate; **it writes no
marker**, so a monthly run that stops happening is invisible to the 48h check; and **a headless
session may not have `WebSearch` granted** — the grant above requests it, but if the harness
denies it, every prompt fails and the phase honestly records `measured: false` with a zero score
for that month (`references/ai-visibility.md` section 3 owns that branch). Tell the user that
before they schedule it, not after the first empty month. Neither installer creates this entry;
the user adds it themselves.

## 6. Maintenance — what accumulates, and what is safe to delete

| Path | What it is | Safe to delete? |
| --- | --- | --- |
| `.seo-god/backup/<run-stamp>/` | undo snapshots taken before each edit batch by AUDIT and ACT | yes, once a run is old — anything older than ~14 days is a snapshot of files you have since committed. The skill never deletes them for you. |
| `.seo-god/cron.log`, `.seo-god/launchd.log` | the scheduler's raw stdout/stderr | yes, any time. They grow forever otherwise. Windows keeps its history in Task Scheduler instead of a file. |
| `.seo-god/run.lock` | the zero-byte lock `flock` holds (Linux) | leave it |
| `.seo-god/last-run.json` | the marker the self-check reads | no — deleting it reads as a missed run |
| `dist/seo/snapshots/`, `dist/seo/readouts/` (or `seo/…`) | the measurement history and the daily readouts | **no.** The diff compares today against the newest earlier snapshot; deleting them deletes the ability to see a regression. |

Everything under `.seo-god/` is gitignored and local. Only the snapshots, readouts and
`seo-god.json` belong in the repo.

## 7. Write state

Read `seo-god.json`, modify, write the whole object back — preserving every key you do not
recognise, keeping `version: 1`:

- `schedule.mode` — `"os"` or `"cloud"`.
- `schedule.time_local` — the `HH:MM` you actually registered, exactly as passed to the installer.
- `schedule.marker` — write it explicitly on **both** paths, never "leave it as you found it":
  `".seo-god/last-run.json"` on the OS path, `"seo/last-run.json"` on the cloud path (4.4). The
  reason is switching: a project that was on a cloud routine has this key pointing at the
  committed file, and an OS install that leaves it there points the self-check at a path nothing
  writes any more — so SKILL.md would warn about a missed run in every single invocation, for
  ever, while the schedule is in fact working. Whichever path you install, set the key that
  path's runner actually writes.
- `phases.schedule` — `"in_progress"` when you start this file, `"done"` only after the
  installer exited 0 and echoed the entry it registered (or, on the cloud path, after the user
  confirms the routine is saved). An installer that refused leaves the phase at
  `"in_progress"`: report its message verbatim and stop.

Never write `.seo-god/last-run.json` from here, in any circumstance, on either path. It is the
runner's file, and a marker written by anything else is a lie about a run that did not happen.

## 8. Hand back

Briefly, without embellishment:

- what was registered, in one line, and when it next fires;
- where tomorrow's readout will appear, and that the loop never commits (OS path) or that the
  routine commits its readout (cloud path);
- that a missed run shows up as a warning at the start of their next `/seo-god` session — and
  that a hard-killed run shows up as a silent gap first, then that warning (section 3);
- the uninstall command for their OS, which the installer also printed;
- the AI-visibility cadence from section 5, if they have run that phase.

## 9. Troubleshooting — marker message to cause

| What the user sees | What it means | What to do |
| --- | --- | --- |
| `last run: never`, right after installing | expected — no run has fired yet | wait for the first fire, or run `/seo-god act` now |
| `ok:false`, `claude CLI not found` | the scheduler's `PATH` has no `claude` (launchd and cron both start minimal) | macOS: re-run the installer from a shell where `claude --version` works. Linux: add a `PATH=` line at the top of `crontab -e`. Windows: fix the CLI install. |
| `ok:false`, `seo-god.json not found in the working directory` | the entry's working directory is wrong, or the project moved | re-run the installer from the project root |
| `ok:false`, `failed during <step> (line N)` | the runner died at that step | quote it to the user verbatim; `<step>` names the stage, and the scheduler's log has the rest |
| `ok:false`, `interrupted during <step>` | something asked the run to stop mid-flight | usually a logout or a shutdown during the run; no action if the next run is clean |
| `ok:false`, `failed during claude -p /seo-god daily` with no other clue | most often the session hit `--max-turns 80` and exited non-zero | read yesterday's readout for how far it got; a run that does the full loop on a large site can reach the cap, and raising it is a hand-edit of the runner's last line |
| marker notes carry `skill dir not found, phase files unreadable` | the skill folder moved or was renamed after the schedule was installed | re-run the installer so the entry carries the new path, then prove it with section 2.5's dry run |
| marker stale, log empty or absent | the entry never fired: machine off, task disabled, agent not loaded | Windows: Task Scheduler → SEO-GOD Daily → History. macOS: `launchctl list \| grep com.seo-god.daily`. Linux: `crontab -l`, then the system log for `CRON`. |
| marker stale, log shows a run that started and stopped | a hard kill — the 2h limit, a power cut, a forced reboot (section 3) | read yesterday's readout for what it was doing; a run that hits 2h is usually waiting on a crawl that never completed |
| `mode` is `cloud` and the marker is missing | nothing has been pulled yet | `git pull`; still nothing means the routine has not run — check it in claude.ai and look for its commits |
| `mode` is `cloud` and the marker is **stale** | most likely a checkout that has not been pulled for days, not a stopped routine | **`git pull` first**, then read the marker again. Still stale → check the routine's commit history on GitHub and the routine itself in claude.ai |

**Read the `mode` before you debug.** Every row above `mode is cloud` assumes an OS-native
entry; on the cloud path there is no task, no agent, no crontab line and no local log to inspect,
so those checks return nothing and prove nothing. `git pull`, the repository's commit history and
the routine's own page are the whole diagnostic surface there.

Every row is a real state, and none of them is a reason to soften the warning. The warning is
the feature.
