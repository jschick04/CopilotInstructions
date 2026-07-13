#Requires -Version 5.1
# Standalone pwsh self-test for scripts/check-audit-notes-prepush.ps1 (the pre-push
# local-note gate). NOT Pester. Run: pwsh -File scripts/tests/check-audit-notes-prepush.tests.ps1

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-common.ps1')
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$validator = Join-Path $repoRoot 'scripts/check-audit-notes-prepush.ps1'
Import-Module (Join-Path $repoRoot 'scripts/lib/audit-note-helpers.psm1') -Force -DisableNameChecking

$script:Pass = 0
$script:Fail = 0

function New-IdRepo {
    param([switch] $NoSetup)
    $dir = New-TestGitRepository -Prefix 'anp'
    git -C $dir remote add origin 'https://github.com/jschick04/CopilotInstructions.git'
    Set-Content -LiteralPath (Join-Path $dir 'AGENTS.md') -Value 'x' -NoNewline
    New-Item -ItemType Directory -Path (Join-Path $dir 'scripts') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $dir 'scripts/check-post-code-change.ps1') -Value 'x' -NoNewline
    New-Item -ItemType Directory -Path (Join-Path $dir '.github/pr-quality-gate/audits') -Force | Out-Null
    if (-not $NoSetup) {
        git -C $dir config --add notes.rewriteRef (Get-PanelNoteRef)
        git -C $dir config --add notes.rewriteRef (Get-CommentNoteRef)
        git -C $dir config --add notes.rewriteRef (Get-ReadsNoteRef)
        git -C $dir config --add notes.rewriteRef (Get-PreCommitNoteRef)
        git -C $dir config notes.rewriteMode overwrite
        git -C $dir config core.hooksPath '.githooks'
    }
    return $dir
}

function Write-PanelNote {
    param([string] $Dir, [string] $Sha)
    $parent = Get-CommitParentSha -RepoRoot $Dir -CommitSha $Sha
    $body = @("parent_sha: $parent", 'commit_subject: panel commit', 'POST-CODE-CHANGE LEDGER') +
        (Get-ValidPreRows -G5 'panel-ran') +
        @('  post-code-change-panel: ran, unanimous', '  build: N/A: docs', '  tests: passed') + (Get-ValidPanelTranscript)
    Write-AuditNote -RepoRoot $Dir -NoteRef (Get-PanelNoteRef) -CommitSha $Sha -BodyLines $body
}
function Write-CommentNote {
    param([string] $Dir, [string] $Sha, [int] $Bullets = 1)
    $parent = Get-CommitParentSha -RepoRoot $Dir -CommitSha $Sha
    $body = @("parent_sha: $parent", 'commit_subject: comment commit')
    for ($i = 1; $i -le $Bullets; $i++) { $body += "- src.cs:${i}: approval_turn: n/a - exempt: generated" }
    Write-AuditNote -RepoRoot $Dir -NoteRef (Get-CommentNoteRef) -CommitSha $Sha -BodyLines $body
}
function Write-ReadsNote {
    param([string] $Dir, [string] $Sha, [string] $Path, [string] $Token)
    $parent = Get-CommitParentSha -RepoRoot $Dir -CommitSha $Sha
    Write-AuditNote -RepoRoot $Dir -NoteRef (Get-ReadsNoteRef) -CommitSha $Sha -BodyLines @("parent_sha: $parent", "reads=$Path@$Token")
}
function Write-PreCommitNote {
    param([string] $Dir, [string] $Sha)
    $parent = Get-CommitParentSha -RepoRoot $Dir -CommitSha $Sha
    $pv = if ($parent -eq $GitEmptyTreeSha) { 'NONE' } else { $parent }
    $body = @(
        "parent_sha: $pv",
        'commit_subject: precommit commit',
        'PRE-COMMIT GATE PASSED',
        'gate|diff_shown=yes:t1|diff_approved=yes:t2|staged_diff_verified=yes:(1 files,+1/-0)matches|profile=full|author_identity=T <t@t.t>|commit_ownership=agent|rule_coverage_passed=true|pr_creation=deferred',
        'subject|proposed_subject="precommit commit"|subject_approved=yes:t2|format_check=single_line:yes',
        'core_rules_acknowledged:',
        '  - slug:comment-necessity status:applied sites:[x:1] metric:rg=0/0 disp:keep',
        'staged_files:',
        '  - x'
    )
    Write-AuditNote -RepoRoot $Dir -NoteRef (Get-PreCommitNoteRef) -CommitSha $Sha -BodyLines $body
}

function Invoke-Validator {
    param([string] $Dir, [string[]] $RefLines)
    $refText = ($RefLines -join "`n")
    $out = $refText | pwsh -NoProfile -File $validator -RepoRoot $Dir -RemoteName origin 2>&1
    return [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Output = ($out | Out-String) }
}

function RefLine { param($Local, $Remote) "refs/heads/main $Local refs/heads/main $Remote" }
$ZERO = '0' * 40

try {
    Write-Host "`n=== panel note: present/valid vs missing vs stale ==="
    $d = New-IdRepo
    $c0 = New-TestCommit -Directory $d -File 'a.txt' -Content 'base' -Message 'c0'
    $c1 = New-TestCommit -Directory $d -File 'scripts/x.ps1' -Content 'code' -Message 'c1 (panel-required)'
    Write-PanelNote -Dir $d -Sha $c1
    $r = Invoke-Validator -Dir $d -RefLines @(RefLine $c1 $c0)
    Assert-True ($r.ExitCode -eq 0) "panel-required commit with valid note -> exit 0 ($($r.Output.Trim()))"

    $d2 = New-IdRepo
    $e0 = New-TestCommit -Directory $d2 -File 'a.txt' -Content 'base' -Message 'e0'
    $e1 = New-TestCommit -Directory $d2 -File 'scripts/x.ps1' -Content 'code' -Message 'e1 (panel-required, NO note)'
    $r2 = Invoke-Validator -Dir $d2 -RefLines @(RefLine $e1 $e0)
    Assert-True ($r2.ExitCode -eq 1) 'panel-required commit with NO note -> exit 1'
    Assert-True ($r2.Output -match 'no panel-ledger note') 'reports missing panel note'

    $dN = New-IdRepo
    $n0 = New-TestCommit -Directory $dN -File 'a.txt' -Content 'base' -Message 'n0'
    $n1 = New-TestCommit -Directory $dN -File 'notes.txt' -Content 'docs only' -Message 'n1 (NOT panel-required)'
    $np = Get-CommitParentSha -RepoRoot $dN -CommitSha $n1
    $badPanel = @("parent_sha: $np", 'commit_subject: n1', 'POST-CODE-CHANGE LEDGER', '  post-code-change-panel: ran, unanimous', '  build: N/A: docs', '  tests: passed')
    Write-AuditNote -RepoRoot $dN -NoteRef (Get-PanelNoteRef) -CommitSha $n1 -BodyLines $badPanel
    $rN = Invoke-Validator -Dir $dN -RefLines @(RefLine $n1 $n0)
    Assert-True ($rN.ExitCode -eq 1) 'non-panel-required commit + present-but-invalid panel note -> exit 1 (present-note OR-branch)'

    # stale: write the note, then amend the commit's tree without re-flushing
    $d3 = New-IdRepo
    $f0 = New-TestCommit -Directory $d3 -File 'a.txt' -Content 'base' -Message 'f0'
    $f1 = New-TestCommit -Directory $d3 -File 'scripts/x.ps1' -Content 'code' -Message 'f1'
    Write-PanelNote -Dir $d3 -Sha $f1
    Set-Content -LiteralPath (Join-Path $d3 'scripts/x.ps1') -Value 'CHANGED'
    git -C $d3 add -A 2>$null; git -C $d3 commit -q --amend -m 'f1 amended'
    $f1b = (git -C $d3 rev-parse HEAD).Trim()
    $r3 = Invoke-Validator -Dir $d3 -RefLines @(RefLine $f1b $f0)
    Assert-True ($r3.ExitCode -eq 1) 'panel-required commit with STALE carried note -> exit 1'
    Assert-True ($r3.Output -match 'stale|audited_tree') 'reports staleness'

    Write-Host "`n=== docs-only commit needs no note ==="
    $d4 = New-IdRepo
    $g0 = New-TestCommit -Directory $d4 -File 'a.txt' -Content 'base' -Message 'g0'
    $g1 = New-TestCommit -Directory $d4 -File 'README.md' -Content "# docs`nplain prose" -Message 'g1 docs'
    $r4 = Invoke-Validator -Dir $d4 -RefLines @(RefLine $g1 $g0)
    Assert-True ($r4.ExitCode -eq 0) 'docs-only (non-panel, no comments) commit -> exit 0'

    Write-Host "`n=== comment note: covered vs missing vs under-covered ==="
    $d5 = New-IdRepo
    $h0 = New-TestCommit -Directory $d5 -File 'a.txt' -Content 'base' -Message 'h0'
    $h1 = New-TestCommit -Directory $d5 -File 'src.cs' -Content "int x = 1; // a new comment" -Message 'h1 comment'
    Write-PanelNote -Dir $d5 -Sha $h1          # .cs is also panel-required
    Write-CommentNote -Dir $d5 -Sha $h1 -Bullets 1
    $r5 = Invoke-Validator -Dir $d5 -RefLines @(RefLine $h1 $h0)
    Assert-True ($r5.ExitCode -eq 0) 'commit with 1 new comment + covering note -> exit 0'

    $d6 = New-IdRepo
    $i0 = New-TestCommit -Directory $d6 -File 'a.txt' -Content 'base' -Message 'i0'
    $i1 = New-TestCommit -Directory $d6 -File 'src.cs' -Content "int x = 1; // a new comment" -Message 'i1 comment'
    Write-PanelNote -Dir $d6 -Sha $i1          # panel ok, but NO comment note
    $r6 = Invoke-Validator -Dir $d6 -RefLines @(RefLine $i1 $i0)
    Assert-True ($r6.ExitCode -eq 1) 'commit with new comment but NO comment note -> exit 1'
    Assert-True ($r6.Output -match 'comment') 'reports the comment violation'

    Write-Host "`n=== new-branch range (remote all-zero) ==="
    $d7 = New-IdRepo
    $j0 = New-TestCommit -Directory $d7 -File 'scripts/x.ps1' -Content 'code' -Message 'j0 panel'
    Write-PanelNote -Dir $d7 -Sha $j0
    $r7 = Invoke-Validator -Dir $d7 -RefLines @(RefLine $j0 $ZERO)
    Assert-True ($r7.ExitCode -eq 0) 'new-branch push validates the new commit(s) with valid notes -> exit 0'

    Write-Host "`n=== no-publish guard + delete-push + setup assertion + identity ==="
    $d8 = New-IdRepo
    [void](New-TestCommit -Directory $d8 -File 'a.txt' -Content 'base' -Message 'k0')
    $rNote = Invoke-Validator -Dir $d8 -RefLines @("refs/notes/copilot-audit-panel $('a'*40) refs/notes/copilot-audit-panel $ZERO")
    Assert-True ($rNote.ExitCode -eq 1 -and $rNote.Output -match 'refusing to push') 'no-publish guard refuses pushing a note ref'

    $rDel = Invoke-Validator -Dir $d8 -RefLines @(RefLine $ZERO ('b'*40))
    Assert-True ($rDel.ExitCode -eq 0) 'delete-push (local all-zero) -> exit 0 (nothing to validate)'

    $d9 = New-IdRepo -NoSetup     # no notes.rewriteRef / hooksPath
    $m0 = New-TestCommit -Directory $d9 -File 'a.txt' -Content 'base' -Message 'm0'
    $m1 = New-TestCommit -Directory $d9 -File 'scripts/x.ps1' -Content 'code' -Message 'm1'
    Write-PanelNote -Dir $d9 -Sha $m1
    $r9 = Invoke-Validator -Dir $d9 -RefLines @(RefLine $m1 $m0)
    Assert-True ($r9.ExitCode -eq 1 -and $r9.Output -match 'notes.rewriteRef|hooksPath') 'missing setup -> exit 1 (fail loud)'

    # identity gate: a non-instructions repo no-ops even with a panel-required, note-less commit
    $dF = New-TestGitRepository -Prefix 'anp-foreign'
    git -C $dF remote add origin 'https://github.com/someone/other.git'
    $n0 = New-TestCommit -Directory $dF -File 'a.txt' -Content 'base' -Message 'n0'
    $n1 = New-TestCommit -Directory $dF -File 'scripts/x.ps1' -Content 'code' -Message 'n1 panel (no note)'
    $rF = Invoke-Validator -Dir $dF -RefLines @(RefLine $n1 $n0)
    Assert-True ($rF.ExitCode -eq 0) 'non-instructions repo: identity gate -> exit 0 (no-op, never enforces on a consumer)'

    Write-Host "`n=== merge commit validated via first-parent (no silent --no-merges skip) ==="
    $dM = New-IdRepo
    $b0 = New-TestCommit -Directory $dM -File 'a.txt' -Content 'base' -Message 'b0'
    git -C $dM checkout -q -b feature
    $bf = New-TestCommit -Directory $dM -File 'scripts/feat.ps1' -Content 'feat' -Message 'bf panel on feature'
    git -C $dM checkout -q main
    [void](New-TestCommit -Directory $dM -File 'b.txt' -Content 'main-side' -Message 'bm')
    git -C $dM merge -q --no-ff -m 'merge feature' feature
    $mergeSha = (git -C $dM rev-parse HEAD).Trim()
    Write-PanelNote -Dir $dM -Sha $bf      # the feature commit is noted; the MERGE is not (yet)
    # the merge's first-parent diff integrates scripts/feat.ps1 -> panel-required -> needs its own note
    $rM1 = Invoke-Validator -Dir $dM -RefLines @(RefLine $mergeSha $b0)
    $mergeShort = $mergeSha.Substring(0, 8)
    Assert-True ($rM1.ExitCode -eq 1 -and $rM1.Output -match $mergeShort) 'un-noted merge with a panel-required first-parent diff -> exit 1 (NOT silently skipped)'
    Write-PanelNote -Dir $dM -Sha $mergeSha
    $rM2 = Invoke-Validator -Dir $dM -RefLines @(RefLine $mergeSha $b0)
    Assert-True ($rM2.ExitCode -eq 0) 'merge + feature commit both noted -> exit 0'

    Write-Host "`n=== rev-list failure (remote tip absent locally) -> fail closed ==="
    $dgf = New-IdRepo
    [void](New-TestCommit -Directory $dgf -File 'a.txt' -Content 'base' -Message 'g0')
    $g1 = New-TestCommit -Directory $dgf -File 'scripts/x.ps1' -Content 'code' -Message 'g1'
    Write-PanelNote -Dir $dgf -Sha $g1; Write-CommentNote -Dir $dgf -Sha $g1
    $fakeRemote = 'deadbeefbeefbeefbeefbeefbeefbeefbeefdead'
    $rgf = Invoke-Validator -Dir $dgf -RefLines @(RefLine $g1 $fakeRemote)
    Assert-True ($rgf.ExitCode -ne 0 -and $rgf.Output -match 'rev-list') 'rev-list failure (remote tip not present) -> non-zero exit (fail closed, not skip)'

    Write-Host "`n=== reads note: a commit matching a gated code-topic glob requires a fresh reads note ==="
    $dr = New-IdRepo
    New-Item -ItemType Directory -Path (Join-Path $dr '.github/instructions') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $dr '.github/instructions/fake-cs.instructions.md') "---`napplyTo: `"**/*.cs`"`n---`n`n# Fake CS`n`n<!-- read-receipt-token: 11111111 -->`n" -NoNewline
    $rbase = New-TestCommit -Directory $dr -File 'README.md' -Content 'base' -Message 'base + gated instr'
    $rcs = New-TestCommit -Directory $dr -File 'Foo.cs' -Content 'class F{}' -Message 'touch cs'
    Write-PanelNote -Dir $dr -Sha $rcs
    $ra = Invoke-Validator -Dir $dr -RefLines @(RefLine $rcs $rbase)
    Assert-True ($ra.ExitCode -ne 0 -and $ra.Output -match 'reads') 'gated .cs commit, no reads note -> fail (reads enforcement)'
    Write-ReadsNote -Dir $dr -Sha $rcs -Path '.github/instructions/fake-cs.instructions.md' -Token '11111111'
    $rb = Invoke-Validator -Dir $dr -RefLines @(RefLine $rcs $rbase)
    Assert-True ($rb.ExitCode -eq 0) 'gated .cs commit, fresh valid reads note (token matches commit tree) -> pass'
    Write-ReadsNote -Dir $dr -Sha $rcs -Path '.github/instructions/fake-cs.instructions.md' -Token '99999999'
    $rc = Invoke-Validator -Dir $dr -RefLines @(RefLine $rcs $rbase)
    Assert-True ($rc.ExitCode -ne 0 -and $rc.Output -match 'reads') 'gated .cs commit, stale reads token -> fail'

    Write-Host "`n=== reads membership is per-commit-tree: a worktree delete of the instruction file does not un-gate the pushed commit ==="
    $drd = New-IdRepo
    New-Item -ItemType Directory -Path (Join-Path $drd '.github/instructions') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $drd '.github/instructions/fake-cs.instructions.md') "---`napplyTo: `"**/*.cs`"`n---`n`n# Fake CS`n`n<!-- read-receipt-token: 11111111 -->`n" -NoNewline
    $drdBase = New-TestCommit -Directory $drd -File 'README.md' -Content 'base' -Message 'base + gated instr'
    $drdCs = New-TestCommit -Directory $drd -File 'Foo.cs' -Content 'class F{}' -Message 'touch cs'
    Write-PanelNote -Dir $drd -Sha $drdCs
    Remove-Item -LiteralPath (Join-Path $drd '.github/instructions/fake-cs.instructions.md')
    $rdd = Invoke-Validator -Dir $drd -RefLines @(RefLine $drdCs $drdBase)
    Assert-True ($rdd.ExitCode -ne 0 -and $rdd.Output -match 'reads') 'instruction file deleted in the worktree (unstaged; still in every commit tree) -> the pushed gated .cs commit still requires a reads note -> fail (membership is per-commit-tree, no fail-open)'

    Write-Host "`n=== pre-commit-gate note (4th receipt): adopted range requires a fresh valid note ==="
    $dp = New-IdRepo
    Set-Content -LiteralPath (Join-Path $dp 'scripts/check-pre-commit-gate.ps1') -Value 'x' -NoNewline
    $p0 = New-TestCommit -Directory $dp -File 'a.txt' -Content 'base' -Message 'p0 (adopted base)'
    $p1 = New-TestCommit -Directory $dp -File 'code.cs' -Content 'class C{}' -Message 'p1'
    Write-PanelNote -Dir $dp -Sha $p1
    $rp = Invoke-Validator -Dir $dp -RefLines @(RefLine $p1 $p0)
    Assert-True ($rp.ExitCode -ne 0 -and $rp.Output -match 'pre-commit-gate') 'adopted range, missing pre-commit-gate note -> fail'
    Write-PreCommitNote -Dir $dp -Sha $p1
    $rp2 = Invoke-Validator -Dir $dp -RefLines @(RefLine $p1 $p0)
    Assert-True ($rp2.ExitCode -eq 0) "adopted range, valid pre-commit-gate note -> pass ($($rp2.Output.Trim()))"

    Write-Host "`n=== pre-commit-gate: non-adopted range (no checker anywhere in range or its base) is exempt ==="
    $dn = New-IdRepo
    $n0 = New-TestCommit -Directory $dn -File 'a.txt' -Content 'base' -Message 'n0'
    $n1 = New-TestCommit -Directory $dn -File 'code.cs' -Content 'class C{}' -Message 'n1'
    Write-PanelNote -Dir $dn -Sha $n1
    $rn = Invoke-Validator -Dir $dn -RefLines @(RefLine $n1 $n0)
    Assert-True ($rn.ExitCode -eq 0) 'non-adopted range (no check-pre-commit-gate.ps1 in tree) -> pre-commit-gate not required -> pass'

    Write-Host "`n=== pre-commit-gate: two-commit --no-verify removal cannot self-exempt (range base is adopted) ==="
    $dx = New-IdRepo
    Set-Content -LiteralPath (Join-Path $dx 'scripts/check-pre-commit-gate.ps1') -Value 'x' -NoNewline
    $x0 = New-TestCommit -Directory $dx -File 'a.txt' -Content 'base' -Message 'x0 (adopted base)'
    Remove-Item -LiteralPath (Join-Path $dx 'scripts/check-pre-commit-gate.ps1')
    $xa = New-TestCommit -Directory $dx -File 'b.txt' -Content 'more' -Message 'A removes checker'
    $xb = New-TestCommit -Directory $dx -File 'code.cs' -Content 'class C{}' -Message 'B'
    Write-PanelNote -Dir $dx -Sha $xa
    Write-PanelNote -Dir $dx -Sha $xb
    $rx = Invoke-Validator -Dir $dx -RefLines @(RefLine $xb $x0)
    Assert-True ($rx.ExitCode -ne 0 -and $rx.Output -match 'pre-commit-gate') 'two-commit removal: base (x0) still carries the checker -> A+B still require pre-commit notes -> fail (bypass closed)'
}
finally { Remove-TestTempDirectories }

Complete-TestRun
