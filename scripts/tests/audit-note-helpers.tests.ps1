#Requires -Version 5.1
# Standalone pwsh self-test for scripts/lib/audit-note-helpers.psm1 + scripts/flush-audits.ps1.
# NOT Pester (Assert-* helpers). Run: pwsh -File scripts/tests/audit-note-helpers.tests.ps1

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-common.ps1')
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $repoRoot 'scripts/lib/audit-note-helpers.psm1') -Force -DisableNameChecking

$script:Pass = 0
$script:Fail = 0

function New-TempRepo {
    param([switch] $WithIdentity)
    $dir = New-TestGitRepository -Prefix 'anh'
    if ($WithIdentity) {
        git -C $dir remote add origin 'https://github.com/jschick04/CopilotInstructions.git'
        Set-Content -LiteralPath (Join-Path $dir 'AGENTS.md') -Value 'x' -NoNewline
        New-Item -ItemType Directory -Path (Join-Path $dir 'scripts') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $dir 'scripts/check-post-code-change.ps1') -Value 'x' -NoNewline
        New-Item -ItemType Directory -Path (Join-Path $dir '.github/pr-quality-gate/audits') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $dir '.github/pr-quality-gate/panel-policy.md') -Value 'fixture policy'
    }
    return $dir
}

function New-PanelBody {
    param([string] $Parent)
    @(
        "parent_sha: $Parent"
        'commit_subject: Test panel commit'
        'POST-CODE-CHANGE LEDGER'
    ) + (Get-ValidPreRows) + @(
        '  post-code-change-panel: ran, unanimous'
    ) + (Get-ValidPanelTranscript) + @(
        '  build: N/A: docs-only'
        '  tests: passed, all green'
    )
}
function New-CommentBody {
    param([string] $Parent)
    @(
        "parent_sha: $Parent"
        'commit_subject: Test comment commit'
        'Comment audit: scope=<none>, 0 new comment lines, zero-count justification: test fixture.'
    )
}
function New-ReadsBody {
    param([string] $Parent)
    @(
        "parent_sha: $Parent"
        'reads=topic/example.instructions.md@deadbeef'
    )
}

try {
    Write-Host "`n=== write/read round-trip + freshness ==="
    $r = New-TempRepo
    $c0 = New-TestCommit -Directory $r -File 'a.txt' -Content 'one' -Message 'c0'
    $parent0 = Get-CommitParentSha -RepoRoot $r -CommitSha $c0
    Assert-Equal 'refs/notes/copilot-audit-panel' (Get-PanelNoteRef) 'panel ref name' -CaseSensitive
    Assert-Equal $GitEmptyTreeSha $parent0 'root commit parent -> empty-tree sentinel' -CaseSensitive

    Write-AuditNote -RepoRoot $r -NoteRef (Get-PanelNoteRef) -CommitSha $c0 -BodyLines (New-PanelBody $parent0)
    $note = Read-RawAuditNote -RepoRoot $r -NoteRef (Get-PanelNoteRef) -CommitSha $c0
    Assert-True ($null -ne $note) 'note readable after write'
    Assert-True ([bool](@($note) | Where-Object { $_ -cmatch '^audited_tree: [0-9a-f]{40}$' })) 'audited_tree freshness line prepended'
    Assert-True ([bool](@($note) | Where-Object { $_ -ceq '  post-code-change-panel: ran, unanimous' })) 'receipt body preserved in note'

    $fresh = Test-AuditNoteFreshness -NoteLines $note -RepoRoot $r -CommitSha $c0
    Assert-True $fresh.Fresh 'freshness holds on the authored commit'

    Write-Host "`n=== Read-PanelNoteValidated ==="
    $v = Read-PanelNoteValidated -RepoRoot $r -CommitSha $c0 -GovernanceTier 1
    Assert-True $v.Valid 'valid panel note on panel-required commit -> Valid'
    $c1 = New-TestCommit -Directory $r -File 'b.txt' -Content 'two' -Message 'c1'
    $vNo = Read-PanelNoteValidated -RepoRoot $r -CommitSha $c1 -GovernanceTier 1
    Assert-True (-not $vNo.Valid) 'commit with NO note -> invalid'
    Assert-True ([bool]($vNo.Errors -match 'no panel-ledger note')) 'no-note error message'

    # wrong parent_sha in the body -> Test-PanelLedger stale
    $badParentBody = New-PanelBody 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef'
    Write-AuditNote -RepoRoot $r -NoteRef (Get-PanelNoteRef) -CommitSha $c1 -BodyLines $badParentBody
    $vBad = Read-PanelNoteValidated -RepoRoot $r -CommitSha $c1 -GovernanceTier 1
    Assert-True (-not $vBad.Valid) 'note with wrong parent_sha -> invalid (stale)'


    Write-Host "`n=== panel artifact binding ==="
    $bindingRepo = New-TempRepo
    New-Item -ItemType Directory -Path (Join-Path $bindingRepo 'scripts') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts/Get-ReviewedArtifactId.ps1') -Destination (Join-Path $bindingRepo 'scripts/Get-ReviewedArtifactId.ps1')
    $bindingSha = New-TestCommit -Directory $bindingRepo -File 'scripts/Get-ReviewedArtifactId.ps1' -Content (Get-Content -LiteralPath (Join-Path $repoRoot 'scripts/Get-ReviewedArtifactId.ps1') -Raw) -Message 'artifact binding feature'
    $bindingParent = Get-CommitParentSha -RepoRoot $bindingRepo -CommitSha $bindingSha
    $artifactResult = @(& pwsh -NoProfile -File (Join-Path $repoRoot 'scripts/Get-ReviewedArtifactId.ps1') -Commit $bindingSha -RepoRoot $bindingRepo)
    Assert-Equal 0 $LASTEXITCODE 'commit artifact resolver succeeds for binding fixture'
    $bindingArtifact = [string]$artifactResult[0]
    $bindingBody = @(New-PanelBody $bindingParent)
    $missingBindingBody = @($bindingBody)
    Write-AuditNote -RepoRoot $bindingRepo -NoteRef (Get-PanelNoteRef) -CommitSha $bindingSha -BodyLines $missingBindingBody
    $missingBinding = Read-PanelNoteValidated -RepoRoot $bindingRepo -CommitSha $bindingSha -GovernanceTier 1 -RequireArtifactBinding $true
    Assert-True (-not $missingBinding.Valid -and (@($missingBinding.Errors) -join ' ') -match 'requires an artifact token') 'adopted binding rejects panel notes with missing tokens'
    $wrongBindingBody = @($bindingBody | ForEach-Object { if ($_ -cmatch '^\s*- slot:') { $_ + (' artifact:' + ('0' * 64)) } else { $_ } })
    Write-AuditNote -RepoRoot $bindingRepo -NoteRef (Get-PanelNoteRef) -CommitSha $bindingSha -BodyLines $wrongBindingBody
    $wrongBinding = Read-PanelNoteValidated -RepoRoot $bindingRepo -CommitSha $bindingSha -GovernanceTier 1 -RequireArtifactBinding $true
    Assert-True (-not $wrongBinding.Valid -and (@($wrongBinding.Errors) -join ' ') -match 'does not match') 'adopted binding rejects the wrong artifact token'
    $correctBindingBody = @($bindingBody | ForEach-Object { if ($_ -cmatch '^\s*- slot:') { $_ + " artifact:$bindingArtifact" } else { $_ } })
    Write-AuditNote -RepoRoot $bindingRepo -NoteRef (Get-PanelNoteRef) -CommitSha $bindingSha -BodyLines $correctBindingBody
    $correctBinding = Read-PanelNoteValidated -RepoRoot $bindingRepo -CommitSha $bindingSha -GovernanceTier 1 -RequireArtifactBinding $true
    Assert-True $correctBinding.Valid 'adopted binding accepts the exact commit artifact token'
    Write-AuditNote -RepoRoot $bindingRepo -NoteRef (Get-PanelNoteRef) -CommitSha $bindingSha -BodyLines $missingBindingBody
    Assert-True (Read-PanelNoteValidated -RepoRoot $bindingRepo -CommitSha $bindingSha -GovernanceTier 1).Valid 'legacy binding mode accepts missing artifact tokens'
    $auditHelpersModule = Get-Module audit-note-helpers
    $actualHelperRoot = Join-Path $repoRoot 'scripts/lib'
    try {
        & $auditHelpersModule { $script:here = $args[0] } (Join-Path $bindingRepo 'lib')
        $missingScriptBinding = Read-PanelNoteValidated -RepoRoot $bindingRepo -CommitSha $bindingSha -GovernanceTier 1 -RequireArtifactBinding $true
        Assert-True (-not $missingScriptBinding.Valid -and (@($missingScriptBinding.Errors) -join ' ') -match 'missing') 'required binding fails closed when artifact script is absent'
    } finally { & $auditHelpersModule { $script:here = $args[0] } $actualHelperRoot }
    $failureRoot = Join-Path $bindingRepo 'failure/scripts'
    $failureHelperRoot = Join-Path $failureRoot 'lib'
    New-Item -ItemType Directory -Path $failureHelperRoot -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $failureRoot 'Get-ReviewedArtifactId.ps1') -Value "Write-Output 'fixture child failure'`nexit 1"
    try {
        & $auditHelpersModule { $script:here = $args[0] } $failureHelperRoot
        $failedCommitBinding = Read-PanelNoteValidated -RepoRoot $bindingRepo -CommitSha $bindingSha -GovernanceTier 1 -RequireArtifactBinding $true
        $failedCommitError = (@($failedCommitBinding.Errors) -join ' ')
        Assert-True (-not $failedCommitBinding.Valid -and $failedCommitError -match 'exit 1' -and $failedCommitError -match 'fixture child failure') 'failed commit artifact includes child exit code and output'
    } finally { & $auditHelpersModule { $script:here = $args[0] } $actualHelperRoot }

    Write-Host "`n=== Read-ReadsNoteValidated: parent_sha binding (rebase parity with panel/comment) ==="
    $rc = New-TestCommit -Directory $r -File 'reads.txt' -Content 'rr' -Message 'reads commit'
    $rcParent = Get-CommitParentSha -RepoRoot $r -CommitSha $rc
    Write-AuditNote -RepoRoot $r -NoteRef (Get-ReadsNoteRef) -CommitSha $rc -BodyLines (New-ReadsBody $rcParent)
    Assert-True (Read-ReadsNoteValidated -RepoRoot $r -CommitSha $rc).Valid 'reads note with correct parent_sha + fresh tree -> valid'
    Write-AuditNote -RepoRoot $r -NoteRef (Get-ReadsNoteRef) -CommitSha $rc -BodyLines (New-ReadsBody 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef')
    Assert-True (-not (Read-ReadsNoteValidated -RepoRoot $r -CommitSha $rc).Valid) 'reads note with wrong parent_sha -> invalid (stale across rebase)'
    Write-AuditNote -RepoRoot $r -NoteRef (Get-ReadsNoteRef) -CommitSha $rc -BodyLines @('reads=topic/example.instructions.md@deadbeef')
    Assert-True (-not (Read-ReadsNoteValidated -RepoRoot $r -CommitSha $rc).Valid) 'reads note missing parent_sha -> invalid (fail-closed)'
    Write-AuditNote -RepoRoot $r -NoteRef (Get-ReadsNoteRef) -CommitSha $rc -BodyLines (New-ReadsBody ($rcParent.Substring(0, 7)))
    Assert-True (-not (Read-ReadsNoteValidated -RepoRoot $r -CommitSha $rc).Valid) 'reads note with a 7-char prefix parent_sha -> invalid (full 40-char required; parity with panel/comment)'
    Write-AuditNote -RepoRoot $r -NoteRef (Get-ReadsNoteRef) -CommitSha $rc -BodyLines (New-ReadsBody ('f' * 64))
    $reads256 = Read-ReadsNoteValidated -RepoRoot $r -CommitSha $rc
    Assert-True (-not $reads256.Valid -and (@($reads256.Errors) -match 'does not match the commit parent')) '64-hex reads parent_sha passes the shape check (rejected only as stale)'

    Write-Host "`n=== freshness: stale tree (direct + real rewriteRef amend-carry) ==="
    # direct: a note whose audited_tree points at a different commit's tree
    $rd = New-TempRepo
    $d0 = New-TestCommit -Directory $rd -File 'x.txt' -Content 'aaa' -Message 'd0'
    $d1 = New-TestCommit -Directory $rd -File 'x.txt' -Content 'bbb' -Message 'd1'
    $treeD0 = Get-CommitTreeSha -RepoRoot $rd -CommitSha $d0
    $staleNote = @("audited_tree: $treeD0", 'parent_sha: x', 'commit_subject: y')   # tree of d0, attached to d1
    $freshD1 = Test-AuditNoteFreshness -NoteLines $staleNote -RepoRoot $rd -CommitSha $d1
    Assert-True (-not $freshD1.Fresh) 'note carrying a different commit tree -> stale'

    # a prefix-only audited_tree must NOT count as fresh, even against its own commit (full 40-char required)
    $prefixNote = @("audited_tree: $($treeD0.Substring(0,12))", 'parent_sha: x', 'commit_subject: y')
    $freshPrefix = Test-AuditNoteFreshness -NoteLines $prefixNote -RepoRoot $rd -CommitSha $d0
    Assert-True (-not $freshPrefix.Fresh) 'note with a 12-char prefix of the real audited_tree -> NOT fresh (no prefix match)'
    $sha256TreeNote = @("audited_tree: $('e' * 64)", 'parent_sha: x', 'commit_subject: y')
    $fresh256 = Test-AuditNoteFreshness -NoteLines $sha256TreeNote -RepoRoot $rd -CommitSha $d0
    Assert-True (-not $fresh256.Fresh -and -not (@($fresh256.Errors) -match 'must be a full')) '64-hex audited_tree passes the shape check (stale only by mismatch)'

    # real path: notes.rewriteRef copies the note across commit --amend; the carried note is stale
    $ra = New-TempRepo
    git -C $ra config notes.rewriteRef (Get-PanelNoteRef)
    git -C $ra config notes.rewriteMode overwrite
    $a0 = New-TestCommit -Directory $ra -File 'a.txt' -Content 'orig' -Message 'a0'
    $pa = Get-CommitParentSha -RepoRoot $ra -CommitSha $a0
    Write-AuditNote -RepoRoot $ra -NoteRef (Get-PanelNoteRef) -CommitSha $a0 -BodyLines (New-PanelBody $pa)
    Set-Content -LiteralPath (Join-Path $ra 'a.txt') -Value 'AMENDED'
    git -C $ra add -A 2>$null
    git -C $ra commit -q --amend -m 'a0 amended'
    $a1 = (git -C $ra rev-parse HEAD).Trim()
    $carried = Read-RawAuditNote -RepoRoot $ra -NoteRef (Get-PanelNoteRef) -CommitSha $a1
    Assert-True ($null -ne $carried) 'notes.rewriteRef carried the note onto the amended commit'
    $freshA1 = Test-AuditNoteFreshness -NoteLines $carried -RepoRoot $ra -CommitSha $a1
    Assert-True (-not $freshA1.Fresh) 'carried note onto amended (changed tree) commit -> STALE (stale-carry hole closed)'
    $vA1 = Read-PanelNoteValidated -RepoRoot $ra -CommitSha $a1 -GovernanceTier 1
    Assert-True (-not $vA1.Valid) 'validated read rejects the stale carried note'

    Write-Host "`n=== two-ref independence (a single-ref re-flush never destroys the other) ==="
    $r2 = New-TempRepo
    git -C $r2 config --add notes.rewriteRef (Get-PanelNoteRef)     # BOTH refs carry (as setup.ps1 wires)
    git -C $r2 config --add notes.rewriteRef (Get-CommentNoteRef)
    git -C $r2 config notes.rewriteMode overwrite
    $b0 = New-TestCommit -Directory $r2 -File 'a.txt' -Content 'orig' -Message 'b0'
    $pb = Get-CommitParentSha -RepoRoot $r2 -CommitSha $b0
    Write-AuditNote -RepoRoot $r2 -NoteRef (Get-PanelNoteRef)   -CommitSha $b0 -BodyLines (New-PanelBody $pb)
    Write-AuditNote -RepoRoot $r2 -NoteRef (Get-CommentNoteRef) -CommitSha $b0 -BodyLines (New-CommentBody $pb)
    # amend -> panel note carries; re-flush ONLY the panel note fresh; comment note must survive
    Set-Content -LiteralPath (Join-Path $r2 'a.txt') -Value 'AMENDED'
    git -C $r2 add -A 2>$null
    git -C $r2 commit -q --amend -m 'b0 amended'
    $b1 = (git -C $r2 rev-parse HEAD).Trim()
    $pb1 = Get-CommitParentSha -RepoRoot $r2 -CommitSha $b1
    Write-AuditNote -RepoRoot $r2 -NoteRef (Get-PanelNoteRef) -CommitSha $b1 -BodyLines (New-PanelBody $pb1)  # fresh panel only
    $panelB1 = Read-RawAuditNote -RepoRoot $r2 -NoteRef (Get-PanelNoteRef)   -CommitSha $b1
    $commentB1 = Read-RawAuditNote -RepoRoot $r2 -NoteRef (Get-CommentNoteRef) -CommitSha $b1
    Assert-True ((Test-AuditNoteFreshness -NoteLines $panelB1 -RepoRoot $r2 -CommitSha $b1).Fresh) 're-flushed panel note is fresh'
    Assert-True ($null -ne $commentB1) 'comment note still present after panel re-flush (NOT destroyed) - two-ref independence'
    Assert-True ([bool](@($commentB1) | Where-Object { $_ -cmatch 'Comment audit:' })) 'comment note body intact'
    Assert-True (-not (Test-AuditNoteFreshness -NoteLines $commentB1 -RepoRoot $r2 -CommitSha $b1).Fresh) 'carried comment note is STALE (whole-tree freshness; agent re-authors both receipts on amend)'

    Write-Host "`n=== Get-NormalizedRemoteIdentity + Test-RequiresFullPanel ==="
    Assert-Equal 'github.com/jschick04/copilotinstructions' (Get-NormalizedRemoteIdentity 'https://github.com/jschick04/CopilotInstructions.git') 'https url normalized' -CaseSensitive
    Assert-Equal 'github.com/jschick04/copilotinstructions' (Get-NormalizedRemoteIdentity 'git@github.com:jschick04/CopilotInstructions.git') 'scp-style url normalized' -CaseSensitive
    Assert-Equal 'github.com/jschick04/copilotinstructions' (Get-NormalizedRemoteIdentity 'ssh://git@github.com/jschick04/CopilotInstructions') 'ssh url (no .git) normalized' -CaseSensitive
    Assert-Equal 'github.com/other/repo' (Get-NormalizedRemoteIdentity 'https://github.com/other/repo.git') 'foreign url normalized (no false match)' -CaseSensitive

    $idRepo = New-TempRepo -WithIdentity
    [void](New-TestCommit -Directory $idRepo -File 'seed.txt' -Content 's' -Message 'seed')
    Assert-True (Test-RequiresFullPanel -RepoRoot $idRepo) 'identity repo (jschick04 remote + sentinels) -> true'
    $foreign = New-TempRepo
    [void](New-TestCommit -Directory $foreign -File 'seed.txt' -Content 's' -Message 'seed')
    Assert-True (-not (Test-RequiresFullPanel -RepoRoot $foreign)) 'repo without the identity remote -> false'
    git -C $idRepo remote set-url origin 'https://github.com/someone/Else.git'
    Assert-True (Test-RequiresFullPanel -RepoRoot $idRepo) 'object activation survives fork remote URL'
    $consumer = New-TempRepo -WithIdentity
    git -C $consumer remote set-url origin 'https://github.com/acme/their-app.git'
    git -C $consumer remote add upstream 'https://github.com/jschick04/CopilotInstructions.git'
    [void](New-TestCommit -Directory $consumer -File 'seed.txt' -Content 'seed' -Message 'activate')
    Assert-True (Test-RequiresFullPanel -RepoRoot $consumer) 'committed activation does not depend on origin identity'

    Write-Host "`n=== flush-audits.ps1 end-to-end (identity repo) + identity no-op ==="
    $fr = New-TempRepo -WithIdentity
    $fc = New-TestCommit -Directory $fr -File 'src.txt' -Content 'code' -Message 'feat'
    $fp = Get-CommitParentSha -RepoRoot $fr -CommitSha $fc
    Set-Content -LiteralPath (Join-Path $fr '.github/pr-quality-gate/audits/post-code-change-last.md') -Value ((New-PanelBody $fp) -join "`n")
    Set-Content -LiteralPath (Join-Path $fr '.github/pr-quality-gate/audits/last.md') -Value ((New-CommentBody $fp) -join "`n")
    $pcBody = @(
        "parent_sha: $fp", 'commit_subject: feat', 'PRE-COMMIT GATE PASSED',
        'gate|diff_shown=yes|diff_approved=yes:t1|staged_diff_verified=yes:(1 files)matches|profile=full|author_identity=T <t@t.t>|commit_ownership=agent|rule_coverage_passed=true|pr_creation=deferred',
        'subject|proposed_subject="feat"|subject_approved=yes:t1|format_check=single_line:yes,co_authored_by_trailer:no,body:no,conventional_commit_prefix:no,subject_length_chars:4',
        'core_rules_acknowledged:', '  - slug:comment-necessity status:applied sites:[s:1] metric:rg=0/0 disp:keep',
        'staged_files:', '  - src.txt'
    )
    Set-Content -LiteralPath (Join-Path $fr '.github/pr-quality-gate/audits/pre-commit-gate-last.md') -Value ($pcBody -join "`n")
    & (Join-Path $repoRoot 'scripts/flush-audits.ps1') -RepoRoot $fr -CommitSha HEAD -Quiet
    Assert-True ($null -ne (Read-RawAuditNote -RepoRoot $fr -NoteRef (Get-PanelNoteRef)   -CommitSha $fc)) 'flush wrote the panel note'
    Assert-True ($null -ne (Read-RawAuditNote -RepoRoot $fr -NoteRef (Get-CommentNoteRef) -CommitSha $fc)) 'flush wrote the comment note'
    Assert-True (-not (Test-Path (Join-Path $fr '.github/pr-quality-gate/audits/post-code-change-last.md'))) 'flush cleared the panel receipt'
    Assert-True (-not (Test-Path (Join-Path $fr '.github/pr-quality-gate/audits/last.md'))) 'flush cleared the comment receipt'
    Assert-True (Read-PanelNoteValidated -RepoRoot $fr -CommitSha $fc -GovernanceTier 1).Valid 'flushed panel note validates'
    Assert-Equal 'refs/notes/copilot-audit-precommit' (Get-PreCommitNoteRef) 'pre-commit ref name' -CaseSensitive
    Assert-True ($null -ne (Read-RawAuditNote -RepoRoot $fr -NoteRef (Get-PreCommitNoteRef) -CommitSha $fc)) 'flush wrote the pre-commit-gate note (4th receipt)'
    Assert-True (-not (Test-Path (Join-Path $fr '.github/pr-quality-gate/audits/pre-commit-gate-last.md'))) 'flush cleared the pre-commit-gate receipt'
    Assert-True (Read-PreCommitGateNoteValidated -RepoRoot $fr -CommitSha $fc -GovernanceTier 1).Valid 'flushed pre-commit-gate note validates'

    $nr = New-TempRepo   # no identity
    $nc = New-TestCommit -Directory $nr -File 'src.txt' -Content 'code' -Message 'feat'
    New-Item -ItemType Directory -Path (Join-Path $nr '.github/pr-quality-gate/audits') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $nr '.github/pr-quality-gate/audits/post-code-change-last.md') -Value 'should-not-be-flushed'
    & (Join-Path $repoRoot 'scripts/flush-audits.ps1') -RepoRoot $nr -CommitSha HEAD -Quiet
    Assert-True ($null -eq (Read-RawAuditNote -RepoRoot $nr -NoteRef (Get-PanelNoteRef) -CommitSha $nc)) 'no-identity repo: flush wrote NO note'
    Assert-True (Test-Path (Join-Path $nr '.github/pr-quality-gate/audits/post-code-change-last.md')) 'no-identity repo: receipt left untouched'

    foreach ($remoteForm in @('https://github.example/fork/instructions.git','git@instructions-alias:owner/repository.git','none')) {
        if ($remoteForm -eq 'none') { & git -C $fr remote remove origin }
        else { & git -C $fr remote set-url origin $remoteForm }
        Set-Content -LiteralPath (Join-Path $fr '.github/pr-quality-gate/audits/post-code-change-last.md') -Value (New-PanelBody $fp)
        & pwsh -NoProfile -File (Join-Path $repoRoot 'scripts/flush-audits.ps1') -RepoRoot $fr -CommitSha $fc 2>&1 | Out-Null
        Assert-True ($LASTEXITCODE -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $fr '.github/pr-quality-gate/audits/post-code-change-last.md'))) "note writer activates on git objects for remote form $remoteForm"
    }

    Write-Host "`n=== idempotent re-flush (audited_tree not doubled) ==="
    $ir = New-TempRepo
    $ic = New-TestCommit -Directory $ir -File 'a.txt' -Content 'x' -Message 'c'
    $ip = Get-CommitParentSha -RepoRoot $ir -CommitSha $ic
    $bodyWithTree = @("audited_tree: 0000000000000000000000000000000000000000") + (New-PanelBody $ip)
    Write-AuditNote -RepoRoot $ir -NoteRef (Get-PanelNoteRef) -CommitSha $ic -BodyLines $bodyWithTree
    $reflushed = Read-RawAuditNote -RepoRoot $ir -NoteRef (Get-PanelNoteRef) -CommitSha $ic
    $treeCount = (@($reflushed) | Where-Object { $_ -cmatch '^audited_tree:' }).Count
    Assert-Equal 1 $treeCount 'exactly one audited_tree line after writing a body that already had one' -CaseSensitive
}
finally { Remove-TestTempDirectories }

Complete-TestRun
