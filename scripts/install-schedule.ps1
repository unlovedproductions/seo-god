# SEO-GOD schedule installer (Cursor fork) — Windows Task Scheduler.
#
# Registers "SEO-GOD Daily": pwsh 7 runs <project>\scripts\daily-run.ps1 once a day
# with PROJECT ROOT as working directory.
#
#   pwsh -NoProfile -File install-schedule.ps1
#   pwsh -NoProfile -File install-schedule.ps1 -Time 05:30
#   pwsh -NoProfile -File install-schedule.ps1 -Time 05:30 -ProjectDir C:\code\mysite
#
# Uninstall:  Unregister-ScheduledTask -TaskName "SEO-GOD Daily" -Confirm:$false
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

$pwshCmd = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $pwshCmd -or -not $pwshCmd.Source) {
  Fail 'pwsh (PowerShell 7) is not on PATH - install it, then re-run: winget install --id Microsoft.PowerShell (or https://aka.ms/powershell-release)'
}
$pwshPath = $pwshCmd.Source

$srcRunner = Join-Path $PSScriptRoot 'daily-run.ps1'
if (-not (Test-Path -LiteralPath $srcRunner -PathType Leaf)) {
  Fail "daily-run.ps1 is not next to this installer ($PSScriptRoot) - run the copy that ships in the skill's scripts folder"
}
$destDir = Join-Path $ProjectDir 'scripts'
$destRunner = Join-Path $destDir 'daily-run.ps1'

$skillRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

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
  $runnerNote = 'already in place'
} else {
  Copy-Item -LiteralPath $srcRunner -Destination $destRunner -Force
  Unblock-File -LiteralPath $destRunner -ErrorAction SilentlyContinue
}
if (-not (Test-Path -LiteralPath $destRunner -PathType Leaf)) {
  Fail "the runner did not land at $destRunner - nothing was scheduled"
}

# Ensure .seo-god exists for marker writes
$seoGodDir = Join-Path $ProjectDir '.seo-god'
if (-not (Test-Path -LiteralPath $seoGodDir -PathType Container)) {
  New-Item -ItemType Directory -Force -Path $seoGodDir | Out-Null
}

$hasAgent = [bool](Get-Command cursor-agent -CommandType Application -ErrorAction SilentlyContinue) -or
  [bool](Get-Command cursor -CommandType Application -ErrorAction SilentlyContinue)
if (-not $hasAgent) {
  Write-Host "warn: cursor-agent is not on PATH - until it is, every run records ok:false, 'cursor-agent not found'"
  Write-Host "      Install Cursor Agent CLI and run: cursor agent login"
}
try {
  $policy = (& $pwshPath -NoProfile -NonInteractive -Command 'Get-ExecutionPolicy' 2>$null | Select-Object -First 1)
  if ($policy -eq 'Restricted' -or $policy -eq 'AllSigned') {
    Write-Host "warn: pwsh execution policy is $policy - the task cannot run a .ps1 file. Fix: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned"
  }
} catch {
}

$hh = [int]$Time.Substring(0, 2)
$mm = [int]$Time.Substring(3, 2)
$at = Get-Date -Hour $hh -Minute $mm -Second 0 -Millisecond 0
if ($at -le (Get-Date).AddMinutes(2)) { $at = $at.AddDays(1) }

$existed = [bool](Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)

$taskArgument = "-NoProfile -File `"$destRunner`" -SkillDir `"$skillRoot`""
$action = New-ScheduledTaskAction -Execute $pwshPath `
  -Argument $taskArgument -WorkingDirectory $ProjectDir
$trigger = New-ScheduledTaskTrigger -Daily -At $at
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
  -StartWhenAvailable -WakeToRun -MultipleInstances IgnoreNew `
  -ExecutionTimeLimit (New-TimeSpan -Hours 2)
$description = 'SEO-GOD daily loop (Cursor): runs scripts/daily-run.ps1 → cursor-agent /seo-god daily → .seo-god/last-run.json.'

try {
  Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
    -Settings $settings -Description $description -Force | Out-Null
} catch {
  Fail "Register-ScheduledTask failed: $($_.Exception.Message)"
}

$task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $task) { Fail "the task is not registered after Register-ScheduledTask reported success" }

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
  $nextRun = $info.NextRunTime.ToString('yyyy-MM-dd HH:mm', [System.Globalization.CultureInfo]::InvariantCulture)
}
$verb = 'Registered'
if ($existed) { $verb = 'Replaced' }

Write-Host ""
Write-Host "$verb scheduled task '$TaskName' - daily at $Time local time. Runner $runnerNote."
Write-Host "  runs:        $pwshPath $taskArgument"
Write-Host "  working dir: $ProjectDir  (seo-god.json must stay here)"
Write-Host "  skill dir:   $skillRoot"
Write-Host "               passed as -SkillDir, so the scheduled run can read references/"
Write-Host "  next run:    $nextRun  (time under 2 minutes away goes to tomorrow)"
Write-Host "  hardening:   battery OK, wake, catch-up, no overlap, kill after 2h"
Write-Host "  logged at:   Task Scheduler > Task Status"
Write-Host "  marker:      $ProjectDir\.seo-god\last-run.json"
Write-Host "  dry run it:  `$env:SEO_GOD_DRY_RUN=1; Push-Location '$ProjectDir'; pwsh -NoProfile -File '$destRunner' -SkillDir '$skillRoot'; Pop-Location; Remove-Item Env:\SEO_GOD_DRY_RUN"
Write-Host "  uninstall:   Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false"
Write-Host ""
Write-Host "The task runs as you while logged on. A PC off at $Time skips that day until online."
Write-Host "Prerequisite: cursor agent login (once). Agent PATH is bootstrapped inside the runner."
exit 0
