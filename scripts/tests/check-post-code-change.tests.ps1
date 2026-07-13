#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Standalone pwsh self-test (Assert-* helpers, not Pester). Run: pwsh -File <this file>

$modulePath = Join-Path $PSScriptRoot '../lib/panel-ledger-helpers.psm1'
Import-Module $modulePath -Force
. (Join-Path $PSScriptRoot 'test-common.ps1')
$checkerPath = Join-Path $PSScriptRoot '../check-post-code-change.ps1'

$script:Fail = 0
$script:Pass = 0

Write-Host ""
Write-Host "=== Test-PathPanelRequired ===" -ForegroundColor Cyan
Assert-True  (Test-PathPanelRequired -Path 'src/Foo.cs')                                  'C# source is panel-required'
Assert-True  (Test-PathPanelRequired -Path 'scripts/check-post-code-change.ps1')          'scripts/ ps1 is panel-required'
Assert-True  (Test-PathPanelRequired -Path 'AGENTS.md')                                   'AGENTS.md is panel-required (governance)'
Assert-True  (Test-PathPanelRequired -Path '.github/playbooks/post-code-change.md')       'playbook .md is panel-required (governance)'
Assert-True  (Test-PathPanelRequired -Path 'profiles/full/profile.template.md')           'profiles/ template is panel-required (governance)'
Assert-True  (Test-PathPanelRequired -Path 'setup.sh')                                     'setup.sh is panel-required'
Assert-True  (Test-PathPanelRequired -Path 'sub/dir/app.ts')                               'nested TS is panel-required'
Assert-False (Test-PathPanelRequired -Path 'README.md')                                    'README.md is NOT panel-required (pure docs)'
Assert-False (Test-PathPanelRequired -Path 'docs/guide.md')                                'docs/ .md is NOT panel-required'
Assert-False (Test-PathPanelRequired -Path 'notes.txt')                                    'plain .txt is NOT panel-required'
Assert-False (Test-PathPanelRequired -Path '.github/pr-quality-gate/audits/post-code-change-last.md') 'the receipt itself is EXCLUDED (no self-trip)'
Assert-False (Test-PathPanelRequired -Path '.github/pr-quality-gate/audits/last.md')       'comment-audit receipt is EXCLUDED too'
Assert-True  (Test-PathPanelRequired -Path '.github\workflows\ci.yml')                      'backslash path normalized + governed'
Assert-True  (Test-PathPanelRequired -Path '.githooks/pre-commit')                          '.githooks/ enforcement hook is panel-required (governance; cannot self-bypass)'
Assert-True  (Test-PathPanelRequired -Path 'src/App.csproj')                                'csproj build/project file is panel-required'
Assert-True  (Test-PathPanelRequired -Path 'Directory.Packages.props')                      'MSBuild .props is panel-required'
Assert-True  (Test-PathPanelRequired -Path '.gitattributes')                                '.gitattributes is governance/panel-required'
Assert-True  (Test-PathPanelRequired -Path '.gitignore')                                    '.gitignore is governance/panel-required'
Assert-True  (Test-PathPanelRequired -Path '.github/copilot-instructions.md')               'consumer copilot-instructions.md is governance/panel-required'

Write-Host ""
Write-Host "=== Get-PanelRequired (any-path) ===" -ForegroundColor Cyan
Assert-True  (Get-PanelRequired -ChangedPaths @('README.md','src/Foo.cs'))                 'mixed docs+code -> required'
Assert-False (Get-PanelRequired -ChangedPaths @('README.md','docs/x.md'))                  'docs-only -> not required'
Assert-False (Get-PanelRequired -ChangedPaths @('.github/pr-quality-gate/audits/post-code-change-last.md')) 'receipt-only -> not required (self-trip guard)'
Assert-False (Get-PanelRequired -ChangedPaths @())                                          'empty changeset -> not required'

Write-Host ""
Write-Host "=== Test-PanelLedger ===" -ForegroundColor Cyan
function New-Ledger {
    param([string] $ParentSha = '1234567890abcdef1234567890abcdef12345678', [string] $Subject = 'do a thing',
          [string] $Panel = 'ran, unanimous', [string] $Build = 'passed', [string] $Tests = 'passed, 10/10',
          [string] $PrePanel = 'ran, unanimous', [string] $G5 = 'not-applicable')
    return @(
        "parent_sha: $ParentSha",
        "commit_subject: $Subject",
        'POST-CODE-CHANGE LEDGER',
        '  gates:'
    ) + (Get-ValidPreRows -PrePanel $PrePanel -G5 $G5) + @(
        "    post-code-change-panel: $Panel"
    ) + (Get-ValidPanelTranscript) + @(
        "    build: $Build",
        "    tests: $Tests"
    )
}

$r = Test-PanelLedger -LedgerLines (New-Ledger) -ExpectedParentSha '1234567890abcdef1234567890abcdef12345678' -GovernanceTier 1
Assert-True $r.Valid 'panel-required + ran,unanimous + fresh parent -> valid'

$bomLedger = @(New-Ledger); $bomLedger[0] = [char]0xFEFF + $bomLedger[0]
$r = Test-PanelLedger -LedgerLines $bomLedger -ExpectedParentSha '1234567890abcdef1234567890abcdef12345678' -GovernanceTier 1
Assert-True $r.Valid 'leading UTF-8 BOM on the first ledger line is tolerated (parent_sha still matches)'

$r = Test-PanelLedger -LedgerLines (New-Ledger -Panel 'N/A: docs-only') -ExpectedParentSha '1234567890abcdef1234567890abcdef12345678' -GovernanceTier 1
Assert-False $r.Valid 'panel-required + N/A -> INVALID (the non-bypassable rule)'

$r = Test-PanelLedger -LedgerLines (New-Ledger -Panel 'N/A: no code change') -ExpectedParentSha '1234567890abcdef1234567890abcdef12345678' -GovernanceTier 0
Assert-True $r.Valid 'NOT panel-required + N/A -> valid'

$r = Test-PanelLedger -LedgerLines (New-Ledger -Panel 'N/A') -ExpectedParentSha '1234567890abcdef1234567890abcdef12345678' -GovernanceTier 0
Assert-False $r.Valid 'NOT panel-required + bare N/A (no reason) -> INVALID (requires N/A: <reason>)'

$r = Test-PanelLedger -LedgerLines (New-Ledger -ParentSha 'fedcba0987654321fedcba0987654321fedcba09') -ExpectedParentSha '1234567890abcdef1234567890abcdef12345678' -GovernanceTier 1
Assert-False $r.Valid 'mismatched parent_sha -> INVALID (stale)'

$fullSha = 'a1b2c3d4e5f60718293041526374859607a8b9c0'
$r = Test-PanelLedger -LedgerLines (New-Ledger -ParentSha $fullSha) -ExpectedParentSha $fullSha -GovernanceTier 1
Assert-True $r.Valid 'full 40-char parent_sha exactly matching expected -> valid'
$r = Test-PanelLedger -LedgerLines (New-Ledger -ParentSha $fullSha.Substring(0,7)) -ExpectedParentSha $fullSha -GovernanceTier 1
Assert-False $r.Valid '7-char prefix of the full expected parent_sha -> INVALID (exact 40-char binding; no prefix match)'

$r = Test-PanelLedger -LedgerLines (New-Ledger -ParentSha 'fedcba0987654321fedcba0987654321fedcba09') -ExpectedParentSha $fullSha -GovernanceTier 1
Assert-False $r.Valid '7-char of a DIFFERENT sha vs full expected -> INVALID'

$r = Test-PanelLedger -LedgerLines (New-Ledger -Panel 'ran, unanimous' -Build 'failed: CS1002') -ExpectedParentSha '1234567890abcdef1234567890abcdef12345678' -GovernanceTier 1
Assert-False $r.Valid 'build failed -> INVALID'

$r = Test-PanelLedger -LedgerLines (New-Ledger -Build 'Failed: CS1002') -ExpectedParentSha '1234567890abcdef1234567890abcdef12345678' -GovernanceTier 1
Assert-False $r.Valid 'build Failed (capitalized) -> INVALID (case-insensitive failure detection)'

$r = Test-PanelLedger -LedgerLines (New-Ledger -Panel 'ran, unanimous extra') -ExpectedParentSha '1234567890abcdef1234567890abcdef12345678' -GovernanceTier 1
Assert-False $r.Valid 'panel value with trailing text -> INVALID (end-anchored)'

$r = Test-PanelLedger -LedgerLines (New-Ledger -Tests 'failed: 2/10') -ExpectedParentSha '1234567890abcdef1234567890abcdef12345678' -GovernanceTier 1
Assert-False $r.Valid 'tests failed -> INVALID'

$r = Test-PanelLedger -LedgerLines (New-Ledger -Build 'skipped') -ExpectedParentSha '1234567890abcdef1234567890abcdef12345678' -GovernanceTier 1
Assert-False $r.Valid 'build unknown value (skipped) -> INVALID (fail-closed allowlist)'

$r = Test-PanelLedger -LedgerLines (New-Ledger -Build 'passsed') -ExpectedParentSha '1234567890abcdef1234567890abcdef12345678' -GovernanceTier 1
Assert-False $r.Valid 'build typo (passsed) -> INVALID (fail-closed allowlist)'

$r = Test-PanelLedger -LedgerLines (New-Ledger -Build 'N/A: no compile step') -ExpectedParentSha '1234567890abcdef1234567890abcdef12345678' -GovernanceTier 1
Assert-True $r.Valid 'build N/A: <reason> -> valid'

$r = Test-PanelLedger -LedgerLines (New-Ledger -Tests 'skipped') -ExpectedParentSha '1234567890abcdef1234567890abcdef12345678' -GovernanceTier 1
Assert-False $r.Valid 'tests unknown value (skipped) -> INVALID (fail-closed allowlist)'

$r = Test-PanelLedger -LedgerLines (New-Ledger -Tests 'N/A: no test suite') -ExpectedParentSha '1234567890abcdef1234567890abcdef12345678' -GovernanceTier 1
Assert-True $r.Valid 'tests N/A: <reason> -> valid'

Assert-Equal '4b825dc642cb6eb9a060e54bf8d69288fbee4904' (Get-GitEmptyTreeSha) 'Get-GitEmptyTreeSha returns the canonical empty-tree SHA (single source, no script duplicate)'

$r = Test-PanelLedger -LedgerLines (New-Ledger -Panel 'user-waived: "skip it"') -ExpectedParentSha '1234567890abcdef1234567890abcdef12345678' -GovernanceTier 1
Assert-False $r.Valid 'panel-required + OLD free-text user-waived -> INVALID (tightened: needs panel-waive-acknowledged token + ref)'

$r = Test-PanelLedger -LedgerLines (New-Ledger -Panel 'user-waived: "panel-waive-acknowledged" ref:turn-42') -ExpectedParentSha '1234567890abcdef1234567890abcdef12345678' -GovernanceTier 1
Assert-True $r.Valid 'panel-required + tightened user-waived (panel-waive-acknowledged token + ref) -> valid'

$r = Test-PanelLedger -LedgerLines (New-Ledger -Panel 'user-waived: "no close') -ExpectedParentSha '1234567890abcdef1234567890abcdef12345678' -GovernanceTier 1
Assert-False $r.Valid 'panel-required + user-waived missing closing quote -> INVALID'

$r = Test-PanelLedger -LedgerLines (New-Ledger -Panel '<ran, unanimous | N/A>') -ExpectedParentSha '1234567890abcdef1234567890abcdef12345678' -GovernanceTier 1
Assert-False $r.Valid 'unsubstituted placeholder panel value -> INVALID'

$r = Test-PanelLedger -LedgerLines (New-Ledger -Panel 'user-waived: "panel-waive-acknowledged" ref:<call-ref>') -ExpectedParentSha '1234567890abcdef1234567890abcdef12345678' -GovernanceTier 1
Assert-False $r.Valid 'panel-required + user-waived with UNSUBSTITUTED ref:<call-ref> placeholder -> INVALID (fail-closed)'

$r = Test-PanelLedger -LedgerLines (New-Ledger -Panel 'user-waived: "panel-waive-acknowledged" ref:<ask_user-call-ref>') -ExpectedParentSha '1234567890abcdef1234567890abcdef12345678' -GovernanceTier 1
Assert-False $r.Valid 'panel-required + user-waived with the post-code-change.md template ref:<ask_user-call-ref> placeholder -> INVALID'

$r = Test-PanelLedger -LedgerLines (New-Ledger -Panel 'N/A: <reason>') -ExpectedParentSha '1234567890abcdef1234567890abcdef12345678' -GovernanceTier 0
Assert-False $r.Valid 'non-panel-required + N/A with UNSUBSTITUTED <reason> placeholder -> INVALID (embedded-placeholder fail-closed)'

$r = Test-PanelLedger -LedgerLines (New-Ledger -Panel 'user-waived: "panel-waive-acknowledged" ref:turn-42') -ExpectedParentSha '1234567890abcdef1234567890abcdef12345678' -GovernanceTier 1
Assert-True $r.Valid 'panel-required + user-waived with a real substituted ref (no angle brackets) -> still valid (no false-reject)'

$missingPanel = @('parent_sha: 1234567890abcdef1234567890abcdef12345678','commit_subject: x','  build: passed','  tests: passed, 1/1')
$r = Test-PanelLedger -LedgerLines $missingPanel -ExpectedParentSha '1234567890abcdef1234567890abcdef12345678' -GovernanceTier 1
Assert-False $r.Valid 'missing post-code-change-panel row -> INVALID'

$r = Test-PanelLedger -LedgerLines @('commit_subject: x','  post-code-change-panel: ran, unanimous','  build: passed','  tests: passed, 1/1') -ExpectedParentSha '1234567890abcdef1234567890abcdef12345678' -GovernanceTier 1
Assert-False $r.Valid 'missing parent_sha -> INVALID'

$withExtras = @(
    'parent_sha: 1234567890abcdef1234567890abcdef12345678','commit_subject: x','POST-CODE-CHANGE LEDGER','  gates:',
    '    hygiene-cleanup: ran','    emdash-scan: ran, clean','    some-future-row: whatever'
) + (Get-ValidPreRows) + @(
    '    post-code-change-panel: ran, unanimous'
) + (Get-ValidPanelTranscript) + @('    build: passed','    tests: passed, 9/9')
$r = Test-PanelLedger -LedgerLines $withExtras -ExpectedParentSha '1234567890abcdef1234567890abcdef12345678' -GovernanceTier 1
Assert-True $r.Valid 'unknown/extra §2B rows are ignored (parser is structurally opaque)'

Write-Host ""
Write-Host "=== panel-transcript floor (full-slate enforcement) ===" -ForegroundColor Cyan
$tParent = '1234567890abcdef1234567890abcdef12345678'
function New-LedgerWithTranscript {
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $Transcript)
    return @("parent_sha: $tParent", 'commit_subject: t', 'POST-CODE-CHANGE LEDGER', '  gates:') + (Get-ValidPreRows) + @(
        '    post-code-change-panel: ran, unanimous') + $Transcript + @('    build: passed', '    tests: passed, 1/1')
}
function Test-TranscriptValid {
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $Transcript)
    return (Test-PanelLedger -LedgerLines (New-LedgerWithTranscript $Transcript) -ExpectedParentSha $tParent -GovernanceTier 1).Valid
}
$HDR = '    panel-transcript:'
$duckC = '      - slot:duck model:claude-opus-4.8 family:claude role:rubber-duck tier:heavy verdict:CODE_REVIEW_READY rounds:2'
$crC   = '      - slot:crc model:claude-opus-4.8 family:claude role:code-review tier:heavy verdict:CODE_REVIEW_READY rounds:2'
$crG1  = '      - slot:crg1 model:gpt-5.5 family:gpt role:code-review tier:heavy verdict:CODE_REVIEW_READY rounds:2'
$crG2  = '      - slot:crg2 model:gpt-5.3-codex family:gpt role:code-review tier:heavy verdict:CODE_REVIEW_READY rounds:2'
$crGem = '      - slot:crgem model:gemini-3.1-pro-preview family:gemini role:code-review tier:heavy verdict:CODE_REVIEW_READY rounds:2'
$find  = '      - findings: closed a fail-open and tightened a regex'

Assert-True  (Test-TranscriptValid @($HDR, $duckC, $crC, $crG1, $crG2, $crGem, $find)) 'valid full slate (2 DISTINCT GPT models) + findings -> valid (distinct-by-slot does not false-reject the happy path)'
Assert-False (Test-TranscriptValid @()) 'ran, unanimous with NO panel-transcript block -> INVALID'
Assert-False (Test-TranscriptValid @($HDR, $find)) 'panel-transcript header + findings but no reviewer lines -> INVALID'
Assert-False (Test-TranscriptValid @($HDR, $duckC, $crC, $crG1, $crG2, $find)) 'transcript missing the Gemini family -> INVALID'
Assert-False (Test-TranscriptValid @($HDR, $duckC, $crC, $crG1, $crGem, $find)) 'transcript with only 1 GPT reviewer -> INVALID (full floor needs >= 2 GPT)'
Assert-False (Test-TranscriptValid @($HDR, $duckC, $crG1, $crGem, $find)) 'transcript with only 1 code-review (and 3 reviewers) -> INVALID'
$dup = @($HDR, $duckC, $crC, $crG1, $crG2, $crGem, $find, ($crG2 -replace 'verdict:CODE_REVIEW_READY', 'verdict:NEEDS_REWORK'))
Assert-False (Test-TranscriptValid $dup) 'duplicate reviewer slot (a dup carrying NEEDS_REWORK cannot be masked) -> INVALID'
$rework = @($HDR, $duckC, $crC, $crG1, $crG2, ($crGem -replace 'verdict:CODE_REVIEW_READY', 'verdict:NEEDS_REWORK'), $find)
Assert-False (Test-TranscriptValid $rework) 'a NEEDS_REWORK verdict (floor path, not grammar) -> INVALID (panel not converged)'
$rounds0 = @($HDR, ($duckC -replace 'rounds:2', 'rounds:0'), $crC, $crG1, $crG2, $crGem, $find)
Assert-False (Test-TranscriptValid $rounds0) 'rounds:0 -> INVALID (>= 1 required, distinct from malformed)'
$bigRounds = @($HDR, ($duckC -replace 'rounds:2', 'rounds:1000'), $crC, $crG1, $crG2, $crGem, $find)
Assert-False (Test-TranscriptValid $bigRounds) 'rounds:1000 (4 digits) -> INVALID (malformed; bounded so no [int] overflow)'
$allLight = @($HDR, $duckC, $crC, $crG1, $crG2, $crGem, $find) -replace 'tier:heavy', 'tier:light'
Assert-False (Test-TranscriptValid $allLight) 'all light-tier slate -> INVALID (full floor needs >= 1 heavy)'
$malformed = @($HDR, $duckC, $crC, $crG1, $crG2, $find, '      - slot:x family:gpt role:code-review verdict:CODE_REVIEW_READY')
Assert-False (Test-TranscriptValid $malformed) 'a malformed reviewer line (missing fields) -> INVALID'
Assert-False (Test-TranscriptValid @($HDR, $duckC, $crC, $crG1, $crG2, $crGem)) 'full slate but NO findings line -> INVALID (exactly-1 findings required)'
Assert-False (Test-TranscriptValid @($HDR, $duckC, $crC, $crG1, $crG2, $crGem, $find, ($find -replace 'closed', 'also'))) 'TWO findings lines -> INVALID (exactly-1)'
Assert-False (Test-TranscriptValid @($HDR, $duckC, $crC, $crG1, $crG2, $crGem, '      - findings:    ')) 'empty findings line -> INVALID'
Assert-False (Test-TranscriptValid @($HDR, $duckC, $crC, $crG1, $crG2, $crGem, '      - findings: <one-line-summary>')) 'whole-value placeholder findings -> INVALID (fail-closed template)'
Assert-True  (Test-TranscriptValid @($HDR, $duckC, $crC, $crG1, $crG2, $crGem, '      - findings: fixed <Foo>.Create paramName leak')) 'findings text containing inner <...> (a generic/type) -> VALID (whole-value guard, not contains)'
$outOfBlock = @("parent_sha: $tParent", 'commit_subject: t', 'POST-CODE-CHANGE LEDGER', '  gates:',
    '    post-code-change-panel: ran, unanimous', '    panel-transcript:', '    build: passed', '    tests: passed, 1/1',
    '  appendix:', $duckC, $crC, $crG1, $crG2, $crGem)
Assert-False (Test-PanelLedger -LedgerLines $outOfBlock -ExpectedParentSha $tParent -GovernanceTier 1).Valid 'slot lines OUTSIDE the panel-transcript block do not satisfy the floor -> INVALID'

$playbook = Join-Path $PSScriptRoot '../../.github/playbooks/post-code-change.md'
if (Test-Path $playbook) {
    $pbLines = @(Get-Content -LiteralPath $playbook)
    Assert-True ([bool]((@($pbLines | Where-Object { $_ -cmatch '^\s*panel-transcript:\s*$' })).Count -ge 1)) 'post-code-change.md ships a BARE panel-transcript: header (verbatim copy is detected)'
    $tmplSlot = @($pbLines | Where-Object { $_ -cmatch '^\s*-\s*slot:' })
    $tmplBlock = @('    panel-transcript:') + $tmplSlot
    Assert-False (Test-TranscriptValid $tmplBlock) 'the shipped post-code-change.md transcript template (placeholders) -> INVALID (stale-template fail-closed)'
    $tmplFind = @($pbLines | Where-Object { $_ -cmatch '^\s*-\s*findings:' })
    Assert-True ([bool]($tmplFind.Count -ge 2)) 'post-code-change.md ships a `- findings:` line in BOTH transcript templates'
    $validSlate = @($duckC, $crC, $crG1, $crG2, $crGem)
    foreach ($tf in $tmplFind) {
        Assert-False (Test-TranscriptValid (@($HDR) + $validSlate + @($tf))) "shipped findings template '$(([string]$tf).Trim())' + valid slate -> INVALID (whole-value <...> fail-closed)"
    }
}

Write-Host ""
Write-Host "=== PRE-EDIT SENTINEL enum <-> LEDGER pre-code-change-panel row (drift guard) ===" -ForegroundColor Cyan
$agentsRaw = Get-Content (Join-Path $PSScriptRoot '../../AGENTS.md') -Raw
$sweeps2 = Get-Content (Join-Path $PSScriptRoot '../../.github/playbooks/review-workflow-gates-sweeps.md') -Raw
Assert-True ($agentsRaw -match 'PRE-EDIT SENTINEL') 'AGENTS.md defines the PRE-EDIT SENTINEL'
Assert-True ($agentsRaw -match [regex]::Escape('pre_impl_panel=<ran:unanimous|user-waived:ref:<call-ref>|na:not-panel-required>')) 'sentinel pre_impl_panel enum = the fixed 3-value set'
Assert-True ($agentsRaw -match 'NEVER trivial') 'sentinel: governance/instruction artifacts NEVER trivial'
Assert-True ($agentsRaw -match [regex]::Escape('tier-2 forbids `user-waived`/`na`')) 'sentinel: tier-2 forbids user-waived/na'
Assert-True ($sweeps2 -match [regex]::Escape('pre-code-change-panel: <ran, unanimous | user-waived: "panel-waive-acknowledged" ref:<call-ref> | N/A: reason>')) '2B pre-code-change-panel row carries the 3 mapped values (<-> sentinel enum)'

$floor = Get-PanelSlateFloor
$pp = Get-Content (Join-Path $PSScriptRoot '../../.github/pr-quality-gate/panel-policy.md') -Raw
Assert-True ($pp -match "$($floor.MinReviewers)\s+reviewers")            "floor MinReviewers=$($floor.MinReviewers) matches panel-policy.md S27-32"
Assert-True ($pp -match "$($floor.MinClaude)\s+Claude\s+family")          "floor MinClaude=$($floor.MinClaude) matches panel-policy.md"
Assert-True ($pp -match "$($floor.MinGpt)\s+GPT\s+family")                "floor MinGpt=$($floor.MinGpt) matches panel-policy.md"
Assert-True ($pp -match "$($floor.MinGemini)\s+Gemini\s+family")          "floor MinGemini=$($floor.MinGemini) matches panel-policy.md"
Assert-True ($pp -match "$($floor.MinRubberDuck)\s+\x60?rubber-duck")     "floor MinRubberDuck=$($floor.MinRubberDuck) matches panel-policy.md"
Assert-True ($pp -match "$($floor.MinCodeReview)\s+\x60?code-review")     "floor MinCodeReview=$($floor.MinCodeReview) matches panel-policy.md"
Assert-True ($pp -match "$($floor.MinHeavy)\s+heavy-tier")                "floor MinHeavy=$($floor.MinHeavy) matches panel-policy.md"

Write-Host ""
Write-Host "=== KV v1 keyset sync (2B grammar <-> worked example) ===" -ForegroundColor Cyan
function Get-KvLedgerBlock {
    param([string] $Path)
    $raw = Get-Content (Join-Path $PSScriptRoot $Path) -Raw
    $m = [regex]::Match($raw, '(?ms)^```\r?\nPOST-CODE-CHANGE LEDGER \(KV v1\)\r?\n(.*?)\r?\n```')
    if (-not $m.Success) { return $null }
    return $m.Groups[1].Value
}
function Get-KvKeySet {
    param([string] $Block)
    $keys = [ordered]@{}
    foreach ($line in ($Block -split "\r?\n")) {
        if ($line -notmatch '^(core|gates)\|') { continue }
        foreach ($segment in ($line -split '\|')) {
            if ($segment -match '^([a-z][a-z0-9-]*)=') { $keys[$matches[1] + '='] = $true }
        }
    }
    return @($keys.Keys)
}
$kvV1FrozenKeys = @('profile=', 'commit=', 'files=', 'hygiene=', 'lpa=', 'vsa=', 'difit=', 'emdash=', 'purge=', 'recurring=', 'priorpr=', 'dry=', 'prepanel=', 'diag=', 'g3=', 'g5=', 'g6=', 'impl=', 'panel=', 'itd=', 'delta-g=', 'comment=', 'build=', 'tests=', 'diff=', 'msg=')
$kvV1Expected = ($kvV1FrozenKeys | Sort-Object) -join ','
$grammarBlock = Get-KvLedgerBlock '../../.github/playbooks/review-workflow-gates-sweeps.md'
$exampleBlock = Get-KvLedgerBlock '../../.github/playbooks/post-code-change.md'
Assert-True ($null -ne $grammarBlock) 'KV v1 grammar block extracted from review-workflow-gates-sweeps.md'
Assert-True ($null -ne $exampleBlock) 'KV v1 worked-example block extracted from post-code-change.md'
$grammarActual = (Get-KvKeySet $grammarBlock | Sort-Object) -join ','
$exampleActual = (Get-KvKeySet $exampleBlock | Sort-Object) -join ','
Assert-True ($grammarActual -eq $kvV1Expected) "2B KV v1 grammar core|/gates| pipe-keyset equals the frozen 26-key contract (got: $grammarActual)"
Assert-True ($exampleActual -eq $kvV1Expected) "post-code-change.md worked KV example core|/gates| pipe-keyset equals the frozen 26-key contract (got: $exampleActual)"

Write-Host ""
Write-Host "=== Governance tier classifier (T2 equivalence + tier-2 self-protection) ===" -ForegroundColor Cyan
foreach ($p in @('AGENTS.md','setup.ps1','setup.sh','.gitattributes','.gitignore','.github/copilot-instructions.md','.github/instructions/x.md','.github/playbooks/post-code-change.md','.github/workflows/ci.yml','.github/pr-quality-gate/panel-policy.md','.githooks/pre-commit','profiles/full/x.md','scripts/foo.ps1','src/Foo.cs','app.ts','x.csproj')) {
    Assert-True ((Get-PathGovernanceTier -Path $p) -ge 1) "T2: $p -> tier>=1 (== old panel-required)"
}
foreach ($p in @('scripts/lib/panel-ledger-helpers.psm1','scripts/lib/audit-note-helpers.psm1','scripts/check-post-code-change.ps1','scripts/check-audit-notes-prepush.ps1','scripts/check-no-panel-artifacts.ps1','.githooks/pre-commit','.githooks/pre-push','.github/pr-quality-gate/panel-policy.md','AGENTS.md','.github/workflows/ci.yml')) {
    Assert-True ((Get-PathGovernanceTier -Path $p) -eq 2) "tier-2 self-protection: $p"
}
foreach ($p in @('.github/playbooks/post-code-change.md','scripts/foo.ps1','src/Foo.cs','app.ts')) { Assert-True ((Get-PathGovernanceTier -Path $p) -eq 1) "tier-1 (panel-required, not safety): $p" }
foreach ($p in @('README.md','docs/g.md','notes.txt','.github/pr-quality-gate/audits/post-code-change-last.md','security-notes.md','mysecurityfile.md')) { Assert-True ((Get-PathGovernanceTier -Path $p) -eq 0) "tier-0/carve-out/false-match: $p" }
Assert-True  (Test-PathPanelRequired -Path 'src/Foo.cs') 'Test-PathPanelRequired derives true from tier'
Assert-False (Test-PathPanelRequired -Path 'README.md') 'Test-PathPanelRequired derives false from tier'
Assert-True ((Get-ChangedGovernanceTier -ChangedPaths @('README.md','src/Foo.cs') -NameStatusLines @()) -eq 1) 'changed tier=1 (mixed docs+code)'
Assert-True ((Get-ChangedGovernanceTier -ChangedPaths @('README.md','scripts/lib/panel-ledger-helpers.psm1') -NameStatusLines @()) -eq 2) 'changed tier=2 (engine touched)'
Assert-True ((Get-ChangedGovernanceTier -ChangedPaths @() -NameStatusLines @()) -eq 0) 'changed tier=0 (empty -> StrictMode-safe)'
Assert-True ((Get-ChangedGovernanceTier -ChangedPaths @('README.md','docs/x.md') -NameStatusLines @()) -eq 0) 'changed tier=0 (docs only)'
Assert-True ((Get-ChangedGovernanceTier -ChangedPaths @('a.txt') -NameStatusLines @("R100`ttests/Old.cs`tnewd/New.cs")) -eq 2) 'rename test-surface migration -> tier 2'

Write-Host ""
Write-Host "=== T1 monotonicity: pre-code-change-panel x governance tier ===" -ForegroundColor Cyan
function PreV { param([string] $PrePanel, [int] $Tier) $g5 = if ($Tier -ge 2) { 'panel-ran' } else { 'not-applicable' }; (Test-PanelLedger -LedgerLines (New-Ledger -PrePanel $PrePanel -G5 $g5) -ExpectedParentSha '1234567890abcdef1234567890abcdef12345678' -GovernanceTier $Tier).Valid }
$WV = 'user-waived: "panel-waive-acknowledged" ref:turn-9'
Assert-True  (PreV 'ran, unanimous' 0) 'tier0: pre ran -> ok'
Assert-True  (PreV $WV 0)              'tier0: pre waive -> ok'
Assert-True  (PreV 'N/A: docs' 0)      'tier0: pre N/A -> ok'
Assert-True  (PreV 'ran, unanimous' 1) 'tier1: pre ran -> ok'
Assert-True  (PreV $WV 1)              'tier1: pre waive -> ok'
Assert-False (PreV 'N/A: docs' 1)      'tier1: pre N/A -> INVALID'
Assert-True  (PreV 'ran, unanimous' 2) 'tier2: pre ran -> ok'
Assert-False (PreV $WV 2)              'tier2: pre waive -> INVALID (safety-critical)'
Assert-False (PreV 'N/A: docs' 2)      'tier2: pre N/A -> INVALID (safety-critical)'
Assert-False (Test-PanelLedger -LedgerLines (New-Ledger -G5 'not-applicable') -ExpectedParentSha '1234567890abcdef1234567890abcdef12345678' -GovernanceTier 2).Valid 'tier2 + safety-critical-eval-G5: not-applicable -> INVALID (gate already knows it IS safety-critical)'
Assert-True  (Test-PanelLedger -LedgerLines (New-Ledger -G5 'panel-ran') -ExpectedParentSha '1234567890abcdef1234567890abcdef12345678' -GovernanceTier 2).Valid 'tier2 + safety-critical-eval-G5: panel-ran -> ok'
Assert-True  (Test-PanelLedger -LedgerLines (New-Ledger -G5 'not-applicable') -ExpectedParentSha '1234567890abcdef1234567890abcdef12345678' -GovernanceTier 1).Valid 'tier1 + safety-critical-eval-G5: not-applicable -> ok (not path-safety-critical)'
Assert-True ((Get-PathGovernanceTier -Path 'src/Payments/Charge.cs') -eq 2) 'payments path -> tier 2 (the path-reducible G5 category from pre-implementation.md L84)'
$P = '1234567890abcdef1234567890abcdef12345678'
$WVp = 'user-waived: "panel-waive-acknowledged" ref:turn-9'
Assert-False (Test-PanelLedger -LedgerLines (New-Ledger -G5 'panel-ran' -Panel $WVp) -ExpectedParentSha $P -GovernanceTier 2).Valid 'tier2: POST panel waive -> INVALID (force-both safety-critical)'
Assert-False (Test-PanelLedger -LedgerLines (New-Ledger -G5 'panel-ran' -Panel 'N/A: docs') -ExpectedParentSha $P -GovernanceTier 2).Valid 'tier2: POST panel N/A -> INVALID (force-both safety-critical)'
Assert-True  (Test-PanelLedger -LedgerLines (New-Ledger -G5 'panel-ran') -ExpectedParentSha $P -GovernanceTier 2).Valid 'tier2: POST panel ran -> ok'
Assert-True  (Test-PanelLedger -LedgerLines (New-Ledger -Panel $WVp) -ExpectedParentSha $P -GovernanceTier 1).Valid 'tier1: POST panel waive -> still ok (post not forced below tier 2)'
Assert-False (Test-PanelLedger -LedgerLines (@(New-Ledger) | ForEach-Object { $_ -replace 'approach-selection-G3: fix-cause', 'approach-selection-G3: document-symptom: "no close' }) -ExpectedParentSha $P -GovernanceTier 1).Valid 'G3 document-symptom missing closing quote -> INVALID (end-anchored)'
$g6noClose = @(New-Ledger) | ForEach-Object { $_ -replace 'implementation-planning: no$', 'implementation-planning: yes' -replace 'implementation-planning: not-required-trigger-not-detected', 'implementation-planning: required-but-skipped: "no close' }
Assert-False (Test-PanelLedger -LedgerLines $g6noClose -ExpectedParentSha $P -GovernanceTier 1).Valid 'G6 required-but-skipped missing closing quote -> INVALID (end-anchored)'
Assert-False (Test-PanelLedger -LedgerLines (@(New-Ledger) | ForEach-Object { $_ -replace 'approach-selection-G3: fix-cause', 'approach-selection-G3: document-symptom: ""' }) -ExpectedParentSha $P -GovernanceTier 1).Valid 'G3 document-symptom EMPTY quotes -> INVALID (non-empty rationale required)'
$g6empty = @(New-Ledger) | ForEach-Object { $_ -replace 'implementation-planning: no$', 'implementation-planning: yes' -replace 'implementation-planning: not-required-trigger-not-detected', 'implementation-planning: required-but-skipped: ""' }
Assert-False (Test-PanelLedger -LedgerLines $g6empty -ExpectedParentSha $P -GovernanceTier 1).Valid 'G6 required-but-skipped EMPTY quotes -> INVALID (non-empty rationale required)'

Write-Host ""
Write-Host "=== Pre rows: Guard1 placeholder + anchored enum + required-when-tier>=1 ===" -ForegroundColor Cyan
function Mut { param([string] $Find, [string] $Repl, [int] $Tier) (Test-PanelLedger -LedgerLines (@(New-Ledger) | ForEach-Object { $_ -replace [regex]::Escape($Find), $Repl }) -ExpectedParentSha '1234567890abcdef1234567890abcdef12345678' -GovernanceTier $Tier).Valid }
function Drop { param([string] $Key, [int] $Tier) (Test-PanelLedger -LedgerLines (@(New-Ledger) | Where-Object { $_ -notmatch ('^\s*' + [regex]::Escape($Key) + ':') }) -ExpectedParentSha '1234567890abcdef1234567890abcdef12345678' -GovernanceTier $Tier).Valid }
Assert-False (Mut 'diagnosis-repro-ref: reproduction-locked: tests/Repro.cs' 'diagnosis-repro-ref: <path>' 1) 'diagnosis-repro-ref: <path> placeholder -> INVALID (round-3 guard on new row)'
Assert-True  (Mut 'diagnosis-repro-ref: reproduction-locked: tests/Repro.cs' 'diagnosis-repro-ref: benchmark: 1.2s to 0.4s' 1) 'diagnosis-repro-ref benchmark -> ok'
Assert-True  (Mut 'diagnosis-repro-ref: reproduction-locked: tests/Repro.cs' 'diagnosis-repro-ref: N/A: pure refactor' 1) 'diagnosis-repro-ref N/A -> ok'
Assert-False (Mut 'approach-selection-G3: fix-cause' 'approach-selection-G3: maybe-later' 1) 'approach-selection-G3 unknown enum -> INVALID'
Assert-True  (Mut 'approach-selection-G3: fix-cause' 'approach-selection-G3: document-symptom: "out of scope"' 1) 'G3 document-symptom (quoted) -> ok'
Assert-False (Mut 'safety-critical-eval-G5: not-applicable' 'safety-critical-eval-G5: safety-critical-confirmed-skip: ref:<x>' 1) 'G5 placeholder ref -> INVALID'
Assert-True  (Mut 'safety-critical-eval-G5: not-applicable' 'safety-critical-eval-G5: safety-critical-confirmed-skip: ref:turn-3' 1) 'G5 real skip ref -> ok'
Assert-False (Mut 'approach-selection-G3: fix-cause' 'approach-selection-G3: <approach or document-symptom>' 1) 'G3 whole-template placeholder -> INVALID (quote-aware guard)'
Assert-False (Mut 'approach-selection-G3: fix-cause' 'approach-selection-G3: document-symptom: <reason>' 1) 'G3 unquoted sub-placeholder -> INVALID (quote-aware guard)'
Assert-False (Mut 'approach-selection-G3: fix-cause' 'approach-selection-G3: document-symptom: "<reason>"' 1) 'G3 quoted bare-placeholder note -> INVALID (quote-aware guard)'
Assert-True  (Mut 'approach-selection-G3: fix-cause' 'approach-selection-G3: document-symptom: "Fix <T> handling"' 1) 'G3 quoted note with <T> type syntax -> ok (G3 relaxation, no longer over-rejected)'
Assert-True  (Mut 'approach-selection-G3: fix-cause' 'approach-selection-G3: document-symptom: "<A> to <B>"' 1) 'G3 quoted multi-bracket note -> ok (G3 relaxation)'
Assert-False (Drop 'diagnosis-repro-ref' 1) 'diagnosis-repro-ref missing @ tier1 -> INVALID'
Assert-False (Drop 'approach-selection-G3' 1) 'approach-selection-G3 missing @ tier1 -> INVALID'
Assert-False (Drop 'pre-code-change-panel' 1) 'pre-code-change-panel missing @ tier1 -> INVALID'
Assert-True  (Drop 'diagnosis-repro-ref' 0) 'diagnosis-repro-ref missing @ tier0 -> ok (not required)'
Assert-False (Test-PanelLedger -LedgerLines (@(New-Ledger -PrePanel $WV) | Where-Object { $_ -notmatch '^\s*safety-critical-eval-G5:' }) -ExpectedParentSha '1234567890abcdef1234567890abcdef12345678' -GovernanceTier 1).Valid 'G5 required even when pre-panel is waived -> INVALID'
$preWrongVerdict = @(New-Ledger) | ForEach-Object { $_ -replace 'DESIGN_READY', 'CODE_REVIEW_READY' }
Assert-False (Test-PanelLedger -LedgerLines $preWrongVerdict -ExpectedParentSha '1234567890abcdef1234567890abcdef12345678' -GovernanceTier 1).Valid 'pre-transcript with CODE_REVIEW_READY (not DESIGN_READY) -> INVALID'

Write-Host ""
Write-Host "=== G6 sub-line validation (MF7: both trigger directions) ===" -ForegroundColor Cyan
function G6V { param([string[]] $Lines, [int] $Tier = 1) (Test-PanelLedger -LedgerLines $Lines -ExpectedParentSha '1234567890abcdef1234567890abcdef12345678' -GovernanceTier $Tier).Valid }
function G6Sub { param([string] $Find, [string] $Repl) @(New-Ledger) | ForEach-Object { $_ -replace [regex]::Escape($Find), $Repl } }
Assert-True  (G6V (@(New-Ledger)) 1) 'baseline G6 (all triggers no) -> valid @ tier1'
Assert-False (G6V (G6Sub '      design-exploration: not-applicable' '      design-exploration: invoked')) 'OFFERED trigger=no but decision=invoked -> INVALID (must be not-applicable)'
$g6yesNoDec = @(New-Ledger) | ForEach-Object { $_ -replace 'design-exploration: no$', 'design-exploration: yes' }
Assert-False (G6V $g6yesNoDec) 'OFFERED trigger=yes but decision still not-applicable -> INVALID (silent-downgrade)'
$g6yesInv = @(New-Ledger) | ForEach-Object { $_ -replace 'design-exploration: no$', 'design-exploration: yes' -replace 'design-exploration: not-applicable$', 'design-exploration: invoked' }
Assert-True  (G6V $g6yesInv) 'OFFERED trigger=yes + decision=invoked -> ok'
Assert-False (G6V (G6Sub '      implementation-planning: not-required-trigger-not-detected' '      implementation-planning: offered-and-declined: "x"')) 'REQUIRED class with offered-and-declined -> INVALID'
Assert-False (G6V (G6Sub '      implementation-planning: not-required-trigger-not-detected' '      implementation-planning: not-applicable')) 'REQUIRED class with not-applicable -> INVALID (silent-bypass)'
Assert-False (G6V (G6Sub '      project-vocabulary: no' '      project-vocabulary: maybe')) 'trigger value not yes|no -> INVALID'
Assert-False (G6V (G6Sub '      design-exploration: not-applicable' '      design-exploration: <decision>')) 'G6 decision placeholder -> INVALID'
Assert-False (G6V (G6Sub '      performance-comparison: N/A: trigger not detected' '      performance-comparison: bogus')) 'playbook-invocations bad value -> INVALID'
$g6reqYes = @(New-Ledger) | ForEach-Object { $_ -replace 'implementation-planning: no$', 'implementation-planning: yes' }
Assert-False (G6V $g6reqYes) 'REQUIRED trigger=yes + decision=not-required-trigger-not-detected -> INVALID (trigger-coupling)'
$g6reqYesOk = @(New-Ledger) | ForEach-Object { $_ -replace 'implementation-planning: no$', 'implementation-planning: yes' -replace 'implementation-planning: not-required-trigger-not-detected', 'implementation-planning: invoked' }
Assert-True  (G6V $g6reqYesOk) 'REQUIRED trigger=yes + decision=invoked -> ok'
Assert-True  (G6V (@(New-Ledger) | Where-Object { $_ -notmatch '^\s*pre-impl-trigger-detections:' -and $_ -notmatch '^\s*project-vocabulary:' }) 0) 'G6 not required @ tier0'

Write-Host ""
Write-Host "=== implementation-checkpoint (D3 co-presence node; gated on the DESIGN panel having run) ===" -ForegroundColor Cyan
function ICErrs { param([string[]] $Block) @(Test-LedgerImplementationCheckpoint -LedgerLines $Block).Count }
Assert-True  ((ICErrs @('implementation-checkpoint:','  status: complete','  design_ready: yes','  diff_matches_design: yes')) -eq 0) 'checkpoint complete/yes/yes -> 0 errors'
Assert-True  ((ICErrs @('implementation-checkpoint:','  status: complete','  design_ready: yes','  diff_matches_design: diverged:"review feedback reshaped the API"')) -eq 0) 'checkpoint diff_matches_design=diverged disclosure -> 0 errors'
Assert-True  ((ICErrs @('post-code-change-panel: ran, unanimous')) -ge 1) 'checkpoint block absent -> error (co-presence)'
Assert-True  ((ICErrs @('implementation-checkpoint:','  status: wip','  design_ready: yes','  diff_matches_design: yes')) -ge 1) 'checkpoint status!=complete -> error'
Assert-True  ((ICErrs @('implementation-checkpoint:','  status: complete','  design_ready: no','  diff_matches_design: yes')) -ge 1) 'checkpoint design_ready!=yes -> error'
Assert-True  ((ICErrs @('implementation-checkpoint:','  status: complete','  design_ready: yes','  diff_matches_design: no')) -ge 1) 'checkpoint diff_matches_design bare "no" (not a disclosure) -> error'
Assert-True  ((ICErrs @('implementation-checkpoint:','  status: complete','  design_ready: yes','  diff_matches_design: diverged:""')) -ge 1) 'checkpoint diverged with EMPTY note -> error'
Assert-True  ((ICErrs @('implementation-checkpoint:','  status: complete','  design_ready: yes','  diff_matches_design: diverged:"Fix <Foo> contract"')) -eq 0) 'checkpoint diverged note with an angle-bracket type substring -> 0 errors (PR#18: <Foo> is content, not a placeholder)'
Assert-True  ((ICErrs @('implementation-checkpoint:','  status: complete','  design_ready: yes','  diff_matches_design: diverged:"<Foo> remapped to <Bar>"')) -eq 0) 'checkpoint diverged multi-token note bracketed at both ends -> 0 errors (note-check uses [^>]*, no greedy ^<.*>$ false-reject)'
Assert-True  ((ICErrs @('implementation-checkpoint:','  status: complete','  design_ready: yes','  diff_matches_design: diverged:"renamed "OldName" to "NewName""')) -eq 0) 'checkpoint diverged note containing quotes -> 0 errors (parser not truncated at inner quote; PR#89 Copilot sibling)'
Assert-True  ((ICErrs @('implementation-checkpoint:','  status: complete','  design_ready: yes','  diff_matches_design: <yes | diverged:"<one-line what+why>">')) -ge 1) 'checkpoint diff_matches_design unsubstituted whole-field template -> error (placeholder; greedy ^<.*>$ catches the inner >)'
Assert-True  ((ICErrs @('implementation-checkpoint:','  status: complete','  design_ready: yes','  diff_matches_design: diverged:"<one-line what+why>"')) -ge 1) 'checkpoint diverged note that is a bare <...> placeholder -> error (stale-template hole stays closed)'
Assert-True  ((ICErrs @('implementation-checkpoint:','  status: <fill>','  design_ready: yes','  diff_matches_design: yes')) -ge 1) 'checkpoint status placeholder -> error'
Assert-True  ((ICErrs @('implementation-checkpoint:','next-key: x')) -eq 3) 'childless checkpoint block -> 3 per-key absent errors (load-bearing, not the null guard)'
$icTP = '1234567890abcdef1234567890abcdef12345678'
function PLValid { param([string[]] $Lines, [int] $Tier = 1) (Test-PanelLedger -LedgerLines $Lines -ExpectedParentSha $icTP -GovernanceTier $Tier).Valid }
$icBase = @("parent_sha: $icTP", 'commit_subject: x', 'POST-CODE-CHANGE LEDGER', '  gates:')
Assert-True  (PLValid (@(New-Ledger))) 'baseline ledger (design ran, checkpoint present) -> valid'
$noIC = $icBase + (Get-ValidPreRows -OmitImplementationCheckpoint) + @('    post-code-change-panel: ran, unanimous') + (Get-ValidPanelTranscript) + @('    build: passed', '    tests: passed, 1/1')
Assert-False (PLValid $noIC) 'design panel ran but implementation-checkpoint MISSING -> INVALID (trigger fires on the DESIGN panel having run)'
Assert-False (PLValid (@(New-Ledger) | ForEach-Object { $_ -replace 'status: complete', 'status: wip' })) 'full design-ran ledger, checkpoint status!=complete -> INVALID'
$waivedNoIC = $icBase + (Get-ValidPreRows -PrePanel 'user-waived: "panel-waive-acknowledged" ref:t1' -OmitImplementationCheckpoint) + @('    post-code-change-panel: ran, unanimous') + (Get-ValidPanelTranscript) + @('    build: passed', '    tests: passed, 1/1')
Assert-True  (PLValid $waivedNoIC) 'pre-panel user-waived (DESIGN panel NOT ran) + no checkpoint -> valid @ tier1 (trigger does not fire)'

Write-Host ""
Write-Host "=== End-to-end checker (temp git repo) ===" -ForegroundColor Cyan

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("pcc-test-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$AUDIT = '.github/pr-quality-gate/audits/post-code-change-last.md'

function TG {
    & git -C $tmp @args 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "git $($args -join ' ') failed" }
}
function Write-RepoFile { param([string] $Rel, [string[]] $Lines)
    $full = Join-Path $tmp $Rel
    New-Item -ItemType Directory -Path (Split-Path $full) -Force | Out-Null
    Set-Content -LiteralPath $full -Value $Lines -Encoding UTF8 }
function Head { ((& git -C $tmp rev-parse HEAD) | Out-String).Trim() }
function Write-Receipt { param([string] $ParentSha, [string] $Subject = 'change', [string] $Panel = 'ran, unanimous')
    Write-RepoFile -Rel $AUDIT -Lines (New-Ledger -ParentSha $ParentSha -Subject $Subject -Panel $Panel) }
function Invoke-Checker { param([string[]] $ScriptArgs)
    & pwsh -NoProfile -File $checkerPath @ScriptArgs *> $null; return $LASTEXITCODE }

try {
    TG init
    TG config user.email 'test@example.com'
    TG config user.name 'Test'
    TG config commit.gpgsign false
    TG config core.autocrlf false

    Write-RepoFile -Rel 'README.md' -Lines @('# repo')
    Write-RepoFile -Rel 'scripts/check-post-code-change.ps1' -Lines @('# anchor stub')
    TG add -A; TG commit -m 'init'
    $base = Head

    $p1 = Head
    Write-RepoFile -Rel 'src/app.cs' -Lines @('class A {}')
    Write-Receipt -ParentSha $p1 -Subject 'add app'
    TG add -A; TG commit -m 'add app'

    $code = Invoke-Checker -ScriptArgs @('-BaseRef', $base, '-RepoRoot', $tmp)
    Assert-Equal 0 $code 'history walk: first-add commit with a fresh valid receipt is VALIDATED (no bootstrap skip) -> OK'

    $p2 = Head
    Write-RepoFile -Rel 'src/app.cs' -Lines @('class A { int X; }')
    Write-Receipt -ParentSha $p2 -Subject 'edit app'
    TG add -A; TG commit -m 'edit app'
    $code = Invoke-Checker -ScriptArgs @('-BaseRef', $base, '-RepoRoot', $tmp)
    Assert-Equal 0 $code 'history walk: panel-required commit with fresh valid receipt -> OK'

    Write-RepoFile -Rel 'README.md' -Lines @('# repo', 'more docs')
    TG add -A; TG commit -m 'docs'
    $code = Invoke-Checker -ScriptArgs @('-BaseRef', $base, '-RepoRoot', $tmp)
    Assert-Equal 0 $code 'history walk: docs-only commit needs no receipt -> OK'

    Write-RepoFile -Rel 'src/app.cs' -Lines @('class A { int X; int Y; }')
    Write-Receipt -ParentSha $p2 -Subject 'stale'
    TG add -A; TG commit -m 'stale receipt'
    $code = Invoke-Checker -ScriptArgs @('-BaseRef', $base, '-RepoRoot', $tmp)
    Assert-Equal 1 $code 'history walk: panel-required commit with STALE receipt -> violation'

    TG reset --hard HEAD
    $h = Head

    Write-RepoFile -Rel 'src/app.cs' -Lines @('class A { int Z; }')
    TG add src/app.cs
    $code = Invoke-Checker -ScriptArgs @('-StagedMode', '-RepoRoot', $tmp)
    Assert-Equal 1 $code 'staged: code change without fresh receipt -> violation'

    Write-Receipt -ParentSha $h -Subject 'staged ok'
    TG add $AUDIT
    $code = Invoke-Checker -ScriptArgs @('-StagedMode', '-RepoRoot', $tmp)
    Assert-Equal 0 $code 'staged: code change WITH fresh valid receipt -> OK'

    TG reset --hard HEAD
    Write-RepoFile -Rel 'README.md' -Lines @('# repo', 'docs only staged')
    TG add README.md
    $code = Invoke-Checker -ScriptArgs @('-StagedMode', '-RepoRoot', $tmp)
    Assert-Equal 0 $code 'staged: docs-only change needs no receipt -> OK'

    TG reset --hard HEAD
    Write-RepoFile -Rel 'src/app.cs' -Lines @('class A { int W; }')
    Write-Receipt -ParentSha $h -Subject 'sneaky' -Panel 'N/A: no code change'
    TG add -A
    $code = Invoke-Checker -ScriptArgs @('-StagedMode', '-RepoRoot', $tmp)
    Assert-Equal 1 $code 'staged: na:CODE on a code change -> violation'

    TG reset --hard HEAD
    $hParent = ((& git -C $tmp rev-parse HEAD^) | Out-String).Trim()
    Write-RepoFile -Rel 'src/app.cs' -Lines @('class A { int Q; }')
    Write-Receipt -ParentSha $hParent -Subject 'amend'
    TG add -A
    $code = Invoke-Checker -ScriptArgs @('-StagedMode', '-RepoRoot', $tmp)
    Assert-Equal 1 $code 'staged fresh commit: stale HEAD^ receipt rejected (freshness preserved)'
    $env:PANEL_GATE_AMEND = '1'
    $code = Invoke-Checker -ScriptArgs @('-StagedMode', '-RepoRoot', $tmp)
    Remove-Item Env:PANEL_GATE_AMEND
    Assert-Equal 0 $code 'staged amend (PANEL_GATE_AMEND=1): HEAD^ accepted'

    TG reset --hard HEAD
    $hHeadShort = $h.Substring(0, 8)
    $hParentShort = $hParent.Substring(0, 8)
    TG rm --cached --ignore-unmatch $AUDIT
    Remove-Item -LiteralPath (Join-Path $tmp $AUDIT) -Force -ErrorAction SilentlyContinue
    Write-RepoFile -Rel 'src/app.cs' -Lines @('class A { int R; }')
    TG add src/app.cs
    $env:PANEL_GATE_AMEND = '1'
    $hintOut = (& pwsh -NoProfile -File $checkerPath -StagedMode -RepoRoot $tmp 2>&1) -join "`n"
    Remove-Item Env:PANEL_GATE_AMEND
    Assert-True ($hintOut -match $hParentShort -and $hintOut -notmatch $hHeadShort) 'missing-receipt hint under PANEL_GATE_AMEND shows HEAD^, not HEAD'

    $tmp2 = Join-Path ([System.IO.Path]::GetTempPath()) ("pcc-t2-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp2 -Force | Out-Null
    function TG2 { & git -C $tmp2 @args 2>&1 | Out-Null; if ($LASTEXITCODE -ne 0) { throw "git2 failed: $($args -join ' ')" } }
    function Head2 { ((& git -C $tmp2 rev-parse HEAD) | Out-String).Trim() }
    try {
        TG2 init; TG2 config user.email 't@e.com'; TG2 config user.name 'T'; TG2 config commit.gpgsign false; TG2 config core.autocrlf false
        New-Item -ItemType Directory -Path (Join-Path $tmp2 '.github/pr-quality-gate/audits') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tmp2 'src') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tmp2 'scripts') -Force | Out-Null
        Set-Content (Join-Path $tmp2 'scripts/check-post-code-change.ps1') '# anchor stub'
        Set-Content (Join-Path $tmp2 'README.md') '# r'; TG2 add -A; TG2 commit -m 'init'
        $e0 = Head2
        $mainB = ((& git -C $tmp2 rev-parse --abbrev-ref HEAD) | Out-String).Trim()
        Set-Content (Join-Path $tmp2 'src/a.cs') 'class A{}'
        Set-Content (Join-Path $tmp2 $AUDIT) (New-Ledger -ParentSha $e0 -Subject 'add a')
        TG2 add -A; TG2 commit -m 'add a'
        $pBase = Head2

        $code = Invoke-Checker -ScriptArgs @('-BaseRef', (Head2), '-RepoRoot', $tmp2)
        Assert-Equal 0 $code 'history walk: empty range (base==head) -> OK'

        TG2 checkout -b feature
        $pf = Head2
        Set-Content (Join-Path $tmp2 'src/f.cs') 'class F{}'
        Set-Content (Join-Path $tmp2 $AUDIT) (New-Ledger -ParentSha $pf -Subject 'feat')
        TG2 add -A; TG2 commit -m 'feature'
        TG2 checkout $mainB
        TG2 merge --no-ff -m 'merge feature' feature
        $code = Invoke-Checker -ScriptArgs @('-BaseRef', $pBase, '-RepoRoot', $tmp2)
        Assert-Equal 0 $code 'history walk: merge commit skipped (--no-merges), feature commit valid -> OK'
    }
    finally {
        Set-Location $PSScriptRoot
        Remove-Item -LiteralPath $tmp2 -Recurse -Force -ErrorAction SilentlyContinue
    }

    $tmp3 = Join-Path ([System.IO.Path]::GetTempPath()) ("pcc-t3-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp3 -Force | Out-Null
    function TG3 { & git -C $tmp3 @args 2>&1 | Out-Null; if ($LASTEXITCODE -ne 0) { throw "git3 failed: $($args -join ' ')" } }
    try {
        TG3 init; TG3 config user.email 't@e.com'; TG3 config user.name 'T'; TG3 config commit.gpgsign false; TG3 config core.autocrlf false
        New-Item -ItemType Directory -Path (Join-Path $tmp3 '.github/pr-quality-gate/audits') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tmp3 'src') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $tmp3 'scripts') -Force | Out-Null
        Set-Content (Join-Path $tmp3 'scripts/check-post-code-change.ps1') '# anchor stub'
        Set-Content (Join-Path $tmp3 'src/x.cs') 'class X{}'
        Set-Content (Join-Path $tmp3 $AUDIT) (New-Ledger -ParentSha 'EMPTY_TREE' -Subject 'initial' -G5 'panel-ran')
        TG3 add -A
        $code = Invoke-Checker -ScriptArgs @('-StagedMode', '-RepoRoot', $tmp3)
        Assert-Equal 0 $code 'staged on a repo with NO HEAD (initial commit): empty-tree path -> OK'
    }
    finally {
        Set-Location $PSScriptRoot
        Remove-Item -LiteralPath $tmp3 -Recurse -Force -ErrorAction SilentlyContinue
    }
}
finally {
    Set-Location $PSScriptRoot
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

$tmp4 = Join-Path ([System.IO.Path]::GetTempPath()) ("pcc-t4-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp4 -Force | Out-Null
function TG4 { & git -C $tmp4 @args 2>&1 | Out-Null; if ($LASTEXITCODE -ne 0) { throw "git4 failed: $($args -join ' ')" } }
function Head4 { ((& git -C $tmp4 rev-parse HEAD) | Out-String).Trim() }
try {
    TG4 init; TG4 config user.email 't@e.com'; TG4 config user.name 'T'; TG4 config commit.gpgsign false; TG4 config core.autocrlf false
    New-Item -ItemType Directory -Path (Join-Path $tmp4 '.github/pr-quality-gate/audits') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tmp4 'src') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tmp4 'scripts') -Force | Out-Null
    Set-Content (Join-Path $tmp4 'scripts/check-post-code-change.ps1') '# anchor stub'
    Set-Content (Join-Path $tmp4 'README.md') '# r'; TG4 add -A; TG4 commit -m 'init'
    $h4 = Head4
    Set-Content (Join-Path $tmp4 'src/x.cs') 'class X{}'
    TG4 add src/x.cs
    Set-Content (Join-Path $tmp4 $AUDIT) (New-Ledger -ParentSha $h4 -Subject 'worktree-receipt')
    $code = Invoke-Checker -ScriptArgs @('-StagedMode', '-WorktreeReceipt', '-RepoRoot', $tmp4)
    Assert-Equal 0 $code '-WorktreeReceipt: panel-required staged change + valid receipt on disk (unstaged) -> OK'
    Remove-Item -LiteralPath (Join-Path $tmp4 $AUDIT) -Force
    $code = Invoke-Checker -ScriptArgs @('-StagedMode', '-WorktreeReceipt', '-RepoRoot', $tmp4)
    Assert-Equal 1 $code '-WorktreeReceipt: panel-required but receipt missing on disk -> VIOLATION (fail-closed local-only path)'
}
finally {
    Set-Location $PSScriptRoot
    Remove-Item -LiteralPath $tmp4 -Recurse -Force -ErrorAction SilentlyContinue
}

$tmp5 = Join-Path ([System.IO.Path]::GetTempPath()) ("pcc-t5-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp5 -Force | Out-Null
function TG5 { & git -C $tmp5 @args 2>&1 | Out-Null; if ($LASTEXITCODE -ne 0) { throw "git5 failed: $($args -join ' ')" } }
function Head5 { ((& git -C $tmp5 rev-parse HEAD) | Out-String).Trim() }
try {
    TG5 init; TG5 config user.email 't@e.com'; TG5 config user.name 'T'; TG5 config commit.gpgsign false; TG5 config core.autocrlf false
    New-Item -ItemType Directory -Path (Join-Path $tmp5 '.github/pr-quality-gate/audits') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tmp5 'src') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tmp5 'docs') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tmp5 'scripts') -Force | Out-Null
    Set-Content (Join-Path $tmp5 'scripts/check-post-code-change.ps1') '# anchor stub'
    Set-Content (Join-Path $tmp5 'README.md') '# r'; TG5 add -A; TG5 commit -m 'init'
    $e0 = Head5
    Set-Content (Join-Path $tmp5 'src/app.cs') 'class A{}'
    Set-Content (Join-Path $tmp5 $AUDIT) (New-Ledger -ParentSha $e0 -Subject 'add code')
    TG5 add -A; TG5 commit -m 'add code'
    TG5 mv src/app.cs docs/app.md
    Set-Content (Join-Path $tmp5 $AUDIT) (New-Ledger -ParentSha 'badf00d' -Subject 'rename')
    TG5 add -A
    $code = Invoke-Checker -ScriptArgs @('-StagedMode', '-RepoRoot', $tmp5)
    Assert-Equal 1 $code 'code->docs rename stays panel-required via --no-renames; wrong parent_sha -> VIOLATION (exit 0 would mean the rename bypassed classification)'
}
finally {
    Set-Location $PSScriptRoot
    Remove-Item -LiteralPath $tmp5 -Recurse -Force -ErrorAction SilentlyContinue
}

$tmp6 = Join-Path ([System.IO.Path]::GetTempPath()) ("pcc-t6-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp6 -Force | Out-Null
function TG6 { & git -C $tmp6 @args 2>&1 | Out-Null; if ($LASTEXITCODE -ne 0) { throw "git6 failed: $($args -join ' ')" } }
function Head6 { ((& git -C $tmp6 rev-parse HEAD) | Out-String).Trim() }
try {
    TG6 init; TG6 config user.email 't@e.com'; TG6 config user.name 'T'; TG6 config commit.gpgsign false; TG6 config core.autocrlf false
    New-Item -ItemType Directory -Path (Join-Path $tmp6 '.github/pr-quality-gate/audits') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tmp6 'src') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tmp6 'scripts') -Force | Out-Null
    Set-Content (Join-Path $tmp6 'scripts/check-post-code-change.ps1') '# anchor stub'
    Set-Content (Join-Path $tmp6 'README.md') '# r'; TG6 add -A; TG6 commit -m 'init'
    $e0 = Head6
    Set-Content (Join-Path $tmp6 'src/code.cs') 'class C{}'
    Set-Content (Join-Path $tmp6 $AUDIT) (New-Ledger -ParentSha 'badf00d' -Subject 'first-add bootstrap')
    TG6 add -A; TG6 commit -m 'add gate + code'
    $code = Invoke-Checker -ScriptArgs @('-BaseRef', $e0, '-RepoRoot', $tmp6)
    Assert-Equal 1 $code 'history walk: first-add commit with an INVALID receipt is CAUGHT (fail-closed; no bootstrap skip)'
}
finally {
    Set-Location $PSScriptRoot
    Remove-Item -LiteralPath $tmp6 -Recurse -Force -ErrorAction SilentlyContinue
}

# Hardened (no bootstrap/never-existed skip): a panel-required commit whose tree carries NO audit
# file anywhere in history is a VIOLATION, not a silent skip (fail-closed CI).
$tmp7 = Join-Path ([System.IO.Path]::GetTempPath()) ("pcc-t7-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp7 -Force | Out-Null
function TG7 { & git -C $tmp7 @args 2>&1 | Out-Null; if ($LASTEXITCODE -ne 0) { throw "git7 failed: $($args -join ' ')" } }
function Head7 { ((& git -C $tmp7 rev-parse HEAD) | Out-String).Trim() }
try {
    TG7 init; TG7 config user.email 't@e.com'; TG7 config user.name 'T'; TG7 config commit.gpgsign false; TG7 config core.autocrlf false
    New-Item -ItemType Directory -Path (Join-Path $tmp7 'src') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tmp7 'scripts') -Force | Out-Null
    Set-Content (Join-Path $tmp7 'scripts/check-post-code-change.ps1') '# anchor stub'
    Set-Content (Join-Path $tmp7 'README.md') '# r'; TG7 add -A; TG7 commit -m 'init'
    $f0 = Head7
    Set-Content (Join-Path $tmp7 'src/code.cs') 'class C{}'
    TG7 add -A; TG7 commit -m 'panel-required, no receipt ever'
    $code = Invoke-Checker -ScriptArgs @('-BaseRef', $f0, '-RepoRoot', $tmp7)
    Assert-Equal 1 $code 'history walk: panel-required commit with NO audit file in history -> VIOLATION (fail-closed; no never-existed skip)'
}
finally {
    Set-Location $PSScriptRoot
    Remove-Item -LiteralPath $tmp7 -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "=== D2 structural sweep: panel-tag rename completeness (stale + double-rename guard) ===" -ForegroundColor Cyan
$sweepRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$sweepPaths = @('AGENTS.md', 'README.md', 'scripts', '.github', 'profiles', ':!scripts/tests/check-post-code-change.tests.ps1')
function Get-SweepCount {
    param([Parameter(Mandatory)][string] $Pattern)
    $stderrFile = [System.IO.Path]::GetTempFileName()
    Push-Location $sweepRoot
    try {
        $hits = & git grep -I -o -h -E $Pattern -- @sweepPaths 2>$stderrFile
        if ($LASTEXITCODE -gt 1) {
            throw "Get-SweepCount: git grep failed (exit $LASTEXITCODE) for pattern '$Pattern': $((Get-Content -LiteralPath $stderrFile -Raw))"
        }
        return @($hits | Where-Object { $_ }).Count
    } finally {
        Pop-Location
        Remove-Item -LiteralPath $stderrFile -Force -ErrorAction SilentlyContinue
    }
}
Assert-Equal 0 (Get-SweepCount 'READY_TO_IMPLEMENT') 'sweep: 0 stale READY_TO_IMPLEMENT (all renamed to DESIGN_READY)'
Assert-Equal 0 (Get-SweepCount 'CODE_REVIEW_READY_TO_IMPLEMENT') 'sweep: 0 double-rename CODE_REVIEW_READY_TO_IMPLEMENT (bare-READY-before-long order)'
Assert-Equal 0 (Get-SweepCount 'DESIGN_CODE_REVIEW_READY') 'sweep: 0 double-rename DESIGN_CODE_REVIEW_READY (bare-READY-after-long order)'
Assert-Equal 0 (Get-SweepCount 'DESIGN_DESIGN_READY') 'sweep: 0 double-rename DESIGN_DESIGN_READY'
Assert-Equal 0 (Get-SweepCount 'CODE_REVIEW_CODE_REVIEW_READY') 'sweep: 0 double-rename CODE_REVIEW_CODE_REVIEW_READY'
Assert-Equal 0 (Get-SweepCount 'verdict:READY([^_]|$)') 'sweep: 0 stale verdict:READY (ERE-safe boundary; all renamed to verdict:CODE_REVIEW_READY)'
$pcTotal = Get-SweepCount 'PANEL CONVERGED'
$pcPrefixed = Get-SweepCount '(DESIGN|CODE-REVIEW) PANEL CONVERGED'
Assert-Equal $pcTotal $pcPrefixed "sweep: every PANEL CONVERGED is phase-prefixed (total=$pcTotal prefixed=$pcPrefixed; 0 bare)"

Write-Host ""
Write-Host "===================================" -ForegroundColor Cyan
Write-Host "PASS: $script:Pass   FAIL: $script:Fail" -ForegroundColor $(if ($script:Fail -gt 0) { 'Red' } else { 'Green' })
if ($script:Fail -gt 0) { exit 1 } else { exit 0 }
