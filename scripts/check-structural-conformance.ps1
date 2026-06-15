#Requires -Version 5.1
# Structural-conformance gate (spec V5). Every Added/Copied/Renamed tracked path must
# match an allowed pattern in the committed structure manifest, else HARD-BLOCK. This is
# the mechanical fix for cross-session structural divergence: the manifest is the explicit
# source of truth, so an amnesic session cannot invent a divergent folder layout.
#
# Read-only checker (writes nothing). Runs locally (staged/index diff) and in CI (base..head).
# The manifest is the authority; the agent does not judge conformance, it reacts to exit 1.
[CmdletBinding()]
param(
    [string] $RepoRoot = '',
    [string] $ManifestPath = '.github/pr-quality-gate/structure-manifest.txt',
    [string[]] $Paths,                 # explicit paths (tests); else derive from the diff
    [string] $BaseRef = '',            # CI: diff BaseRef..HEAD; else the staged (index) diff
    [switch] $AllTracked,              # bootstrap validation: check every tracked file
    [switch] $Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'lib/repo-root.psm1') -Force -DisableNameChecking

$ExitOk = 0; $ExitViolation = 1; $ExitConfig = 2

if ($RepoRoot) {
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
} else {
    $RepoRoot = Resolve-RepoRoot -Explicit '' -ScriptRoot $PSScriptRoot -Anchors @('scripts/check-structural-conformance.ps1') -RequireGitWorkTree
}

function Write-Info { param([string] $Message) if (-not $Quiet) { Write-Host $Message } }

# Manifest source. When checking a diff against a base ref (CI + the local-CI mirror) and the
# caller did NOT pin an explicit -ManifestPath, read the manifest from the PROTECTED BASE so a
# PR cannot broaden its OWN gate (spec V3d): a new layout pattern must land in a prior reviewed
# commit on the base first. Falls back to the worktree manifest when the base lacks it (bootstrap:
# the commit that first introduces the manifest). An explicit -ManifestPath always wins (tests, or
# a pre-extracted file); the staged/index path (no -BaseRef) uses the worktree manifest.
$manifestLines = $null
$manifestSource = ''
$baseResolved = $false
if (-not $PSBoundParameters.ContainsKey('ManifestPath') -and $BaseRef) {
    # Probe the base TREE for the manifest first (separating the three cases an unchecked `git show`
    # conflates): ls-tree nonzero = base ref unreadable (unresolvable / not fetched / object error)
    # -> fail closed, a hard-block gate must NOT fall back to the PR-head manifest; empty output =
    # the manifest is genuinely absent at the base = legit bootstrap fallback; an entry present =
    # bind to the base manifest (a subsequent read failure is then a real error, not "absent").
    $entry = & git -C $RepoRoot ls-tree $BaseRef -- $ManifestPath 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "check-structural-conformance: cannot read base ref '$BaseRef' (is it fetched?). Failing closed - a hard-block gate must not fall back to the PR-head manifest."
        exit $ExitConfig
    }
    if ($entry) {
        $shown = & git -C $RepoRoot show "${BaseRef}:$ManifestPath" 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "check-structural-conformance: base manifest '${BaseRef}:$ManifestPath' exists but could not be read (exit $LASTEXITCODE). Failing closed."
            exit $ExitConfig
        }
        # Bind to the base manifest even when empty - an empty base manifest is a misconfiguration
        # that must fail closed (-> "no usable rules", exit 2), NOT silently fall back to the PR-head
        # worktree manifest (which would let a PR define its own gate).
        if ($null -eq $shown) { $manifestLines = @() } else { $manifestLines = @($shown) }
        $manifestSource = "base-pinned from $BaseRef"
        $baseResolved = $true
    }
}
if (-not $baseResolved) {
    $manifestFull = Join-Path $RepoRoot $ManifestPath
    if (-not (Test-Path -LiteralPath $manifestFull -PathType Leaf)) {
        Write-Info "check-structural-conformance: no manifest at '$ManifestPath'; nothing to enforce."
        exit $ExitOk
    }
    $manifestLines = [IO.File]::ReadAllLines($manifestFull)
    $manifestSource = "worktree $ManifestPath"
}
Write-Info "check-structural-conformance: manifest source = $manifestSource"

function ConvertTo-PathRegex {
    param([Parameter(Mandatory)] [string] $Glob)
    $sb = [System.Text.StringBuilder]::new('^')
    $i = 0
    while ($i -lt $Glob.Length) {
        $ch = $Glob[$i]
        if ($ch -eq '*') {
            if ($i + 1 -lt $Glob.Length -and $Glob[$i + 1] -eq '*') { [void]$sb.Append('.*'); $i += 2 }
            else { [void]$sb.Append('[^/]*'); $i++ }
        } elseif ($ch -eq '?') { [void]$sb.Append('[^/]'); $i++ }
        else { [void]$sb.Append([regex]::Escape([string]$ch)); $i++ }
    }
    [void]$sb.Append('$')
    return $sb.ToString()
}

# Parse + VALIDATE the manifest. Every rule MUST be anchored to a literal first segment
# (no leading-wildcard / pure-wildcard rules), so an over-broad glob cannot silently
# re-open divergence (spec V3d).
$rules = @()
$configErrors = @()
$lineNo = 0
foreach ($raw in $manifestLines) {
    $lineNo++
    $line = $raw.Trim()
    if (-not $line -or $line.StartsWith('#')) { continue }
    $firstSeg = ($line -split '/')[0]
    if ($firstSeg -eq '' -or $firstSeg -match '[*?]') {
        $configErrors += "manifest line ${lineNo}: rule '$line' is not anchored to a literal first path segment (leading-wildcard rules are forbidden - they admit arbitrary divergence)"
        continue
    }
    $rules += [PSCustomObject]@{ Glob = $line; Regex = (ConvertTo-PathRegex $line) }
}
if ($configErrors.Count -gt 0) {
    Write-Host "check-structural-conformance: INVALID manifest:"
    foreach ($e in $configErrors) { Write-Host "  - $e" }
    exit $ExitConfig
}
if ($rules.Count -eq 0) {
    Write-Host "check-structural-conformance: manifest has no usable rules."
    exit $ExitConfig
}

function Get-AcrPaths {
    param([string[]] $GitArgs)
    $out = & git -C $RepoRoot @GitArgs 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "check-structural-conformance: 'git $($GitArgs -join ' ')' failed (exit $LASTEXITCODE); cannot compute the diff (is the base ref fetched?). Failing closed - a hard-block gate must not pass on an uncomputable diff."
        exit $ExitConfig
    }
    $paths = @()
    foreach ($row in @($out)) {
        $fields = ([string]$row) -split "`t"
        if ($fields.Count -lt 2) { continue }
        # A/C: field[1] is the path; R: the NEW path is the last field (the re-homed location)
        $paths += ($fields[$fields.Count - 1]).Trim()
    }
    return @($paths | Where-Object { $_ })
}

if ($PSBoundParameters.ContainsKey('Paths')) {
    $checkPaths = @($Paths)
} elseif ($AllTracked) {
    $lsFiles = @(& git -C $RepoRoot ls-files 2>$null)
    if ($LASTEXITCODE -ne 0) {
        Write-Host "check-structural-conformance: 'git ls-files' failed (exit $LASTEXITCODE). Failing closed."
        exit $ExitConfig
    }
    $checkPaths = @($lsFiles | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
} elseif ($BaseRef) {
    $checkPaths = Get-AcrPaths -GitArgs @('diff', '--name-status', '--diff-filter=ACR', '-M', "$BaseRef...HEAD")
} else {
    $checkPaths = Get-AcrPaths -GitArgs @('diff', '--cached', '--name-status', '--diff-filter=ACR', '-M')
}
$checkPaths = @($checkPaths)

if ($checkPaths.Count -eq 0) {
    Write-Info "check-structural-conformance: no Added/Copied/Renamed paths to check."
    exit $ExitOk
}

$unmatched = @()
foreach ($path in $checkPaths) {
    $norm = ($path -replace '\\', '/').Trim()
    $hit = $rules | Where-Object { $norm -cmatch $_.Regex } | Select-Object -First 1
    if ($hit) { Write-Info "  MATCHED   $norm  ($($hit.Glob))" }
    else { $unmatched += $norm }
}

if ($unmatched.Count -gt 0) {
    Write-Host "check-structural-conformance: $($unmatched.Count) path(s) do NOT conform to the structure manifest:"
    foreach ($u in $unmatched) { Write-Host "  UNMATCHED $u" }
    Write-Host ""
    Write-Host "Either place the file to match an existing manifest pattern, OR (if a new structural"
    Write-Host "convention is genuinely intended) add a pattern to '$ManifestPath' - which is a governance"
    Write-Host "change requiring explicit user sign-off (ask_user)."
    exit $ExitViolation
}

Write-Info "check-structural-conformance: PASS - all $($checkPaths.Count) checked path(s) conform to the manifest."
exit $ExitOk
