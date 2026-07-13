#Requires -Version 5.1
# PRE-COMMIT GATE PASSED receipt gate (the 4th audit receipt). Two contexts share one validator:
# -StagedMode reads the INDEX (pre-commit hook); default walks BaseRef..HEAD history (test-only - the
# receipt is gitignored/note-flushed, so CI runs the unit tests, and the pre-push note gate is the real
# cross-commit enforcement). Unlike the LEDGER, this block is a user-approval artifact required on EVERY
# commit, so there is NO tier-0 early-exit; GovernanceTier is computed only to relax the slug sub-check.
# Mirrors check-post-code-change.ps1 (Invoke-Git duplicated) minus the hygiene-signals floor.

[CmdletBinding()]
param(
    [string] $BaseRef,
    [string] $HeadRef = 'HEAD',
    [string] $RepoRoot = '',
    [string] $AuditPath = '.github/pr-quality-gate/audits/pre-commit-gate-last.md',
    [switch] $StagedMode,
    [switch] $WorktreeReceipt
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:ExitOk = 0
$script:ExitViolation = 1
$script:ExitInvocation = 2

function Write-Invocation { param([string] $Msg) Write-Host "::error::INVOCATION_FAILED:$Msg" }
function Write-Violation { param([string] $Msg) Write-Host "::error::VIOLATION:$Msg" }

Import-Module (Join-Path $PSScriptRoot 'lib/repo-root.psm1') -Force
try {
    $RepoRoot = Resolve-RepoRoot -Explicit $RepoRoot -ScriptRoot $PSScriptRoot -Anchors @('scripts/check-pre-commit-gate.ps1') -RequireGitWorkTree
} catch {
    Write-Invocation $_.Exception.Message
    exit $script:ExitInvocation
}

$modulePath = Join-Path $PSScriptRoot 'lib/panel-ledger-helpers.psm1'
if (-not (Test-Path -LiteralPath $modulePath)) {
    Write-Invocation "module not found: $modulePath"
    exit $script:ExitInvocation
}
Import-Module $modulePath -Force
$gitEmptyTreeSha = Get-GitEmptyTreeSha


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

function Get-ChangedPaths {
    param([Parameter(Mandatory)] [PSObject] $GitResult)
    return @($GitResult.Stdout) | Where-Object { $_ } | ForEach-Object { $_.Trim() }
}

if ($StagedMode) {
    $stagedResult = Invoke-Git -Arguments @('-c', 'core.quotePath=false', 'diff', '--cached', '--name-only', '--no-renames', '--diff-filter=ACMRTD')
    $changedPaths = Get-ChangedPaths -GitResult $stagedResult
    if (-not $changedPaths) {
        Write-Host "OK: no staged changes."
        exit $script:ExitOk
    }

    # No tier-0 early-exit: the PRE-COMMIT GATE PASSED block is required on every commit. GovernanceTier
    # is computed only so Test-PreCommitGateBlock can relax the code-slug sub-check for a tier-0 diff.
    $nameStatusResult = Invoke-Git -Arguments @('-c', 'core.quotePath=false', 'diff', '--cached', '--name-status', '-M', '--diff-filter=ACMRTD')
    $nameStatusLines = @($nameStatusResult.Stdout) | Where-Object { $_ }
    $governanceTier = Get-ChangedGovernanceTier -ChangedPaths $changedPaths -NameStatusLines $nameStatusLines

    # Parent must be HEAD (fresh commit). For `git commit --amend` set PANEL_GATE_AMEND=1 to also accept HEAD^ (CI stays strict).
    $amendAllowed = ($env:PANEL_GATE_AMEND) -and ($env:PANEL_GATE_AMEND -ne '0')
    $acceptableParents = @()
    $headResult = Invoke-Git -Arguments @('rev-parse', 'HEAD') -AllowFailure
    if ($headResult.ExitCode -ne 0) {
        $acceptableParents = @($gitEmptyTreeSha)
    } else {
        $acceptableParents += ($headResult.Stdout | Out-String).Trim()
        if ($amendAllowed) {
            $headParentResult = Invoke-Git -Arguments @('rev-parse', 'HEAD^') -AllowFailure
            if ($headParentResult.ExitCode -eq 0) {
                $acceptableParents += ($headParentResult.Stdout | Out-String).Trim()
            } else {
                $acceptableParents += $gitEmptyTreeSha
            }
        }
    }
    $hintParent = $acceptableParents[0]
    $hintParentDisplay = if ($hintParent -eq $gitEmptyTreeSha) { 'EMPTY_TREE' } else { $hintParent.Substring(0, [Math]::Min(8, $hintParent.Length)) }

    if ($WorktreeReceipt) {
        # Local-only adoption: the receipt is git-excluded (never staged), so read it from disk.
        $receiptFull = Join-Path $RepoRoot $AuditPath
        if (-not (Test-Path -LiteralPath $receiptFull)) {
            Write-Violation "staged diff needs a PRE-COMMIT GATE PASSED receipt but no '$AuditPath' exists on disk. Emit the block, write it (parent_sha=$hintParentDisplay), and keep it on disk."
            exit $script:ExitViolation
        }
        $blockLines = @(Get-Content -LiteralPath $receiptFull)
    } else {
        $receiptResult = Invoke-Git -Arguments @('show', ":$AuditPath") -AllowFailure
        if ($receiptResult.ExitCode -ne 0 -or -not $receiptResult.Stdout) {
            Write-Violation "staged diff needs a PRE-COMMIT GATE PASSED receipt but no fresh '$AuditPath' is present. Emit the block and write it (parent_sha=$hintParentDisplay) to '$AuditPath'."
            exit $script:ExitViolation
        }
        $blockLines = @($receiptResult.Stdout) | ForEach-Object { $_ }
    }

    $check = $null
    foreach ($candidateParent in $acceptableParents) {
        $candidate = Test-PreCommitGateBlock -BlockLines $blockLines -ExpectedParentSha $candidateParent -GovernanceTier $governanceTier
        if ($candidate.Valid) { $check = $candidate; break }
        if (-not $check) { $check = $candidate }
    }
    if (-not $check.Valid) {
        foreach ($err in $check.Errors) { Write-Violation "staged $AuditPath : $err" }
        exit $script:ExitViolation
    }
    Write-Host "OK: staged PRE-COMMIT GATE PASSED receipt is fresh and valid."
    exit $script:ExitOk
}

if (-not $BaseRef) {
    Write-Invocation "BaseRef is required in history mode (use -StagedMode for the pre-commit hook)"
    exit $script:ExitInvocation
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
    Write-Host "OK: no non-merge commits in range."
    exit $script:ExitOk
}

$violations = @()
foreach ($commitSha in $commitsForward) {
    $shortSha = $commitSha.Substring(0, 8)

    $parentResult = Invoke-Git -Arguments @('rev-parse', "${commitSha}^") -AllowFailure
    if ($parentResult.ExitCode -ne 0) {
        $expectedParentSha = $gitEmptyTreeSha
        $diffResult = Invoke-Git -Arguments @('-c', 'core.quotePath=false', '--no-pager', 'diff', '--name-only', '--no-renames', $gitEmptyTreeSha, $commitSha)
    } else {
        $expectedParentSha = ($parentResult.Stdout | Out-String).Trim()
        $diffResult = Invoke-Git -Arguments @('-c', 'core.quotePath=false', '--no-pager', 'diff', '--name-only', '--no-renames', "${expectedParentSha}..${commitSha}")
    }
    $changedPaths = Get-ChangedPaths -GitResult $diffResult

    $nameStatusResult = if ($parentResult.ExitCode -ne 0) {
        Invoke-Git -Arguments @('-c', 'core.quotePath=false', '--no-pager', 'diff', '--name-status', '-M', $gitEmptyTreeSha, $commitSha)
    } else {
        Invoke-Git -Arguments @('-c', 'core.quotePath=false', '--no-pager', 'diff', '--name-status', '-M', "${expectedParentSha}..${commitSha}")
    }
    $nameStatusLines = @($nameStatusResult.Stdout) | Where-Object { $_ }
    $governanceTier = Get-ChangedGovernanceTier -ChangedPaths $changedPaths -NameStatusLines $nameStatusLines

    $receiptResult = Invoke-Git -Arguments @('show', "${commitSha}:$AuditPath") -AllowFailure
    if ($receiptResult.ExitCode -ne 0 -or -not $receiptResult.Stdout) {
        $violations += "Commit ${shortSha}: missing $AuditPath in tree (PRE-COMMIT GATE PASSED receipt required)"
        continue
    }
    $blockLines = @($receiptResult.Stdout) | ForEach-Object { $_ }

    $check = Test-PreCommitGateBlock -BlockLines $blockLines -ExpectedParentSha $expectedParentSha -GovernanceTier $governanceTier
    if (-not $check.Valid) {
        foreach ($err in $check.Errors) { $violations += "Commit ${shortSha}: $err" }
        continue
    }
    Write-Host "Commit ${shortSha}: fresh valid PRE-COMMIT GATE PASSED receipt - OK"
}

if ($violations) {
    foreach ($v in $violations) { Write-Violation $v }
    exit $script:ExitViolation
}

Write-Host "OK: all $(@($commitsForward).Count) commit(s) passed pre-commit-gate receipt verification."
exit $script:ExitOk
