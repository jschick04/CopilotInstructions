#Requires -Version 5.1
# Repo-wide convention guard for the two git-diff path-parsing sub-conventions the catalog rule
# `git-diff-path-parsing-requires-quote-path-false` describes:
#  (A) every `git diff`/`diff-tree` invocation in scripts/check-*.ps1 + the gate-runner.ps1/.sh publish-gate twins
#      whose output is parsed for file paths (--name-only / --name-status) or whose `+++ b/<path>` content headers
#      are parsed (-U0 / --unified=0) MUST carry `-c core.quotePath=false`, else a git-quoted non-ASCII path is
#      octal-escaped and the gate silently misses the file (the round-6 check-post-code-change false-negative).
#      Diffs routed through the flag-injecting helper Get-MatchedGatedFiles are exempt; this also asserts injection.
#  (B) every regex that captures the path from a `+++ b/` header MUST stop at git's disambiguation tab (`[^\t]+`,
#      not a greedy `.+`), else a space-containing path folds the trailing tab into the captured path.
# Honest ceiling: detection keys on `@('diff'...)` array literals (A1, check-*) + direct `& git`/`git -C ... diff`
# (A2, the gate-runner twins). The narrower residual - a bareword `git diff` (no `&`/`-C`), or a variable-built /
# default-context diff that parses `+++ b/` paths in some OTHER file - is invisible here; the catalog slug backstops it.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-common.ps1')
$script:Pass = 0
$script:Fail = 0

$scriptsDir = Split-Path -Parent $PSScriptRoot
$checkers = @(Get-ChildItem -LiteralPath $scriptsDir -Filter 'check-*.ps1')
Assert-True ($checkers.Count -ge 10) "found the scripts/check-*.ps1 cohort [anti-vacuous: $($checkers.Count)]"

# The single path-matching diff that injects the flag for its callers - assert that injection so the helper-fed
# call sites below are genuinely covered, not silently skipped.
$helper = Get-Content -LiteralPath (Join-Path $scriptsDir 'lib/read-receipt-helpers.psm1') -Raw
Assert-True ($helper.Contains('@(''-c'', ''core.quotePath=false'') + $DiffArgs')) 'Get-MatchedGatedFiles prepends -c core.quotePath=false to its caller DiffArgs (helper-fed sites are covered)'

$totalScanned = 0
$violations = @()
foreach ($checker in $checkers) {
    $lines = Get-Content -LiteralPath $checker.FullName
    $helperFedVars = @()
    foreach ($l in $lines) {
        if ($l -match 'Get-MatchedGatedFiles' -and $l -match '-DiffArgs\s+\$(\w+)') { $helperFedVars += $Matches[1] }
    }
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $isDiffLiteral = ($line -match '@\(') -and ($line -match "'diff'|'diff-tree'") -and `
            (($line -match '--name-only|--name-status') -or ($line -match "'-U0'|--unified=0"))
        if (-not $isDiffLiteral) { continue }
        $inlineHelper = $line -match 'Get-MatchedGatedFiles'
        $assignedVar = if ($line -match '^\s*\$(\w+)\s*=') { $Matches[1] } else { $null }
        $helperFed = $inlineHelper -or ($assignedVar -and ($helperFedVars -contains $assignedVar))
        if ($helperFed) { continue }
        $totalScanned++
        if ($line -notmatch 'core\.quotePath=false') {
            $violations += ('{0}:{1}: {2}' -f $checker.Name, ($i + 1), $line.Trim())
        }
    }
}
Assert-True ($totalScanned -ge 15) "scanned the path/content-parsing diff cohort [anti-vacuous: $totalScanned]"
Assert-True ($violations.Count -eq 0) ('every path/content-parsing diff in scripts/check-*.ps1 carries -c core.quotePath=false [violations: ' + ($violations -join ' | ') + ']')

# Sub-convention A also covers the publish-gate engine gate-runner, which uses the DIRECT `& git -C ... diff`
# (.ps1) / `git -C ... diff` (.sh) form, not an `@('diff'...)` array literal. The guard is a flag-presence
# text-scan, so it binds BOTH twins mechanically (no bash parsing required).
$repoRoot = Split-Path -Parent $scriptsDir
$gateRunnerScanned = 0
$gateRunnerViolations = @()
foreach ($gateRunnerName in @('gate-runner.ps1', 'gate-runner.sh')) {
    $gateRunnerLines = Get-Content -LiteralPath (Join-Path $repoRoot ('.github/pr-quality-gate/' + $gateRunnerName))
    for ($g = 0; $g -lt $gateRunnerLines.Count; $g++) {
        $gateRunnerLine = $gateRunnerLines[$g]
        if ($gateRunnerLine -match '^\s*#') { continue }
        $directGitDiff = ($gateRunnerLine -match '&\s*git\b' -or $gateRunnerLine -match '\bgit\s+-C\b') -and ($gateRunnerLine -match '\bdiff(?:-tree)?\b')
        $hasPathFlag = ($gateRunnerLine -match '--name-only|--name-status') -or ($gateRunnerLine -match "'-U0'|--unified=0")
        if ($directGitDiff -and $hasPathFlag) {
            $gateRunnerScanned++
            if ($gateRunnerLine -notmatch 'core\.quotePath=false') {
                $gateRunnerViolations += ('{0}:{1}: {2}' -f $gateRunnerName, ($g + 1), $gateRunnerLine.Trim())
            }
        }
    }
}
Assert-True ($gateRunnerScanned -ge 2) "scanned the gate-runner.ps1 + gate-runner.sh path-parsing diff(s) [anti-vacuous: $gateRunnerScanned]"
Assert-True ($gateRunnerViolations.Count -eq 0) ('every path-parsing diff in the gate-runner twins carries -c core.quotePath=false [violations: ' + ($gateRunnerViolations -join ' | ') + ']')

# Sub-convention B: every `+++ b/` path-CAPTURE regex must stop at the disambiguation tab (`[^\t]`, not greedy
# `.+`). Scanned across lib/*.psm1 + check-*.ps1; the Substring(...).Trim() form (check-no-machine-paths) is
# tab-safe and uses no `b/(` capture, so it is not matched here.
$parserFiles = @(Get-ChildItem -LiteralPath (Join-Path $scriptsDir 'lib') -Filter '*.psm1') + $checkers
$plusParsers = 0
$greedyParsers = @()
foreach ($parserFile in $parserFiles) {
    $parserLines = Get-Content -LiteralPath $parserFile.FullName
    for ($k = 0; $k -lt $parserLines.Count; $k++) {
        $parserLine = $parserLines[$k]
        if ($parserLine.Contains('\+\+\+') -and $parserLine.Contains('b/(')) {
            $plusParsers++
            if (-not $parserLine.Contains('b/([^\t]')) {
                $greedyParsers += ('{0}:{1}: {2}' -f $parserFile.Name, ($k + 1), $parserLine.Trim())
            }
        }
    }
}
Assert-True ($plusParsers -ge 2) "scanned the +++ b/ path-capture parsers [anti-vacuous: $plusParsers]"
Assert-True ($greedyParsers.Count -eq 0) ('every +++ b/ path-capture parser stops at the disambiguation tab [greedy: ' + ($greedyParsers -join ' | ') + ']')

Write-Host ''
if ($script:Fail -gt 0) { Write-Host "Failures: $script:Fail" -ForegroundColor Red; exit 1 }
Write-Host "ALL PASS ($script:Pass assertions)"
exit 0
