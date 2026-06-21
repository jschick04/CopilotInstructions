<#
  check-pr-text.ps1 - fail-closed gate: a PR title + body must be free of internal plan markers (mechanizes the
  honor-system convention in pre-pr-push.md, which self-admits leaks "caught only post-open").

  HONEST CEILING: fail-closed on MODELED structured markers; a heuristic floor-raise on SHAs. It RAISES the floor;
  it does NOT guarantee no-leak. An unmodeled marker format / paraphrase / hex-before-context SHA escapes. The
  bare-adjacent plan-shape (`task A1`) is caught-by-design and an over-catch is escaped by rephrasing the PR text
  (the author controls it).

  TWO INPUT MODES (one scan path), STRICT single-source:
    -Title <str> [-BodyFile <path> | -Body <str>]   the pre-create agent-prerequisite path
    $env:PR_TITLE / $env:PR_BODY                     the CI `pull_request` job path
  Providing BOTH a -Title param AND a PR_TITLE env, or a partial param set, is ambiguous -> exit 2.
  NO input source at all (local-CI mirror; the PR text is not a local artifact) -> exit 0 with a notice; CI is the
  authoritative gate. The short-circuit keys on the TITLE source being absent (GitHub always supplies a title, so CI
  never short-circuits); an EMPTY body is a real scannable state (a title-only leak in an empty-body PR still scans).

  TIERS:
    TIER 1 hard-fail (exit 1): near-0-FP structured markers - (i) workspace artifacts, (ii) compound plan-IDs,
      (iii) context-anchored short plan-IDs (a plan-specific word immediately hugging the ID, or a trailing-paren ID),
      (iv) plan-shaped phase markers.
    TIER 2 warn (exit 0, surfaced not blocked): bare un-anchored short plan-IDs + a context-anchored bare-SHA.

  Exit: 0 clean (or no local input), 1 a tier-1 hard-fail, 2 invocation/config error. Fail-closed on any error.
#>
[CmdletBinding()]
param(
    [string] $Title,
    [string] $BodyFile,
    [string] $Body,
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

# --- TIER 1 (hard-fail) markers: name -> regex. Near-0 FP (verified against a legit-text FP battery). ---------------
$script:Tier1Patterns = @(
    # (i) workspace / session-state artifacts (path-shaped, near-0 FP)
    [pscustomobject]@{ Name = 'session-state-path'; Regex = '(?i)(?:\.copilot[\\/])?session-state[\\/]' }
    [pscustomobject]@{ Name = 'session-files-ref';  Regex = '(?i)\bfiles[\\/][A-Za-z0-9._-]+\.(?:md|txt)\b' }
    [pscustomobject]@{ Name = 'session-plan-file';  Regex = '(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}[\\/]plan\.md\b' }
    # (ii) compound plan-IDs (specific shapes: FX-3, F16e-2)
    [pscustomobject]@{ Name = 'compound-plan-id';   Regex = '(?i)(?<![A-Za-z0-9_-])(?:FX-\d+|F\d+[A-Za-z]*-\d+)(?![A-Za-z0-9_-])' }
    # (iii) context-anchored short plan-IDs: a plan-specific word IMMEDIATELY hugging the ID (only ws / [:#-] between)
    [pscustomobject]@{ Name = 'anchored-short-id';  Regex = '(?i)\b(?:plan|task|follow[- ]?up|cascade)\s*[:#-]?\s*(?:T\d+|A\d+|C\d+|D\d+)(?![A-Za-z0-9_-])' }
    # (iii) trailing-paren plan-ID at end-of-line (multiline)
    [pscustomobject]@{ Name = 'trailing-paren-id';  Regex = '(?im)\((?:T\d+|A\d+|C\d+|D\d+|FX-\d+|F\d+[A-Za-z]*-\d+)\)\s*$' }
    # (iv) plan-SHAPED phase markers (keeps "Phase 5.5"/"step 7c"/"option B-"; drops bare "Phase 1"/"step 3")
    [pscustomobject]@{ Name = 'phase-shape';        Regex = '(?i)\bPhase\s+\d+\.\d' }
    [pscustomobject]@{ Name = 'step-shape';         Regex = '(?i)\bstep\s+\d+[a-z]\b' }
    [pscustomobject]@{ Name = 'option-shape';       Regex = '\b[Oo]ption\s+[A-Z]-' }
)

# --- TIER 2 (warn-only) markers. -----------------------------------------------------------------------------------
$script:Tier2Patterns = @(
    [pscustomobject]@{ Name = 'bare-short-id'; Regex = '(?<![A-Za-z0-9_-])(?:T\d+|A\d+|C\d+|D\d+)(?![A-Za-z0-9_-])' }
    [pscustomobject]@{ Name = 'per-anchored-short-id'; Regex = '(?i)\bper\s*[:#-]?\s*(?:T\d+|A\d+|C\d+|D\d+)(?![A-Za-z0-9_-])' }
    [pscustomobject]@{ Name = 'context-sha';   Regex = '(?i)\b(?:upstream|already shipped|shipped|backported|cherry[- ]picked|rebased from|introduced in)\b.{0,40}\b[0-9a-f]{7,40}\b' }
)

function Get-PrTextFindings {
    <# Scans a title + body and returns the tier-1 (Severity=hard-fail) + tier-2 (Severity=warn) marker hits. #>
    param([string] $TitleText = '', [string] $BodyText = '')
    $findings = New-Object System.Collections.Generic.List[object]
    $surfaces = @(
        [pscustomobject]@{ Surface = 'title'; Text = $TitleText }
        [pscustomobject]@{ Surface = 'body';  Text = $BodyText }
    )
    foreach ($surface in $surfaces) {
        if ([string]::IsNullOrEmpty($surface.Text)) { continue }
        foreach ($pattern in $script:Tier1Patterns) {
            $regexMatch = [regex]::Match($surface.Text, $pattern.Regex)
            if ($regexMatch.Success) {
                $findings.Add([pscustomobject]@{ Severity = 'hard-fail'; Marker = $pattern.Name; Surface = $surface.Surface; Match = $regexMatch.Value.Trim() })
            }
        }
        foreach ($pattern in $script:Tier2Patterns) {
            $regexMatch = [regex]::Match($surface.Text, $pattern.Regex)
            if ($regexMatch.Success) {
                $findings.Add([pscustomobject]@{ Severity = 'warn'; Marker = $pattern.Name; Surface = $surface.Surface; Match = $regexMatch.Value.Trim() })
            }
        }
    }
    return $findings
}

# ---- main (skipped when dot-sourced by the tests) -----------------------------------------------------------------
if ($MyInvocation.InvocationName -eq '.') { return }

# Resolve the single input source (strict): param (-Title) XOR env (PR_TITLE).
$paramMode = $PSBoundParameters.ContainsKey('Title')
$envTitle = $env:PR_TITLE
$envMode = -not [string]::IsNullOrEmpty($envTitle)
# Body-aware vacuity (distinct from title-only $envMode): an empty title with a present body must still scan,
# but folding body into $envMode would false-trip the param+env ambiguity check below.
$envHasText = -not ([string]::IsNullOrEmpty($env:PR_TITLE) -and [string]::IsNullOrEmpty($env:PR_BODY))

if ($paramMode -and $envMode) {
    Write-Host "::error::INVOCATION_FAILED: both -Title and `$env:PR_TITLE supplied - ambiguous input source"
    exit $script:ExitInvocation
}
if (-not $paramMode -and ($PSBoundParameters.ContainsKey('Body') -or $PSBoundParameters.ContainsKey('BodyFile'))) {
    Write-Host "::error::INVOCATION_FAILED: -Body / -BodyFile supplied without -Title; a body source is not scanned without the title source"
    exit $script:ExitInvocation
}
if (-not $paramMode -and -not $envHasText) {
    if ($Json) {
        [pscustomobject]@{ hardFails = @(); warns = @() } | ConvertTo-Json -Depth 5
    } else {
        Write-Host "check-pr-text: no PR text supplied (local-CI mirror; the PR title/body is not a local artifact). CI is the authoritative gate. OK."
    }
    exit $script:ExitOk
}

if ($paramMode) {
    $bodyFileBound = $PSBoundParameters.ContainsKey('BodyFile')
    if ($bodyFileBound -and $PSBoundParameters.ContainsKey('Body')) {
        Write-Host "::error::INVOCATION_FAILED: supply at most one of -BodyFile / -Body"
        exit $script:ExitInvocation
    }
    if ([string]::IsNullOrWhiteSpace($Title)) {
        Write-Host "::error::INVOCATION_FAILED: -Title is empty; param mode requires the actual (non-empty) PR title to scan"
        exit $script:ExitInvocation
    }
    $titleText = $Title
    if ($bodyFileBound) {
        if ([string]::IsNullOrWhiteSpace($BodyFile)) {
            Write-Host "::error::INVOCATION_FAILED: -BodyFile is empty; supply the actual body-file path (an empty path is not a valid source)"
            exit $script:ExitInvocation
        }
        if (-not (Test-Path -LiteralPath $BodyFile)) {
            Write-Host "::error::INVOCATION_FAILED: -BodyFile '$BodyFile' does not exist"
            exit $script:ExitInvocation
        }
        $bodyText = Get-Content -LiteralPath $BodyFile -Raw -ErrorAction Stop
    } else {
        $bodyText = $Body
    }
} else {
    $titleText = $envTitle
    $bodyText = $env:PR_BODY
}

try {
    $findings = Get-PrTextFindings -TitleText $titleText -BodyText $bodyText
} catch {
    Write-Host "::error::INVOCATION_FAILED: scan threw - refusing to run fail-open: $($_.Exception.Message)"
    exit $script:ExitInvocation
}

$hardFails = @($findings | Where-Object { $_.Severity -eq 'hard-fail' })
$warns = @($findings | Where-Object { $_.Severity -eq 'warn' })

if ($Json) {
    [pscustomobject]@{ hardFails = $hardFails; warns = $warns } | ConvertTo-Json -Depth 5
    if ($hardFails.Count -gt 0) { exit $script:ExitViolation }
    exit $script:ExitOk
}

foreach ($warn in $warns) {
    Write-Host "::warning::check-pr-text [tier-2 warn] $($warn.Marker) in PR $($warn.Surface): '$($warn.Match)' (surfaced, not blocking; rephrase if it is an internal marker)"
}

if ($hardFails.Count -gt 0) {
    foreach ($hardFail in $hardFails) {
        Write-Host "::error::check-pr-text [tier-1] internal plan marker '$($hardFail.Match)' ($($hardFail.Marker)) in PR $($hardFail.Surface) - strip it before opening the PR (use the behavior change, not the internal phase ID)"
    }
    Write-Host "check-pr-text: FAIL - $($hardFails.Count) internal plan marker(s) in the PR title/body."
    exit $script:ExitViolation
}

Write-Host "check-pr-text: OK - no tier-1 internal plan markers in the PR title/body ($($warns.Count) tier-2 warning(s))."
exit $script:ExitOk
