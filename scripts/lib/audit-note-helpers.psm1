#Requires -Version 5.1
# Local git-notes audit ledger helpers (redesign: committed ledgers -> local notes,
# zero remote footprint). Two independent refs (panel + comment) so a partial amend
# rewrites only the regenerated ref. Each note carries a FRESHNESS binding re-checked
# at read time: audited_tree (the commit's tree) catches amends (tree changed); the
# receipt's existing parent_sha catches rebases (parent changed). Both together bind
# the exact panel-reviewed diff, so a notes.rewriteRef carry onto a changed commit is
# rejected as stale. Pure note mechanics; reuses Test-PanelLedger / Test-AuditFile
# UNCHANGED (they are structurally opaque to the extra audited_tree line).

Set-StrictMode -Version Latest

$script:PanelNoteRef    = 'refs/notes/copilot-audit-panel'
$script:CommentNoteRef  = 'refs/notes/copilot-audit-comment'
$script:GitEmptyTreeSha = '4b825dc642cb6eb9a060e54bf8d69288fbee4904'

function Get-PanelNoteRef   { $script:PanelNoteRef }
function Get-CommentNoteRef { $script:CommentNoteRef }

function Invoke-AuditGit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RepoRoot,
        [Parameter(Mandatory)] [string[]] $GitArgs
    )
    $stdout = & git -C $RepoRoot @GitArgs 2>$null
    return [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Stdout = @($stdout) }
}

function Get-CommitTreeSha {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RepoRoot,
        [Parameter(Mandatory)] [string] $CommitSha
    )
    $r = Invoke-AuditGit -RepoRoot $RepoRoot -GitArgs @('rev-parse', '--verify', '--quiet', "$CommitSha^{tree}")
    if ($r.ExitCode -ne 0 -or $r.Stdout.Count -eq 0) { return $null }
    return ([string]$r.Stdout[0]).Trim()
}

function Get-CommitParentSha {
    # Returns the first-parent sha, or the empty-tree sentinel for a root commit
    # (mirrors the ExpectedParentSha contract of Test-PanelLedger / Test-AuditFile).
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RepoRoot,
        [Parameter(Mandatory)] [string] $CommitSha
    )
    $r = Invoke-AuditGit -RepoRoot $RepoRoot -GitArgs @('rev-parse', '--verify', '--quiet', "$CommitSha^")
    if ($r.ExitCode -ne 0 -or $r.Stdout.Count -eq 0 -or -not ([string]$r.Stdout[0]).Trim()) {
        return $script:GitEmptyTreeSha
    }
    return ([string]$r.Stdout[0]).Trim()
}

function Read-RawAuditNote {
    # Returns the note body lines, or $null when no note exists on the commit.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RepoRoot,
        [Parameter(Mandatory)] [string] $NoteRef,
        [Parameter(Mandatory)] [string] $CommitSha
    )
    $r = Invoke-AuditGit -RepoRoot $RepoRoot -GitArgs @('notes', "--ref=$NoteRef", 'show', $CommitSha)
    if ($r.ExitCode -ne 0) { return $null }
    return @($r.Stdout)
}

function Write-AuditNote {
    # Writes (force-overwrites) the note for the ref on the commit, prepending the
    # audited_tree freshness binding. Any pre-existing audited_tree line in BodyLines
    # is stripped first so re-flushing is idempotent.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RepoRoot,
        [Parameter(Mandatory)] [string] $NoteRef,
        [Parameter(Mandatory)] [string] $CommitSha,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $BodyLines
    )
    $tree = Get-CommitTreeSha -RepoRoot $RepoRoot -CommitSha $CommitSha
    if (-not $tree) { throw "Write-AuditNote: cannot resolve tree for commit '$CommitSha' in '$RepoRoot'." }

    $clean = @($BodyLines) | Where-Object { $_ -cnotmatch '^audited_tree:\s*' }
    $full  = @("audited_tree: $tree") + @($clean)

    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllText($tmp, (($full -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
        $r = Invoke-AuditGit -RepoRoot $RepoRoot -GitArgs @('notes', "--ref=$NoteRef", 'add', '-f', '-F', $tmp, $CommitSha)
        if ($r.ExitCode -ne 0) { throw "Write-AuditNote: 'git notes add' failed for ref '$NoteRef' on '$CommitSha'." }
    }
    finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

function Remove-AuditNote {
    # Best-effort note removal (used by tests + re-author flows). No-op when absent.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RepoRoot,
        [Parameter(Mandatory)] [string] $NoteRef,
        [Parameter(Mandatory)] [string] $CommitSha
    )
    [void](Invoke-AuditGit -RepoRoot $RepoRoot -GitArgs @('notes', "--ref=$NoteRef", 'remove', '--ignore-missing', $CommitSha))
}

function Test-AuditNoteFreshness {
    # The note's audited_tree must equal the commit's current tree. A notes.rewriteRef
    # carry onto an amended/rebased commit leaves the OLD tree in the note -> stale.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $NoteLines,
        [Parameter(Mandatory)] [string] $RepoRoot,
        [Parameter(Mandatory)] [string] $CommitSha
    )
    $result = [PSCustomObject]@{ Fresh = $true; Errors = @(); AuditedTree = $null }

    $treeLine = @($NoteLines) | Where-Object { $_ -cmatch '^audited_tree:\s*([a-fA-F0-9]+)\s*$' } | Select-Object -First 1
    if (-not $treeLine) {
        $result.Fresh = $false
        $result.Errors += "note is missing its required 'audited_tree:' freshness binding"
        return $result
    }
    if ($treeLine -cmatch '^audited_tree:\s*([a-fA-F0-9]{40})\s*$') {
        $noteTree = $matches[1]
    } else {
        $result.Fresh = $false
        $result.Errors += "note 'audited_tree:' must be a full 40-char SHA (got: $($treeLine.Trim())); refusing to treat as fresh"
        return $result
    }
    $result.AuditedTree = $noteTree

    $actualTree = Get-CommitTreeSha -RepoRoot $RepoRoot -CommitSha $CommitSha
    if (-not $actualTree) {
        $result.Fresh = $false
        $result.Errors += "cannot resolve the tree of commit '$CommitSha' to verify note freshness"
        return $result
    }
    if (-not $actualTree.Equals($noteTree, [System.StringComparison]::OrdinalIgnoreCase)) {
        $result.Fresh = $false
        $result.Errors += "note audited_tree '$noteTree' does not match the commit tree '$actualTree' (stale note carried onto a changed commit)"
    }
    return $result
}

$here = Split-Path -Parent $PSCommandPath
Import-Module (Join-Path $here 'panel-ledger-helpers.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $here 'comment-audit-helpers.psm1') -Force -DisableNameChecking

function Read-FreshAuditNote {
    # Shared reader for the validated-note functions: fetch the note, reject when absent or
    # stale, and resolve the commit's parent. Returns Ok=$true plus NoteLines/Parent, or
    # Ok=$false plus Errors. $Kind names the note in the absent-note message.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RepoRoot,
        [Parameter(Mandatory)] [string] $NoteRef,
        [Parameter(Mandatory)] [string] $CommitSha,
        [Parameter(Mandatory)] [string] $Kind
    )
    $noteLines = Read-RawAuditNote -RepoRoot $RepoRoot -NoteRef $NoteRef -CommitSha $CommitSha
    if ($null -eq $noteLines) {
        return [PSCustomObject]@{ Ok = $false; Errors = @("no $Kind note on commit '$CommitSha'"); NoteLines = $null; Parent = $null }
    }
    $fresh = Test-AuditNoteFreshness -NoteLines $noteLines -RepoRoot $RepoRoot -CommitSha $CommitSha
    if (-not $fresh.Fresh) {
        return [PSCustomObject]@{ Ok = $false; Errors = $fresh.Errors; NoteLines = $null; Parent = $null }
    }
    $parent = Get-CommitParentSha -RepoRoot $RepoRoot -CommitSha $CommitSha
    return [PSCustomObject]@{ Ok = $true; Errors = @(); NoteLines = $noteLines; Parent = $parent }
}

function Read-PanelNoteValidated {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RepoRoot,
        [Parameter(Mandatory)] [string] $CommitSha,
        [Parameter(Mandatory)] [ValidateRange(0, 2)] [int] $GovernanceTier
    )
    $n = Read-FreshAuditNote -RepoRoot $RepoRoot -NoteRef $script:PanelNoteRef -CommitSha $CommitSha -Kind 'panel-ledger'
    if (-not $n.Ok) { return [PSCustomObject]@{ Valid = $false; Errors = $n.Errors } }
    $r = Test-PanelLedger -LedgerLines $n.NoteLines -ExpectedParentSha $n.Parent -GovernanceTier $GovernanceTier
    return [PSCustomObject]@{ Valid = $r.Valid; Errors = @($r.Errors) }
}

function Test-PanelNoteExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RepoRoot,
        [Parameter(Mandatory)] [string] $CommitSha
    )
    return ($null -ne (Read-RawAuditNote -RepoRoot $RepoRoot -NoteRef $script:PanelNoteRef -CommitSha $CommitSha))
}

function Read-CommentNoteValidated {
    # Coverage (covered >= new-comment count) stays with the caller, which derives the commit's
    # new-comment count from its diff; this returns the AuditFile result for that comparison.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RepoRoot,
        [Parameter(Mandatory)] [string] $CommitSha
    )
    $n = Read-FreshAuditNote -RepoRoot $RepoRoot -NoteRef $script:CommentNoteRef -CommitSha $CommitSha -Kind 'comment-audit'
    if (-not $n.Ok) { return [PSCustomObject]@{ Valid = $false; Errors = $n.Errors; Audit = $null } }
    $audit = Test-AuditFile -AuditLines $n.NoteLines -ExpectedParentSha $n.Parent
    return [PSCustomObject]@{ Valid = $audit.Valid; Errors = @($audit.Errors); Audit = $audit }
}

function Get-NormalizedRemoteIdentity {
    # Normalizes a git remote URL to '<host>/<owner>/<repo>' (lowercased, .git/trailing
    # slash stripped, scp- and url-style both handled) for an exact identity compare.
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Url)
    $u = $Url.Trim().ToLowerInvariant()
    if (-not $u) { return '' }
    $u = $u -replace '\.git$', ''
    $u = $u -replace '/+$', ''
    if ($u -match '^[^/@]+@([^:/]+):(.+)$') { return "$($matches[1])/$($matches[2])" }       # scp-style: git@host:owner/repo
    if ($u -match '^[a-z][a-z0-9+.-]*://(?:[^@/]+@)?([^/]+)/(.+)$') { return "$($matches[1])/$($matches[2])" } # scheme://[user@]host/path
    return $u
}

function Test-IsInstructionsRepo {
    # The audit ceremony (receipt -> note) runs ONLY in THIS instruction set's own repo,
    # never in a consuming project (the binding no-modification principle). Gate on the origin
    # remote URL that normalizes to github.com/jschick04/CopilotInstructions AND the
    # structural sentinels; a consumer that merely vendors the scripts still fails the
    # remote-URL check.
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $RepoRoot)

    foreach ($f in @('AGENTS.md', 'scripts/check-post-code-change.ps1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $f) -PathType Leaf)) { return $false }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot '.github/pr-quality-gate') -PathType Container)) { return $false }

    # Check ONLY the `origin` remote, not every remote: a consuming project could add this
    # instruction set as an extra remote (e.g. `upstream` to pull updates), and scanning ALL
    # remotes would then wrongly trip the gate and let the machinery write into the consumer's
    # .git. `git clone` sets `origin`, so the real instructions repo (or a direct clone) matches.
    # (A fork / non-origin-named clone therefore no-ops by design; re-point origin at the
    # canonical repo there to enable the local audit machinery.)
    $url = Invoke-AuditGit -RepoRoot $RepoRoot -GitArgs @('remote', 'get-url', 'origin')
    if ($url.ExitCode -ne 0 -or $url.Stdout.Count -eq 0) { return $false }
    return ((Get-NormalizedRemoteIdentity -Url ([string]$url.Stdout[0])) -eq 'github.com/jschick04/copilotinstructions')
}

function Assert-AuditSetup {
    # spec R4: the pre-push gate fails loud if its own enablement is missing, so a fresh
    # clone that never ran setup.ps1 cannot silently push without the local note gate.
    # Both note refs must be carried by notes.rewriteRef (an explicit entry or a glob),
    # and core.hooksPath must point at the committed .githooks. Returns an error list.
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $RepoRoot)
    $errors = @()

    $cfg = Invoke-AuditGit -RepoRoot $RepoRoot -GitArgs @('config', '--get-all', 'notes.rewriteRef')
    $refVals = @($cfg.Stdout) | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ }
    foreach ($need in @($script:PanelNoteRef, $script:CommentNoteRef)) {
        $covered = $false
        foreach ($val in $refVals) {
            if ($val -eq $need -or $need -like $val) { $covered = $true; break }
        }
        if (-not $covered) {
            $errors += "git config notes.rewriteRef must carry '$need' (re-run the installer: setup.ps1 / setup.sh, to wire the local note gate)"
        }
    }

    $hp = Invoke-AuditGit -RepoRoot $RepoRoot -GitArgs @('config', '--get', 'core.hooksPath')
    $hpVal = if ($hp.Stdout.Count -gt 0) { ([string]$hp.Stdout[0]).Trim() } else { '' }
    if ($hpVal -ne '.githooks') {
        $errors += "git config core.hooksPath must be '.githooks' (re-run the installer: setup.ps1 / setup.sh); got '$hpVal'"
    }
    return , $errors
}

Export-ModuleMember -Function `
    Get-PanelNoteRef, Get-CommentNoteRef, Invoke-AuditGit, `
    Get-CommitTreeSha, Get-CommitParentSha, `
    Read-RawAuditNote, Write-AuditNote, Remove-AuditNote, `
    Test-AuditNoteFreshness, Read-PanelNoteValidated, Read-CommentNoteValidated, Test-PanelNoteExists, `
    Get-NormalizedRemoteIdentity, Test-IsInstructionsRepo, Assert-AuditSetup, `
    Get-PanelRequired, Test-PathPanelRequired, Get-PathGovernanceTier, Get-ChangedGovernanceTier, Get-NewCommentCount, Get-NewCommentSites, Get-UnparseableDiffPaths, Test-CommentCoverage, Get-CoveredCommentCount `
    -Variable PanelNoteRef, CommentNoteRef, GitEmptyTreeSha
