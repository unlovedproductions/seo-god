# SEO-GOD schedule installer — Windows Task Scheduler.
#
# Registers the "SEO-GOD Daily" task: pwsh 7 runs <project>\scripts\daily-run.ps1 once a day
# with the PROJECT ROOT as its working directory, because the runner hard-fails unless
# seo-god.json is in the current directory.
#
#   pwsh -NoProfile -File install-schedule.ps1                                 # 05:00, cwd
#   pwsh -NoProfile -File install-schedule.ps1 -Time 05:30
#   pwsh -NoProfile -File install-schedule.ps1 -Time 05:30 -ProjectDir C:\code\mysite
#
# The runner is COPIED into the project first and the task runs that copy, so updating or
# moving the skill folder never breaks a live schedule. Re-running the installer is safe: it
# overwrites the copy and replaces the task definition in place (idempotent).
#
# Uninstall:  Unregister-ScheduledTask -TaskName "SEO-GOD Daily" -Confirm:$false
#
# references/schedule.md documents every flag, the 48h missed-run check, and the things Task
# Scheduler does NOT do. This file avoids PowerShell-7-only syntax so it can also be run by
# Windows PowerShell 5.1 — but the task it registers always targets pwsh 7.
param(
  [string]$Time = "05:00",
  [string]$ProjectDir = (Get-Location).Path
)
$ErrorActionPreference = 'Stop'
$TaskName = 'SEO-GOD Daily'

function Fail {
  param([string]$Message)
  [Console]::Error.WriteLine("install-schedule: $Message")
  exit 1
}

# --- 1. Validate the arguments -------------------------------------------------------------
if ($Time -notmatch '^([01][0-9]|2[0-3]):[0-5][0-9]$') {
  Fail "invalid -Time '$Time' - use 24-hour HH:MM, e.g. 05:00 or 23:30"
}
if (-not (Test-Path -LiteralPath $ProjectDir -PathType Container)) {
  Fail "no such directory: $ProjectDir"
}
$ProjectDir = (Resolve-Path -LiteralPath $ProjectDir).Path
if (-not (Test-Path -LiteralPath (Join-Path $ProjectDir 'seo-god.json') -PathType Leaf)) {
  Fail "no seo-god.json in $ProjectDir - pass -ProjectDir <project root>, or run /seo-god there first"
}

# pwsh only. The runner itself is 5.1-compatible, but under Windows PowerShell 5.1
# $ErrorActionPreference='Stop' turns any stderr line a native command writes into a
# terminating error - so a run where `claude` merely logged a warning would be recorded as a
# failure. Never schedule onto 5.1.
# -CommandType Application: a `pwsh` alias or function would resolve with an empty .Source and
# register a task with no program to run.
$pwshCmd = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $pwshCmd -or -not $pwshCmd.Source) {
  Fail 'pwsh (PowerShell 7) is not on PATH - install it, then re-run: winget install --id Microsoft.PowerShell (or https://aka.ms/powershell-release)'
}
$pwshPath = $pwshCmd.Source

# --- 2. Copy the runner into the project ---------------------------------------------------
$srcRunner = Join-Path $PSScriptRoot 'daily-run.ps1'
if (-not (Test-Path -LiteralPath $srcRunner -PathType Leaf)) {
  Fail "daily-run.ps1 is not next to this installer ($PSScriptRoot) - run the copy that ships in the skill's scripts folder"
}
$destDir = Join-Path $ProjectDir 'scripts'
$destRunner = Join-Path $destDir 'daily-run.ps1'

# The skill root, resolved from THIS installer's own location. The runner is copied into the
# project and so cannot derive it; a headless `claude -p` can only read files inside its working
# directories, so without this path passed through as -SkillDir the scheduled run can read none
# of references/*.md. The absolute path lives in the machine-local task, never in the committed
# copy of the runner.
$skillRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

# Refuse BEFORE touching the project. scripts\daily-run.ps1 is not an outlandish name for a file
# the user already has, and a silent Copy-Item -Force over it is the one thing in this installer
# that would destroy their work. Only a file carrying the shipped runner's own header marker may
# be overwritten; the marker is on line 1 of daily-run.ps1.
if (Test-Path -LiteralPath $destRunner -PathType Leaf) {
  $existingHead = ''
  try { $existingHead = (Get-Content -LiteralPath $destRunner -TotalCount 5 -ErrorAction Stop) -join "`n" } catch { $existingHead = '' }
  if ($existingHead -notmatch 'SEO-GOD daily runner') {
    Fail "$destRunner already exists and is not the seo-god runner - move or rename it, then re-run. Nothing was scheduled."
  }
}

if (-not (Test-Path -LiteralPath $destDir -PathType Container)) {
  New-Item -ItemType Directory -Force -Path $destDir | Out-Null
}
$runnerNote = 'copied'
if ((Test-Path -LiteralPath $destRunner -PathType Leaf) -and
    ((Resolve-Path -LiteralPath $destRunner).Path -eq (Resolve-Path -LiteralPath $srcRunner).Path)) {
  # -ProjectDir pointed at the skill folder itself: source and destination are one file.
  $runnerNote = 'already in place'
} else {
  Copy-Item -LiteralPath $srcRunner -Destination $destRunner -Force
  # Strips a Zone.Identifier inherited from a downloaded skill folder, which would otherwise
  # make the copy untrusted under a RemoteSigned execution policy.
  Unblock-File -LiteralPath $destRunner -ErrorAction SilentlyContinue
}
# Verify the copy BEFORE registering anything: a task pointed at a missing file fails daily.
if (-not (Test-Path -LiteralPath $destRunner -PathType Leaf)) {
  Fail "the runner did not land at $destRunner - nothing was scheduled"
}

# --- 3. Two non-fatal pre-flight warnings --------------------------------------------------
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
  Write-Host "warn: the claude CLI is not on PATH - until it is, every run records ok:false, 'claude CLI not found'"
}
try {
  $policy = (& $pwshPath -NoProfile -NonInteractive -Command 'Get-ExecutionPolicy' 2>$null | Select-Object -First 1)
  if ($policy -eq 'Restricted' -or $policy -eq 'AllSigned') {
    Write-Host "warn: pwsh execution policy is $policy - the task cannot run a .ps1 file. Fix: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned"
  }
} catch {
  # A policy we could not read is not a reason to refuse; the marker reports a failed run.
}

# --- 4. Register the task ------------------------------------------------------------------
$hh = [int]$Time.Substring(0, 2)
$mm = [int]$Time.Substring(3, 2)
# Start the trigger at the NEXT occurrence, with two minutes of margin. With today's
# occurrence already in the past, StartWhenAvailable reads it as a missed start and can fire a
# full unattended run minutes after install - which nobody asked for while they are still
# sitting at the machine. The margin covers installing at 04:59 for 05:00: that run belongs to
# tomorrow, not to the middle of this setup.
$at = Get-Date -Hour $hh -Minute $mm -Second 0 -Millisecond 0
if ($at -le (Get-Date).AddMinutes(2)) { $at = $at.AddDays(1) }

$existed = [bool](Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)

$taskArgument = "-NoProfile -File `"$destRunner`" -SkillDir `"$skillRoot`""
$action = New-ScheduledTaskAction -Execute $pwshPath `
  -Argument $taskArgument -WorkingDirectory $ProjectDir
$trigger = New-ScheduledTaskTrigger -Daily -At $at
# AllowStartIfOnBatteries + DontStopIfGoingOnBatteries: a laptop on battery still runs, and a
# run does not die when the charger comes out. StartWhenAvailable: a start missed because the
# machine was off happens at the next opportunity. WakeToRun: wakes it from sleep (needs wake
# timers allowed in the power plan). IgnoreNew: never two runs in one repo at once.
# ExecutionTimeLimit 2h: a stuck agentic session is killed rather than left running all day -
# Task Scheduler terminates it hard, so read the hard-kill note in references/schedule.md.
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
  -StartWhenAvailable -WakeToRun -MultipleInstances IgnoreNew `
  -ExecutionTimeLimit (New-TimeSpan -Hours 2)
$description = 'SEO-GOD daily loop: runs scripts/daily-run.ps1 in the project root, which hands the run to Claude Code (/seo-god daily) and writes .seo-god/last-run.json.'

try {
  Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
    -Settings $settings -Description $description -Force | Out-Null
} catch {
  Fail "Register-ScheduledTask failed: $($_.Exception.Message)"
}

# --- 5. Read it back and report ------------------------------------------------------------
$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $task) { Fail "the task is not registered after Register-ScheduledTask reported success" }

# Never trust the registration call alone - a group policy can drop individual settings.
$s = $task.Settings
$dropped = @()
if ($s.WakeToRun -ne $true) { $dropped += 'WakeToRun' }
if ($s.StartWhenAvailable -ne $true) { $dropped += 'StartWhenAvailable' }
if ($s.DisallowStartIfOnBatteries -ne $false) { $dropped += 'AllowStartIfOnBatteries' }
if ($s.StopIfGoingOnBatteries -ne $false) { $dropped += 'DontStopIfGoingOnBatteries' }
if ($s.ExecutionTimeLimit -ne 'PT2H') { $dropped += 'ExecutionTimeLimit=2h' }
if ($s.MultipleInstances -ne 'IgnoreNew') { $dropped += 'MultipleInstances=IgnoreNew' }
if ($dropped.Count -gt 0) {
  Write-Host "warn: the registered task did not keep: $($dropped -join ', ') - a group policy may be overriding it"
}

$nextRun = 'unknown (open Task Scheduler to check)'
$info = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
if ($info -and $info.NextRunTime) {
  # InvariantCulture: ':' is the culture's time separator inside a .NET custom format string.
  $nextRun = $info.NextRunTime.ToString('yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
}
$verb = 'Registered'
if ($existed) { $verb = 'Replaced' }

Write-Host ""
Write-Host "$verb scheduled task '$TaskName' - daily at $Time local time. Runner $runnerNote."
Write-Host "  runs:        $pwshPath $taskArgument"
Write-Host "  working dir: $ProjectDir  (seo-god.json must stay here)"
Write-Host "  skill dir:   $skillRoot"
Write-Host "               passed as -SkillDir, so the scheduled run can read the phase files in references/"
Write-Host "  next run:    $nextRun  (the next occurrence; a time under 2 minutes away goes to tomorrow, never mid-install)"
Write-Host "  hardening:   runs on battery, survives unplugging, wakes the PC, catches up a start missed while it was off, never overlaps itself, killed after 2h"
Write-Host "  logged at:   Task Scheduler > Task Status (Windows keeps the history, not a log file)"
Write-Host "  marker:      $ProjectDir\.seo-god\last-run.json - /seo-god warns you when it goes 48h stale"
Write-Host "  dry run it:  `$env:SEO_GOD_DRY_RUN=1; Push-Location '$ProjectDir'; pwsh -NoProfile -File '$destRunner' -SkillDir '$skillRoot'; Pop-Location; Remove-Item Env:\SEO_GOD_DRY_RUN"
Write-Host "  uninstall:   Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false"
Write-Host ""
Write-Host "The task runs as you and only while you are logged on. It is not a service: a PC that"
Write-Host "is off at $Time runs nothing until it is back on."
exit 0
