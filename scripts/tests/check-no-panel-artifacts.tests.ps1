#Requires -Version 5.1
# Standalone pwsh self-test for scripts/check-no-panel-artifacts.ps1.
# NOT Pester. Run: pwsh -File scripts/tests/check-no-panel-artifacts.tests.ps1
#
# This file embeds artifact tokens as fixtures; that is why the checker excludes its own test file
# from the real scan (same self-reference pattern as check-playbook-refs.tests.ps1).

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-common.ps1')
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$checker = Join-Path $repoRoot 'scripts/check-no-panel-artifacts.ps1'
$script:Pass = 0; $script:Fail = 0

function New-CodeRepo {
    $dir = New-TestGitRepository -Prefix 'npa'
    New-Item -ItemType Directory -Path (Join-Path $dir 'scripts') -Force | Out-Null
    return $dir
}
function Add-Script {
    param([string] $Dir, [string] $Rel, [string[]] $Lines)
    $full = Join-Path $Dir $Rel
    New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
    Set-Content -LiteralPath $full -Value $Lines -Encoding utf8
    git -C $Dir add -A 2>$null; git -C $Dir commit -q -m fixture | Out-Null
}
function Run {
    param([string] $Dir)
    $out = & pwsh -NoProfile -File $checker -RepoRoot $Dir 2>&1
    return [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Output = ($out | Out-String) }
}

try {
    Write-Host "`n=== a clean code file passes ==="
    $clean = New-CodeRepo
    Add-Script $clean 'scripts/foo.ps1' @('# a normal rationale comment', '$x = 1', 'Write-Output $x')
    Assert-True ((Run $clean).ExitCode -eq 0) 'a code file with no review-process artifacts -> exit 0'

    Write-Host "`n=== each artifact-token class is caught ==="
    $tokens = @('# fix (gemini gap #1)', '# gpt55 re-panel note', '# regression (R3-BLOCKING-2)',
                '# (R4-MAJOR-1 fix)', '# (R6 Slot D fix)', '# Round 5 hardening', '# PR #9 review',
                '# the bot-flagged class', '# duck-logic review',
                '# sed exclusion (forcing re-review #1)', '# forcing#5 hardening')
    foreach ($tok in $tokens) {
        $d = New-CodeRepo
        Add-Script $d 'scripts/bar.ps1' @('$y = 1', $tok)
        Assert-True ((Run $d).ExitCode -eq 1) "artifact line '$tok' -> exit 1 (caught)"
    }

    Write-Host "`n=== generic domain words are NOT flagged (false-positive guard) ==="
    $generic = New-CodeRepo
    Add-Script $generic 'scripts/baz.ps1' @('# the panel reviewed this; a finding from the review; a regression test', '$z = 1')
    Assert-True ((Run $generic).ExitCode -eq 0) 'generic words (panel/review/finding/regression) -> exit 0 (not a false positive)'

    Write-Host "`n=== word-boundary false positives are NOT flagged ==="
    $wb = New-CodeRepo
    Add-Script $wb 'scripts/wb.ps1' @('# a workaround 10 for the bug', '# background 2 process', '# a timeslot A here', '# the value ducked under', '$w = 1')
    Assert-True ((Run $wb).ExitCode -eq 0) 'common words (workaround/background/timeslot/ducked) -> exit 0 (\b guard)'

    Write-Host "`n=== invoke-panel.ps1 may name models but NOT carry finding labels ==="
    $ipOk = New-CodeRepo
    Add-Script $ipOk '.github/pr-quality-gate/invoke-panel.ps1' @('# slate: claude_family gpt_family gemini_family rubber_duck; fix-then-re-panel', '$p = 1')
    Assert-True ((Run $ipOk).ExitCode -eq 0) 'invoke-panel naming models -> exit 0 (allowed)'
    $ipBad = New-CodeRepo
    Add-Script $ipBad '.github/pr-quality-gate/invoke-panel.ps1' @('# claude_family slate (R4-MAJOR-2 fix)', '$p = 1')
    Assert-True ((Run $ipBad).ExitCode -eq 1) 'invoke-panel carrying a finding label (R4-MAJOR-2) -> exit 1 (still flagged)'
}
finally { Remove-TestTempDirectories }

Complete-TestRun
