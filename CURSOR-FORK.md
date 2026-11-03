# SEO-GOD (Cursor fork)

Fork of upstream seo-god for **Cursor Agent** + **Cursor Automations** (not Claude Code).

## Install skill

```bash
# Linux / macOS
ln -sfn /path/to/seo-god-cursor ~/.cursor/skills/seo-god

# Windows (PowerShell, Admin not required)
New-Item -ItemType SymbolicLink -Path "$env:USERPROFILE\.cursor\skills\seo-god" -Target "C:\path\to\seo-god-cursor" -Force
# or copy/junction if symlink policy blocks you
```

## Schedule options

| Mode | Command | Notes |
| --- | --- | --- |
| **OS** Linux/macOS | `bash scripts/install-schedule.sh 05:00 <project>` | cron / launchd → `cursor-agent` |
| **OS** Windows | `pwsh -NoProfile -File scripts\install-schedule.ps1 -Time 05:00 -ProjectDir <project>` | Task Scheduler → `daily-run.ps1` |
| **Cloud** | Cursor Automations (cron) + prompt in `references/cloud-prompt.md` | no local OpenSEO |

### OS dry run

```bash
# Unix
SEO_GOD_DRY_RUN=1 bash scripts/daily-run.sh --skill-dir /path/to/seo-god-cursor

# Windows
$env:SEO_GOD_DRY_RUN=1
pwsh -NoProfile -File scripts\daily-run.ps1 -SkillDir C:\path\to\seo-god-cursor
Remove-Item Env:\SEO_GOD_DRY_RUN
```

Expect: `Cursor agent CLI found` and `references/act.md readable`.

### Windows requirements

- PowerShell **7** (`pwsh`) for the scheduled task
- Cursor Agent CLI on PATH (`cursor-agent` or `cursor agent`)
- One-time: `cursor agent login`
- Runner prepends `%LOCALAPPDATA%\cursor-agent` (and similar) to PATH for Task Scheduler

### Cloud requirements

- Repo on GitHub
- Cursor Automations / Cloud Agents enabled
- Committed snapshots under `dist/seo/snapshots/` or `seo/snapshots/` (cloud cannot talk to local OpenSEO)
- Marker: `seo/last-run.json` (`schedule.mode: "cloud"`)

## What changed vs upstream

- Headless: `cursor-agent -p … --print --force --trust` (not `claude -p`)
- Skill path: `~/.cursor/skills/seo-god`
- Cloud: **Cursor Automations**, not claude.ai routines
- Windows Task Scheduler path fully ported to Cursor Agent
