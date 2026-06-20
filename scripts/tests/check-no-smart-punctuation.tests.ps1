# Standalone pwsh self-test for check-no-smart-punctuation.ps1 (Assert-* helpers, NOT Pester).
# Run: pwsh -File scripts/tests/check-no-smart-punctuation.tests.ps1
# Builds throwaway git repos (the checker enumerates via `git ls-files`) and exercises pass / violation / stale paths.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'test-common.ps1')
$pwshExe = Get-TestPwshExe
$checker = Join-Path $PSScriptRoot '..' | Join-Path -ChildPath 'check-no-smart-punctuation.ps1'
$script:Pass = 0
$script:Fail = 0
$repos = New-Object System.Collections.Generic.List[string]

$em = [char]0x2014   # em-dash, built at runtime so this test file stays ASCII (self-enforcing)
$en = [char]0x2013   # en-dash

function New-Repo {
    param([hashtable] $Files, [string[]] $Allowlist)
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("snp-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $dataDir = Join-Path $dir '.github/pr-quality-gate/data'
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    foreach ($rel in $Files.Keys) {
        $p = Join-Path $dir $rel
        New-Item -ItemType Directory -Path (Split-Path $p -Parent) -Force -ErrorAction SilentlyContinue | Out-Null
        [System.IO.File]::WriteAllText($p, $Files[$rel], (New-Object System.Text.UTF8Encoding($false)))
    }
    [System.IO.File]::WriteAllText((Join-Path $dataDir 'smart-punctuation-allowlist.txt'), (($Allowlist -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
    Push-Location $dir
    try {
        & git init -q 2>$null
        & git add -A 2>$null
        & git -c user.email='t@t' -c user.name='t' -c commit.gpgsign=false commit -qm init 2>$null
    } finally { Pop-Location }
    $repos.Add($dir)
    return $dir
}

function Invoke-Checker {
    param([string] $Dir)
    $out = & $pwshExe @('-NoProfile', '-File', $checker, '-RepoRoot', $Dir) 2>&1 | Out-String
    return [pscustomobject]@{ Output = $out; ExitCode = $LASTEXITCODE }
}

Write-Host "=== check-no-smart-punctuation ===" -ForegroundColor Cyan

# Clean repo, empty allowlist -> PASS
$d = New-Repo -Files @{ 'a.md' = 'clean ascii text'; 'b.ps1' = '# clean' } -Allowlist @('# only a header comment')
$r = Invoke-Checker $d
Assert-True ($r.ExitCode -eq 0) 'clean repo (no dashes) passes'

# Unlisted em-dash -> FAIL, naming the file
$d = New-Repo -Files @{ 'a.md' = "has an $em dash" } -Allowlist @('# header')
$r = Invoke-Checker $d
Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'a\.md') 'unlisted em-dash fails and names the file'

# Allowlisted em-dash -> PASS
$d = New-Repo -Files @{ 'a.md' = "has an $em dash" } -Allowlist @('a.md')
$r = Invoke-Checker $d
Assert-True ($r.ExitCode -eq 0) 'allowlisted em-dash passes'

# Stale allowlist entry (clean file listed) -> FAIL
$d = New-Repo -Files @{ 'a.md' = 'clean' } -Allowlist @('a.md')
$r = Invoke-Checker $d
Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'stale') 'stale allowlist entry (clean file) fails'

# Allowlist entry for a non-existent path -> FAIL
$d = New-Repo -Files @{ 'a.md' = 'clean' } -Allowlist @('does/not/exist.md')
$r = Invoke-Checker $d
Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'stale') 'allowlist entry not matching a tracked file fails'

# En-dash is also caught
$d = New-Repo -Files @{ 'a.md' = "range 1${en}2" } -Allowlist @('# header')
$r = Invoke-Checker $d
Assert-True ($r.ExitCode -eq 1) 'en-dash is also caught'

$smartPunctCases = @(
    [PSCustomObject]@{ Name = 'horizontal-bar';     Char = [char]0x2015 },
    [PSCustomObject]@{ Name = 'left-single-quote';  Char = [char]0x2018 },
    [PSCustomObject]@{ Name = 'right-single-quote'; Char = [char]0x2019 },
    [PSCustomObject]@{ Name = 'left-double-quote';  Char = [char]0x201C },
    [PSCustomObject]@{ Name = 'right-double-quote'; Char = [char]0x201D },
    [PSCustomObject]@{ Name = 'ellipsis';           Char = [char]0x2026 }
)
foreach ($smartPunctCase in $smartPunctCases) {
    $d = New-Repo -Files @{ 'a.md' = "smart $($smartPunctCase.Char) punct" } -Allowlist @('# header')
    $r = Invoke-Checker $d
    Assert-True ($r.ExitCode -eq 1) "$($smartPunctCase.Name) (smart punctuation) is caught"
}

# '#'-comment + blank lines in allowlist are ignored
$d = New-Repo -Files @{ 'a.md' = "has $em" } -Allowlist @('# comment', '', 'a.md')
$r = Invoke-Checker $d
Assert-True ($r.ExitCode -eq 0) 'allowlist comment/blank lines are ignored; real entry honored'

foreach ($p in $repos) { if (Test-Path -LiteralPath $p) { Remove-Item -Recurse -Force -LiteralPath $p -ErrorAction SilentlyContinue } }

Write-Host ""
$summaryColor = if ($script:Fail -eq 0) { 'Green' } else { 'Red' }
Write-Host "check-no-smart-punctuation.tests: $($script:Pass) passed, $($script:Fail) failed" -ForegroundColor $summaryColor
exit ([int]($script:Fail -gt 0))
