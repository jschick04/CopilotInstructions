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

$canonicalAuditPath = '.github/pr-quality-gate/audits/last.md'
$auditFileFullPath = Join-Path $RepoRoot ($canonicalAuditPath -replace '/', [System.IO.Path]::DirectorySeparatorChar)

$playbookPattern = '\.github/playbooks/[a-zA-Z0-9_.-/]+\.md'
$auditPathPattern = '\.github/pr-quality-gate/audits/[a-zA-Z0-9_.-/]+\.md'

$pathRefs = & git -C $RepoRoot grep -nE "$playbookPattern|$auditPathPattern" -- ':!**/HIGH-TIER-SLUGS.md' ':!*.lock' 2>$null

$violations = @()
foreach ($line in $pathRefs) {
    foreach ($match in [regex]::Matches($line, $playbookPattern)) {
        $cited = $match.Value
        if (-not $existingSet[$cited]) {
            $violations += "$line  (cited playbook path '$cited' does not resolve)"
        }
    }
    foreach ($match in [regex]::Matches($line, $auditPathPattern)) {
        $cited = $match.Value
        if ($cited -ne $canonicalAuditPath) {
            $violations += "$line  (audit-file path '$cited' diverges from canonical '$canonicalAuditPath')"
        }
    }
}

if ($violations) {
    foreach ($v in ($violations | Sort-Object -Unique)) { Write-Violation $v }
    exit $script:ExitViolation
}

Write-Host "All playbook references resolve; audit-file path is canonical. ($($existingPlaybooks.Count) playbooks scanned.)"
exit $script:ExitOk
