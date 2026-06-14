<#
  check-no-smart-punctuation.ps1 - enforce the AGENTS.md 3.14 ban on em-dash (U+2014) / en-dash (U+2013) in repo text.

  An exception allowlist (.github/pr-quality-gate/data/smart-punctuation-allowlist.txt) lists files permitted to
  retain a banned char; it is normally EMPTY (the ban is enforced repo-wide). Fail-closed in BOTH
  directions: an UNLISTED file containing a banned char FAILS (no new violations), and a LISTED file that is already
  CLEAN (or whose path no longer exists) FAILS as a stale entry, so cleaning a file forces removing its allowlist line
  in the same change. Code that must MATCH the literal char should use a Unicode escape (regex `\u2014`) or build it at
  runtime (`[char]0x2014`) so the source itself stays ASCII.

  Exit: 0 clean, 1 violation(s), 2 invocation error.
#>
[CmdletBinding()]
param(
    [string] $RepoRoot = (Get-Location).Path
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ExitOk = 0
$script:ExitViolation = 1
$script:ExitInvocation = 2

# Banned set (AGENTS.md 3.14 dashes): em-dash U+2014, en-dash U+2013. Expressed as escapes so this file stays ASCII.
$bannedPattern = "[\u2014\u2013]"
$allowlistPath = Join-Path $RepoRoot '.github/pr-quality-gate/data/smart-punctuation-allowlist.txt'

if (-not (Test-Path -LiteralPath $allowlistPath)) {
    Write-Host "::error::INVOCATION_FAILED: allowlist not found at $allowlistPath"
    exit $script:ExitInvocation
}

# Allowlist grammar: one repo-relative path per line (forward slashes); skip blank lines and '#' comments.
$allow = @(Get-Content -LiteralPath $allowlistPath | ForEach-Object { $_.Trim() } | Where-Object { $_ -and ($_ -notmatch '^#') })
$allowSet = @{}
foreach ($entry in $allow) { $allowSet[$entry] = $true }

Push-Location $RepoRoot
try { $tracked = @(& git ls-files | Where-Object { $_ }) } finally { Pop-Location }
if ($tracked.Count -eq 0) {
    Write-Host "::error::INVOCATION_FAILED: git ls-files returned no files (not a git checkout?)"
    exit $script:ExitInvocation
}

$violations = New-Object System.Collections.Generic.List[string]
$stale = New-Object System.Collections.Generic.List[string]
$seenAllow = @{}

foreach ($rel in $tracked) {
    $abs = Join-Path $RepoRoot $rel
    if (-not (Test-Path -LiteralPath $abs)) { continue }
    $content = [System.IO.File]::ReadAllText($abs)
    if ($content.IndexOf([char]0) -ge 0) { continue }   # binary file; skip
    $hasBanned = [regex]::IsMatch($content, $bannedPattern)
    $inAllow = $allowSet.ContainsKey($rel)
    if ($inAllow) { $seenAllow[$rel] = $true }

    if ($hasBanned -and -not $inAllow) {
        $count = ([regex]::Matches($content, $bannedPattern)).Count
        $violations.Add("${rel}: $count em/en-dash character(s) - banned by AGENTS.md 3.14 (use ASCII '-', or a Unicode escape / [char]0x2014 in code that must match the literal)")
    }
    elseif ((-not $hasBanned) -and $inAllow) {
        $stale.Add("${rel}: allowlisted but already CLEAN - remove this line from smart-punctuation-allowlist.txt (allowlist hygiene: de-list cleaned files)")
    }
}

# Allowlist entries that no longer correspond to a tracked file.
foreach ($entry in $allow) {
    if (-not $seenAllow.ContainsKey($entry)) {
        $stale.Add("${entry}: allowlist entry does not match a tracked file - fix the path or remove the line")
    }
}

if ($violations.Count -gt 0) {
    Write-Host "check-no-smart-punctuation: $($violations.Count) file(s) with banned em/en-dashes OUTSIDE the allowlist:" -ForegroundColor Red
    $violations | ForEach-Object { Write-Host "  ::error::$_" }
}
if ($stale.Count -gt 0) {
    Write-Host "check-no-smart-punctuation: $($stale.Count) stale allowlist entr(y/ies) (clean or missing - de-list them):" -ForegroundColor Red
    $stale | ForEach-Object { Write-Host "  ::error::$_" }
}

if (($violations.Count + $stale.Count) -gt 0) { exit $script:ExitViolation }

Write-Host "check-no-smart-punctuation: PASS - no em/en-dashes outside the allowlist ($($allow.Count) exception path(s))." -ForegroundColor Green
exit $script:ExitOk
