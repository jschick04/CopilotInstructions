#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Standalone pwsh self-test (Assert-* helpers, not Pester) for check-no-automation-identity.ps1.
# Run: pwsh -File scripts/tests/check-no-automation-identity.tests.ps1

$checkerPath = (Resolve-Path (Join-Path $PSScriptRoot '../check-no-automation-identity.ps1')).Path
. (Join-Path $PSScriptRoot 'test-common.ps1')
$pwshExe = Get-TestPwshExe

$script:Fail = 0
$script:Pass = 0

$repos = New-Object System.Collections.Generic.List[string]
function Track { param([string] $Repo) $repos.Add($Repo); return $Repo }

function New-IdRepo {
    $repo = Join-Path ([System.IO.Path]::GetTempPath()) ("cnai-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $repo | Out-Null
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    Push-Location $repo
    try {
        git init -q
        git config user.email 'base@t'; git config user.name 'base'
        git config commit.gpgsign false; git config core.autocrlf false
        New-Item -ItemType Directory -Path (Join-Path $repo 'scripts') -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $repo 'scripts/check-no-automation-identity.ps1'), "# anchor stub`n", $utf8)
        [System.IO.File]::WriteAllText((Join-Path $repo 'base.txt'), "base`n", $utf8)
        git add -A | Out-Null; git commit -qm 'base' | Out-Null
        git branch -m main | Out-Null; git checkout -q -b feature | Out-Null
    } finally { Pop-Location }
    return $repo
}

function Add-IdCommit {
    param([string] $Repo, [string] $AuthorName, [string] $AuthorEmail, [string] $CommitterName, [string] $CommitterEmail, [string] $Msg = 'change')
    if (-not $PSBoundParameters.ContainsKey('CommitterName')) { $CommitterName = $AuthorName }
    if (-not $PSBoundParameters.ContainsKey('CommitterEmail')) { $CommitterEmail = $AuthorEmail }
    Push-Location $Repo
    try {
        $env:GIT_AUTHOR_NAME = $AuthorName; $env:GIT_AUTHOR_EMAIL = $AuthorEmail
        $env:GIT_COMMITTER_NAME = $CommitterName; $env:GIT_COMMITTER_EMAIL = $CommitterEmail
        git commit -q --allow-empty -m $Msg | Out-Null
    } finally {
        Remove-Item Env:\GIT_AUTHOR_NAME, Env:\GIT_AUTHOR_EMAIL, Env:\GIT_COMMITTER_NAME, Env:\GIT_COMMITTER_EMAIL -ErrorAction SilentlyContinue
        Pop-Location
    }
}

# Low-level commit with a possibly-empty/whitespace identity via commit-tree (git commit rejects empty idents).
function Add-RawCommit {
    param([string] $Repo, [string] $AuthorName, [string] $AuthorEmail, [string] $Msg = 'raw')
    Push-Location $Repo
    try {
        $tree = (git rev-parse 'HEAD^{tree}').Trim()
        $parent = (git rev-parse HEAD).Trim()
        $env:GIT_AUTHOR_NAME = $AuthorName; $env:GIT_AUTHOR_EMAIL = $AuthorEmail; $env:GIT_AUTHOR_DATE = '2024-01-01T00:00:00'
        $env:GIT_COMMITTER_NAME = $AuthorName; $env:GIT_COMMITTER_EMAIL = $AuthorEmail; $env:GIT_COMMITTER_DATE = '2024-01-01T00:00:00'
        $sha = (git commit-tree $tree -p $parent -m $Msg).Trim()
        git update-ref refs/heads/feature $sha | Out-Null
    } finally {
        Remove-Item Env:\GIT_AUTHOR_NAME, Env:\GIT_AUTHOR_EMAIL, Env:\GIT_AUTHOR_DATE, Env:\GIT_COMMITTER_NAME, Env:\GIT_COMMITTER_EMAIL, Env:\GIT_COMMITTER_DATE -ErrorAction SilentlyContinue
        Pop-Location
    }
}

function Invoke-Range {
    param([string] $Repo, [string] $Base = 'main', [string] $Head = 'feature', [string[]] $Extra)
    $argList = @('-NoProfile', '-File', $checkerPath, '-RepoRoot', $Repo, '-BaseRef', $Base, '-HeadRef', $Head)
    if ($Extra) { $argList += $Extra }
    $out = & $pwshExe @argList 2>&1 | Out-String
    return [pscustomobject]@{ Output = $out; ExitCode = $LASTEXITCODE }
}

function Invoke-PreCommit {
    param([string] $Repo, [hashtable] $Env)
    $argList = @('-NoProfile', '-File', $checkerPath, '-RepoRoot', $Repo)
    $saved = @{}
    if ($Env) { foreach ($k in $Env.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); Set-Item "Env:\$k" $Env[$k] } }
    try { $out = & $pwshExe @argList 2>&1 | Out-String }
    finally { if ($Env) { foreach ($k in $Env.Keys) { if ($null -eq $saved[$k]) { Remove-Item "Env:\$k" -ErrorAction SilentlyContinue } else { Set-Item "Env:\$k" $saved[$k] } } } }
    return [pscustomobject]@{ Output = $out; ExitCode = $LASTEXITCODE }
}

Write-Host ""
Write-Host "=== check-no-automation-identity: disallowed-automation predicate (range mode) ===" -ForegroundColor Cyan

$repo = Track (New-IdRepo); Add-IdCommit $repo 'copilot[bot]' '198982+Copilot@users.noreply.github.com'
$r = Invoke-Range $repo
Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'bot-suffix') "copilot[bot] author fails (bot-suffix)"

$repo = Track (New-IdRepo); Add-IdCommit $repo 'github-actions[bot]' '41898282+github-actions[bot]@users.noreply.github.com'
$r = Invoke-Range $repo
Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'bot-suffix') "github-actions[bot] author fails (bot-suffix)"

$repo = Track (New-IdRepo); Add-IdCommit $repo 'dependabot[bot]' 'dependabot[bot]@users.noreply.github.com'
$r = Invoke-Range $repo
Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'bot-suffix') "generic dependabot[bot] fails (bot-suffix)"

$repo = Track (New-IdRepo); Add-IdCommit $repo 'Copilot' '223556219+Copilot@users.noreply.github.com'
$r = Invoke-Range $repo
Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'copilot-noreply') "the 223556219+Copilot noreply email fails (copilot-noreply)"
Assert-True ($r.Output -match 'copilot\b') "bare Copilot name also fails (copilot rule)"

$repo = Track (New-IdRepo); Add-IdCommit $repo 'github-actions' 'gha@example.com'
$r = Invoke-Range $repo
Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'github-actions') "bare github-actions name fails (github-actions)"

$repo = Track (New-IdRepo); Add-IdCommit $repo 'Jane Human' 'jane@example.com' -CommitterName 'copilot[bot]' -CommitterEmail 'x@y'
$r = Invoke-Range $repo
Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'committer .*\[bot\]') "human author + bot committer fails (committer checked)"

# empty email (git permits `Name <>`; an empty name is rejected by git itself, so empty-name stays a defensive guard)
$repo = Track (New-IdRepo); Add-RawCommit $repo 'Somebody' ''
$r = Invoke-Range $repo
Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'empty-email') "empty author email fails (empty-email)"

Write-Host ""
Write-Host "=== ALLOWED forms (must NOT match the modeled predicate) ===" -ForegroundColor Cyan

$repo = Track (New-IdRepo); Add-IdCommit $repo 'jschick04' 'jschick04@gmail.com'
$r = Invoke-Range $repo
Assert-True ($r.ExitCode -eq 0) "a real human (jschick04) passes"

$repo = Track (New-IdRepo); Add-IdCommit $repo 'Jane Copilot' 'jane.copilot@example.com'
$r = Invoke-Range $repo
Assert-True ($r.ExitCode -eq 0) "a human named 'Jane Copilot' passes (bare-name match is EXACT)"

$repo = Track (New-IdRepo); Add-IdCommit $repo 'GitHub' 'noreply@github.com'
$r = Invoke-Range $repo
Assert-True ($r.ExitCode -eq 0) "web-flow 'GitHub <noreply@github.com>' is NOT matched (intentional)"

$repo = Track (New-IdRepo); Add-IdCommit $repo 'Jane Dev' '12345+jane@users.noreply.github.com'
$r = Invoke-Range $repo
Assert-True ($r.ExitCode -eq 0) "a normal NNN+user noreply email passes (not the copilot noreply)"

$repo = Track (New-IdRepo); Add-IdCommit $repo 'Abbott Robotics' 'abbott@example.com'
$r = Invoke-Range $repo
Assert-True ($r.ExitCode -eq 0) "names containing 'bot'/'abbott' without literal [bot] pass"

$repo = Track (New-IdRepo); Add-IdCommit $repo 'Project[bot]Tool' 'dev@example.com'
$r = Invoke-Range $repo
Assert-True ($r.ExitCode -eq 0) "a mid-string [bot] in the name is NOT matched (suffix-anchored, not substring)"

$repo = Track (New-IdRepo); Add-IdCommit $repo 'Dev' 'foo[bot]bar@example.com'
$r = Invoke-Range $repo
Assert-True ($r.ExitCode -eq 0) "a mid-string [bot] in the email local-part is NOT matched (must be [bot]@)"

Write-Host ""
Write-Host "=== range-mode mechanics ===" -ForegroundColor Cyan

$repo = Track (New-IdRepo)
Add-IdCommit $repo 'Jane Dev' 'jane@example.com' -Msg 'feature work'
Push-Location $repo
try {
    git checkout -q -b side main | Out-Null
    git commit -q --allow-empty -m 'side work' | Out-Null
    git checkout -q feature | Out-Null
    $env:GIT_AUTHOR_NAME = 'copilot[bot]'; $env:GIT_AUTHOR_EMAIL = 'x@y'
    $env:GIT_COMMITTER_NAME = 'copilot[bot]'; $env:GIT_COMMITTER_EMAIL = 'x@y'
    git merge -q --no-ff --no-edit side | Out-Null
    Remove-Item Env:\GIT_AUTHOR_NAME, Env:\GIT_AUTHOR_EMAIL, Env:\GIT_COMMITTER_NAME, Env:\GIT_COMMITTER_EMAIL -ErrorAction SilentlyContinue
} finally { Pop-Location }
$r = Invoke-Range $repo
Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'bot-suffix') "a bot-authored MERGE commit is caught (range scans merges; no --no-merges)"

$repo = Track (New-IdRepo)
Add-IdCommit $repo 'Jane Dev' 'jane@example.com' -Msg 'good 1'
Add-IdCommit $repo 'copilot[bot]' 'x@y' -Msg 'bad'
Add-IdCommit $repo 'Jane Dev' 'jane@example.com' -Msg 'good 2'
$r = Invoke-Range $repo
Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'bot-suffix') "multi-commit range flags the one bot commit"

$repo = Track (New-IdRepo); Add-IdCommit $repo 'Jane Dev' 'jane@example.com'
$r = Invoke-Range $repo -Base 'no-such-ref'
Assert-True ($r.ExitCode -eq 2) "bogus base ref fails closed (exit 2)"

$repo = Track (New-IdRepo); Add-IdCommit $repo 'Jane Dev' 'jane@example.com'
$r = Invoke-Range $repo -Base 'feature' -Head 'feature'
Assert-True ($r.ExitCode -eq 0) "empty range passes in local mode"
$r = Invoke-Range $repo -Base 'feature' -Head 'feature' -Extra @('-CiMode')
Assert-True ($r.ExitCode -eq 2) "empty range fails closed under -CiMode"

$repo = Track (New-IdRepo); Add-IdCommit $repo 'copilot[bot]' 'x@y'
$r = Invoke-Range $repo -Extra @('-Json')
Assert-True ($r.Output -match '"status":\s*"fail"' -and $r.Output -match '"checker":\s*"check-no-automation-identity"') "-Json emits a structured fail record"

Write-Host ""
Write-Host "=== pre-commit mode (git var reads the exported GIT_AUTHOR_* env) ===" -ForegroundColor Cyan

$repo = Track (New-IdRepo)
$r = Invoke-PreCommit $repo @{ GIT_AUTHOR_NAME = 'copilot[bot]'; GIT_AUTHOR_EMAIL = '198982+Copilot@users.noreply.github.com' }
Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'bot-suffix') "pre-commit mode catches a planted bot GIT_AUTHOR_* (git var reads env)"

$repo = Track (New-IdRepo)
$r = Invoke-PreCommit $repo @{ GIT_AUTHOR_NAME = 'Jane Dev'; GIT_AUTHOR_EMAIL = 'jane@example.com'; GIT_COMMITTER_NAME = 'Jane Dev'; GIT_COMMITTER_EMAIL = 'jane@example.com' }
Assert-True ($r.ExitCode -eq 0) "pre-commit mode passes a human GIT_AUTHOR_*"

foreach ($p in $repos) { if (Test-Path -LiteralPath $p) { Remove-Item -Recurse -Force -LiteralPath $p -ErrorAction SilentlyContinue } }

Write-Host ""
$summaryColor = if ($script:Fail -eq 0) { 'Green' } else { 'Red' }
Write-Host "check-no-automation-identity.tests: $($script:Pass) passed, $($script:Fail) failed" -ForegroundColor $summaryColor
exit ([int]($script:Fail -gt 0))
