#Requires -Version 5.1
# Standalone pwsh self-test for scripts/check-signoff.ps1.
# Run: pwsh -File scripts/tests/check-signoff.tests.ps1

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-common.ps1')
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
    Stage $d2 'a.txt' 'one'; git -C $d2 commit -q -m c
    $ct = (git -C $d2 rev-parse 'HEAD^{tree}').Trim()
    WriteReceipt $d2 @("force_push_approved: turn-9 tree:$ct")
    $r = Run $d2 @('-Mode', 'force-push', '-Tree', $ct)
    Assert-True ($r.ExitCode -eq 0) 'force-push + marker matching the pushed tip tree -> exit 0'

    WriteReceipt $d2 @("amend_approved: turn-9 tree:$ct")
    $r = Run $d2 @('-Mode', 'force-push', '-Tree', $ct)
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'no .force_push_approved') 'force-push + only an amend marker -> exit 1'

    WriteReceipt $d2 @("force_push_approved: turn-9 tree:$ct")
    $r = Run $d2 @('-Mode', 'force-push', '-Tree', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')
    Assert-True ($r.ExitCode -eq 1) 'force-push + tree mismatch -> exit 1'

    # a short/prefix tree binding must NOT authorize (full 40-char SHA required)
    WriteReceipt $d2 @("force_push_approved: turn-9 tree:$($ct.Substring(0,12))")
    $r = Run $d2 @('-Mode', 'force-push', '-Tree', $ct)
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'full 40-char') 'force-push + 12-char tree prefix -> exit 1 (no prefix match)'

    WriteReceipt $d2 @("force_push_approved: turn-9 (no tree binding)")
    $r = Run $d2 @('-Mode', 'force-push', '-Tree', $ct)
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match "missing its .tree") 'marker missing tree binding -> exit 1'

    Write-Host "`n=== identity gate ==="
    $f = New-IdRepo -Foreign
    Stage $f 'a.txt' 'one'
    $r = Run $f @('-Mode', 'amend')   # no receipt, but foreign repo -> no-op
    Assert-True ($r.ExitCode -eq 0) 'non-instructions repo -> exit 0 (no-op, never blocks a consumer)'
}
finally { Remove-TestTempDirectories }

Complete-TestRun
