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
    [string] $BaseRef,
    [string] $HeadRef = 'HEAD',
    [string] $RepoRoot = (Get-Location).Path,
    [string] $FetchBranch,
    [string] $MessageFile,
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
# Trailer names - for a clearer diagnostic only; the no-body rule (any line after the subject) is the real boundary.
$trailerRegex = '^(Co-authored-by|Signed-off-by|Reviewed-by|Acked-by|Co-developed-by|Tested-by|Reported-by|Suggested-by|Cc|Fixes|Closes|Refs):'

function Get-MessageFindings {
    param([string] $Text, [string] $Label)
    $result = New-Object System.Collections.Generic.List[object]
    $norm = ($Text -replace "`r", '')
    $lines = @($norm -split "`n")
    # Strip exactly ONE trailing terminator newline; ANY remaining line after the subject (blank or content) is a
    # body/footer/trailer and fails the single-line rule - git's cleanup does not reliably strip a trailing blank line.
    if ($lines.Count -gt 1 -and $lines[-1] -eq '') { $lines = @($lines[0..($lines.Count - 2)]) }
    $subject = if ($lines.Count -ge 1) { $lines[0] } else { '' }
    $bodyLines = @(if ($lines.Count -ge 2) { $lines[1..($lines.Count - 1)] })

    if ($subject -cmatch '^Revert "') {
        $allTemplate = $true
        $hasRevertLine = $false
        foreach ($bodyLine in $bodyLines) {
            if ($bodyLine.Trim() -eq '') { continue }
            if ($bodyLine -match $revertBodyLine) { $hasRevertLine = $true }
            else { $allTemplate = $false; break }
        }
        # A genuine git revert ALWAYS carries the "This reverts commit <hex>." body line. Without it (e.g. a single-line
        # `Revert "x".`), an EMPTY body vacuously satisfies "all template" - do NOT exempt; fall through so trailing-period
        # / subject-too-long / CC-prefix still apply.
        if ($allTemplate -and $hasRevertLine) { return $result }
    }
    if ($subject.Trim() -eq '') {
        $result.Add([pscustomobject]@{ Rule = 'empty-subject'; Message = "$Label has an empty or whitespace-only subject line" }); return $result
    }
    if ($bodyLines.Count -gt 0) {
        $contentLine = $bodyLines | Where-Object { $_.Trim() -ne '' } | Select-Object -First 1
        $shown = if ($null -ne $contentLine) { $contentLine.Trim() } else { '(blank line)' }
        $diag = if ($null -ne $contentLine -and $contentLine -match $trailerRegex) { " (looks like a '$($matches[1])' trailer)" } else { '' }
        $result.Add([pscustomobject]@{ Rule = 'no-body'; Message = "$Label has a body/footer/trailer$diag; the message must be a single line. First offending line: '$shown'" })
    }
    if ($subject.Length -gt 72) { $result.Add([pscustomobject]@{ Rule = 'subject-too-long'; Message = "$Label subject is $($subject.Length) chars (max 72): '$subject'" }) }
    if ($subject -cmatch $ccPrefix) { $result.Add([pscustomobject]@{ Rule = 'conventional-commit-prefix'; Message = "$Label subject uses a Conventional-Commit prefix (not allowed): '$subject'" }) }
    if ($subject.EndsWith('.')) { $result.Add([pscustomobject]@{ Rule = 'trailing-period'; Message = "$Label subject ends with a period: '$subject'" }) }
    return $result
}

$findings = New-Object System.Collections.Generic.List[object]

if ($MessageFile) {
    # commit-msg hook path: check a single in-progress message file (the commit does not exist yet).
    if (-not (Test-Path -LiteralPath $MessageFile)) {
        Write-Host "::error::INVOCATION_FAILED: message file not found: $MessageFile"; exit $script:ExitInvocation
    }
    $msgLines = @(([System.IO.File]::ReadAllText($MessageFile) -replace "`r", '') -split "`n")
    # Replicate git's default cleanup before checking: drop the verbose `>8` scissors section and everything after it,
    # then drop comment lines (git strips lines whose first char is the comment char), then leading blanks ONLY.
    # Do NOT strip trailing blanks: a blank second line is an (empty) body and MUST fail strict no-body. Get-MessageFindings
    # strips exactly one terminating newline, so `Subject\n` passes while `Subject\n\n` fails.
    $scissors = @($msgLines | Select-String -SimpleMatch '------------------------ >8' | Select-Object -First 1)
    if ($scissors.Count -gt 0 -and $scissors[0].LineNumber -gt 1) { $msgLines = @($msgLines[0..($scissors[0].LineNumber - 2)]) }
    $cleaned = ((@($msgLines | Where-Object { $_ -notmatch '^#' }) -join "`n").TrimStart("`n"))
    foreach ($finding in (Get-MessageFindings -Text $cleaned -Label 'commit message')) { $findings.Add($finding) }
}
else {
    if (-not $BaseRef) { Write-Host "::error::INVOCATION_FAILED: provide -BaseRef (range mode) or -MessageFile (single-message mode)"; exit $script:ExitInvocation }
    if ($FetchBranch) { Invoke-Git @('fetch', 'origin', $FetchBranch) | Out-Null }
    $commits = @(Invoke-Git @('rev-list', '--reverse', '--no-merges', "$BaseRef..$HeadRef") | Where-Object { $_ })
    if ($commits.Count -eq 0) {
        if ($CiMode) { Write-Host "::error::no commits found in $BaseRef..$HeadRef; refusing to pass without checking"; exit $script:ExitInvocation }
        if (-not $Json) { Write-Host "check-commit-message: PASS (0 commits in range $BaseRef..$HeadRef)" -ForegroundColor Green }
        else { [pscustomobject]@{ checker = 'check-commit-message'; scope = "$BaseRef..$HeadRef"; finding_count = 0; status = 'pass'; findings = @() } | ConvertTo-Json -Depth 5 }
        exit $script:ExitOk
    }
    foreach ($sha in $commits) {
        $raw = Invoke-Git @('show', '-s', '--format=%B', $sha)
        $short = $sha.Substring(0, [Math]::Min(8, $sha.Length))
        foreach ($finding in (Get-MessageFindings -Text (@($raw) -join "`n") -Label "commit $short")) { $findings.Add($finding) }
    }
}

$exitCode = if ($findings.Count -gt 0) { $script:ExitViolation } else { $script:ExitOk }
$scope = if ($MessageFile) { "message file" } else { "$BaseRef..$HeadRef" }
if ($Json) {
    [pscustomobject]@{
        checker       = 'check-commit-message'
        scope         = $scope
        finding_count = $findings.Count
        status        = if ($findings.Count -gt 0) { 'fail' } else { 'pass' }
        findings      = @($findings | ForEach-Object { [pscustomobject]@{ rule = $_.Rule; message = $_.Message } })
    } | ConvertTo-Json -Depth 5
}
else {
    if ($findings.Count -eq 0) {
        Write-Host "check-commit-message: PASS (0 findings) [$scope]" -ForegroundColor Green
    }
    else {
        Write-Host "check-commit-message: $($findings.Count) finding(s) [$scope]" -ForegroundColor Yellow
        $findings | ForEach-Object { Write-Host ("  ::error::[{0}] {1}" -f $_.Rule, $_.Message) }
    }
}
exit $exitCode
