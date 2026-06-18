[CmdletBinding()]
param(
    [string] $RepoRoot = ''
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/repo-root.psm1') -Force
try {
    $RepoRoot = Resolve-RepoRoot -Explicit $RepoRoot -ScriptRoot $PSScriptRoot -Anchors @('.github/playbooks') -RequireGitWorkTree
} catch {
    Write-Host "::error::$($_.Exception.Message)"
    exit 2
}

$script:ExitInvocation = 2
$script:ExitViolation = 1
$script:ExitOk = 0

function Write-Invocation { param([string] $Msg) Write-Host "::error::INVOCATION_FAILED:$Msg" }
function Write-Violation { param([string] $Msg) Write-Host "::error::VIOLATION:$Msg" }


$playbookFolder = Join-Path $RepoRoot '.github/playbooks'
if (-not (Test-Path -LiteralPath $playbookFolder)) {
    Write-Invocation "playbook folder not found: $playbookFolder"
    exit $script:ExitInvocation
}

$existingPlaybooks = Get-ChildItem -Path $playbookFolder -Filter '*.md' -Recurse -File |
    ForEach-Object { ($_.FullName.Substring($RepoRoot.Length + 1) -replace '\\', '/') }

$existingSet = @{}
foreach ($path in $existingPlaybooks) { $existingSet[$path] = $true }


$playbookPattern = '\.github/playbooks/[a-zA-Z0-9_./-]+\.md'

# Exclude this checker's OWN test file: it embeds fixture citations (including intentionally-broken
# ones) as test data, which are not real references and must not be scanned as such.
$pathRefs = & git -C $RepoRoot grep -nE "$playbookPattern" -- ':!**/HIGH-TIER-SLUGS.md' ':!*.lock' ':!scripts/tests/check-playbook-refs.tests.ps1' 2>$null
# git grep: 0 = matches, 1 = no matches (legitimate), >1 = real error. A real failure must fail
# closed (do not silently treat an errored grep as "no broken references").
if ($LASTEXITCODE -gt 1) {
    Write-Invocation "git grep for playbook citations failed (exit $LASTEXITCODE); cannot validate references. Failing closed."
    exit $script:ExitInvocation
}

$violations = @()
foreach ($line in $pathRefs) {
    foreach ($match in [regex]::Matches($line, $playbookPattern)) {
        $cited = $match.Value
        if (-not $existingSet[$cited]) {
            $violations += "$line  (cited playbook path '$cited' does not resolve)"
        }
    }
}

if ($violations) {
    foreach ($v in ($violations | Sort-Object -Unique)) { Write-Violation $v }
    exit $script:ExitViolation
}

$stagePattern = 'git add.{0,5}\.github/pr-quality-gate/audits/(last|post-code-change-last|read-receipts-last)\.md'
$stageHits = & git -C $RepoRoot grep -nE "$stagePattern" -- .github/playbooks 2>$null
if ($LASTEXITCODE -gt 1) {
    Write-Invocation "git grep for the receipt-staging guard failed (exit $LASTEXITCODE); cannot verify no playbook stages a receipt. Failing closed."
    exit $script:ExitInvocation
}
$stageViolations = @()
foreach ($line in @($stageHits)) {
    if ($line) { $stageViolations += "$line  (instructs staging a gitignored audit receipt; receipts are flushed to git notes, never staged - see comment-protocol.md §Persisted audit record)" }
}
if ($stageViolations) {
    foreach ($v in ($stageViolations | Sort-Object -Unique)) { Write-Violation $v }
    exit $script:ExitViolation
}

Write-Host "All playbook references resolve. ($($existingPlaybooks.Count) playbooks scanned.)"
exit $script:ExitOk
