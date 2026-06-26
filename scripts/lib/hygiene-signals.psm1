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
# SCOPE: the visibility (ii) + DI (iii) signals are WIDENING / additions-only - they fire on ADDED exposed
# surface, mirroring the least-privilege-audit rule's added-token trigger; pure narrowing (removed members,
# removed IVT, whole-file deletions, ->private) does NOT fire (the LPA rule treats removals as always-allowed).
# B1 is the mechanical FLOOR; the least-privilege-audit review-pass rule is the broader visibility check. For a
# NON-test InternalsVisibleTo target (a production friend-grant) B1 additionally FLAGS it and FORCES the
# touched-file-LPA field to carry a `production-ivt:` marker (shape-checked PRESENT, not aptness-verified; the
# panel + the non-test-ivt-target catalog slug verify the justification). B1 does NOT prevent/guarantee no-prod-IVT.
#
# DISCLOSED false-negatives / blind spots (heuristic floor, not a guarantee):
#  - a cohesive slice whose files share NO domain token (pure role names: Handler/Command/Result) does not fire (i);
#  - a group dribbled in <3-at-a-time across separate commits is missed by the per-commit threshold (history-mode
#    would catch it, but the receipt is local-only and not CI-wired);
#  - visibility (ii) + DI (iii) are C#/.NET-shaped (access-modifier keywords, services.Add*/[Inject], csproj
#    InternalsVisibleTo); they do NOT fire on JS/TS `export`, Go capitalization, Rust `pub`, or framework DI
#    annotations even though those extensions are in CodeFileExtensions - only (i) slice-cohesion is language-agnostic;
#  - DI (iii) detects explicit container registration / [Inject] only, NOT bare constructor injection whose
#    registration sits in an unchanged composition root (split-commit DI wiring is missed); it skips leading
#    comment lines but is line-regex (not a parser): a registration sharing a line with a leading comment-open
#    (`/* x */ services.Add()`) is MISSED, and a DI token inside a string literal ("...services.Add...") over-fires;
#  - sealed/final REMOVAL (inheritance widening) is not separately detected (no -/+ correlation); note a typical
#    whole-line `-public sealed class X`/`+public class X` STILL fires via the re-emitted `+public` line - the
#    true miss is only the contrived implicit-visibility case (`sealed class X`->`class X`, no access token);
#  - a narrowing MODIFICATION that keeps an access token (`-public class X`/`+internal class X`) STILL fires
#    (additions-only sees only the `+internal` line) - benign (it forces a recorded field, satisfiable by `ran`);
#  - the non-test-IVT classifier (Test-IsTestAssemblyName) is a conservative NAME-proxy for the rule's semantic
#    "no production consumer" test - fallible BOTH ways: a production lib named like a test (a *TestData* util)
#    is treated test (missed); a test convention NOT in the list is treated production (forces a marker);
#  - the non-test-IVT DETECTION (Get-AddedIvtTargets) only matches a grant that STARTS the added line
#    (`+[assembly: InternalsVisibleTo` / `+<InternalsVisibleTo Include=`); a commented-out / string-literal /
#    minified-inline (several elements on one line) IVT is not detected - the line-start anchor won't false-capture
#    a comment, at the cost of the rare inline form (the catalog slug + panel are the broader backstop).

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
    # Return the ADDED (+) content lines belonging to visibility-relevant files (compiled source PLUS project
    # files like .csproj that carry IVT). Additions-only: the widening + DI signals are additions-only, so
    # removed (`-`) lines and whole-file deletions are intentionally excluded (narrowing is not a widening signal).
    # The file path is read from the `+++ b/<path>` header ONLY in the pre-`@@` file-header section (inHeader),
    # so a hunk CONTENT line that merely looks like a header cannot spuriously mark a file relevant.
    param([string[]] $DiffLines)
    $inRelevantFile = $false
    $inHeader = $false
    $out = @()
    foreach ($line in @($DiffLines)) {
        if ($line -match '^diff --git ') { $inRelevantFile = $false; $inHeader = $true; continue }
        if ($line -match '^@@ ') { $inHeader = $false; continue }
        if ($inHeader) {
            if ($line -match '^\+\+\+ b/(.+)$') { $inRelevantFile = (Test-IsVisibilityRelevantFile $Matches[1]) }
            continue
        }
        if (-not $inRelevantFile) { continue }
        if ($line -match '^\+' -and $line -notmatch '^\+{3}') { $out += $line }
    }
    return $out
}

function Test-VisibilityDeltaSignal {
    # WIDENING-only floor: fires on an ADDED exposed declaration (public/protected/internal - NOT private) or an
    # ADDED InternalsVisibleTo friend-grant, mirroring the least-privilege-audit rule's added-token trigger.
    # Narrowing (removed members, removed IVT, deletions, ->private) does NOT fire - the LPA rule treats removals
    # as always-allowed. Operates on the additions-only visibility-relevant diff lines. C#/.NET-shaped (header FN).
    param([string[]] $DiffLines)
    foreach ($line in @($DiffLines)) {
        if ($line -match '^\+\s*\[assembly:\s*(?:[\w.]+\.)?InternalsVisibleTo(?:Attribute)?\b|^\+\s*<InternalsVisibleTo\b') { return $true }
        if ($line -match '^\+\s*(public|protected|internal)\s+([A-Za-z\[]|static\b|sealed\b|abstract\b|partial\b|readonly\b|virtual\b|override\b|async\b|const\b|new\b)') { return $true }
    }
    return $false
}

function Get-AddedIvtTargets {
    # Target assembly names from ADDED InternalsVisibleTo grants - the C# attribute (optional namespace qualifier
    # / `Attribute` suffix, legacy AssemblyInfo.cs or modern) AND the preferred .NET 5+ csproj
    # `<InternalsVisibleTo Include="..." />` item (Include in any position, single or double quotes). The IVT arg
    # may carry `, PublicKey=...` - the assembly name is the part before the first comma. The grant must START the
    # added line (after `+` and indentation): a commented-out / string-literal / minified-inline (several elements
    # on one line) IVT is not detected - the line-start anchor is the safe direction (never false-captures a comment).
    param([string[]] $DiffLines)
    $targets = @()
    foreach ($line in @($DiffLines)) {
        if ($line -notmatch '^\+') { continue }
        if ($line -match '^\+\s*\[assembly:\s*(?:[\w.]+\.)?InternalsVisibleTo(?:Attribute)?\s*\(\s*"([^"]+)"') { $targets += ($Matches[1] -split ',')[0].Trim() }
        elseif ($line -match '^\+\s*<InternalsVisibleTo\b[^>]*\bInclude\s*=\s*["'']([^"'']+)["'']') { $targets += ($Matches[1] -split ',')[0].Trim() }
    }
    return @($targets)
}

function Test-IsTestAssemblyName {
    # Conservative NAME-proxy for the least-privilege-audit rule's semantic "test / no-production-consumer"
    # assembly (canonical definition: least-privilege-audit.md). Matches a PascalCase segment (case-sensitive,
    # boundary-aware) of a test / test-double convention. Fallible BOTH ways (see the header blind-spot note);
    # NOT project-kind-verified.
    param([string] $Name)
    if (-not $Name) { return $false }
    $asm = ($Name -split ',')[0].Trim().Trim('"').Trim()
    return $asm -cmatch '(?:^|\.|[a-z0-9])(?:Tests?|Specs?|Fakes?|Mocks?|Fixtures?|Benchmarks?|Stubs?|E2E|Acceptance)(?=$|\.|[A-Z])'
}

function Test-NonTestIvtSignal {
    # Fires when an ADDED IVT grant targets a NON-test assembly (a production friend-grant) - the GATED case that
    # must record a deliberate production-ivt decision. Returns the first non-test target name (or $null).
    param([string[]] $DiffLines)
    foreach ($target in (Get-AddedIvtTargets -DiffLines $DiffLines)) {
        if (-not (Test-IsTestAssemblyName $target)) { return $target }
    }
    return $null
}

function Test-DiSignal {
    # A new dependency-injection registration / injectable marker (DI-shape only; visibility stays with LPA).
    # Operates on pre-filtered visibility-relevant diff lines.
    param([string[]] $DiffLines)
    foreach ($line in @($DiffLines)) {
        if ($line -notmatch '^\+') { continue }
        if ($line -match '^\+\s*(//|/\*|\*)') { continue }
        if ($line -match '\.Add(Singleton|Scoped|Transient|HostedService)\b') { return $true }
        if ($line -match '\bservices\.Add|\bServices\.Add|\bbuilder\.Services\b') { return $true }
        # Anchor each attribute token on a word boundary so a longer name that merely starts with one
        # (e.g. [FromKeyedServicesRegistry]) does not false-positive; [FromKeyedServices(...)] args still match.
        if ($line -match '\[Inject\b|\[FromServices\b|\[FromKeyedServices\b') { return $true }
    }
    return $false
}

function Get-LedgerFieldValue {
    # First value for a `key: value` line. With -ParentKey, restrict the match to lines INSIDE that parent
    # block (the deeper-indented lines after the `<ParentKey>:` header, until a line at the parent's indent
    # or shallower closes it). This is required because some keys (notably library-restructure) appear under
    # MULTIPLE parent blocks (pre-impl-trigger-detections AND pre-impl-playbook-decisions); a flat first-match
    # would read the wrong block's value.
    param([string[]] $LedgerLines, [string] $Key, [string] $ParentKey)
    $regex = '^\s*' + [regex]::Escape($Key) + ':\s*(.*\S)\s*$'
    if (-not $ParentKey) {
        foreach ($line in @($LedgerLines)) { if ($line -match $regex) { return $Matches[1] } }
        return $null
    }
    $parentRegex = '^(\s*)' + [regex]::Escape($ParentKey) + ':\s*$'
    $parentIndent = -1
    foreach ($line in @($LedgerLines)) {
        if ($parentIndent -lt 0) {
            if ($line -match $parentRegex) { $parentIndent = $Matches[1].Length }
            continue
        }
        if ($line -match '^(\s*)\S' -and $Matches[1].Length -le $parentIndent) { return $null }
        if ($line -match $regex) { return $Matches[1] }
    }
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
        $libRestructure = Get-LedgerFieldValue -LedgerLines $LedgerLines -Key 'library-restructure' -ParentKey 'pre-impl-playbook-decisions'
        if ($libRestructure -and $libRestructure -match '^\s*not-required-trigger-not-detected') {
            $violations += "structural-hygiene: a net-new cohesive slice is present but pre-impl-playbook-decisions.library-restructure is 'not-required-trigger-not-detected' - must be 'invoked' or 'required-but-skipped: <re-confirmation>'."
        }
    }

    if (Test-VisibilityDeltaSignal -DiffLines $relevantDiffLines) {
        if (-not (Test-FieldJustified (Get-LedgerFieldValue -LedgerLines $LedgerLines -Key 'touched-file-LPA'))) {
            $violations += "structural-hygiene: a visibility-widening signal (added exposed declaration / InternalsVisibleTo) is present in code but the LEDGER 'touched-file-LPA' field is absent/bare/uncited - record 'ran (...)' or 'N/A - <playbook>:<line>'."
        }
    }

    $nonTestIvtTarget = Test-NonTestIvtSignal -DiffLines $relevantDiffLines
    if ($nonTestIvtTarget) {
        $lpaValue = Get-LedgerFieldValue -LedgerLines $LedgerLines -Key 'touched-file-LPA'
        if (-not ($lpaValue -and $lpaValue -match '^\s*ran\s*\([^)]*production-ivt:\s*[^)\s]')) {
            $violations += "structural-hygiene: a non-test InternalsVisibleTo target '$nonTestIvtTarget' was added (a production friend-grant) but the LEDGER 'touched-file-LPA' does not record the deliberate decision - record 'ran (production-ivt: <why a test target / DI-seam / public API is unsuitable>)' (a bare 'ran' / 'N/A' is not valid for a non-test friend-grant)."
        }
    }

    if (Test-DiSignal -DiffLines $relevantDiffLines) {
        if (-not (Test-FieldJustified (Get-LedgerFieldValue -LedgerLines $LedgerLines -Key 'dependency-injection-fit'))) {
            $violations += "structural-hygiene: a dependency-injection registration / injectable signal is present in code but the LEDGER 'dependency-injection-fit' field is absent/bare/uncited - record 'ran (...)' or 'N/A - <playbook>:<line>'."
        }
    }

    return $violations
}

Export-ModuleMember -Function Test-IsCodeFile, Test-IsVisibilityRelevantFile, Get-DomainTokens, Test-CohesiveSliceSignal, Get-VisibilityRelevantDiffLines, Test-VisibilityDeltaSignal, Test-DiSignal, Get-AddedIvtTargets, Test-IsTestAssemblyName, Test-NonTestIvtSignal, Get-LedgerFieldValue, Test-FieldJustified, Get-StructuralHygieneViolations
