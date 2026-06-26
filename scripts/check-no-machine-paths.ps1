<#
  check-no-machine-paths.ps1 - fail-closed gate: a committed change must not ADD a CONCRETE local-machine
  absolute path (a developer home directory or a CI-runner home). Mechanizes the absolute-path clause of
  coding-standards-code.instructions.md ("absolute path that references your local machine"). The sibling
  TODO / FIXME / debug-print clause stays authoring discipline (ungated - higher false-positive) per the panel.

  HONEST CEILING: this RAISES the floor on concrete machine paths; it does NOT guarantee no-leak. It scans
  ADDED lines only (introductions). It suppresses placeholder segments (`<...>`, `{...}`, `%...%`, `$...`, `~`)
  and the shared / CI-runner canonical homes (Public, Default, Shared, runner, runneradmin), so an env-var
  indirection ($HOME, %USERPROFILE%), an unusual mount, or a placeholder-that-is-a-real-name escapes. The
  /Users/ anchor is matched case-sensitively (so a lowercase `/users/:id` REST route is NOT flagged); the
  lowercase `/home/` anchor is inherently route-ambiguous, so in a repo that contains web routes a `/home/...`
  route can false-positive - a documented residual, not a regex-fixable case. Fail-CLOSED on any git / scan /
  invocation error.

  TWO GIT MODES (one scan path):
    -Staged          pre-commit: scans `git diff --cached` added lines.
    -BaseRef <ref>      CI + run-local-ci: scans `git diff <ref>...HEAD` added lines (the whole branch diff).
  Both modes self-exclude THIS script + its test file (they embed concrete fixtures by necessity), so the
  gate's own introducing change does not self-trip. An empty diff is clean (empty input = clean, exit 0) -
  not a deferral.

  Exit: 0 clean (or nothing to scan), 1 violation(s), 2 invocation/config error.
#>
[CmdletBinding()]
param(
    [switch] $Staged,
    [string] $BaseRef,
    [string] $RepoRoot = '',
    [switch] $Json
)
# Strict mode only when invoked, not when dot-sourced by the tests (so it doesn't leak into the caller scope).
if ($MyInvocation.InvocationName -ne '.') {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
}

$script:ExitOk = 0
$script:ExitViolation = 1
$script:ExitInvocation = 2

# The two self-excluded files (they embed concrete machine-path fixtures by necessity). Applied IDENTICALLY in
# both -Staged and -BaseRef mode so the gate's own introducing change never self-trips.
$script:SelfExcludePathspecs = @(
    ':!scripts/check-no-machine-paths.ps1'
    ':!scripts/tests/check-no-machine-paths.tests.ps1'
)

# Excluded first-segment tokens: doc placeholders + Windows/macOS shared homes + CI-runner canonical homes.
# A token only suppresses when it is a COMPLETE path segment (the `(?![A-Za-z0-9._-])` tail), so a real name
# that merely starts with a token (younes, userland, sharedrive, defaultsmith) still fires.
$script:ExcludedSegmentTokens = 'you|name|user|username|youruser|public|default|shared|runner|runneradmin'

# Windows branch: whole-branch case-insensitive (Windows paths are case-insensitive; no web-route collision).
# The `[\\/]+` separator catches the single-backslash path, the escaped `\\` form (C#/JSON/TS string literals),
# and the forward-slash form. The capture tail extends the match to the full path snippet for the message.
$script:WindowsHomePattern = '(?i)[A-Za-z]:[\\/]+Users[\\/]+(?!(?:{0})(?![A-Za-z0-9._-]))(?![<{{%$~])[A-Za-z0-9._-][^\s"''<>|]*' -f $script:ExcludedSegmentTokens
# Unix branch: anchor matched CASE-SENSITIVELY (so a lowercase `/users/:id` route is not flagged); only the
# placeholder/shared token lookahead is case-insensitive `(?i:...)`.
$script:UnixHomePattern = '/(?:Users|home)/(?!(?i:{0})(?![A-Za-z0-9._-]))(?![<{{~])[A-Za-z0-9._-][^\s"''<>|]*' -f $script:ExcludedSegmentTokens

$script:MachinePathPatterns = @(
    [pscustomobject]@{ Name = 'windows-home'; Regex = $script:WindowsHomePattern }
    [pscustomobject]@{ Name = 'unix-home';    Regex = $script:UnixHomePattern }
)

function Get-MachinePathFindings {
    <#
      Pure scanner: takes added-line texts, returns one finding per (line, pattern) hit
      (Pattern name + the matched path snippet + the source line text). No git needed - the tests feed
      in-memory lines. Stops at the first matching pattern per line (a line needs only one reason to fail).
    #>
    param([string[]] $AddedLines)
    $findings = New-Object System.Collections.Generic.List[object]
    if ($null -eq $AddedLines) { return $findings }
    foreach ($line in $AddedLines) {
        if ([string]::IsNullOrEmpty($line)) { continue }
        foreach ($pattern in $script:MachinePathPatterns) {
            $regexMatch = [regex]::Match($line, $pattern.Regex)
            if ($regexMatch.Success) {
                $findings.Add([pscustomobject]@{ Pattern = $pattern.Name; Match = $regexMatch.Value; LineText = $line })
                break
            }
        }
    }
    return $findings
}

# ---- main (skipped when dot-sourced by the tests) -----------------------------------------------------------
if ($MyInvocation.InvocationName -eq '.') { return }

Import-Module (Join-Path $PSScriptRoot 'lib/repo-root.psm1') -Force
if ($RepoRoot) {
    try {
        $repoRoot = (Resolve-Path -LiteralPath $RepoRoot -ErrorAction Stop).Path
    } catch {
        Write-Host "::error::INVOCATION_FAILED: -RepoRoot '$RepoRoot' does not resolve: $($_.Exception.Message)"
        exit $script:ExitInvocation
    }
} else {
    try {
        $repoRoot = Resolve-RepoRoot -Explicit '' -ScriptRoot $PSScriptRoot -Anchors @('scripts/check-no-machine-paths.ps1') -RequireGitWorkTree
    } catch {
        Write-Host "::error::$($_.Exception.Message)"
        exit $script:ExitInvocation
    }
}
$stagedMode = $Staged.IsPresent
$baseMode = -not [string]::IsNullOrWhiteSpace($BaseRef)
if ($stagedMode -and $baseMode) {
    Write-Host "::error::INVOCATION_FAILED: supply at most one of -Staged / -BaseRef, not both"
    exit $script:ExitInvocation
}
if (-not $stagedMode -and -not $baseMode) {
    Write-Host "::error::INVOCATION_FAILED: supply -Staged (pre-commit) or -BaseRef <ref> (CI / branch diff)"
    exit $script:ExitInvocation
}

if ($stagedMode) {
    $rangeLabel = 'staged diff'
    $diffArgs = @('-c', 'core.quotePath=false', '-C', $repoRoot, 'diff', '--cached', '--no-color', '-U0', '--', '.') + $script:SelfExcludePathspecs
} else {
    $rangeLabel = "$BaseRef...HEAD range"
    $diffArgs = @('-c', 'core.quotePath=false', '-C', $repoRoot, 'diff', '--no-color', '-U0', "$BaseRef...HEAD", '--', '.') + $script:SelfExcludePathspecs
}

$diffOutput = & git @diffArgs 2>$null
$gitExit = $LASTEXITCODE
if ($gitExit -ne 0) {
    Write-Host "::error::INVOCATION_FAILED: git diff failed (exit $gitExit) for the $rangeLabel; cannot scan for machine paths. Failing closed."
    exit $script:ExitInvocation
}

# Walk the unified diff HUNK-AWARE: the `+++ b/<path>` file header only appears in a file's PREAMBLE (before the
# first `@@` hunk), so track whether we are inside a hunk. In the preamble, the `+++ ` line sets the target file;
# inside a hunk, a `+`-prefixed line is added CONTENT (even if that content itself begins with `+`/`++`). This
# avoids the header-vs-content ambiguity of a naive `StartsWith('+++')` test. git emits no `+` content for binary
# files, so binaries are naturally skipped.
$addedRecords = New-Object System.Collections.Generic.List[object]
$currentFile = '(unknown)'
$inHunk = $false
foreach ($diffLine in $diffOutput) {
    if ($diffLine -isnot [string]) { continue }
    if ($diffLine.StartsWith('diff --git ')) { $inHunk = $false; $currentFile = '(unknown)'; continue }
    if ($diffLine.StartsWith('@@')) { $inHunk = $true; continue }
    if (-not $inHunk) {
        # Preamble (---, +++, index, mode lines): only the `+++ ` header is meaningful; nothing here is content.
        if ($diffLine.StartsWith('+++ ')) {
            $target = $diffLine.Substring(4).Trim()
            if ($target -eq '/dev/null') { $currentFile = '(deleted)' }
            elseif ($target.StartsWith('b/')) { $currentFile = $target.Substring(2) }
            else { $currentFile = $target }
        }
        continue
    }
    # Inside a hunk: a `+`-prefixed line is added content (its text is everything after the leading '+').
    if ($diffLine.StartsWith('+')) {
        $addedRecords.Add([pscustomobject]@{ File = $currentFile; Text = $diffLine.Substring(1) })
    }
}

if ($addedRecords.Count -eq 0) {
    if ($Json) {
        [pscustomobject]@{ violations = @() } | ConvertTo-Json -Depth 5
    } else {
        Write-Host "check-no-machine-paths: nothing to scan (no added lines in the $rangeLabel; empty input = clean). OK."
    }
    exit $script:ExitOk
}

try {
    $violations = New-Object System.Collections.Generic.List[object]
    foreach ($record in $addedRecords) {
        foreach ($finding in (Get-MachinePathFindings -AddedLines @($record.Text))) {
            $violations.Add([pscustomobject]@{ File = $record.File; Pattern = $finding.Pattern; Match = $finding.Match })
        }
    }
} catch {
    Write-Host "::error::INVOCATION_FAILED: scan threw - refusing to run fail-open: $($_.Exception.Message)"
    exit $script:ExitInvocation
}

if ($Json) {
    [pscustomobject]@{ violations = $violations } | ConvertTo-Json -Depth 5
    if ($violations.Count -gt 0) { exit $script:ExitViolation }
    exit $script:ExitOk
}

if ($violations.Count -gt 0) {
    Write-Host "check-no-machine-paths: $($violations.Count) added line(s) embed a concrete local-machine absolute path - strip it (use a relative path, a well-known-folder API, or a placeholder like C:\Users\<you>\...):" -ForegroundColor Red
    foreach ($violation in $violations) {
        Write-Host "  ::error::$($violation.File): [$($violation.Pattern)] $($violation.Match)"
    }
    exit $script:ExitViolation
}

Write-Host "check-no-machine-paths: OK - no concrete local-machine absolute paths in the added lines of the $rangeLabel." -ForegroundColor Green
exit $script:ExitOk
