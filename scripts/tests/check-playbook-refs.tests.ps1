#Requires -Version 5.1
# Standalone pwsh self-test for scripts/check-playbook-refs.ps1.
# NOT Pester. Run: pwsh -File scripts/tests/check-playbook-refs.tests.ps1

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-common.ps1')
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$checker = Join-Path $repoRoot 'scripts/check-playbook-refs.ps1'
$script:Pass = 0; $script:Fail = 0

function New-PlaybookRepo {
    $dir = New-TestGitRepository -Prefix 'pbref'
    New-Item -ItemType Directory -Path (Join-Path $dir '.github/playbooks') -Force | Out-Null
    return $dir
}
function Add-RepoFile {
    param([string] $Dir, [string] $Rel, [string[]] $Lines)
    $full = Join-Path $Dir $Rel
    New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
    Set-Content -LiteralPath $full -Value $Lines -Encoding utf8
}
function Run {
    param([string] $Dir)
    $out = & pwsh -NoProfile -File $checker -RepoRoot $Dir 2>&1
    return [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Output = ($out | Out-String) }
}

try {
    Write-Host "`n=== a citation to an EXISTING hyphenated playbook resolves (regex range-bug regression) ==="
    $d = New-PlaybookRepo
    Add-RepoFile $d '.github/playbooks/review-workflow-gates-sweeps.md' @('# a hyphenated playbook name')
    Add-RepoFile $d '.github/playbooks/intake.md' @('see .github/playbooks/review-workflow-gates-sweeps.md for details')
    git -C $d add -A 2>$null; git -C $d commit -q -m init
    $r = Run $d
    Assert-True ($r.ExitCode -eq 0) 'citation to an existing hyphenated playbook -> exit 0 (now validated, not skipped)'

    Write-Host "`n=== a BROKEN hyphenated citation is caught (was silently missed by the .-/ range bug) ==="
    $d2 = New-PlaybookRepo
    Add-RepoFile $d2 '.github/playbooks/intake.md' @('see .github/playbooks/does-not-exist-hyphenated.md')
    git -C $d2 add -A 2>$null; git -C $d2 commit -q -m init
    $r = Run $d2
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'does-not-exist-hyphenated') 'citation to a MISSING hyphenated playbook -> exit 1 (caught)'

    Write-Host "`n=== fail closed when the playbook folder is absent ==="
    $d3 = New-TestGitRepository -Prefix 'pbref-none'
    Add-RepoFile $d3 'README.md' @('# no playbooks here')
    git -C $d3 add -A 2>$null; git -C $d3 commit -q -m init
    $r = Run $d3
    Assert-True ($r.ExitCode -eq 2) 'no .github/playbooks folder -> exit 2 (invocation failure, fail closed)'

    Write-Host "`n=== a wrong-prefix 'playbooks/<leaf>.md' ref (missing .github/) is caught when canonical resolves ==="
    $d4 = New-PlaybookRepo
    Add-RepoFile $d4 '.github/playbooks/intake.md' @('# a real playbook')
    Add-RepoFile $d4 'README.md' @('see playbooks/intake.md for details')
    git -C $d4 add -A 2>$null; git -C $d4 commit -q -m init
    $r = Run $d4
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match [regex]::Escape('.github/playbooks/intake.md')) 'wrong-prefix playbooks/intake.md -> exit 1, names the canonical path'

    Write-Host "`n=== a bare-leaf '<leaf>.md' ref (the established convention) is NOT flagged ==="
    $d5 = New-PlaybookRepo
    Add-RepoFile $d5 '.github/playbooks/intake.md' @('# a real playbook')
    Add-RepoFile $d5 'README.md' @('see intake.md for details')
    git -C $d5 add -A 2>$null; git -C $d5 commit -q -m init
    $r = Run $d5
    Assert-True ($r.ExitCode -eq 0) 'bare-leaf intake.md (the convention) -> exit 0 (not flagged)'

    Write-Host "`n=== a wrong-prefix ref whose leaf does NOT resolve is NOT flagged (bounded contract) ==="
    $d6 = New-PlaybookRepo
    Add-RepoFile $d6 '.github/playbooks/intake.md' @('# a real playbook')
    Add-RepoFile $d6 'README.md' @('see playbooks/ghost.md for details')
    git -C $d6 add -A 2>$null; git -C $d6 commit -q -m init
    $r = Run $d6
    Assert-True ($r.ExitCode -eq 0) 'wrong-prefix playbooks/ghost.md (canonical absent) -> exit 0 (only real-playbook wrong-prefix flagged)'

    Write-Host "`n=== a mixed line with BOTH a correct full ref and a truncated ref flags only the truncated ==="
    $d7 = New-PlaybookRepo
    Add-RepoFile $d7 '.github/playbooks/alpha.md' @('# alpha')
    Add-RepoFile $d7 '.github/playbooks/bravo.md' @('# bravo')
    Add-RepoFile $d7 'README.md' @('refs: .github/playbooks/alpha.md and playbooks/bravo.md here')
    git -C $d7 add -A 2>$null; git -C $d7 commit -q -m init
    $r = Run $d7
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'wrong-prefix' -and $r.Output -match 'bravo' -and $r.Output -notmatch 'does not resolve') 'mixed line -> exit 1, flags only truncated playbooks/bravo.md (alpha full-ref resolves)'

    Write-Host "`n=== a truncated ref at line start is caught (boundary start-anchor) ==="
    $d8 = New-PlaybookRepo
    Add-RepoFile $d8 '.github/playbooks/intake.md' @('# a real playbook')
    Add-RepoFile $d8 'note.md' @('playbooks/intake.md is the wrong way to cite it')
    git -C $d8 add -A 2>$null; git -C $d8 commit -q -m init
    $r = Run $d8
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'wrong-prefix') 'line-start playbooks/intake.md -> exit 1 (caught)'

    Write-Host "`n=== a backtick-wrapped wrong-prefix ref is caught (extraction must strip the boundary char) ==="
    $d9 = New-PlaybookRepo
    Add-RepoFile $d9 '.github/playbooks/intake.md' @('# a real playbook')
    Add-RepoFile $d9 'note.md' @('use `playbooks/intake.md` is wrong')
    git -C $d9 add -A 2>$null; git -C $d9 commit -q -m init
    $r = Run $d9
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match [regex]::Escape('.github/playbooks/intake.md')) 'backtick-wrapped playbooks/intake.md -> exit 1 (clean extraction, flagged)'

    Write-Host "`n=== a wrong-prefix ref to a NESTED playbook resolves and is caught (recursive set) ==="
    $d10 = New-PlaybookRepo
    Add-RepoFile $d10 '.github/playbooks/sub/deep.md' @('# nested playbook')
    Add-RepoFile $d10 'README.md' @('see playbooks/sub/deep.md for details')
    git -C $d10 add -A 2>$null; git -C $d10 commit -q -m init
    $r = Run $d10
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match [regex]::Escape('.github/playbooks/sub/deep.md')) 'nested wrong-prefix playbooks/sub/deep.md -> exit 1 (caught at depth)'

    Write-Host "`n=== a wrong-CASE citation is caught (Ordinal set; would false-resolve on a case-insensitive hashtable) ==="
    $d11 = New-PlaybookRepo
    Add-RepoFile $d11 '.github/playbooks/pre-commit.md' @('# the real playbook')
    Add-RepoFile $d11 'note.md' @('see .github/playbooks/Pre-Commit.md for the gate')
    git -C $d11 add -A 2>$null; git -C $d11 commit -q -m init
    $r = Run $d11
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match [regex]::Escape('Pre-Commit.md')) 'wrong-case Pre-Commit.md -> exit 1 (case-sensitive, no Linux fail-open)'

    Write-Host "`n=== a wrong-prefix AND wrong-case citation is caught (case-insensitive wrong-prefix scan) ==="
    $d12 = New-PlaybookRepo
    Add-RepoFile $d12 '.github/playbooks/pre-commit.md' @('# the real playbook')
    Add-RepoFile $d12 'README.md' @('see playbooks/Pre-Commit.md for the gate')
    git -C $d12 add -A 2>$null; git -C $d12 commit -q -m init
    $r = Run $d12
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match [regex]::Escape('Pre-Commit.md')) 'wrong-prefix + wrong-case playbooks/Pre-Commit.md -> exit 1 (does not slip through)'
}
finally { Remove-TestTempDirectories }

Complete-TestRun
