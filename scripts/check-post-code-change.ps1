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
if ($StagedMode) {
    try { $activated = Test-RequiresFullPanel -RepoRoot $RepoRoot } catch {
        Write-Violation $_.Exception.Message
        exit $script:ExitViolation
    }
    if (-not $activated) {
        Write-Host 'OK: instruction-set activation sentinel absent; panel-ledger validation is inactive.'
        exit $script:ExitOk
    }
}


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
    if (-not $WorktreeReceipt) { Write-Invocation 'staged mode requires -WorktreeReceipt; audit receipts cannot be staged'; exit $script:ExitInvocation }
    $unmergedResult = Invoke-Git -Arguments @('ls-files', '-u')
    $unmergedEntries = @($unmergedResult.Stdout | Where-Object { $_ })
    if ($unmergedEntries.Count -gt 0) { Write-Invocation 'index contains unmerged entries; resolve conflicts before panel validation'; exit $script:ExitInvocation }
    $stagedResult = Invoke-Git -Arguments @('-c', 'core.quotePath=false', 'diff', '--cached', '--name-only', '--no-renames', '--diff-filter=ACMRTD')
    $changedPaths = Get-ChangedPaths -GitResult $stagedResult
    if (-not $changedPaths) {
        Write-Host "OK: no staged changes."
        exit $script:ExitOk
    }

    $nameStatusResult = Invoke-Git -Arguments @('-c', 'core.quotePath=false', 'diff', '--cached', '--name-status', '-M', '--diff-filter=ACMRTD')
    $nameStatusLines = @($nameStatusResult.Stdout) | Where-Object { $_ }
    $governanceTier = Get-ChangedGovernanceTier -ChangedPaths $changedPaths -NameStatusLines $nameStatusLines
    $requiresFull = $activated
    if ($governanceTier -lt 1 -and -not $requiresFull) {
        Write-Host "OK: staged diff touches no code/governance paths; panel ledger not required."
        exit $script:ExitOk
    }

    $amendAllowed = ($env:PANEL_GATE_AMEND) -and ($env:PANEL_GATE_AMEND -ne '0')
    $acceptableParents = @()
    $headResult = Invoke-Git -Arguments @('rev-parse', 'HEAD') -AllowFailure
    if ($headResult.ExitCode -ne 0) {
        $acceptableParents = @($gitEmptyTreeSha)
    } elseif ($amendAllowed) {
        $headParentResult = Invoke-Git -Arguments @('rev-parse', 'HEAD^') -AllowFailure
        if ($headParentResult.ExitCode -eq 0) {
            $acceptableParents = @(($headParentResult.Stdout | Out-String).Trim())
        } else {
            $acceptableParents = @($gitEmptyTreeSha)
        }
    } else {
        $acceptableParents = @(($headResult.Stdout | Out-String).Trim())
    }
    $hintParent = $acceptableParents[0]
    $hintParentDisplay = if ($hintParent -eq $gitEmptyTreeSha) { 'EMPTY_TREE' } else { $hintParent.Substring(0, [Math]::Min(8, $hintParent.Length)) }

    # Local-only adoption: the receipt is git-excluded (never staged), so read it from disk.
    $receiptFull = Join-Path $RepoRoot $AuditPath
    if (-not (Test-Path -LiteralPath $receiptFull)) { Write-Violation "staged diff is panel-required but no '$AuditPath' exists on disk. Run the panel, write the LEDGER receipt (parent_sha=$hintParentDisplay), and keep it on disk."; exit $script:ExitViolation }
    $ledgerLines = @(Get-Content -LiteralPath $receiptFull)

    $stagedAuditPaths = @($changedPaths | Where-Object { $_ -match '^\.github/pr-quality-gate/audits/(?!\.gitkeep$)' })
    if ($stagedAuditPaths.Count -gt 0) {
        Write-Violation "audit receipts must remain worktree-only and cannot be staged: $($stagedAuditPaths -join ', ')"
        exit $script:ExitViolation
    }
    $indexTreeResult = Invoke-Git -Arguments @('write-tree')
    $expectedIndexTree = ([string]($indexTreeResult.Stdout | Out-String)).Trim()
    if ($expectedIndexTree -notmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$') {
        Write-Invocation 'git write-tree returned an invalid tree id'
        exit $script:ExitInvocation
    }
    $indexLines = Invoke-Git -Arguments @('-c', 'core.quotePath=false', 'ls-files', '-s')
    $treeLines = Invoke-Git -Arguments @('-c', 'core.quotePath=false', 'ls-tree', '-r', '--full-tree', $expectedIndexTree)
    $treeEntries = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($treeLine in $treeLines.Stdout) {
        if ([string]$treeLine -cnotmatch '^(?<mode>\d{6}) (?<type>blob|commit) (?<oid>[0-9a-f]{40}|[0-9a-f]{64})\t(?<path>.*)$') {
            Write-Invocation "git ls-tree returned an unrecognized entry: $treeLine"
            exit $script:ExitInvocation
        }
        [void]$treeEntries.Add("$($matches['mode']) $($matches['oid']) 0`t$($matches['path'])")
    }
    $intentToAddPaths = [System.Collections.Generic.List[string]]::new()
    foreach ($indexLine in $indexLines.Stdout) {
        if ([string]$indexLine -cnotmatch '^(?<mode>\d{6}) (?<oid>[0-9a-f]{40}|[0-9a-f]{64}) (?<stage>[0-3])\t(?<path>.*)$') {
            Write-Invocation "git ls-files returned an unrecognized entry: $indexLine"
            exit $script:ExitInvocation
        }
        if ($matches['stage'] -eq '0' -and -not $treeEntries.Contains("$($matches['mode']) $($matches['oid']) 0`t$($matches['path'])")) {
            $intentToAddPaths.Add($matches['path'])
        }
    }
    if ($intentToAddPaths.Count -gt 0) {
        $missingPaths = @($intentToAddPaths.ToArray() | Sort-Object -Unique -CaseSensitive)
        Write-Violation "intent-to-add paths must be staged or removed: $($missingPaths -join ', ')"
        exit $script:ExitViolation
    }

    $parentLine = @($ledgerLines | Where-Object { $_ -cmatch '^parent_sha:\s*\S' })
    $matchedParent = ''
    if ($parentLine.Count -eq 1 -and $parentLine[0] -cmatch '^parent_sha:\s*(\S+)\s*$') {
        $declared = $matches[1]
        if ($declared -cin @('NONE','EMPTY_TREE')) { $declared = $gitEmptyTreeSha }
        foreach ($candidateParent in $acceptableParents) { if ($candidateParent -ieq $declared) { $matchedParent = $candidateParent; break } }
    }
    if (-not $matchedParent) { Write-Violation 'ledger parent_sha does not match an accepted commit parent'; exit $script:ExitViolation }
    $artifactParent = if ($matchedParent -eq $gitEmptyTreeSha) { 'none' } else { $matchedParent.ToLowerInvariant() }
    $artifactOutput = & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'Get-ReviewedArtifactId.ps1') -Staged -ParentSha $artifactParent -RepoRoot $RepoRoot
    if ($LASTEXITCODE -ne 0 -or @($artifactOutput).Count -lt 2 -or ([string]$artifactOutput[0]) -notmatch '^[0-9a-f]{64}$' -or ([string]$artifactOutput[1]) -notmatch '^worktree_divergent=\d+$') { Write-Invocation 'Get-ReviewedArtifactId -Staged returned an invalid result'; exit $script:ExitInvocation }
    $expectedArtifact = ([string]$artifactOutput[0]).Trim()
    $worktreeDivergentCount = [int](([string]$artifactOutput[1]) -replace '^worktree_divergent=', '')
    $boundPathsResult = Invoke-Git -Arguments @('-c', 'core.quotePath=false', 'diff', '--cached', '--name-only', '--no-renames', $matchedParent)
    $boundPaths = @(Get-ChangedPaths -GitResult $boundPathsResult)
    $guardedPaths = @($boundPaths | Where-Object { Test-GuardedPath -Path $_ } | Sort-Object -Unique)
    if ($guardedPaths.Count -gt 0) { Write-Host "GUARDED PATHS: $($guardedPaths -join ', ')" }
    $registryPath = '.github/playbooks/multi-model-review/current-model-registry.md'
    $stagedRegistryResult = Invoke-Git -Arguments @('show', ":$registryPath") -AllowFailure
    $parentRegistryResult = if ($matchedParent -eq $gitEmptyTreeSha) { $stagedRegistryResult } else { Invoke-Git -Arguments @('show', "${matchedParent}:$registryPath") -AllowFailure }
    if ($stagedRegistryResult.ExitCode -ne 0 -or $parentRegistryResult.ExitCode -ne 0) { Write-Violation 'matched parent or staged registry is unavailable'; exit $script:ExitViolation }
    $registryText = (@($parentRegistryResult.Stdout) -join "`n")
    $stagedRegistryText = (@($stagedRegistryResult.Stdout) -join "`n")
    $postAdoption = Test-IsPostAdoption -RepoRoot $RepoRoot -StagedMode
    $heavyPolicy = Get-HeavyModelPolicy -RepoRoot $RepoRoot -StagedMode -ParentSha $matchedParent -LedgerLines $ledgerLines
    if ($heavyPolicy.Errors.Count -gt 0) { foreach ($errorText in $heavyPolicy.Errors) { Write-Violation $errorText }; exit $script:ExitViolation }
    $check = Test-PanelLedger -LedgerLines $ledgerLines -ExpectedParentSha $matchedParent -GovernanceTier $governanceTier -RequiresFull $requiresFull -PostAdoption:$postAdoption -BoundStaged -WorktreeDivergentCount $worktreeDivergentCount -ExpectedIndexTree $expectedIndexTree -ExpectedArtifact $expectedArtifact -RegistryText $registryText -StagedRegistryText $stagedRegistryText -HeavyModels $heavyPolicy.Models -GuardedPathCount $guardedPaths.Count
    if (-not $check.Valid) {
        foreach ($err in $check.Errors) { Write-Violation "staged $AuditPath : $err" }
        exit $script:ExitViolation
    }
    # B1 structural-hygiene diff-signal floor (LOCAL, --no-verify-bypassable, CI-blind; see lib/hygiene-signals.psm1).
    # Each detected code-diff signal forces its matching ledger field to be present-with-a-justified-value.
    $diffContentResult = Invoke-Git -Arguments @('-c', 'core.quotePath=false', 'diff', '--cached', '-U0', '--no-color', '--diff-filter=ACMRTD')
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

$commitsForwardResult = Invoke-Git -Arguments @('log', '--reverse', '--format=%H', "$baseSha..$HeadRef")
$commitsForward = @($commitsForwardResult.Stdout) | Where-Object { $_ } | ForEach-Object { $_.Trim() }

if (-not $commitsForward) {
    Write-Host "OK: no commits in PR range."
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
    $requiresFull = Test-RequiresFullPanel -RepoRoot $RepoRoot -CommitSha $commitSha
    if (-not $requiresFull) { continue }
    $postAdoption = Test-IsPostAdoption -RepoRoot $RepoRoot -CommitSha $commitSha
    if ($governanceTier -lt 1 -and -not $postAdoption) {
        Write-Host "Commit ${shortSha}: no code/governance paths touched - panel ledger not required - OK"
        continue
    }

    $receiptResult = Invoke-Git -Arguments @('show', "${commitSha}:$AuditPath") -AllowFailure
    if ($receiptResult.ExitCode -ne 0 -or -not $receiptResult.Stdout) {
        $violations += "Commit ${shortSha}: panel-required but missing $AuditPath in tree"
        continue
    }
    $ledgerLines = @($receiptResult.Stdout) | ForEach-Object { $_ }

    $heavyModels = @()
    if ($postAdoption) {
        $heavyPolicy = Get-HeavyModelPolicy -RepoRoot $RepoRoot -CommitSha $commitSha -ParentSha $expectedParentSha -LedgerLines $ledgerLines
        if ($heavyPolicy.Errors.Count -gt 0) { foreach ($errorText in $heavyPolicy.Errors) { $violations += "Commit ${shortSha}: $errorText" }; continue }
        $heavyModels = $heavyPolicy.Models
    }
    $guardedCount = @($changedPaths | Where-Object { Test-GuardedPath -Path $_ } | Sort-Object -Unique).Count
    $check = Test-PanelLedger -LedgerLines $ledgerLines -ExpectedParentSha $expectedParentSha -GovernanceTier $governanceTier -RequiresFull $requiresFull -PostAdoption:$postAdoption -HeavyModels $heavyModels -GuardedPathCount $guardedCount
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
