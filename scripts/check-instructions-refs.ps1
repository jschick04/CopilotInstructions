[CmdletBinding()]
param(
    [string] $RepoRoot = ''
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/repo-root.psm1') -Force
try {
    $RepoRoot = Resolve-RepoRoot -Explicit $RepoRoot -ScriptRoot $PSScriptRoot -Anchors @('.github/instructions') -RequireGitWorkTree
} catch {
    Write-Host "::error::$($_.Exception.Message)"
    exit 2
}

$script:ExitInvocation = 2
$script:ExitViolation = 1
$script:ExitOk = 0

function Write-Invocation { param([string] $Msg) Write-Host "::error::INVOCATION_FAILED:$Msg" }
function Write-Violation { param([string] $Msg) Write-Host "::error::VIOLATION:$Msg" }


$instructionsFolder = Join-Path $RepoRoot '.github/instructions'
if (-not (Test-Path -LiteralPath $instructionsFolder)) {
    Write-Invocation "instructions folder not found: $instructionsFolder"
    exit $script:ExitInvocation
}

$existingInstructions = Get-ChildItem -Path $instructionsFolder -Filter '*.instructions.md' -File |
    ForEach-Object { $_.Name }

# Case-sensitive (Ordinal) lookups: a wrong-case ref (CSharp.instructions.md) must NOT false-resolve on the
# case-sensitive Linux CI filesystem (PowerShell hashtables are case-insensitive).
$existingSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($name in $existingInstructions) { [void]$existingSet.Add($name) }

# active-profile.instructions.md is the gitignored, setup-generated per-machine profile selector: absent
# by default (floor fail-closes to full-default per check-profile-invariants.ps1), so refs to it are valid.
$exemptNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
[void]$exemptNames.Add('active-profile.instructions.md')

$refPattern = '[a-zA-Z0-9_.-]+\.instructions\.md'

# Exclude the generated HIGH-TIER-SLUGS.md projection, lock + CSV data ledgers, scripts/tests/* (test suites
# embed synthetic fixture instruction names that are not real references), and this checker's own source (its
# comments may carry example tokens that are not citations). The generated pattern-catalog.md is intentionally
# NOT excluded - its instruction-file references must resolve, as check-playbook-refs validates playbook refs there.
$excludeSpecs = @(':!**/HIGH-TIER-SLUGS.md', ':!*.lock', ':!**/*.csv', ':!scripts/tests/*', ':!scripts/check-instructions-refs.ps1')

$refs = & git -C $RepoRoot grep -nzE "$refPattern" -- $excludeSpecs 2>$null
# git grep: 0 = matches, 1 = no matches (legitimate), >1 = real error. A real failure must fail closed
# (do not silently treat an errored grep as "no broken references").
if ($LASTEXITCODE -gt 1) {
    Write-Invocation "git grep for instruction-file citations failed (exit $LASTEXITCODE); cannot validate references. Failing closed."
    exit $script:ExitInvocation
}

$violations = @()
foreach ($record in $refs) {
    # git grep -nz emits NUL-delimited "<path>\0<lineno>\0<content>"; split on NUL (which cannot appear in a
    # path) so a path containing ':' cannot corrupt parsing, and scan only the content so a file NAMED
    # *.instructions.md outside the folder is not mistaken for a citation via its own path.
    $fields = $record -split "`0", 3
    if ($fields.Count -lt 3) { continue }
    $citation = "$($fields[0]):$($fields[1]):$($fields[2])"
    foreach ($match in [regex]::Matches($fields[2], $refPattern)) {
        $cited = $match.Value
        if ($exemptNames.Contains($cited)) { continue }
        if (-not $existingSet.Contains($cited)) {
            $violations += "$citation  (cited instruction file '$cited' does not resolve to .github/instructions/$cited)"
        }
    }
}

if ($violations) {
    foreach ($v in ($violations | Sort-Object -Unique)) { Write-Violation $v }
    exit $script:ExitViolation
}

Write-Host "All instruction-file references resolve. ($($existingInstructions.Count) instruction files scanned; active-profile.instructions.md exempt as the gitignored profile selector.)"
exit $script:ExitOk
