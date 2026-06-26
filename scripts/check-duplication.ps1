#Requires -Version 5.1
# Duplication (DRY) detector - a HEURISTIC (spec V3c: PARTIALLY mechanical). Flags an added
# contiguous block of >= MinLines normalized, non-trivial lines whose signature ALSO appears
# as a block in committed (HEAD) content OR is repeated within the same staged changeset.
# Catches obvious copy-paste; it does NOT prove DRY compliance (renamed/reordered/below-
# threshold clones slip through - those remain agent judgment + manual review).
[CmdletBinding()]
param(
    [string] $RepoRoot = '',
    [int] $MinLines = 6,
    [string] $BaseRef = '',
    [string] $WaiverPath = '.github/pr-quality-gate/dry-waivers.txt',
    [switch] $Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/repo-root.psm1') -Force -DisableNameChecking

$ExitOk = 0; $ExitViolation = 1
if ($RepoRoot) { $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path }
else { $RepoRoot = Resolve-RepoRoot -Explicit '' -ScriptRoot $PSScriptRoot -Anchors @('scripts/check-duplication.ps1') -RequireGitWorkTree }
function Write-Info { param([string] $M) if (-not $Quiet) { Write-Host $M } }

# A duplicated block can be JUSTIFIED (dry-audit disposition) when it is idiomatic boilerplate
# that is intentionally self-contained (per-script bootstrap, required CI checkout, etc.). The
# waiver is keyed on a short hash of the EXACT normalized block, so it covers only that block and
# self-expires the moment the code changes (forcing a re-justification rather than rotting open).
function Get-SigHash {
    param([string] $Sig)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Sig))) -replace '-', '').ToLower().Substring(0, 16) }
    finally { $sha.Dispose() }
}
$waivers = @{}
$waiverFull = Join-Path $RepoRoot $WaiverPath
if (Test-Path -LiteralPath $waiverFull -PathType Leaf) {
    foreach ($wl in [IO.File]::ReadAllLines($waiverFull)) {
        $t = $wl.Trim()
        if (-not $t -or $t.StartsWith('#')) { continue }
        $parts = $t -split '\s+', 2
        if ($parts[0]) { $waivers[$parts[0].ToLower()] = if ($parts.Count -ge 2) { $parts[1] } else { '(no reason given)' } }
    }
}

function Get-Normalized { param([string] $Line) ($Line -replace '\s+', ' ').Trim() }
function Test-Trivial { param([string] $Norm) ($Norm.Length -le 2) -or ($Norm -notmatch '[A-Za-z0-9]') }

$diffArgs = if ($BaseRef) { @('-c', 'core.quotePath=false', 'diff', '-U0', '--no-color', "$BaseRef...HEAD") } else { @('-c', 'core.quotePath=false', 'diff', '--cached', '-U0', '--no-color') }
$diffLines = @(& git -C $RepoRoot @diffArgs 2>$null)
if ($LASTEXITCODE -ne 0) {
    Write-Host "check-duplication: 'git $($diffArgs -join ' ')' failed (exit $LASTEXITCODE); cannot compute the diff (is the base ref fetched?). Failing closed."
    exit $ExitViolation
}

$blocks = New-Object System.Collections.ArrayList   # each: @{ File; Start; Lines(normalized) }
$curFile = $null; $curRun = $null; $curExcluded = $false
function Complete-Run {
    if ($curRun -and $curRun.Lines.Count -ge $MinLines) { [void]$blocks.Add($curRun) }
    $script:curRun = $null
}
function Test-GeneratedMirror { param([string] $Path) ($Path -replace '\\', '/') -cmatch '^\.github/pr-quality-gate/pattern-catalog\.md$' }
foreach ($line in $diffLines) {
    if ($line -cmatch '^\+\+\+\s+b/([^\t]+)') { Complete-Run; $curFile = $matches[1]; $curExcluded = (Test-GeneratedMirror $curFile); continue }
    if ($line -cmatch '^(---|diff |index |@@|\\ )' ) { Complete-Run; continue }
    if ($line.StartsWith('+')) {
        if ($curExcluded) { continue }
        $norm = Get-Normalized $line.Substring(1)
        if (-not $curRun) { $script:curRun = [PSCustomObject]@{ File = $curFile; Lines = (New-Object System.Collections.ArrayList) } }
        [void]$curRun.Lines.Add($norm)
    } else { Complete-Run }
}
Complete-Run

if ($blocks.Count -eq 0) { Write-Info "check-duplication: no added blocks >= $MinLines lines."; exit $ExitOk }

function Add-Windows {
    param($Index, [string] $File, [string[]] $Content)
    $norm = @($Content | ForEach-Object { Get-Normalized $_ })
    for ($i = 0; $i + $MinLines -le $norm.Count; $i++) {
        $window = $norm[$i..($i + $MinLines - 1)]
        $nonTrivial = (@($window | Where-Object { -not (Test-Trivial $_) })).Count
        if ($nonTrivial * 2 -lt $MinLines) { continue }   # skip low-signal (mostly-boilerplate) windows
        $sig = ($window -join "`n")
        if (-not $Index.ContainsKey($sig)) { $Index[$sig] = New-Object System.Collections.ArrayList }
        [void]$Index[$sig].Add("${File}:$($i + 1)")
    }
}
$baselineRef = if ($BaseRef) { $BaseRef } else { 'HEAD' }
$headIndex = @{}
# Typed ls-tree output: "<mode> <type> <sha>`t<path>". Index ONLY blob entries (gitlinks/submodules
# are commit entries, skipped). Index content by OBJECT ID via `git cat-file` (NOT `git show <ref>:<path>`)
# so unusual/quoted paths can't break the lookup; the path is used only for reporting. A cat-file
# failure on a present blob (corrupt/missing object) fails closed rather than silently dropping it.
$lsTree = @(& git -C $RepoRoot ls-tree -r $baselineRef 2>$null)
if ($LASTEXITCODE -ne 0) {
    Write-Host "check-duplication: 'git ls-tree $baselineRef' failed (exit $LASTEXITCODE); cannot index the baseline (is the base ref fetched?). Failing closed."
    exit $ExitViolation
}
$headBlobs = @($lsTree | ForEach-Object {
    $parts = ([string]$_) -split "`t", 2
    if ($parts.Count -eq 2) {
        $meta = ($parts[0] -split '\s+')
        if ($meta[1] -eq 'blob') { [PSCustomObject]@{ Sha = $meta[2]; Path = $parts[1].Trim() } }
    }
} | Where-Object { $_ })
foreach ($hb in $headBlobs) {
    if (Test-GeneratedMirror $hb.Path) { continue }
    $content = @(& git -C $RepoRoot cat-file -p $hb.Sha 2>$null)
    if ($LASTEXITCODE -ne 0) {
        Write-Host "check-duplication: 'git cat-file -p $($hb.Sha)' ($($hb.Path)) failed (exit $LASTEXITCODE); cannot index a baseline blob. Failing closed."
        exit $ExitViolation
    }
    if ($content.Count -ge $MinLines) { Add-Windows -Index $headIndex -File $hb.Path -Content $content }
}

$addedIndex = @{}
$findings = @()
$waived = @()
foreach ($block in $blocks) {
    $lines = @($block.Lines)
    for ($i = 0; $i + $MinLines -le $lines.Count; $i++) {
        $window = $lines[$i..($i + $MinLines - 1)]
        $nonTrivial = (@($window | Where-Object { -not (Test-Trivial $_) })).Count
        if ($nonTrivial * 2 -lt $MinLines) { continue }
        $sig = ($window -join "`n")
        $dupOf = $null
        if ($headIndex.ContainsKey($sig)) { $dupOf = "existing committed content at $($headIndex[$sig][0])" }
        elseif ($addedIndex.ContainsKey($sig)) { $dupOf = "within this changeset (also $($addedIndex[$sig]))" }
        if ($dupOf) {
            $h = Get-SigHash $sig
            if ($waivers.ContainsKey($h)) {
                $waived += "waived [$h] '$($block.File)' <-> $dupOf : $($waivers[$h])"
            } else {
                $findings += "added block in '$($block.File)' duplicates $dupOf  [sig:$h]"
            }
        }
        if (-not $addedIndex.ContainsKey($sig)) { $addedIndex[$sig] = "$($block.File)" }
    }
}

$findings = @($findings | Select-Object -Unique)
$waived = @($waived | Select-Object -Unique)
if ($waived.Count -gt 0) {
    Write-Info "check-duplication: $($waived.Count) duplication(s) waived (dry-audit disposition):"
    foreach ($w in $waived) { Write-Info "  - $w" }
}
if ($findings.Count -gt 0) {
    Write-Host "check-duplication: $($findings.Count) likely duplication(s) (heuristic; >= $MinLines lines):"
    foreach ($f in $findings) { Write-Host "  - $f" }
    Write-Host "Extract the shared logic, OR add the [sig:...] hash to '$WaiverPath' with a justification (dry-audit disposition) if the duplication is intentional idiomatic boilerplate."
    exit $ExitViolation
}
Write-Info "check-duplication: no >= $MinLines-line copy-paste duplication detected (heuristic)."
exit $ExitOk
