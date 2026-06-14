<#
  check-commit-message.ps1 - Fix A deterministic hard gate (size-free; zero loaded LLM context). Enforces the repo's
  commit-message format (AGENTS.md s2 / pre-commit.md "Commit message rules"): a single line ONLY - no body, footer, or
  trailer of any kind (incl. Co-authored-by); a non-empty subject; subject <= 72 chars; NO Conventional-Commit prefix;
  no trailing period. Per-commit RAW parsing over BaseRef..HeadRef with --no-merges; genuine `git revert` commits are
  exempt (their body is git-generated). Fail-closed: any git error -> exit 2; a HARD finding -> exit 1.

  Ref contract: -BaseRef (e.g. origin/main) + -HeadRef (default HEAD). -FetchBranch <name> does a fail-closed
  `git fetch origin <name>` first (so the script owns its own setup in CI). -CiMode treats a 0-commit range as a
  failure (a real PR always has >= 1 commit; 0 means a bad base ref).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $BaseRef,
    [string] $HeadRef = 'HEAD',
    [string] $RepoRoot = (Get-Location).Path,
    [string] $FetchBranch,
    [switch] $CiMode,
    [switch] $Json
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ExitOk = 0
$script:ExitViolation = 1
$script:ExitInvocation = 2

function Invoke-Git {
    param([string[]] $GitArgs, [switch] $AllowFailure)
    $out = & git -C $RepoRoot @GitArgs 2>$null
    if ($LASTEXITCODE -ne 0 -and -not $AllowFailure) {
        Write-Host "::error::INVOCATION_FAILED: git $($GitArgs -join ' ') failed (exit $LASTEXITCODE) - refusing to run fail-open"
        exit $script:ExitInvocation
    }
    return $out
}

# CC-prefix allowlist (lowercase, -cmatch). Colon need not be followed by space so `fix:typo`/`wip:` are caught; `Fix parser:` passes.
$ccPrefix = '^(build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test|wip)(\([^)]+\))?!?:'
# Genuine-revert body line: blank or "This reverts commit <hex>." (no Conflicts: allowance - cleanup=strip drops it; it would let a trailer be smuggled).
$revertBodyLine = '^This reverts commit [0-9a-f]{7,40}\.?$'
# Trailer names - for a clearer diagnostic only; the no-body rule (any non-whitespace body line) is the real boundary.
$trailerRegex = '^(Co-authored-by|Signed-off-by|Reviewed-by|Acked-by|Co-developed-by|Tested-by|Reported-by|Suggested-by|Cc|Fixes|Closes|Refs):'

if ($FetchBranch) { Invoke-Git @('fetch', 'origin', $FetchBranch) | Out-Null }

$commits = @(Invoke-Git @('rev-list', '--reverse', '--no-merges', "$BaseRef..$HeadRef") | Where-Object { $_ })
if ($commits.Count -eq 0) {
    if ($CiMode) {
        Write-Host "::error::no commits found in $BaseRef..$HeadRef; refusing to pass without checking"
        exit $script:ExitInvocation
    }
    if (-not $Json) { Write-Host "check-commit-message: PASS (0 commits in range $BaseRef..$HeadRef)" -ForegroundColor Green }
    else { [pscustomobject]@{ checker = 'check-commit-message'; base_ref = $BaseRef; head_ref = $HeadRef; commits = 0; finding_count = 0; status = 'pass'; findings = @() } | ConvertTo-Json -Depth 5 }
    exit $script:ExitOk
}

$findings = New-Object System.Collections.Generic.List[object]
function Add-Finding {
    param([string] $Sha, [string] $Rule, [string] $Message)
    $findings.Add([pscustomobject]@{ Sha = $Sha; Rule = $Rule; Message = $Message })
}

foreach ($sha in $commits) {
    $raw = Invoke-Git @('show', '-s', '--format=%B', $sha)
    # Normalize %B (a string or string[]) and strip CR so a CRLF `Subject.\r` cannot escape the trailing-period rule.
    $text = ((@($raw) -join "`n") -replace "`r", '')
    $lines = @($text -split "`n")
    # Drop the trailing empty line(s) %B leaves (the final newline), but KEEP interior blanks (subject/body separator).
    while ($lines.Count -gt 1 -and $lines[-1] -eq '') { $lines = @($lines[0..($lines.Count - 2)]) }
    $subject = if ($lines.Count -ge 1) { $lines[0] } else { '' }
    $bodyLines = if ($lines.Count -ge 2) { @($lines[1..($lines.Count - 1)]) } else { @() }
    $short = $sha.Substring(0, [Math]::Min(8, $sha.Length))

    if ($subject -cmatch '^Revert "') {
        $allTemplate = $true
        foreach ($bodyLine in $bodyLines) {
            if ($bodyLine.Trim() -ne '' -and $bodyLine -notmatch $revertBodyLine) { $allTemplate = $false; break }
        }
        if ($allTemplate) { continue }
    }

    if ($subject.Trim() -eq '') {
        Add-Finding $short 'empty-subject' "commit $short has an empty or whitespace-only subject line"
        continue
    }
    $bodyOffender = $bodyLines | Where-Object { $_.Trim() -ne '' } | Select-Object -First 1
    if ($null -ne $bodyOffender) {
        $diag = if ($bodyOffender -match $trailerRegex) { " (looks like a '$($matches[1])' trailer)" } else { '' }
        Add-Finding $short 'no-body' "commit $short has a body/footer/trailer$diag; the message must be a single line. First offending line: '$($bodyOffender.Trim())'"
    }
    if ($subject.Length -gt 72) {
        Add-Finding $short 'subject-too-long' "commit $short subject is $($subject.Length) chars (max 72): '$subject'"
    }
    if ($subject -cmatch $ccPrefix) {
        Add-Finding $short 'conventional-commit-prefix' "commit $short subject uses a Conventional-Commit prefix (not allowed): '$subject'"
    }
    if ($subject.EndsWith('.')) {
        Add-Finding $short 'trailing-period' "commit $short subject ends with a period: '$subject'"
    }
}

$exitCode = if ($findings.Count -gt 0) { $script:ExitViolation } else { $script:ExitOk }
if ($Json) {
    [pscustomobject]@{
        checker       = 'check-commit-message'
        base_ref      = $BaseRef
        head_ref      = $HeadRef
        commits       = $commits.Count
        finding_count = $findings.Count
        status        = if ($findings.Count -gt 0) { 'fail' } else { 'pass' }
        findings      = @($findings | ForEach-Object { [pscustomobject]@{ sha = $_.Sha; rule = $_.Rule; message = $_.Message } })
    } | ConvertTo-Json -Depth 5
}
else {
    if ($findings.Count -eq 0) {
        Write-Host "check-commit-message: PASS (0 findings) over $($commits.Count) commit(s) [$BaseRef..$HeadRef]" -ForegroundColor Green
    }
    else {
        Write-Host "check-commit-message: $($findings.Count) finding(s) over $($commits.Count) commit(s) [$BaseRef..$HeadRef]" -ForegroundColor Yellow
        $findings | ForEach-Object { Write-Host ("  ::error::[{0}] {1} {2}" -f $_.Rule, $_.Sha, $_.Message) }
    }
}
exit $exitCode
