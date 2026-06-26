#Requires -Version 5.1
# Post-code-change panel LEDGER gate. Two contexts share one validator: -StagedMode reads the
# INDEX (pre-commit hook); default walks BaseRef..HEAD history (CI). A receipt is required only
# when a commit's diff is panel-required. Mirrors check-comment-audit.ps1 (Invoke-Git duplicated).

[CmdletBinding()]
param(
    [string] $BaseRef,
    [string] $HeadRef = 'HEAD',
    [string] $RepoRoot = '',
    [string] $AuditPath = '.github/pr-quality-gate/audits/post-code-change-last.md',
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
    $RepoRoot = Resolve-RepoRoot -Explicit $RepoRoot -ScriptRoot $PSScriptRoot -Anchors @('scripts/check-post-code-change.ps1') -RequireGitWorkTree
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
Import-Module (Join-Path $PSScriptRoot 'lib/hygiene-signals.psm1') -Force
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
    $stagedResult = Invoke-Git -Arguments @('diff', '--cached', '--name-only', '--no-renames', '--diff-filter=ACMRTD')
    $changedPaths = Get-ChangedPaths -GitResult $stagedResult
    if (-not $changedPaths) {
        Write-Host "OK: no staged changes."
        exit $script:ExitOk
    }

    $nameStatusResult = Invoke-Git -Arguments @('diff', '--cached', '--name-status', '-M', '--diff-filter=ACMRTD')
    $nameStatusLines = @($nameStatusResult.Stdout) | Where-Object { $_ }
    $governanceTier = Get-ChangedGovernanceTier -ChangedPaths $changedPaths -NameStatusLines $nameStatusLines
    if ($governanceTier -lt 1) {
        Write-Host "OK: staged diff touches no code/governance paths; panel ledger not required."
        exit $script:ExitOk
    }

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

    $receiptResult = $null
    if ($WorktreeReceipt) {
        # Local-only adoption: the receipt is git-excluded (never staged), so read it from disk.
        $receiptFull = Join-Path $RepoRoot $AuditPath
        if (-not (Test-Path -LiteralPath $receiptFull)) {
            Write-Violation "staged diff is panel-required but no '$AuditPath' exists on disk. Run the panel, write the LEDGER receipt (parent_sha=$hintParentDisplay), and keep it on disk."
            exit $script:ExitViolation
        }
        $ledgerLines = @(Get-Content -LiteralPath $receiptFull)
    } else {
        $receiptResult = Invoke-Git -Arguments @('show', ":$AuditPath") -AllowFailure
        if ($receiptResult.ExitCode -ne 0 -or -not $receiptResult.Stdout) {
            Write-Violation "staged diff is panel-required but no fresh '$AuditPath' is staged. Run the post-code-change panel, write the LEDGER receipt (parent_sha=$hintParentDisplay), and stage it."
            exit $script:ExitViolation
        }
        $ledgerLines = @($receiptResult.Stdout) | ForEach-Object { $_ }
    }

    $check = $null
    foreach ($candidateParent in $acceptableParents) {
        $candidate = Test-PanelLedger -LedgerLines $ledgerLines -ExpectedParentSha $candidateParent -GovernanceTier $governanceTier
        if ($candidate.Valid) { $check = $candidate; break }
        if (-not $check) { $check = $candidate }
    }
    if (-not $check.Valid) {
        foreach ($err in $check.Errors) { Write-Violation "staged $AuditPath : $err" }
        exit $script:ExitViolation
    }
    # B1 structural-hygiene diff-signal floor (LOCAL, --no-verify-bypassable, CI-blind; see lib/hygiene-signals.psm1).
    # Each detected code-diff signal forces its matching ledger field to be present-with-a-justified-value.
    $diffContentResult = Invoke-Git -Arguments @('diff', '--cached', '-U0', '--no-color', '--diff-filter=ACMRTD')
    $diffContentLines = @($diffContentResult.Stdout) | ForEach-Object { $_ }
    $hygieneViolations = @(Get-StructuralHygieneViolations -NameStatusLines $nameStatusLines -DiffLines $diffContentLines -LedgerLines $ledgerLines)
    if ($hygieneViolations.Count -gt 0) {
        foreach ($violation in $hygieneViolations) { Write-Violation "staged $AuditPath : $violation" }
        exit $script:ExitViolation
    }
    Write-Host "OK: staged panel ledger is fresh and valid (panel-required commit)."
    exit $script:ExitOk
}

if (-not $BaseRef) {
    Write-Invocation "BaseRef is required in CI/history mode (use -StagedMode for the pre-commit hook)"
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
    Write-Host "OK: no non-merge commits in PR range."
    exit $script:ExitOk
}

$violations = @()
foreach ($commitSha in $commitsForward) {
    $shortSha = $commitSha.Substring(0, 8)

    $parentResult = Invoke-Git -Arguments @('rev-parse', "${commitSha}^") -AllowFailure
    if ($parentResult.ExitCode -ne 0) {
        $expectedParentSha = $gitEmptyTreeSha
        $diffResult = Invoke-Git -Arguments @('--no-pager', 'diff', '--name-only', '--no-renames', $gitEmptyTreeSha, $commitSha)
    } else {
        $expectedParentSha = ($parentResult.Stdout | Out-String).Trim()
        $diffResult = Invoke-Git -Arguments @('--no-pager', 'diff', '--name-only', '--no-renames', "${expectedParentSha}..${commitSha}")
    }
    $changedPaths = Get-ChangedPaths -GitResult $diffResult

    $nameStatusResult = if ($parentResult.ExitCode -ne 0) {
        Invoke-Git -Arguments @('--no-pager', 'diff', '--name-status', '-M', $gitEmptyTreeSha, $commitSha)
    } else {
        Invoke-Git -Arguments @('--no-pager', 'diff', '--name-status', '-M', "${expectedParentSha}..${commitSha}")
    }
    $nameStatusLines = @($nameStatusResult.Stdout) | Where-Object { $_ }
    $governanceTier = Get-ChangedGovernanceTier -ChangedPaths $changedPaths -NameStatusLines $nameStatusLines
    if ($governanceTier -lt 1) {
        Write-Host "Commit ${shortSha}: no code/governance paths touched - panel ledger not required - OK"
        continue
    }

    $receiptResult = Invoke-Git -Arguments @('show', "${commitSha}:$AuditPath") -AllowFailure
    if ($receiptResult.ExitCode -ne 0 -or -not $receiptResult.Stdout) {
        $violations += "Commit ${shortSha}: panel-required but missing $AuditPath in tree"
        continue
    }
    $ledgerLines = @($receiptResult.Stdout) | ForEach-Object { $_ }

    $check = Test-PanelLedger -LedgerLines $ledgerLines -ExpectedParentSha $expectedParentSha -GovernanceTier $governanceTier
    if (-not $check.Valid) {
        foreach ($err in $check.Errors) { $violations += "Commit ${shortSha}: $err" }
        continue
    }
    Write-Host "Commit ${shortSha}: panel-required, fresh valid ledger - OK"
}

if ($violations) {
    foreach ($v in $violations) { Write-Violation $v }
    exit $script:ExitViolation
}

Write-Host "OK: all $(@($commitsForward).Count) commit(s) passed post-code-change panel-ledger verification."
exit $script:ExitOk
