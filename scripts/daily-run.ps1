# SEO-GOD daily runner (Cursor fork) — Windows (pwsh 7; 5.1-compatible syntax).
#
# Run FROM THE PROJECT ROOT (directory with seo-god.json).
#
# Probes OpenSEO, hands the run to Cursor Agent (`/seo-god daily`), writes
# .seo-god/last-run.json.
#
# Requires: cursor-agent (or `cursor agent`) on PATH, logged in via
# `cursor agent login`. -SkillDir defaults to
# $env:CURSOR_CONFIG_DIR\skills\seo-god or $env:USERPROFILE\.cursor\skills\seo-god.
#
# SEO_GOD_DRY_RUN=1: print plan, write dry-run marker, exit 0.
param([string]$SkillDir = '')

$ErrorActionPreference = 'Stop'

$dry = ($env:SEO_GOD_DRY_RUN -eq '1')
$root = (Get-Location).Path
$marker = Join-Path (Join-Path $root '.seo-god') 'last-run.json'
$script:Step = 'startup'
$script:Suffix = ''
$script:SkillNote = ''
$script:MarkerWritten = $false

# Task Scheduler often starts with a minimal PATH. Prepend known Cursor agent locations.
function Ensure-CursorAgentPath {
  $candidates = @(
    (Join-Path $env:LOCALAPPDATA 'cursor-agent'),
    (Join-Path $env:LOCALAPPDATA 'Programs\cursor\resources\app\bin'),
    (Join-Path $env:USERPROFILE '.local\bin'),
    (Join-Path $env:USERPROFILE 'AppData\Local\cursor-agent')
  )
  $prefix = @()
  foreach ($c in $candidates) {
    if ($c -and (Test-Path -LiteralPath $c -PathType Container)) {
      $prefix += $c
    }
  }
  if ($prefix.Count -gt 0) {
    $env:Path = ($prefix -join ';') + ';' + $env:Path
  }
}

Ensure-CursorAgentPath

if (-not $SkillDir) {
  if ($env:CURSOR_CONFIG_DIR) {
    $SkillDir = Join-Path (Join-Path $env:CURSOR_CONFIG_DIR 'skills') 'seo-god'
  } else {
    $SkillDir = Join-Path (Join-Path (Join-Path $env:USERPROFILE '.cursor') 'skills') 'seo-god'
  }
}

function Resolve-CursorAgent {
  $cmd = Get-Command cursor-agent -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cmd -and $cmd.Source) {
    return @{ Kind = 'cursor-agent'; Path = $cmd.Source }
  }
  $cursor = Get-Command cursor -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cursor -and $cursor.Source) {
    return @{ Kind = 'cursor-agent-via-cursor'; Path = $cursor.Source }
  }
  return $null
}

function Write-Marker {
  param([bool]$Ok, [string]$Notes)

  $dir = Split-Path -Parent $marker
  if (-not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $payload = [ordered]@{
    ts    = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
    ok    = $Ok
    notes = $Notes
  }
  [System.IO.File]::WriteAllText($marker, (($payload | ConvertTo-Json -Compress) + "`n"))
  $script:MarkerWritten = $true
}

function Get-AllNotes {
  if ($script:Suffix -and $script:SkillNote) { return "$script:Suffix; $script:SkillNote" }
  if ($script:Suffix) { return $script:Suffix }
  return $script:SkillNote
}

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
    $openseoUrl = [string](Get-Content -LiteralPath $config -Raw | ConvertFrom-Json).openseo.url
  } catch {
    $openseoUrl = ''
  }
  $openseoUrl = $openseoUrl.Trim() -replace '/$', ''
  if (-not $openseoUrl) { $script:Suffix = 'openseo.url unreadable, probe skipped' }

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

  $agent = Resolve-CursorAgent

  if ($dry) {
    Write-Host "DRY: cwd $root"
    $shown = if ($openseoUrl) { $openseoUrl } else { '<unknown>' }
    Write-Host "DRY: would GET $shown/api/health (max 120s, non-fatal)"
    $shownSkill = if ($skillAbs) { $skillAbs } else { $SkillDir }
    Write-Host "DRY: skill dir $shownSkill"
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
    Write-Host 'DRY: would run cursor-agent -p "/seo-god daily" --print --force --trust'
    if ($agent) {
      Write-Host "DRY: Cursor agent CLI found ($($agent.Kind) -> $($agent.Path))"
    } else {
      Write-Host 'DRY: Cursor agent CLI NOT on PATH - a real run would stop here'
    }
    if ($script:Suffix) { Write-Host "DRY: note - $script:Suffix" }
    if ($script:SkillNote) { Write-Host "DRY: note - $script:SkillNote" }
    Write-Host "DRY: would write $marker"
    Write-Marker -Ok $true -Notes 'dry-run'
    exit 0
  }

  $script:Step = 'Cursor agent CLI check'
  if (-not $agent) {
    [Console]::Error.WriteLine('seo-god: cursor-agent not found on PATH (install Cursor Agent CLI, then cursor agent login)')
    Write-Marker -Ok $false -Notes 'cursor-agent not found'
    exit 1
  }

  $script:Step = 'OpenSEO health probe'
  if ($openseoUrl) {
    try {
      Invoke-RestMethod -Uri "$openseoUrl/api/health" -Method Get -TimeoutSec 120 -ErrorAction Stop | Out-Null
    } catch {
      $script:Suffix = 'openseo unreachable'
      [Console]::Error.WriteLine('seo-god: warn: OpenSEO health probe failed - continuing (act.md degrades)')
    }
  }

  $script:Step = 'cursor-agent /seo-god daily'
  $agentArgs = @('-p', '/seo-god daily', '--print', '--force', '--trust') + $addDirArgs
  if ($agent.Kind -eq 'cursor-agent') {
    & $agent.Path @agentArgs
  } else {
    # `cursor agent ...`
    $viaCursor = @('agent') + $agentArgs
    & $agent.Path @viaCursor
  }
  if ($null -eq $LASTEXITCODE) {
    [Console]::Error.WriteLine('seo-god: cursor-agent produced no exit code - not a native command')
    Write-Marker -Ok $false -Notes 'cursor-agent produced no exit code'
    exit 1
  }
  if ($LASTEXITCODE -ne 0) { throw "cursor-agent exited with code $LASTEXITCODE" }

  $allNotes = Get-AllNotes
  if ($allNotes) {
    Write-Marker -Ok $true -Notes "completed ($allNotes)"
  } else {
    Write-Marker -Ok $true -Notes 'completed'
  }
  exit 0
} finally {
  if (-not $script:MarkerWritten) {
    Write-Marker -Ok $false -Notes "interrupted during $script:Step"
  }
}
