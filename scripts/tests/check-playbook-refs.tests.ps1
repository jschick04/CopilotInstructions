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
}
finally { Remove-TestTempDirectories }

Complete-TestRun
