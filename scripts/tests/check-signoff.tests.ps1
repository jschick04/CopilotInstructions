#Requires -Version 5.1
# Standalone pwsh self-test for scripts/check-signoff.ps1.
# Run: pwsh -File scripts/tests/check-signoff.tests.ps1

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-common.ps1')
Import-Module (Join-Path $PSScriptRoot '../lib/panel-ledger-helpers.psm1') -Force -DisableNameChecking
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$checker = Join-Path $repoRoot 'scripts/check-signoff.ps1'

$script:Pass = 0; $script:Fail = 0

function New-IdRepo {
    param([switch] $Foreign)
    $dir = New-TestGitRepository -Prefix 'so'
    git -C $dir remote add origin ($(if ($Foreign) { 'https://github.com/someone/other.git' } else { 'https://github.com/jschick04/CopilotInstructions.git' }))
    Set-Content -LiteralPath (Join-Path $dir 'AGENTS.md') -Value 'x' -NoNewline
    New-Item -ItemType Directory -Path (Join-Path $dir 'scripts') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $dir 'scripts/check-post-code-change.ps1') -Value 'x' -NoNewline
    New-Item -ItemType Directory -Path (Join-Path $dir '.github/pr-quality-gate/audits') -Force | Out-Null
    if (-not $Foreign) {
        Set-Content -LiteralPath (Join-Path $dir '.github/pr-quality-gate/panel-policy.md') -Value 'fixture policy'
        git -C $dir add .github/pr-quality-gate/panel-policy.md 2>$null
    }
    return $dir
}
function Stage { param($Dir, $File, $Content) Set-Content -LiteralPath (Join-Path $Dir $File) -Value $Content; git -C $Dir add $File 2>$null }
function IndexTree { param($Dir) (git -C $Dir write-tree).Trim() }
function WriteReceipt { param($Dir, [string[]]$Lines) Set-Content -LiteralPath (Join-Path $Dir '.github/pr-quality-gate/audits/signoff-receipt') -Value $Lines }
function Run { param($Dir, [string[]]$ExtraArgs)
    $a = @('-NoProfile', '-File', $checker, '-RepoRoot', $Dir) + $ExtraArgs
    $out = & pwsh @a 2>&1
    return [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Output = ($out | Out-String) }
}

try {
    Write-Host "`n=== amend mode ==="
    $d = New-IdRepo
    Stage $d 'a.txt' 'one'
    $tree = IndexTree $d
    WriteReceipt $d @("amend_approved: turn-42 tree:$tree")
    $r = Run $d @('-Mode', 'amend')
    Assert-True ($r.ExitCode -eq 0) 'amend + fresh marker matching the index tree -> exit 0'

    Remove-Item (Join-Path $d '.github/pr-quality-gate/audits/signoff-receipt') -Force
    $r = Run $d @('-Mode', 'amend')
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'no sign-off receipt') 'amend + NO receipt -> exit 1'

    WriteReceipt $d @("amend_approved: turn-1 tree:deadbeefdeadbeefdeadbeefdeadbeefdeadbeef")
    $r = Run $d @('-Mode', 'amend')
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'authorizes tree') 'amend + marker for a DIFFERENT tree (stale) -> exit 1'

    Stage $d 'b.txt' 'two'   # change the index -> tree changes -> the old marker is stale
    $tree2 = IndexTree $d
    WriteReceipt $d @("amend_approved: turn-7 tree:$tree")   # old tree, index now $tree2
    $r = Run $d @('-Mode', 'amend')
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match $tree2) 'amend + marker tree no longer matches the (changed) index -> exit 1 (reports the new index tree)'

    Write-Host "`n=== force-push mode ==="
    $d2 = New-IdRepo
    Stage $d2 'base.txt' 'base'; git -C $d2 commit -q -m base
    $overwrittenRemote = (git -C $d2 rev-parse HEAD).Trim()
    Stage $d2 'a.txt' 'one'; git -C $d2 commit -q -m c
    $ct = (git -C $d2 rev-parse 'HEAD^{tree}').Trim()
    $tip = (git -C $d2 rev-parse HEAD).Trim()
    WriteReceipt $d2 @("force_push_approved: turn-9 tree:$ct")
    $r = Run $d2 @('-Mode', 'force-push', '-Tree', $ct, '-CommitSha', $tip, '-RemoteSha', $overwrittenRemote)
    Assert-True ($r.ExitCode -eq 0) 'force-push + marker matching the pushed tip tree -> exit 0'

    WriteReceipt $d2 @("amend_approved: turn-9 tree:$ct")
    $r = Run $d2 @('-Mode', 'force-push', '-Tree', $ct, '-CommitSha', $tip, '-RemoteSha', $overwrittenRemote)
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'no .force_push_approved') 'force-push + only an amend marker -> exit 1'

    WriteReceipt $d2 @("force_push_approved: turn-9 tree:$ct")
    $r = Run $d2 @('-Mode', 'force-push', '-Tree', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', '-CommitSha', $tip, '-RemoteSha', $overwrittenRemote)
    Assert-True ($r.ExitCode -eq 1) 'force-push + tree mismatch -> exit 1'

    # a short/prefix tree binding must NOT authorize (full 40-char SHA required)
    WriteReceipt $d2 @("force_push_approved: turn-9 tree:$($ct.Substring(0,12))")
    $r = Run $d2 @('-Mode', 'force-push', '-Tree', $ct, '-CommitSha', $tip, '-RemoteSha', $overwrittenRemote)
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'full 40- or 64-char') 'force-push + 12-char tree prefix -> exit 1 (no prefix match)'

    WriteReceipt $d2 @("force_push_approved: turn-9 (no tree binding)")
    $r = Run $d2 @('-Mode', 'force-push', '-Tree', $ct, '-CommitSha', $tip, '-RemoteSha', $overwrittenRemote)
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match "missing its .tree") 'marker missing tree binding -> exit 1'

    foreach ($remoteForm in @('git@instructions-alias:owner/repo.git','none')) {
        if ($remoteForm -eq 'none') { git -C $d2 remote remove origin }
        else { git -C $d2 remote set-url origin $remoteForm }
        Remove-Item -LiteralPath (Join-Path $d2 '.github/pr-quality-gate/audits/signoff-receipt') -ErrorAction SilentlyContinue
        $r = Run $d2 @('-Mode', 'force-push', '-Tree', $ct, '-CommitSha', $tip, '-RemoteSha', $overwrittenRemote)
        Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'no sign-off receipt') 'sign-off stays mandatory for SSH-alias and origin-less clones'
    }

    Write-Host "`n=== force-push activation follows the pushed tip ==="
    $pre = New-IdRepo -Foreign
    Stage $pre 'a.txt' 'one'; git -C $pre commit -q -m base
    $baseBranch = (git -C $pre rev-parse --abbrev-ref HEAD).Trim()
    git -C $pre checkout -q -b adopted 2>$null
    New-Item -ItemType Directory -Path (Join-Path $pre '.github/pr-quality-gate') -Force | Out-Null
    Stage $pre '.github/pr-quality-gate/panel-policy.md' 'fixture policy'; git -C $pre commit -q -m adopt
    $adoptedTip = (git -C $pre rev-parse HEAD).Trim()
    git -C $pre checkout -q $baseBranch 2>$null
    $preTip = (git -C $pre rev-parse HEAD).Trim()
    $r = Run $pre @('-Mode', 'force-push', '-CommitSha', $adoptedTip, '-RemoteSha', $preTip)
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'no sign-off receipt') 'pre-adoption checkout force-pushing an adopted tip requires a sign-off marker'
    git -C $pre checkout -q -b rewritten $baseBranch 2>$null
    Stage $pre 'b.txt' 'rewrite'; git -C $pre commit -q -m rewrite
    $rewrittenTip = (git -C $pre rev-parse HEAD).Trim()
    $r = Run $pre @('-Mode', 'force-push', '-CommitSha', $rewrittenTip, '-RemoteSha', $preTip)
    Assert-True ($r.ExitCode -eq 0) 'ordinary pre-adoption-only force push stays a no-op'
    $r = Run $pre @('-Mode', 'force-push', '-CommitSha', $preTip, '-RemoteSha', $adoptedTip)
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'no sign-off receipt') 'rewinding an adopted remote tip to a pre-adoption SHA requires a sign-off marker'
    $r = Run $pre @('-Mode', 'force-push', '-CommitSha', $rewrittenTip, '-RemoteSha', $adoptedTip)
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'no sign-off receipt') 'replacing an adopted remote history with a divergent pre-adoption tip requires a sign-off marker'
    git -C $pre checkout -q -b transient $baseBranch 2>$null
    Stage $pre '.github/pr-quality-gate/panel-policy.md' 'transient policy'; git -C $pre commit -q -m transient-adopt
    $transientAdopt = (git -C $pre rev-parse HEAD).Trim()
    git -C $pre rm -q '.github/pr-quality-gate/panel-policy.md'; git -C $pre commit -q -m transient-drop
    Stage $pre 'c.txt' 'later'; git -C $pre commit -q -m transient-later
    $transientTip = (git -C $pre rev-parse HEAD).Trim()
    Assert-True (Test-RequiresFullPanel -RepoRoot $pre -CommitSha $transientAdopt) 'fixture: middle overwritten commit carries the sentinel'
    Assert-False (Test-RequiresFullPanel -RepoRoot $pre -CommitSha $transientTip) 'fixture: overwritten remote tip itself is not activated'
    $r = Run $pre @('-Mode', 'force-push', '-CommitSha', $preTip, '-RemoteSha', $transientTip)
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'no sign-off receipt') 'sentinel present only in a middle overwritten commit still requires a sign-off marker'
    $overwrittenSet = @(git -C $pre rev-list $transientTip --not $preTip)
    $perCommit = [bool](@($rewrittenTip, $transientTip) + $overwrittenSet | Where-Object { Test-RequiresFullPanel -RepoRoot $pre -CommitSha $_ })
    Assert-Equal $perCommit (Test-RewriteRequiresFullPanel -RepoRoot $pre -TipSha $rewrittenTip -RemoteSha $transientTip -OverwrittenShas $overwrittenSet) 'batched rewrite activation equals per-commit activation (activated range)'
    $quietSet = @(git -C $pre rev-list $rewrittenTip --not $preTip)
    $perCommitQuiet = [bool](@($preTip, $rewrittenTip) + $quietSet | Where-Object { Test-RequiresFullPanel -RepoRoot $pre -CommitSha $_ })
    Assert-Equal $perCommitQuiet (Test-RewriteRequiresFullPanel -RepoRoot $pre -TipSha $preTip -RemoteSha $rewrittenTip -OverwrittenShas $quietSet) 'batched rewrite activation equals per-commit activation (pre-adoption range)'
    Assert-False (Test-RewriteRequiresFullPanel -RepoRoot $pre -TipSha $preTip -RemoteSha $rewrittenTip -OverwrittenShas $quietSet) 'pre-adoption-only rewrite range is not activated'
    git -C $pre checkout -q $baseBranch 2>$null
    $r = Run $pre @('-Mode', 'force-push', '-CommitSha', $preTip, '-RemoteSha', ('b' * 40))
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'git fetch') 'overwritten remote tip missing locally fails closed with a fetch instruction'
    $r = Run $pre @('-Mode', 'force-push', '-CommitSha', $preTip)
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'RemoteSha') 'force-push without the overwritten remote SHA fails closed'
    $sha256Repo = New-TestTempDirectory -Prefix 'so256'
    & git -C $sha256Repo init -q --object-format=sha256 2>$null
    if ($LASTEXITCODE -eq 0) {
        Set-Content -LiteralPath (Join-Path $sha256Repo 'a.txt') -Value 'one'
        git -C $sha256Repo add a.txt 2>$null; git -C $sha256Repo -c user.name=t -c user.email=t@example.com commit -q -m one 2>$null
        $remote256 = (git -C $sha256Repo rev-parse HEAD).Trim()
        New-Item -ItemType Directory -Path (Join-Path $sha256Repo '.github/pr-quality-gate/audits') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $sha256Repo '.github/pr-quality-gate/panel-policy.md') -Value 'fixture policy'
        git -C $sha256Repo add .github/pr-quality-gate/panel-policy.md 2>$null; git -C $sha256Repo -c user.name=t -c user.email=t@example.com commit -q -m adopt 2>$null
        $tip256 = (git -C $sha256Repo rev-parse HEAD).Trim()
        $tree256 = (git -C $sha256Repo rev-parse 'HEAD^{tree}').Trim()
        Assert-Equal 64 $tip256.Length 'sha256 fixture produces 64-hex commit ids'
        WriteReceipt $sha256Repo @("force_push_approved: turn-9 tree:$tree256")
        $r = Run $sha256Repo @('-Mode', 'force-push', '-Tree', $tree256, '-CommitSha', $tip256, '-RemoteSha', $remote256)
        Assert-True ($r.ExitCode -eq 0) "64-hex tip, remote, and tree binding authorize a sha256 force-push: $($r.Output)"
    }
    $r = Run $pre @('-Mode', 'force-push', '-Tree', (git -C $pre rev-parse "${adoptedTip}^{tree}").Trim())
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'CommitSha') 'force-push without the tip SHA fails closed'
    $r = Run $pre @('-Mode', 'force-push', '-CommitSha', $adoptedTip, '-RemoteSha', $preTip, '-Tree', (git -C $pre rev-parse "${preTip}^{tree}").Trim())
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'does not match the tree') 'force-push tree must belong to the pushed tip'

    Write-Host "`n=== git-object activation ==="
    $f = New-IdRepo -Foreign
    Stage $f 'a.txt' 'one'
    $r = Run $f @('-Mode', 'amend')   # no receipt, but foreign repo -> no-op
    Assert-True ($r.ExitCode -eq 0) 'non-instructions repo -> exit 0 (no-op, never blocks a consumer)'
}
finally { Remove-TestTempDirectories }

Complete-TestRun
