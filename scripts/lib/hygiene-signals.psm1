# B1 structural-hygiene diff-signal detection for the post-code-change gate (v6-p2a RCA).
#
# HONEST CEILING: this is a LOCAL mechanical floor. It runs ONLY in check-post-code-change.ps1 -StagedMode
# (the .githooks/pre-commit hook + the pre-push audit-note gate); both are --no-verify-bypassable and CI does
# NOT revalidate (the LEDGER receipt is gitignored/local-only - git notes + worktree). It binds the PASSIVE
# momentum-skip that caused P2a (rushing past a prose self-check); it is NOT a guarantee against active
# `git commit --no-verify` evasion. The DETECTION is mechanical (a floor-raiser - false negatives possible,
# see the disclosed blind spots below); the field's justification VALUE stays agent-asserted + panel-verified,
# NOT script-verified. The citation token is SHAPE/presence-checked, not aptness-verified.
#
# DISCLOSED false-negatives (heuristic floor, not a guarantee):
#  - a cohesive slice whose files share NO domain token (pure role names: Handler/Command/Result) does not fire (i);
#  - a group dribbled in <3-at-a-time across separate commits is missed by the per-commit threshold (history-mode
#    would catch it, but the receipt is local-only and not CI-wired);
#  - visibility (ii) + DI (iii) detection are C#/.NET-shaped (access-modifier keywords, services.Add*/[Inject], csproj
#    InternalsVisibleTo); they do NOT fire on JS/TS `export`, Go capitalization, Rust `pub`, or framework DI annotations
#    even though those extensions are in CodeFileExtensions - only (i) slice-cohesion is language-agnostic;
#  - DI (iii) detects explicit container registration / [Inject] only, NOT bare constructor injection whose registration
#    sits in an unchanged composition root (same-commit registration is covered; a split-commit DI wiring is missed).

Set-StrictMode -Version Latest

# Compiled-language source where VSA-slice / visibility / DI conventions apply. Deliberately EXCLUDES .ps1
# (flat utility scripts, not VSA slices), .md/.json/.yaml/.txt (docs/config) - so a docs/scripts-only diff
# (like this very PR) never trips the detectors.
$script:CodeFileExtensions = @('.cs', '.ts', '.tsx', '.js', '.jsx', '.java', '.kt', '.go', '.rs', '.cpp', '.cc', '.cxx', '.h', '.hpp', '.py')

# Generic architectural role tokens that do NOT count as a domain-cohesion token (role-suffix stop-list: defuses the
# alert-fatigue / reflex-N/A desensitization risk on token-dense established dirs).
$script:DomainTokenStopList = @(
    'Reader', 'Writer', 'Provider', 'Service', 'Manager', 'Handler', 'Source', 'Session', 'Factory', 'Helper',
    'Repository', 'Controller', 'Tests', 'Test', 'Spec', 'Mock', 'Base', 'Abstract', 'Impl', 'Options', 'Config',
    'Extensions', 'Builder', 'Context', 'Model', 'Entity', 'Args', 'Event', 'Exception', 'Interface', 'Class'
)

function Test-IsCodeFile {
    param([string] $Path)
    if (-not $Path) { return $false }
    return $script:CodeFileExtensions -contains ([System.IO.Path]::GetExtension($Path)).ToLowerInvariant()
}

# Project-metadata files where IVT / friend-grants ALSO live - notably the preferred .NET 5+ csproj
# `<InternalsVisibleTo Include="..."/>`. These are scanned for the VISIBILITY signal in addition to code files, but are
# NOT counted as cohesive-slice members (a project file is not a slice source file).
$script:VisibilityFileExtensions = @($script:CodeFileExtensions + @('.csproj', '.vbproj', '.fsproj', '.props', '.targets'))

function Test-IsVisibilityRelevantFile {
    param([string] $Path)
    if (-not $Path) { return $false }
    return $script:VisibilityFileExtensions -contains ([System.IO.Path]::GetExtension($Path)).ToLowerInvariant()
}

function Get-DomainTokens {
    # Split a file base name into fragments (a PascalCase/camelCase word, an ALLCAPS acronym, or any lowercase/alphanumeric run); a domain token is >=4 chars and not a stop-list role.
    param([string] $FileName)
    $base = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    $segments = [regex]::Matches($base, '[A-Z][a-z0-9]+|[A-Z]{2,}(?![a-z])|[a-z0-9]+') | ForEach-Object { $_.Value }
    return @($segments | Where-Object { $_.Length -ge 4 -and $script:DomainTokenStopList -notcontains $_ } | Sort-Object -Unique)
}

function Test-CohesiveSliceSignal {
    # Fires when >=3 net-new code files land in ONE directory (new OR existing) and >=2 of them share a domain
    # token - the "cohesive slice born flat without a VSA boundary decision" signal. Returns Fired + context.
    param([string[]] $AddedCodeFiles)
    $result = [pscustomobject]@{ Fired = $false; Dir = $null; Files = 0; Token = $null }
    if (-not $AddedCodeFiles -or $AddedCodeFiles.Count -lt 3) { return $result }
    $byDir = $AddedCodeFiles | Group-Object { ([System.IO.Path]::GetDirectoryName($_) -replace '\\', '/') }
    foreach ($group in $byDir) {
        if ($group.Count -lt 3) { continue }
        $tokenCounts = @{}
        foreach ($file in $group.Group) {
            foreach ($token in (Get-DomainTokens ([System.IO.Path]::GetFileName($file)))) {
                $tokenCounts[$token] = 1 + $(if ($tokenCounts.ContainsKey($token)) { $tokenCounts[$token] } else { 0 })
            }
        }
        $sharedTokens = @($tokenCounts.GetEnumerator() | Where-Object { $_.Value -ge 2 } | ForEach-Object { $_.Key } | Sort-Object)
        if ($sharedTokens.Count -gt 0) {
            $result.Fired = $true; $result.Dir = $group.Name; $result.Files = $group.Count; $result.Token = ($sharedTokens -join ',')
            return $result
        }
    }
    return $result
}

function Get-VisibilityRelevantDiffLines {
    # From `git diff --cached -U0` output, return the +/- content lines belonging to visibility-relevant files:
    # compiled source PLUS project/metadata files (.csproj etc.) that carry IVT/friend-grants (see
    # Test-IsVisibilityRelevantFile). NOT code-only - callers must not assume non-source files are excluded.
    param([string[]] $DiffLines)
    $inRelevantFile = $false
    $out = @()
    foreach ($line in @($DiffLines)) {
        if ($line -match '^diff --git ') { $inRelevantFile = $false; continue }
        if ($line -match '^\+\+\+ b/(.+)$') { $inRelevantFile = (Test-IsVisibilityRelevantFile $Matches[1]); continue }
        if ($line -match '^(--- |@@ |index |new file|deleted file|similarity|rename )') { continue }
        if (-not $inRelevantFile) { continue }
        if ($line -match '^[+-]' -and $line -notmatch '^([+]{3}|[-]{3})') { $out += $line }
    }
    return $out
}

function Test-VisibilityDeltaSignal {
    # A visibility/export/friend-grant surface delta (added OR removed access-modified declaration, or IVT).
    # Operates on pre-filtered visibility-relevant diff lines (code + project files like .csproj).
    param([string[]] $DiffLines)
    foreach ($line in @($DiffLines)) {
        if ($line -match '^[+-]\s*(\[assembly:\s*)?InternalsVisibleTo|^[+-]\s*<InternalsVisibleTo\b') { return $true }
        if ($line -match '^[+-]\s*(public|private|protected|internal)\s+([A-Za-z\[]|static\b|sealed\b|abstract\b|partial\b|readonly\b|virtual\b|override\b|async\b|const\b|new\b)') { return $true }
    }
    return $false
}

function Test-DiSignal {
    # A new dependency-injection registration / injectable marker (DI-shape only; visibility stays with LPA).
    # Operates on pre-filtered visibility-relevant diff lines.
    param([string[]] $DiffLines)
    foreach ($line in @($DiffLines)) {
        if ($line -notmatch '^\+') { continue }
        if ($line -match '\.Add(Singleton|Scoped|Transient|HostedService)\b') { return $true }
        if ($line -match '\bservices\.Add|\bServices\.Add|\bbuilder\.Services\b') { return $true }
        # Anchor each attribute token on a word boundary so a longer name that merely starts with one
        # (e.g. [FromKeyedServicesRegistry]) does not false-positive; [FromKeyedServices(...)] args still match.
        if ($line -match '\[Inject\b|\[FromServices\b|\[FromKeyedServices\b') { return $true }
    }
    return $false
}

function Get-LedgerFieldValue {
    # First value for a `key: value` line (the ledger receipt is the canonical/audit-file YAML-ish form).
    param([string[]] $LedgerLines, [string] $Key)
    $regex = '^\s*' + [regex]::Escape($Key) + ':\s*(.*\S)\s*$'
    foreach ($line in @($LedgerLines)) { if ($line -match $regex) { return $Matches[1] } }
    return $null
}

function Test-FieldJustified {
    # present-with-justified-value: `ran ...` OR a cited `N/A - <playbook>:<line>` (or <word>:<digits>). Bare or
    # uncited N/A / absent -> NOT justified. The citation is SHAPE-checked (a <name>.md:<digits> or <word>:<digits>
    # token is present), NOT aptness-verified (B1 does not open the cited line to confirm the carve-out applies).
    param([string] $Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    if ($Value -match '^\s*ran\b') { return $true }
    if ($Value -match '^\s*n/?a\b' -and ($Value -match '[\w./-]+\.md:\d+' -or $Value -match '\b[\w.-]+:\d+')) { return $true }
    return $false
}

function Get-StructuralHygieneViolations {
    # The B1 entry point. Given the staged name-status, the `git diff --cached -U0` content, and the LEDGER
    # receipt lines, return the list of violation strings (empty = clean). Each detected signal forces its
    # matching field to be present-with-a-justified-value; a bare/uncited/absent value is a violation.
    param([string[]] $NameStatusLines, [string[]] $DiffLines, [string[]] $LedgerLines)
    $violations = @()

    $addedCodeFiles = @()
    foreach ($line in @($NameStatusLines)) {
        $parts = $line -split "`t"
        if ($parts.Count -ge 2 -and $parts[0].Trim() -match '^A' -and (Test-IsCodeFile $parts[-1])) { $addedCodeFiles += $parts[-1] }
    }
    $relevantDiffLines = Get-VisibilityRelevantDiffLines -DiffLines $DiffLines

    $slice = Test-CohesiveSliceSignal -AddedCodeFiles $addedCodeFiles
    if ($slice.Fired) {
        if (-not (Test-FieldJustified (Get-LedgerFieldValue -LedgerLines $LedgerLines -Key 'vsa-audit'))) {
            $violations += "structural-hygiene: $($slice.Files) net-new code files in '$($slice.Dir)' share domain token '$($slice.Token)' (cohesive-slice-born-flat signal) but the LEDGER 'vsa-audit' field is absent/bare/uncited - record 'ran (...)' or 'N/A - <playbook>:<line>'."
        }
        $libRestructure = Get-LedgerFieldValue -LedgerLines $LedgerLines -Key 'library-restructure'
        if ($libRestructure -and $libRestructure -match '^\s*not-required-trigger-not-detected') {
            $violations += "structural-hygiene: a net-new cohesive slice is present but pre-impl-playbook-decisions.library-restructure is 'not-required-trigger-not-detected' - must be 'invoked' or 'required-but-skipped: <re-confirmation>'."
        }
    }

    if (Test-VisibilityDeltaSignal -DiffLines $relevantDiffLines) {
        if (-not (Test-FieldJustified (Get-LedgerFieldValue -LedgerLines $LedgerLines -Key 'touched-file-LPA'))) {
            $violations += "structural-hygiene: a visibility / InternalsVisibleTo token delta is present in code but the LEDGER 'touched-file-LPA' field is absent/bare/uncited - record 'ran (...)' or 'N/A - <playbook>:<line>'."
        }
    }

    if (Test-DiSignal -DiffLines $relevantDiffLines) {
        if (-not (Test-FieldJustified (Get-LedgerFieldValue -LedgerLines $LedgerLines -Key 'dependency-injection-fit'))) {
            $violations += "structural-hygiene: a dependency-injection registration / injectable signal is present in code but the LEDGER 'dependency-injection-fit' field is absent/bare/uncited - record 'ran (...)' or 'N/A - <playbook>:<line>'."
        }
    }

    return $violations
}

Export-ModuleMember -Function Test-IsCodeFile, Test-IsVisibilityRelevantFile, Get-DomainTokens, Test-CohesiveSliceSignal, Get-VisibilityRelevantDiffLines, Test-VisibilityDeltaSignal, Test-DiSignal, Get-LedgerFieldValue, Test-FieldJustified, Get-StructuralHygieneViolations
