# SEO-GOD daily runner — Windows (pwsh 7; kept free of 7-only syntax so
# powershell.exe 5.1 can run it too).
#
# Run it FROM THE PROJECT ROOT: the directory that holds seo-god.json. The
# scheduled task created by references/schedule.md sets that working directory.
#
# It probes the local OpenSEO container, hands the run to Claude Code
# (`/seo-god daily`), and ALWAYS leaves a run marker at .seo-god/last-run.json —
# the file SKILL.md's missed-run self-check reads:
#   {"ts":"<UTC ISO 8601>","ok":true|false,"notes":"<short>"}
# The marker is this script's alone; references/act.md never writes it.
#
# Requires: the `claude` CLI on PATH. Nothing else — unlike the sh runner it
# needs no node, because ConvertFrom-Json reads openseo.url natively.
#
# -SkillDir <path> points at THIS skill's folder. A headless session can only
# read files inside its working directories, and the skill lives outside the
# project, so without --add-dir on that path `claude -p` can read none of
# references/*.md and the loop runs on SKILL.md's summary alone. The installer
# passes the real path into the scheduled task; the default below covers a
# hand-run. Defaults to $env:CLAUDE_CONFIG_DIR\skills\seo-god, else
# $env:USERPROFILE\.claude\skills\seo-god.
#
# SEO_GOD_DRY_RUN=1 prints what would happen, writes an ok:true "dry-run"
# marker, and exits 0 — no network call, no Claude Code session.
#
# There is no per-run timeout here on purpose: the scheduled task owns the
# execution time limit (references/schedule.md sets it).
param([string]$SkillDir = '')

$ErrorActionPreference = 'Stop'

$dry = ($env:SEO_GOD_DRY_RUN -eq '1')
$root = (Get-Location).Path
$marker = Join-Path (Join-Path $root '.seo-god') 'last-run.json'
$script:Step = 'startup'
$script:Suffix = ''
$script:SkillNote = ''
$script:MarkerWritten = $false

if (-not $SkillDir) {
  if ($env:CLAUDE_CONFIG_DIR) {
    $SkillDir = Join-Path (Join-Path $env:CLAUDE_CONFIG_DIR 'skills') 'seo-god'
  } else {
    $SkillDir = Join-Path (Join-Path (Join-Path $env:USERPROFILE '.claude') 'skills') 'seo-god'
  }
}

# The permission grant for an unattended turn. acceptEdits covers Write/Edit and
# a fixed filesystem-command set and NOTHING else — every curl (the whole OpenSEO
# MCP surface) and every git call is denied without this. Read-only git only:
# act.md and audit.md forbid committing, so add/commit/push must never appear.
$allowedTools = 'Bash(curl:*),Bash(curl.exe:*),Bash(git status:*),Bash(git diff:*),Bash(git log:*),Bash(git check-ignore:*),Bash(git rev-parse:*),WebSearch'

function Write-Marker {
  param([bool]$Ok, [string]$Notes)

  $dir = Split-Path -Parent $marker
  if (-not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $payload = [ordered]@{
    # InvariantCulture: ':' is the culture's time separator in a .NET custom
    # format string, so a non-en culture would otherwise emit 14.02.03.
    ts    = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
    ok    = $Ok
    notes = $Notes
  }
  # WriteAllText: UTF-8 with no BOM (a BOM breaks JSON.parse), absolute path
  # (.NET does not share PowerShell's location), and an LF ending to match the
  # sh runner's marker byte for byte.
  [System.IO.File]::WriteAllText($marker, (($payload | ConvertTo-Json -Compress) + "`n"))
  $script:MarkerWritten = $true
}

# Both notes matter and neither may overwrite the other: an unreachable OpenSEO
# and unreadable phase files are different degradations of the same run.
function Get-AllNotes {
  if ($script:Suffix -and $script:SkillNote) { return "$script:Suffix; $script:SkillNote" }
  if ($script:Suffix) { return $script:Suffix }
  return $script:SkillNote
}

# Any unhandled terminating error — including a non-zero exit from claude — lands here.
trap {
  [Console]::Error.WriteLine("seo-god: $($_.Exception.Message)")
  Write-Marker -Ok $false -Notes "failed during $script:Step (line $($_.InvocationInfo.ScriptLineNumber))"
  exit 1
}

try {
  $script:Step = 'reading seo-god.json'
  $config = Join-Path $root 'seo-god.json'
  if (-not (Test-Path -LiteralPath $config -PathType Leaf)) {
    [Console]::Error.WriteLine("seo-god: seo-god.json not found in $root - run this from the project root")
    Write-Marker -Ok $false -Notes 'seo-god.json not found in the working directory'
    exit 1
  }

  $openseoUrl = ''
  try {
    # An unreadable URL costs the probe, never the run.
    $openseoUrl = [string](Get-Content -LiteralPath $config -Raw | ConvertFrom-Json).openseo.url
  } catch {
    $openseoUrl = ''
  }
  # Exactly one trailing slash, matching the sh runner's ${OPENSEO_URL%/}.
  $openseoUrl = $openseoUrl.Trim() -replace '/$', ''
  if (-not $openseoUrl) { $script:Suffix = 'openseo.url unreadable, probe skipped' }

  # --add-dir only when the directory exists (claude validates it at startup and
  # a missing path is a hard startup failure) and only when it is not already
  # inside the project root, where the session can read it anyway.
  $script:Step = 'resolving skill dir'
  $addDirArgs = @()
  $skillAbs = ''
  if (Test-Path -LiteralPath $SkillDir -PathType Container) {
    $skillAbs = (Resolve-Path -LiteralPath $SkillDir).Path
    $insideProject = $false
    if ($skillAbs -eq $root) { $insideProject = $true }
    if ($skillAbs.StartsWith(($root + [System.IO.Path]::DirectorySeparatorChar), [System.StringComparison]::OrdinalIgnoreCase)) { $insideProject = $true }
    if (-not $insideProject) { $addDirArgs = @('--add-dir', $skillAbs) }
  } else {
    $script:SkillNote = 'skill dir not found, phase files unreadable'
    [Console]::Error.WriteLine("seo-god: warn: skill dir not found at $SkillDir - the run cannot read references/*.md")
  }

  if ($dry) {
    Write-Host "DRY: cwd $root"
    $shown = if ($openseoUrl) { $openseoUrl } else { '<unknown>' }
    Write-Host "DRY: would GET $shown/api/health (max 120s, non-fatal)"
    $shownSkill = if ($skillAbs) { $skillAbs } else { $SkillDir }
    Write-Host "DRY: skill dir $shownSkill"
    # The dry run proves the phase files are READABLE, not merely that the CLI
    # exists: an unreadable act.md is the failure that silently guts the loop.
    $actPath = Join-Path (Join-Path $shownSkill 'references') 'act.md'
    if (Test-Path -LiteralPath $actPath -PathType Leaf) {
      Write-Host 'DRY: references/act.md readable - yes'
    } else {
      Write-Host 'DRY: references/act.md readable - NO (the daily loop would run blind)'
    }
    if ($addDirArgs.Count -gt 0) {
      Write-Host "DRY: would pass --add-dir ""$skillAbs"""
    } else {
      Write-Host 'DRY: would pass no --add-dir (skill dir missing, or inside the project)'
    }
    Write-Host "DRY: would pass --allowedTools $allowedTools"
    Write-Host 'DRY: would run claude -p "/seo-god daily" --permission-mode acceptEdits --max-turns 80'
    if (Get-Command claude -ErrorAction SilentlyContinue) {
      Write-Host 'DRY: claude CLI found'
    } else {
      Write-Host 'DRY: claude CLI NOT on PATH - a real run would stop here'
    }
    if ($script:Suffix) { Write-Host "DRY: note - $script:Suffix" }
    if ($script:SkillNote) { Write-Host "DRY: note - $script:SkillNote" }
    Write-Host "DRY: would write $marker"
    Write-Marker -Ok $true -Notes 'dry-run'
    exit 0
  }

  $script:Step = 'claude CLI check'
  if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    [Console]::Error.WriteLine('seo-god: claude CLI not found on PATH')
    Write-Marker -Ok $false -Notes 'claude CLI not found'
    exit 1
  }

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
  $script:Step = 'OpenSEO health probe'
  if ($openseoUrl) {
    try {
      Invoke-RestMethod -Uri "$openseoUrl/api/health" -Method Get -TimeoutSec 120 -ErrorAction Stop | Out-Null
    } catch {
      $script:Suffix = 'openseo unreachable'
      [Console]::Error.WriteLine('seo-god: warn: OpenSEO health probe failed - continuing (act.md degrades)')
    }
  }

  $script:Step = 'claude -p /seo-god daily'
  & claude -p '/seo-god daily' --permission-mode acceptEdits --allowedTools $allowedTools @addDirArgs --max-turns 80
  if ($null -eq $LASTEXITCODE) {
    # `claude` resolved to something that is not a native process — a function,
    # alias or .ps1 shim — so there is no exit code to trust. Never read that as
    # success: the loop may not have run at all.
    [Console]::Error.WriteLine('seo-god: claude produced no exit code - not a native command')
    Write-Marker -Ok $false -Notes 'claude produced no exit code'
    exit 1
  }
  # Native exit codes only raise an error on pwsh 7.4+, so check explicitly.
  if ($LASTEXITCODE -ne 0) { throw "claude exited with code $LASTEXITCODE" }

  $allNotes = Get-AllNotes
  if ($allNotes) {
    Write-Marker -Ok $true -Notes "completed ($allNotes)"
  } else {
    Write-Marker -Ok $true -Notes 'completed'
  }
  exit 0
} finally {
  # The scheduled task's execution-time limit kills this run mid-flight, and
  # PowerShell's own stop request (Ctrl+C, a stopped pipeline) unwinds through
  # here. No marker yet means nothing else recorded the outcome, so the PREVIOUS
  # run's ok:true would survive and hide the miss from SKILL.md's self-check.
  # A hard TerminateProcess — Task Scheduler's "End the task if it runs longer
  # than" — bypasses finally entirely; that residual belongs to T9's scheduler
  # configuration, not to this script.
  if (-not $script:MarkerWritten) {
    Write-Marker -Ok $false -Notes "interrupted during $script:Step"
  }
}
