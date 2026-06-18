#Requires -Version 5.1
# Pre-push audit-note gate (local-only; zero remote footprint). For every commit in the
# push range, validates that a panel-required commit carries a fresh valid PANEL note,
# and that a commit introducing new comment lines carries a covering COMMENT note. Reads
# the pre-push ref-update list (`<local-ref> <local-sha> <remote-ref> <remote-sha>` lines)
# from stdin, or from -RefUpdateLines for tests.
#
# Identity-gated (no-op on a consuming repo); asserts its own setup is wired (spec R4);
# refuses to publish the note refs; walks EVERY commit in range (first-parent diff for
# merges - no silent --no-merges skip, spec R4).
[CmdletBinding()]
param(
    [string] $RepoRoot = '',
    [string] $RemoteName = 'origin',
    [string[]] $RefUpdateLines
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'lib/repo-root.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'lib/audit-note-helpers.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'lib/read-receipt-helpers.psm1') -Force -DisableNameChecking

$ExitOk = 0; $ExitViolation = 1

if ($RepoRoot) {
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
} else {
    $RepoRoot = Resolve-RepoRoot -Explicit '' -ScriptRoot $PSScriptRoot -Anchors @('scripts/check-audit-notes-prepush.ps1') -RequireGitWorkTree
}

# Identity gate: on any repo that is not this instruction set's own, do nothing.
if (-not (Test-IsInstructionsRepo -RepoRoot $RepoRoot)) { exit $ExitOk }

if ($PSBoundParameters.ContainsKey('RefUpdateLines')) {
    $lines = @($RefUpdateLines)
} else {
    $stdin = [Console]::In.ReadToEnd()
    $lines = @($stdin -split "`n") | ForEach-Object { ([string]$_).TrimEnd("`r") } | Where-Object { $_.Trim() }
}

$zeroSha = '^0{40}$'
$commitSet = [ordered]@{}

foreach ($line in $lines) {
    $parts = @($line.Trim() -split '\s+')
    if ($parts.Count -lt 4) { continue }
    $localRef = $parts[0]; $localSha = $parts[1]; $remoteRef = $parts[2]; $remoteSha = $parts[3]

    # No-publish guard (R4): the note refs are local-only and must never be pushed.
    if ($localRef -match '^refs/notes/copilot-audit-' -or $remoteRef -match '^refs/notes/copilot-audit-') {
        Write-Host "ERROR: refusing to push the local audit note ref '$remoteRef'."
        Write-Host "       The copilot-audit notes are local-only (zero remote footprint); do not publish them."
        exit $ExitViolation
    }

    if ($localSha -match $zeroSha) { continue }   # branch deletion: nothing to validate

    if ($remoteSha -match $zeroSha) {
        $rl = Invoke-AuditGit -RepoRoot $RepoRoot -GitArgs @('rev-list', $localSha, '--not', "--remotes=$RemoteName")
    } else {
        $rl = Invoke-AuditGit -RepoRoot $RepoRoot -GitArgs @('rev-list', "$remoteSha..$localSha")
    }
    if ($rl.ExitCode -ne 0) {
        Write-Host "ERROR: 'git rev-list' could not compute the pushed range (exit $($rl.ExitCode)); the remote tip '$remoteSha' may not be present locally."
        Write-Host "       Run 'git fetch $RemoteName' so every pushed commit can be validated, then push again (failing closed rather than skipping validation)."
        exit $ExitViolation
    }
    foreach ($sha in $rl.Stdout) {
        $s = ([string]$sha).Trim()
        if ($s -and -not $commitSet.Contains($s)) { $commitSet[$s] = $true }
    }
}

if ($commitSet.Count -eq 0) {
    Write-Host "OK: no pushed commits to validate (delete/up-to-date push)."
    exit $ExitOk
}

# Setup assertion (R4): fail loud if the local note gate is not wired.
$setupErrors = Assert-AuditSetup -RepoRoot $RepoRoot
if ($setupErrors.Count -gt 0) {
    Write-Host "ERROR: the local audit-note gate is not wired up:"
    foreach ($e in $setupErrors) { Write-Host "  - $e" }
    exit $ExitViolation
}

$violations = @()
$readsGitInvoke = { param($a) (Invoke-AuditGit -RepoRoot $RepoRoot -GitArgs $a).Stdout }
foreach ($sha in $commitSet.Keys) {
    $short = $sha.Substring(0, [Math]::Min(8, $sha.Length))
    $parent = Get-CommitParentSha -RepoRoot $RepoRoot -CommitSha $sha

    $dp = Invoke-AuditGit -RepoRoot $RepoRoot -GitArgs @('--no-pager', 'diff', '--name-only', '--no-renames', $parent, $sha)
    if ($dp.ExitCode -ne 0) {
        Write-Host "ERROR: 'git diff' for commit ${short} (parent ${parent}) failed (exit $($dp.ExitCode)); cannot determine whether the panel is required. Failing closed rather than skipping validation."
        exit $ExitViolation
    }
    $changedPaths = @($dp.Stdout) | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ }
    $ns = Invoke-AuditGit -RepoRoot $RepoRoot -GitArgs @('--no-pager', 'diff', '--name-status', '-M', $parent, $sha)
    if ($ns.ExitCode -ne 0) {
        Write-Host "ERROR: 'git diff --name-status' for commit ${short} (parent ${parent}) failed (exit $($ns.ExitCode)); cannot determine the governance tier. Failing closed rather than skipping validation."
        exit $ExitViolation
    }
    $nameStatusLines = @($ns.Stdout) | ForEach-Object { [string]$_ } | Where-Object { $_ }

    $governanceTier = Get-ChangedGovernanceTier -ChangedPaths $changedPaths -NameStatusLines $nameStatusLines
    if ($governanceTier -ge 1 -or (Test-PanelNoteExists -RepoRoot $RepoRoot -CommitSha $sha)) {
        $pv = Read-PanelNoteValidated -RepoRoot $RepoRoot -CommitSha $sha -GovernanceTier $governanceTier
        if (-not $pv.Valid) { foreach ($e in $pv.Errors) { $violations += "commit ${short} (panel): $e" } }
    }

    $diffFull = Invoke-AuditGit -RepoRoot $RepoRoot -GitArgs @('-c', 'core.quotePath=false', '--no-pager', 'diff', '--no-renames', $parent, $sha)
    if ($diffFull.ExitCode -ne 0) {
        Write-Host "ERROR: 'git diff' for commit ${short} (parent ${parent}) failed (exit $($diffFull.ExitCode)); cannot count new comment lines. Failing closed rather than skipping validation."
        exit $ExitViolation
    }
    $diffLinesFull = @($diffFull.Stdout)
    $unparseablePaths = @(Get-UnparseableDiffPaths -DiffLines $diffLinesFull)
    foreach ($badPath in $unparseablePaths) {
        $violations += "commit ${short} (comment): quoted/unparseable file-path header; comment coverage cannot be verified: $badPath"
    }
    $sites = Get-NewCommentSites -DiffLines $diffLinesFull
    if ($sites.Count -gt 0) {
        $cv = Read-CommentNoteValidated -RepoRoot $RepoRoot -CommitSha $sha
        if (-not $cv.Valid) {
            foreach ($e in $cv.Errors) { $violations += "commit ${short} (comment): $e" }
        } else {
            $coverageErrors = @(Test-CommentCoverage -Sites $sites -Bullets $cv.Audit.Bullets)
            foreach ($coverageError in $coverageErrors) { $violations += "commit ${short} (comment): $coverageError" }
        }
    }

    $treeList = Invoke-AuditGit -RepoRoot $RepoRoot -GitArgs @('ls-tree', '-r', '--name-only', $sha, '--', '.github/instructions')
    if ($treeList.ExitCode -ne 0) {
        Write-Host "ERROR: 'git ls-tree' for commit ${short} failed (exit $($treeList.ExitCode)); cannot enumerate gated topic files. Failing closed rather than skipping validation."
        exit $ExitViolation
    }
    $commitReadBlob = { param([string] $p) [string]((Invoke-AuditGit -RepoRoot $RepoRoot -GitArgs @('show', "${sha}:$p")).Stdout -join "`n") }
    $commitClassified = @(Get-GatedTopicsFromBlobs -Paths @($treeList.Stdout) -ReadBlob $commitReadBlob)
    foreach ($absentGate in @($commitClassified | Where-Object { $_.Kind -eq 'absent' })) {
        $violations += "commit ${short} (reads): gated file '$($absentGate.Path)' has no applyTo at this commit"
    }
    $readsGatedSet = @($commitClassified | Where-Object { $_.Kind -eq 'gate' })
    if ($readsGatedSet.Count -gt 0) {
        $readsMatched = @(Get-MatchedGatedFiles -GatedSet $readsGatedSet -DiffArgs @('diff', '--name-only', '--diff-filter=ACMRT', $parent, $sha) -GitInvoke $readsGitInvoke)
        if ($readsMatched.Count -gt 0) {
            $rv = Read-ReadsNoteValidated -RepoRoot $RepoRoot -CommitSha $sha
            if (-not $rv.Valid) {
                foreach ($e in $rv.Errors) { $violations += "commit ${short} (reads): $e" }
            } else {
                $cited = Read-ReadsReceipt -Lines $rv.NoteLines
                foreach ($gf in $readsMatched) {
                    $treeContent = ((Invoke-AuditGit -RepoRoot $RepoRoot -GitArgs @('show', "${sha}:$($gf.Path)")).Stdout -join "`n")
                    $commitToken = if ($treeContent) { Get-TokenFromContent -Content $treeContent } else { $null }
                    if (-not $commitToken) {
                        $violations += "commit ${short} (reads): gated file '$($gf.Path)' has no valid token at this commit"
                    } elseif (-not $cited.Reads.ContainsKey($gf.Path)) {
                        $violations += "commit ${short} (reads): missing read receipt for '$($gf.Path)' (expected @$commitToken)"
                    } elseif ($cited.Reads[$gf.Path] -ne $commitToken) {
                        $violations += "commit ${short} (reads): stale token for '$($gf.Path)': note cites @$($cited.Reads[$gf.Path]) but commit-tree is @$commitToken"
                    }
                }
            }
        }
    }
}

if ($violations.Count -gt 0) {
    Write-Host "Audit-note pre-push gate FAILED:"
    foreach ($v in $violations) { Write-Host "  - $v" }
    Write-Host ""
    Write-Host "Re-author the receipt(s) (.github/pr-quality-gate/audits/*.md) and run scripts/flush-audits.ps1,"
    Write-Host "or amend the commit and re-flush, then push again."
    exit $ExitViolation
}

Write-Host "OK: local audit notes are fresh and valid for all $($commitSet.Count) pushed commit(s)."
exit $ExitOk
