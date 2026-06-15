#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $BaseRef,
    [string] $HeadRef = 'HEAD',
    [string] $RepoRoot = '',
    [string] $AuditPath = '.github/pr-quality-gate/audits/last.md'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'lib/repo-root.psm1') -Force
try {
    $RepoRoot = Resolve-RepoRoot -Explicit $RepoRoot -ScriptRoot $PSScriptRoot -Anchors @('scripts/check-comment-audit.ps1') -RequireGitWorkTree
} catch {
    Write-Host "::error::$($_.Exception.Message)"
    exit 2
}

$script:ExitOk = 0
$script:ExitViolation = 1
$script:ExitInvocation = 2

function Write-Invocation { param([string] $Msg) Write-Host "::error::INVOCATION_FAILED:$Msg" }
function Write-Violation { param([string] $Msg) Write-Host "::error::VIOLATION:$Msg" }

$modulePath = Join-Path $PSScriptRoot 'lib/comment-audit-helpers.psm1'
if (-not (Test-Path -LiteralPath $modulePath)) {
    Write-Invocation "module not found: $modulePath"
    exit $script:ExitInvocation
}
Import-Module $modulePath -Force


function Invoke-Git {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string[]] $Arguments, [switch] $AllowFailure)
    $tmpErr = [System.IO.Path]::GetTempFileName()
    try {
        $stdout = & git -C $RepoRoot @Arguments 2>$tmpErr
        $exit = $LASTEXITCODE
        $stderr = if (Test-Path -LiteralPath $tmpErr) { Get-Content -Raw -LiteralPath $tmpErr } else { '' }
    } finally {
        if (Test-Path -LiteralPath $tmpErr) { Remove-Item -Force -LiteralPath $tmpErr }
    }
    if ($exit -ne 0 -and -not $AllowFailure) {
        Write-Invocation "git $($Arguments -join ' ') exited $exit; stderr: $($stderr.Trim())"
        exit $script:ExitInvocation
    }
    return [PSCustomObject]@{ Stdout = $stdout; ExitCode = $exit; Stderr = $stderr }
}

$baseShaResult = Invoke-Git -Arguments @('merge-base', $BaseRef, $HeadRef)
$baseSha = ($baseShaResult.Stdout | Out-String).Trim()
if (-not $baseSha) {
    Write-Invocation "merge-base of $BaseRef and $HeadRef is empty"
    exit $script:ExitInvocation
}

$headShaResult = Invoke-Git -Arguments @('rev-parse', $HeadRef)
$headSha = ($headShaResult.Stdout | Out-String).Trim()

if ($baseSha -eq $headSha) {
    Write-Host "OK: base and head are the same commit; nothing to verify."
    exit $script:ExitOk
}

$commitsForwardResult = Invoke-Git -Arguments @('log', '--reverse', '--no-merges', '--format=%H', "$baseSha..$HeadRef")
$commitsForward = @($commitsForwardResult.Stdout) | Where-Object { $_ } | ForEach-Object { $_.Trim() }

if (-not $commitsForward) {
    Write-Host "OK: no non-merge commits in PR range."
    exit $script:ExitOk
}

$violations = @()
foreach ($commitSha in $commitsForward) {
    $shortSha = $commitSha.Substring(0, 8)

    $parentResult = Invoke-Git -Arguments @('rev-parse', "${commitSha}^") -AllowFailure
    if ($parentResult.ExitCode -ne 0) {
        $expectedParentSha = $script:GitEmptyTreeSha
        Write-Host "Commit ${shortSha}: root commit (no parent); expecting parent_sha=EMPTY_TREE"
    } else {
        $expectedParentSha = ($parentResult.Stdout | Out-String).Trim()
    }

    $auditResult = Invoke-Git -Arguments @('show', "${commitSha}:$AuditPath") -AllowFailure
    if ($auditResult.ExitCode -ne 0 -or -not $auditResult.Stdout) {
        $violations += "Commit ${shortSha}: missing $AuditPath in tree"
        continue
    }
    $auditLines = @($auditResult.Stdout) | ForEach-Object { $_ }

    $check = Test-AuditFile -AuditLines $auditLines -ExpectedParentSha $expectedParentSha
    if (-not $check.Valid) {
        foreach ($err in $check.Errors) {
            $violations += "Commit ${shortSha}: $err"
        }
        foreach ($bad in $check.InvalidBullets) {
            $violations += "Commit ${shortSha}: invalid bullet '$($bad.Line)' - $($bad.Reason)"
        }
        continue
    }

    $diffResult = if ($parentResult.ExitCode -ne 0) {
        Invoke-Git -Arguments @('--no-pager', 'diff', $script:GitEmptyTreeSha, $commitSha, '--unified=0')
    } else {
        Invoke-Git -Arguments @('--no-pager', 'diff', "${expectedParentSha}..${commitSha}", '--unified=0')
    }
    $diffLines = @($diffResult.Stdout) | ForEach-Object { $_ }

    $newSites = Get-NewCommentSites -DiffLines $diffLines
    $newCount = $newSites.Count
    $coveredCount = Get-CoveredCommentCount -AuditResult $check

    if ($newCount -gt $coveredCount) {
        $violations += "Commit ${shortSha}: $newCount new-or-rewritten comment site(s) in diff but only $coveredCount covered audit entries (approved+exempt only; drops and deleted are audit-trail-only and never satisfy coverage per comment-protocol.md §Persisted audit record)"
        foreach ($site in ($newSites | Select-Object -First 20)) {
            $violations += "  comment at $($site.File):$($site.Line)"
        }
    } else {
        Write-Host "Commit ${shortSha}: $newCount new comment(s), $coveredCount covered audit entries - OK"
    }
}

if ($violations) {
    foreach ($v in $violations) { Write-Violation $v }
    exit $script:ExitViolation
}

Write-Host "OK: all $(@($commitsForward).Count) commit(s) passed comment-audit ledger verification."
exit $script:ExitOk
