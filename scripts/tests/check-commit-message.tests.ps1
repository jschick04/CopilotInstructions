#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Standalone pwsh self-test (Assert-* helpers, not Pester) for check-commit-message.ps1.
# Run: pwsh -File scripts/tests/check-commit-message.tests.ps1

$checkerPath = (Resolve-Path (Join-Path $PSScriptRoot '../check-commit-message.ps1')).Path
$pwshExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }

$script:failures = 0
$script:passes = 0
function Assert-True {
    param([Parameter(Mandatory)] [bool] $Condition, [Parameter(Mandatory)] [string] $Description)
    if ($Condition) { $script:passes++; Write-Host "  [PASS] $Description" }
    else { $script:failures++; Write-Host "  [FAIL] $Description" -ForegroundColor Red }
}

# Temp repo: a `main` base + one --allow-empty feature commit per message, written --cleanup=verbatim so CRLF /
# trailing-period / whitespace survive for the checker. $Merge adds a no-ff merge commit (to test --no-merges).
function New-MsgRepo {
    param([string[]] $Messages, [switch] $Merge)
    $repo = Join-Path ([System.IO.Path]::GetTempPath()) ("ccm-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $repo | Out-Null
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    Push-Location $repo
    try {
        git init -q
        git config user.email 't@t'; git config user.name 't'
        git config commit.gpgsign false; git config core.autocrlf false
        New-Item -ItemType Directory -Path (Join-Path $repo 'scripts') -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $repo 'scripts/check-commit-message.ps1'), "# anchor stub`n", $utf8)
        [System.IO.File]::WriteAllText((Join-Path $repo 'base.txt'), "base`n", $utf8)
        git add -A | Out-Null; git commit -qm 'base' | Out-Null
        git branch -m main | Out-Null; git checkout -q -b feature
        $i = 0
        foreach ($msg in $Messages) {
            $msgPath = Join-Path $repo ".msg$i"
            [System.IO.File]::WriteAllText($msgPath, $msg, $utf8)
            git commit -q --allow-empty --allow-empty-message --cleanup=verbatim -F $msgPath | Out-Null
            Remove-Item -Force $msgPath
            $i++
        }
        if ($Merge) {
            git checkout -q -b side main
            [System.IO.File]::WriteAllText((Join-Path $repo 'side.txt'), "side`n", $utf8)
            git add -A | Out-Null; git commit -qm 'side change' | Out-Null
            git checkout -q feature
            # Merge commit gets a git-generated multi-line message ("Merge branch 'side' ...") - must be SKIPPED.
            git merge -q --no-ff --no-edit side | Out-Null
        }
    } finally { Pop-Location }
    return $repo
}

function Invoke-Checker {
    param([string] $Repo, [string] $Base = 'main', [string] $Head = 'feature', [string[]] $Extra)
    $argList = @('-NoProfile', '-File', $checkerPath, '-RepoRoot', $Repo, '-BaseRef', $Base, '-HeadRef', $Head)
    if ($Extra) { $argList += $Extra }
    $out = & $pwshExe @argList 2>&1 | Out-String
    return [pscustomobject]@{ Output = $out; ExitCode = $LASTEXITCODE }
}

$repos = New-Object System.Collections.Generic.List[string]
function Track { param([string] $Repo) $repos.Add($Repo); return $Repo }

Write-Host ""
Write-Host "=== check-commit-message rule coverage ===" -ForegroundColor Cyan

$r = Invoke-Checker (Track (New-MsgRepo @('Add diff-consistency checker and checker-scoped catalog scope_mode')))
Assert-True ($r.ExitCode -eq 0) "clean single-line subject passes (exit 0)"
Assert-True ($r.Output -match 'PASS') "clean subject reports PASS"

$r = Invoke-Checker (Track (New-MsgRepo @('Fix parser: handle empty input')))
Assert-True ($r.ExitCode -eq 0) "internal-colon subject 'Fix parser: ...' passes (capital Fix, not a CC prefix)"

$s72 = 'x' * 72
$s73 = 'x' * 73
$r = Invoke-Checker (Track (New-MsgRepo @($s72)))
Assert-True ($r.ExitCode -eq 0) "subject of exactly 72 chars passes"
$r = Invoke-Checker (Track (New-MsgRepo @($s73)))
Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'subject-too-long') "subject of 73 chars fails (subject-too-long)"

$r = Invoke-Checker (Track (New-MsgRepo @('')))
Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'empty-subject') "empty message fails (empty-subject)"
$r = Invoke-Checker (Track (New-MsgRepo @("   `n")))
Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'empty-subject') "whitespace-only subject fails (empty-subject)"

$r = Invoke-Checker (Track (New-MsgRepo @("Add a thing`n`nCo-authored-by: Copilot <x@y>")))
Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'no-body') "Co-authored-by trailer fails (no-body)"
Assert-True ($r.Output -match "Co-authored-by' trailer") "Co-authored-by trailer gets a named diagnostic"
$r = Invoke-Checker (Track (New-MsgRepo @("Add a thing`n`nThis is an explanatory paragraph.")))
Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'no-body') "plain body paragraph fails (no-body)"

$r = Invoke-Checker (Track (New-MsgRepo @("Add a thing`n")))
Assert-True ($r.ExitCode -eq 0) "single-line subject with a trailing newline passes"

$r = Invoke-Checker (Track (New-MsgRepo @("Add a thing`n`n")))
Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'no-body') "subject + a blank second line fails (single line and nothing else)"
$r = Invoke-Checker (Track (New-MsgRepo @("Add a thing`n   ")))
Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'no-body') "subject + a whitespace-only second line fails"

foreach ($bad in @('fix: correct the thing', 'fix:correct the thing', 'feat(scope): add', 'feat!: breaking', 'wip:')) {
    $r = Invoke-Checker (Track (New-MsgRepo @($bad)))
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'conventional-commit-prefix') "CC prefix '$bad' fails"
}

$r = Invoke-Checker (Track (New-MsgRepo @('Add a thing.')))
Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'trailing-period') "trailing period fails"
$r = Invoke-Checker (Track (New-MsgRepo @("Add a thing.`r`n")))
Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'trailing-period') "CRLF 'Subject.\r' still fails trailing-period (CR stripped first)"

$r = Invoke-Checker (Track (New-MsgRepo @("Revert `"Add logging to parser`"`n`nThis reverts commit cafe1234.")))
Assert-True ($r.ExitCode -eq 0) "genuine revert (subject + 'This reverts commit <hex>.') is exempt"
$r = Invoke-Checker (Track (New-MsgRepo @("Revert `"Add logging`"`n`nThis reverts commit cafe1234.`nCo-authored-by: x <y>")))
Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'no-body') "revert with a smuggled trailer is NOT exempt (no-body fires)"
$r = Invoke-Checker (Track (New-MsgRepo @("Revert `"Add logging`".")))
Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'trailing-period') "single-line Revert without 'This reverts commit' body is NOT exempt (trailing-period fires)"

$r = Invoke-Checker (Track (New-MsgRepo -Messages @('Add a clean thing') -Merge))
Assert-True ($r.ExitCode -eq 0) "merge commit's git-generated body is skipped (--no-merges)"

$r = Invoke-Checker (Track (New-MsgRepo @('Add a good subject', 'Add a bad subject.')))
Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'trailing-period') "multi-commit range flags the bad commit"

$r = Invoke-Checker (Track (New-MsgRepo @('Add a thing'))) -Base 'no-such-ref'
Assert-True ($r.ExitCode -eq 2) "bogus base ref fails closed (exit 2)"

$repo = Track (New-MsgRepo @('Add a thing'))
$r = Invoke-Checker $repo -Base 'feature' -Head 'feature'
Assert-True ($r.ExitCode -eq 0) "empty range passes in local mode"
$r = Invoke-Checker $repo -Base 'feature' -Head 'feature' -Extra @('-CiMode')
Assert-True ($r.ExitCode -eq 2) "empty range fails closed under -CiMode"

Write-Host ""
Write-Host "=== -MessageFile mode (commit-msg hook path) ===" -ForegroundColor Cyan
$msgFiles = New-Object System.Collections.Generic.List[string]
function Invoke-MsgFile {
    param([string] $Content)
    $f = Join-Path ([System.IO.Path]::GetTempPath()) ("ccm-msg-" + [guid]::NewGuid().ToString('N').Substring(0, 8) + ".txt")
    [System.IO.File]::WriteAllText($f, $Content, (New-Object System.Text.UTF8Encoding($false)))
    $msgFiles.Add($f)
    $out = & $pwshExe @('-NoProfile', '-File', $checkerPath, '-MessageFile', $f) 2>&1 | Out-String
    return [pscustomobject]@{ Output = $out; ExitCode = $LASTEXITCODE }
}
$r = Invoke-MsgFile "Add a clean subject"
Assert-True ($r.ExitCode -eq 0) "message file: clean subject passes"
$r = Invoke-MsgFile "Add a thing`n"
Assert-True ($r.ExitCode -eq 0) "message file: subject + single terminating newline passes"
$r = Invoke-MsgFile "Add a thing`n`n"
Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'no-body') "message file: trailing blank second line fails (no-body)"
$r = Invoke-MsgFile "Add a thing`n`nCo-authored-by: Copilot <x@y>"
Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'no-body') "message file: Co-authored-by trailer fails"
$r = Invoke-MsgFile "Add a thing."
Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'trailing-period') "message file: trailing period fails"
$r = Invoke-MsgFile "fix: do the thing"
Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'conventional-commit-prefix') "message file: CC prefix fails"
# Editor commit: git-appended '#' comment lines must be stripped before checking (else a false no-body).
$r = Invoke-MsgFile "Add a thing`n`n# Please enter the commit message for your changes. Lines starting`n# with '#' will be ignored, and an empty message aborts the commit."
Assert-True ($r.ExitCode -eq 0) "message file: editor '#' comment lines are stripped (no false no-body)"
# Verbose commit: everything after the '>8' scissors line is ignored.
$r = Invoke-MsgFile "Add a thing`n# ------------------------ >8 ------------------------`n# Do not modify this line`ndiff --git a/x b/x"
Assert-True ($r.ExitCode -eq 0) "message file: verbose scissors section is ignored"
$r = Invoke-MsgFile "Revert `"Add logging`"`n`nThis reverts commit cafe1234."
Assert-True ($r.ExitCode -eq 0) "message file: genuine revert is exempt"
$r = Invoke-MsgFile "Revert `"Add logging`"."
Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'trailing-period') "message file: single-line Revert without revert-commit body is NOT exempt"
foreach ($f in $msgFiles) { if (Test-Path -LiteralPath $f) { Remove-Item -Force -LiteralPath $f -ErrorAction SilentlyContinue } }

foreach ($p in $repos) { if (Test-Path -LiteralPath $p) { Remove-Item -Recurse -Force -LiteralPath $p -ErrorAction SilentlyContinue } }

Write-Host ""
$summaryColor = if ($script:failures -eq 0) { 'Green' } else { 'Red' }
Write-Host "check-commit-message.tests: $($script:passes) passed, $($script:failures) failed" -ForegroundColor $summaryColor
exit ([int]($script:failures -gt 0))
