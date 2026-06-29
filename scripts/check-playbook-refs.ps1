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

# Case-sensitive (Ordinal) lookups: a wrong-case ref (Pre-Commit.md) must NOT false-resolve on case-insensitive Windows when CI runs on case-sensitive Linux.
$existingSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($path in $existingPlaybooks) { [void]$existingSet.Add($path) }
# Case-insensitive view: the wrong-prefix scan flags a ref whose canonical path resolves in ANY case (wrong-prefix + wrong-case is still broken).
$existingSetCI = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($path in $existingPlaybooks) { [void]$existingSetCI.Add($path) }


$playbookPattern = '\.github/playbooks/[a-zA-Z0-9_./-]+\.md'

# Exclude this checker's OWN test file: it embeds fixture citations (including intentionally-broken
# ones) as test data, which are not real references and must not be scanned as such.
$pathRefs = & git -C $RepoRoot grep -nE "$playbookPattern" -- ':!**/HIGH-TIER-SLUGS.md' ':!*.lock' ':!**/*.csv' ':!scripts/tests/check-playbook-refs.tests.ps1' 2>$null
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
        if (-not $existingSet.Contains($cited)) {
            $violations += "$line  (cited playbook path '$cited' does not resolve)"
        }
    }
}

$wrongPrefixFindPattern = '(^|[^./a-zA-Z0-9_-])playbooks/[a-zA-Z0-9_./-]+\.md'
$wrongPrefixExtractPattern = '(?<![./a-zA-Z0-9_-])playbooks/[a-zA-Z0-9_./-]+\.md'
$truncatedRefs = & git -C $RepoRoot grep -nE "$wrongPrefixFindPattern" -- ':!**/HIGH-TIER-SLUGS.md' ':!*.lock' ':!**/*.csv' ':!scripts/tests/check-playbook-refs.tests.ps1' 2>$null
if ($LASTEXITCODE -gt 1) {
    Write-Invocation "git grep for wrong-prefix playbook citations failed (exit $LASTEXITCODE); cannot validate references. Failing closed."
    exit $script:ExitInvocation
}
foreach ($line in $truncatedRefs) {
    foreach ($match in [regex]::Matches($line, $wrongPrefixExtractPattern)) {
        $cited = $match.Value
        $canonical = ".github/$cited"
        if ($existingSetCI.Contains($canonical)) {
            $violations += "$line  (wrong-prefix playbook ref '$cited' is missing the '.github/' root; use '$canonical')"
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
