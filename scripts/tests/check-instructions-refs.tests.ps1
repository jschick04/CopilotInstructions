#Requires -Version 5.1
# Standalone pwsh self-test for scripts/check-instructions-refs.ps1.
# NOT Pester. Run: pwsh -File scripts/tests/check-instructions-refs.tests.ps1

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-common.ps1')
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$checker = Join-Path $repoRoot 'scripts/check-instructions-refs.ps1'
$script:Pass = 0; $script:Fail = 0

function New-InstrRepo {
    $dir = New-TestGitRepository -Prefix 'instref'
    New-Item -ItemType Directory -Path (Join-Path $dir '.github/instructions') -Force | Out-Null
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
    Write-Host "`n=== a bare-name citation to an EXISTING instruction file resolves ==="
    $d = New-InstrRepo
    Add-RepoFile $d '.github/instructions/csharp.instructions.md' @('# csharp')
    Add-RepoFile $d 'AGENTS.md' @('topic rules live in csharp.instructions.md')
    git -C $d add -A 2>$null; git -C $d commit -q -m init
    $r = Run $d
    Assert-True ($r.ExitCode -eq 0) 'citation to an existing instruction file -> exit 0'

    Write-Host "`n=== a citation to a MISSING instruction file is caught ==="
    $d2 = New-InstrRepo
    Add-RepoFile $d2 '.github/instructions/csharp.instructions.md' @('# csharp')
    Add-RepoFile $d2 'AGENTS.md' @('see ghost-topic.instructions.md for details')
    git -C $d2 add -A 2>$null; git -C $d2 commit -q -m init
    $r = Run $d2
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'ghost-topic') 'citation to a MISSING instruction file -> exit 1 (caught)'

    Write-Host "`n=== fail closed when the instructions folder is absent ==="
    $d3 = New-TestGitRepository -Prefix 'instref-none'
    Add-RepoFile $d3 'README.md' @('# no instructions here')
    git -C $d3 add -A 2>$null; git -C $d3 commit -q -m init
    $r = Run $d3
    Assert-True ($r.ExitCode -eq 2) 'no .github/instructions folder -> exit 2 (invocation failure, fail closed)'

    Write-Host "`n=== the gitignored active-profile.instructions.md selector is exempt even when absent ==="
    $d4 = New-InstrRepo
    Add-RepoFile $d4 '.github/instructions/csharp.instructions.md' @('# csharp')
    Add-RepoFile $d4 'panel-policy.md' @('invoke-panel.ps1 reads active-profile.instructions.md as the floor')
    # active-profile.instructions.md is intentionally NOT created (gitignored, generated per-machine).
    git -C $d4 add -A 2>$null; git -C $d4 commit -q -m init
    $r = Run $d4
    Assert-True ($r.ExitCode -eq 0) 'reference to the absent active-profile selector -> exit 0 (exempt, not flagged)'

    Write-Host "`n=== a full-path .github/instructions/<name> citation resolves by filename ==="
    $d5 = New-InstrRepo
    Add-RepoFile $d5 '.github/instructions/csharp.instructions.md' @('# csharp')
    Add-RepoFile $d5 'README.md' @('see .github/instructions/csharp.instructions.md')
    git -C $d5 add -A 2>$null; git -C $d5 commit -q -m init
    $r = Run $d5
    Assert-True ($r.ExitCode -eq 0) 'full-path citation to an existing instruction file -> exit 0'

    Write-Host "`n=== a hyphenated/compound instruction name resolves (hyphen is a literal in the class) ==="
    $d6 = New-InstrRepo
    Add-RepoFile $d6 '.github/instructions/coding-standards-code.instructions.md' @('# csc')
    Add-RepoFile $d6 'AGENTS.md' @('see coding-standards-code.instructions.md for code edits')
    git -C $d6 add -A 2>$null; git -C $d6 commit -q -m init
    $r = Run $d6
    Assert-True ($r.ExitCode -eq 0) 'citation to an existing hyphenated instruction file -> exit 0'

    Write-Host "`n=== a fixture citation inside scripts/tests/* is NOT scanned (synthetic fixtures excluded) ==="
    $d7 = New-InstrRepo
    Add-RepoFile $d7 '.github/instructions/csharp.instructions.md' @('# csharp')
    Add-RepoFile $d7 'scripts/tests/fake.tests.ps1' @('Set-Content fake-ghost.instructions.md ""')
    git -C $d7 add -A 2>$null; git -C $d7 commit -q -m init
    $r = Run $d7
    Assert-True ($r.ExitCode -eq 0) 'dangling fixture ref under scripts/tests/* -> exit 0 (test files excluded)'

    Write-Host "`n=== a mixed line flags ONLY the dangling reference, not the resolving one ==="
    $d8 = New-InstrRepo
    Add-RepoFile $d8 '.github/instructions/csharp.instructions.md' @('# csharp')
    Add-RepoFile $d8 'AGENTS.md' @('refs: csharp.instructions.md and ghost-topic.instructions.md here')
    git -C $d8 add -A 2>$null; git -C $d8 commit -q -m init
    $r = Run $d8
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match "ghost-topic\.instructions\.md' does not resolve" -and $r.Output -notmatch "csharp\.instructions\.md' does not resolve") 'mixed line -> exit 1, flags only the dangling ghost ref (csharp resolves)'

    Write-Host "`n=== a citation inside a CSV data ledger is NOT scanned (immutable finding-time data) ==="
    $d9 = New-InstrRepo
    Add-RepoFile $d9 '.github/instructions/csharp.instructions.md' @('# csharp')
    Add-RepoFile $d9 '.github/pr-quality-gate/data/panel-misses.csv' @('id,brief,x', '1,renamed-old.instructions.md,y')
    git -C $d9 add -A 2>$null; git -C $d9 commit -q -m init
    $r = Run $d9
    Assert-True ($r.ExitCode -eq 0) 'dangling ref inside a .csv ledger -> exit 0 (CSV data excluded)'

    Write-Host "`n=== a file NAMED *.instructions.md outside the folder is not flagged via its path prefix ==="
    $d10 = New-InstrRepo
    Add-RepoFile $d10 '.github/instructions/csharp.instructions.md' @('# csharp')
    # docs/notes.instructions.md has a NON-resolving basename but only a VALID content ref; the grep -n path
    # prefix must not be parsed as a citation (regression for the path-prefix false positive).
    Add-RepoFile $d10 'docs/notes.instructions.md' @('see csharp.instructions.md for the rules')
    git -C $d10 add -A 2>$null; git -C $d10 commit -q -m init
    $r = Run $d10
    Assert-True ($r.ExitCode -eq 0) 'file named *.instructions.md outside the folder, valid content ref -> exit 0 (path prefix not scanned)'

    Write-Host "`n=== a wrong-case citation is caught (case-sensitive resolution for Linux CI) ==="
    $d11 = New-InstrRepo
    Add-RepoFile $d11 '.github/instructions/csharp.instructions.md' @('# csharp')
    Add-RepoFile $d11 'AGENTS.md' @('see CSharp.instructions.md for C#')
    git -C $d11 add -A 2>$null; git -C $d11 commit -q -m init
    $r = Run $d11
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'CSharp\.instructions\.md') 'wrong-case CSharp.instructions.md -> exit 1 (case-sensitive, would false-pass on Linux otherwise)'

    Write-Host "`n=== the checker's own source is excluded (example tokens in it are not citations) ==="
    $d12 = New-InstrRepo
    Add-RepoFile $d12 '.github/instructions/csharp.instructions.md' @('# csharp')
    Add-RepoFile $d12 'scripts/check-instructions-refs.ps1' @('# example like ghost-self.instructions.md is not a ref')
    git -C $d12 add -A 2>$null; git -C $d12 commit -q -m init
    $r = Run $d12
    Assert-True ($r.ExitCode -eq 0) 'dangling-looking token in the checker''s own source -> exit 0 (self-excluded)'

    Write-Host "`n=== a line with BOTH the exempt selector and a dangling ref flags only the dangling one ==="
    $d13 = New-InstrRepo
    Add-RepoFile $d13 '.github/instructions/csharp.instructions.md' @('# csharp')
    Add-RepoFile $d13 'panel-policy.md' @('floor reads active-profile.instructions.md; see ghost-x.instructions.md')
    git -C $d13 add -A 2>$null; git -C $d13 commit -q -m init
    $r = Run $d13
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match "ghost-x\.instructions\.md' does not resolve" -and $r.Output -notmatch "active-profile\.instructions\.md' does not resolve") 'exempt + dangling on one line -> exit 1, flags only the dangling ref (active-profile exempt)'
}
finally { Remove-TestTempDirectories }

Complete-TestRun
