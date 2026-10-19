#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Standalone pwsh self-test (Assert-* helpers, not Pester). Run: pwsh -File <this file>

$modulePath = Join-Path $PSScriptRoot '../lib/panel-ledger-helpers.psm1'
Import-Module $modulePath -Force
. (Join-Path $PSScriptRoot 'test-common.ps1')
$checkerPath = Join-Path $PSScriptRoot '../check-post-code-change.ps1'

$approvedHeavyModels = @(& git -C (Join-Path $PSScriptRoot '../..') show ':.github/pr-quality-gate/data/heavy-allowlist.txt')
$script:Fail = 0
$script:Pass = 0

Write-Host ""
Write-Host "=== Test-PathPanelRequired ===" -ForegroundColor Cyan
Assert-True  (Test-PathPanelRequired -Path 'src/Foo.cs')                                  'C# source is panel-required'
Assert-True  (Test-PathPanelRequired -Path 'scripts/check-post-code-change.ps1')          'scripts/ ps1 is panel-required'
Assert-True  (Test-PathPanelRequired -Path 'AGENTS.md')                                   'AGENTS.md is panel-required (governance)'
Assert-True  (Test-PathPanelRequired -Path '.github/playbooks/post-code-change.md')       'playbook .md is panel-required (governance)'
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

$sha256Parent = 'ab' * 32
Assert-True (Test-PanelLedger -LedgerLines (New-Ledger -ParentSha $sha256Parent) -ExpectedParentSha $sha256Parent -GovernanceTier 1).Valid '64-hex parent_sha accepted'
Assert-False (Test-PanelLedger -LedgerLines (New-Ledger -ParentSha $sha256Parent) -ExpectedParentSha ('cd' * 32) -GovernanceTier 1).Valid 'stale 64-hex parent_sha rejected'
Assert-False (Test-PanelLedger -LedgerLines (New-Ledger -ParentSha ('ab' * 26)) -ExpectedParentSha ('ab' * 26) -GovernanceTier 1).Valid '52-hex parent_sha rejected'
Assert-False (Test-PanelLedger -LedgerLines (@('profile: triage') + (New-Ledger)) -ExpectedParentSha '1234567890abcdef1234567890abcdef12345678' -GovernanceTier 1 -RequiresFull $true).Valid 'profile triage ledger rejected whenever full panel is required, even before adoption'

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
$duckC = '      - slot:duck model:claude-opus-5.5 family:claude role:rubber-duck tier:heavy verdict:CODE_REVIEW_READY rounds:2'
$crC   = '      - slot:crc model:grok-4.7 family:grok role:code-review tier:heavy verdict:CODE_REVIEW_READY rounds:2'
$crG1  = '      - slot:crg1 model:gpt-6.1-sol family:gpt role:code-review tier:heavy verdict:CODE_REVIEW_READY rounds:2'
$crG2  = '      - slot:crg2 model:gpt-5.3-codex family:gpt role:code-review tier:heavy verdict:CODE_REVIEW_READY rounds:2'
$crGem = '      - slot:crgem model:gemini-4-argon family:gemini role:code-review tier:heavy verdict:CODE_REVIEW_READY rounds:2'
$find  = '      - findings: closed a fail-open and tightened a regex'
function New-BoundLedger {
    param([AllowEmptyCollection()] [string[]] $SlugRows = @('slug-review: ran findings:3 fixed:1 routed:2'))
    $artifactToken = 'a' * 64
    $transcript = @(Get-ValidPanelTranscript | ForEach-Object {
        if ([string]$_ -cmatch '^\s*-\s*slot:') { ([string]$_) + " artifact:$artifactToken" } else { [string]$_ }
    })
    return @("parent_sha: $tParent", 'commit_subject: t', 'POST-CODE-CHANGE LEDGER', '  gates:') + (Get-ValidPreRows) + @(
        '    post-code-change-panel: ran, unanimous'
    ) + $transcript + @('    build: passed', '    tests: passed, 1/1', 'evidence-tree: worktree-clean') + $SlugRows
}

$r = Test-PanelLedger -LedgerLines (New-BoundLedger) -ExpectedParentSha $tParent -GovernanceTier 1 -BoundStaged
Assert-True $r.Valid 'bound staged panel accepts one top-level slug-review row with findings equal to fixed plus routed'
$waivedBound = @(New-BoundLedger | ForEach-Object { $_ -replace 'post-code-change-panel: ran, unanimous', 'post-code-change-panel: user-waived: "panel-waive-acknowledged" ref:turn-9' })
$r = Test-PanelLedger -LedgerLines $waivedBound -ExpectedParentSha $tParent -GovernanceTier 1 -BoundStaged
Assert-Equal 0 @($r.Errors | Where-Object { $_ -match 'slug-review|evidence-tree' }).Count 'user-waived bound staged ledger with slug-review and evidence-tree has no row errors'
$r = Test-PanelLedger -LedgerLines @($waivedBound | Where-Object { $_ -notmatch '^slug-review:' }) -ExpectedParentSha $tParent -GovernanceTier 1 -BoundStaged
Assert-True (-not $r.Valid -and @($r.Errors | Where-Object { $_ -match 'slug-review' }).Count -gt 0) 'user-waived bound staged ledger still requires slug-review'
$r = Test-PanelLedger -LedgerLines @($waivedBound | Where-Object { $_ -notmatch '^evidence-tree:' }) -ExpectedParentSha $tParent -GovernanceTier 1 -BoundStaged
Assert-True (-not $r.Valid -and @($r.Errors | Where-Object { $_ -match 'evidence-tree' }).Count -gt 0) 'user-waived bound staged ledger still requires evidence-tree'

$designBound = @(New-BoundLedger | ForEach-Object {
    if ($_ -match 'verdict:DESIGN_READY') { $_ + (' artifact:' + ('b' * 64)) } else { $_ }
})
$r = Test-PanelLedger -LedgerLines $designBound -ExpectedParentSha $tParent -GovernanceTier 1 -BoundStaged -ExpectedArtifact ('a' * 64)
Assert-True $r.Valid 'design artifact may differ from staged post-panel artifact'
$missingPostArtifact = @($designBound | ForEach-Object { if ($_ -match 'verdict:CODE_REVIEW_READY') { $_ -replace ' artifact:[a-f0-9]{64}$', '' } else { $_ } })
$r = Test-PanelLedger -LedgerLines $missingPostArtifact -ExpectedParentSha $tParent -GovernanceTier 1 -BoundStaged -ExpectedArtifact ('a' * 64)
Assert-False $r.Valid 'design tokens cannot replace missing post-panel tokens'
$wrongPostArtifact = @($designBound | ForEach-Object { if ($_ -match 'verdict:CODE_REVIEW_READY') { $_ -replace 'artifact:a{64}$', ('artifact:' + ('c' * 64)) } else { $_ } })
$r = Test-PanelLedger -LedgerLines $wrongPostArtifact -ExpectedParentSha $tParent -GovernanceTier 1 -BoundStaged -ExpectedArtifact ('a' * 64)
Assert-False $r.Valid 'post-panel tokens must match the staged artifact'
$oneMissingArtifact = @($designBound | ForEach-Object { if ($_ -match 'slot:duck ') { $_ -replace ' artifact:[a-f0-9]{64}$', '' } else { $_ } })
$r = Test-PanelLedger -LedgerLines $oneMissingArtifact -ExpectedParentSha $tParent -GovernanceTier 1 -BoundStaged -ExpectedArtifact ('a' * 64)
Assert-False $r.Valid 'every post-panel reviewer requires an artifact token'
$r = Test-PanelLedger -LedgerLines (New-Ledger -G5 'panel-ran') -ExpectedParentSha $tParent -GovernanceTier 2 -RequiresFull $true -PostAdoption $true -HeavyModels @($approvedHeavyModels)
Assert-True $r.Valid 'post-adoption history validates approved full slate without registry text'
foreach ($verdict in @('DESIGN_READY','CODE_REVIEW_READY')) {
    foreach ($replacement in @('model:gpt-5-mini family:claude','model:claude-haiku-5.5 family:claude','model:claude-unknown family:claude')) {
        $spoofed = @(New-Ledger -G5 'panel-ran' | ForEach-Object { if ($_ -match "verdict:$verdict") { $_ -replace 'model:claude-opus-5.5 family:claude', $replacement } else { $_ } })
        $r = Test-PanelLedger -LedgerLines $spoofed -ExpectedParentSha $tParent -GovernanceTier 2 -RequiresFull $true -PostAdoption $true -HeavyModels @($approvedHeavyModels)
        Assert-False $r.Valid "post-adoption $verdict rejects $replacement without registry text"
        Assert-True (($r.Errors -join ' ') -match 'prefix does not match|HeavyModelAllowList') 'rejection identifies model family or heavy allowlist mismatch'
    }
}
$legacyModel = @(New-Ledger | ForEach-Object { $_ -replace 'model:claude-opus-5.5', 'model:claude-legacy' })
$r = Test-PanelLedger -LedgerLines $legacyModel -ExpectedParentSha $tParent -GovernanceTier 1
Assert-True $r.Valid 'pre-adoption model labels retain legacy compatibility'

$r = Test-PanelLedger -LedgerLines (New-BoundLedger -SlugRows @()) -ExpectedParentSha $tParent -GovernanceTier 1 -BoundStaged
Assert-False $r.Valid 'bound staged panel rejects a missing slug-review row'
$r = Test-PanelLedger -LedgerLines (New-BoundLedger -SlugRows @('slug-review: ran findings:3 fixed:1 routed:1 dismissed:1')) -ExpectedParentSha $tParent -GovernanceTier 1 -BoundStaged
Assert-False $r.Valid 'bound staged panel rejects a dismissed field in the slug-review row'
$r = Test-PanelLedger -LedgerLines (New-BoundLedger -SlugRows @('slug-review: ran findings:3 fixed:1 routed:1')) -ExpectedParentSha $tParent -GovernanceTier 1 -BoundStaged
Assert-False $r.Valid 'bound staged panel rejects slug-review counts that do not balance'
$r = Test-PanelLedger -LedgerLines (New-BoundLedger -SlugRows @('    slug-review: ran findings:3 fixed:1 routed:2')) -ExpectedParentSha $tParent -GovernanceTier 1 -BoundStaged
Assert-False $r.Valid 'bound staged panel rejects a slug-review row inside the gates block'
$duplicateSlugRows = @(New-BoundLedger) + @('slug-review: ran findings:0 fixed:0 routed:0')
$r = Test-PanelLedger -LedgerLines $duplicateSlugRows -ExpectedParentSha $tParent -GovernanceTier 1 -BoundStaged
Assert-False $r.Valid 'bound staged panel rejects duplicate slug-review rows'
$earlySlugRows = @(New-BoundLedger -SlugRows @())
$panelHeaderIndex = [array]::IndexOf([object[]]$earlySlugRows, [object]'    panel-transcript:')
$earlySlugRows = @($earlySlugRows[0..($panelHeaderIndex - 1)] + @('slug-review: ran findings:3 fixed:1 routed:2') + $earlySlugRows[$panelHeaderIndex..($earlySlugRows.Count - 1)])
$r = Test-PanelLedger -LedgerLines $earlySlugRows -ExpectedParentSha $tParent -GovernanceTier 1 -BoundStaged
Assert-False $r.Valid 'bound staged panel rejects a slug-review row before the panel transcript'

Assert-True  (Test-TranscriptValid @($HDR, $duckC, $crC, $crG1, $crG2, $crGem, $find)) 'valid full slate (2 DISTINCT GPT models) + findings -> valid (distinct-by-slot does not false-reject the happy path)'
Assert-False (Test-TranscriptValid @()) 'ran, unanimous with NO panel-transcript block -> INVALID'
Assert-False (Test-TranscriptValid @($HDR, $find)) 'panel-transcript header + findings but no reviewer lines -> INVALID'
Assert-False (Test-TranscriptValid @($HDR, $duckC, $crC, $crG1, $crG2, $find)) 'transcript missing the Gemini family -> INVALID'
Assert-True (Test-TranscriptValid @($HDR, $duckC, $crC, $crG1, $crGem, $find)) 'one GPT plus one Grok meets the combined-family minimum'
Assert-False (Test-TranscriptValid @($HDR, $duckC, $crG1, $crGem, $find)) 'transcript with only 1 code-review (and 3 reviewers) -> INVALID'
$dup = @($HDR, $duckC, $crC, $crG1, $crG2, $crGem, $find, ($crG2 -replace 'verdict:CODE_REVIEW_READY', 'verdict:NEEDS_REWORK'))
Assert-False (Test-TranscriptValid $dup) 'duplicate reviewer slot (a dup carrying NEEDS_REWORK cannot be masked) -> INVALID'
$rework = @($HDR, $duckC, $crC, $crG1, $crG2, ($crGem -replace 'verdict:CODE_REVIEW_READY', 'verdict:NEEDS_REWORK'), $find)
Assert-False (Test-TranscriptValid $rework) 'a NEEDS_REWORK verdict (floor path, not grammar) -> INVALID (panel not converged)'
$rounds0 = @($HDR, ($duckC -replace 'rounds:2', 'rounds:0'), $crC, $crG1, $crG2, $crGem, $find)
Assert-False (Test-TranscriptValid $rounds0) 'rounds:0 -> INVALID (>= 1 required, distinct from malformed)'
$bigRounds = @($HDR, ($duckC -replace 'rounds:2', 'rounds:1000'), $crC, $crG1, $crG2, $crGem, $find)
Assert-True (Test-TranscriptValid $bigRounds) 'rounds:1000 -> valid (no review-round cap)'
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
Assert-True ($agentsRaw -match [regex]::Escape('full-floor (tier 2 or `Test-RequiresFullPanel`) forbids `user-waived`/`na`')) 'sentinel: full-floor forbids user-waived/na'
Assert-True ($agentsRaw -match [regex]::Escape('Full-floor (tier 2 or `Test-RequiresFullPanel`): both panels `ran:unanimous` only; `na`/`user-waived` rejected.')) 'PRE-GIT sentinel: full-floor panels ran:unanimous only'
Assert-True ($sweeps2 -match [regex]::Escape('pre-code-change-panel: <ran, unanimous | user-waived: "panel-waive-acknowledged" ref:<call-ref> | N/A: reason>')) '2B pre-code-change-panel row carries the 3 mapped values (<-> sentinel enum)'


foreach ($schemaFile in @('post-code-change.md','review-workflow-gates-sweeps.md','multi-model-review.md')) {
    $schema = Get-Content -LiteralPath (Join-Path $PSScriptRoot "../../.github/playbooks/$schemaFile") -Raw
    $postSlots = @($schema -split "`n" | Where-Object { $_ -match 'slot:<id>.*verdict:<CODE_REVIEW_READY' })
    Assert-True ($postSlots.Count -gt 0) "$schemaFile documents post-panel reviewer grammar"
    foreach ($slotLine in $postSlots) {
        Assert-True ($slotLine -match 'rounds:<n> artifact:<sha256>') "$schemaFile post-panel grammar binds artifact"
    }
    Assert-True ($schema -match 'evidence-tree:.*worktree-clean' -and $schema -match 'index-export tree:<full-tree-sha>') "$schemaFile documents both evidence-tree forms"
}
$procedure = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../.github/playbooks/multi-model-review/procedure.md') -Raw
Assert-True ($procedure -match 'implementation -> slug review -> user stages -> INDEX-ONLY diff panel') 'review procedure fixes stage-before-panel order'
Assert-True ($procedure -match 'git show :path' -and $procedure -match 'Any index change invalidates all panel verdicts') 'review procedure requires index sources and invalidates stale verdicts'

$panelPolicy = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../.github/pr-quality-gate/panel-policy.md') -Raw
Assert-True ($panelPolicy -match 'Before the diff panel, let the user review by STAGING' -and $panelPolicy -match 'INDEX-ONLY sources') 'panel policy requires staging before index-only review'
Assert-False ($panelPolicy -match 'After panel convergence, let the user review by STAGING|stage the files you.ve reviewed') 'panel policy contains no panel-before-staging directions'


$floor = Get-PanelSlateFloor
$pp = Get-Content (Join-Path $PSScriptRoot '../../.github/pr-quality-gate/panel-policy.md') -Raw
Assert-True ($pp -match "$($floor.MinReviewers)\s+reviewers")            "floor MinReviewers=$($floor.MinReviewers) matches panel-policy.md S27-32"
Assert-True ($pp -match "$($floor.MinClaude)\s+Claude")          "floor MinClaude=$($floor.MinClaude) matches panel-policy.md"
Assert-True ($pp -match "$($floor.MinGpt)\s+GPT")                "floor MinGpt=$($floor.MinGpt) matches panel-policy.md"
Assert-True ($pp -match "$($floor.MinGemini)\s+Gemini")          "floor MinGemini=$($floor.MinGemini) matches panel-policy.md"
Assert-True ($pp -match "$($floor.MinRubberDuck)\s+\x60?rubber-duck")     "floor MinRubberDuck=$($floor.MinRubberDuck) matches panel-policy.md"
Assert-True ($pp -match "$($floor.MinCodeReview)\s+\x60?code-review")     "floor MinCodeReview=$($floor.MinCodeReview) matches panel-policy.md"
Assert-True ($floor.MinHeavy -eq $floor.MinReviewers -and $pp -match 'all heavy-tier')                "floor MinHeavy=$($floor.MinHeavy) matches panel-policy.md"

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
foreach ($p in @('AGENTS.md','setup.ps1','setup.sh','.gitattributes','.gitignore','.github/copilot-instructions.md','.github/instructions/x.md','.github/playbooks/post-code-change.md','.github/workflows/ci.yml','.github/pr-quality-gate/panel-policy.md','.githooks/pre-commit','scripts/foo.ps1','src/Foo.cs','app.ts','x.csproj')) {
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
function Set-StagedReceiptArtifact {
    param([string] $Directory)
    $receiptPath = Join-Path $Directory $AUDIT
    $parentLine = @(Get-Content -LiteralPath $receiptPath | Where-Object { $_ -cmatch '^parent_sha:\s*\S' })
    if ($parentLine.Count -ne 1 -or $parentLine[0] -cnotmatch '^parent_sha:\s*(\S+)\s*$') { throw 'receipt must have exactly one parent_sha before artifact binding' }
    $parentSha = $matches[1]
    if ($parentSha -cin @('NONE', 'EMPTY_TREE')) { $parentSha = 'none' }
    $artifactOutput = & pwsh -NoProfile -File (Join-Path $PSScriptRoot '../Get-ReviewedArtifactId.ps1') -Staged -ParentSha $parentSha -RepoRoot $Directory
    $artifact = [string]$artifactOutput[0]
    $lines = @(Get-Content -LiteralPath $receiptPath | ForEach-Object {
        if ($_ -match '^\s*- slot:') { $_ + " artifact:$artifact" }
        elseif ($_ -match '^\s*safety-critical-eval-G5:') { '    safety-critical-eval-G5: panel-ran' }
        else { $_ }
    })
    $paths = @(& git -C $Directory diff --cached --name-only --no-renames)
    $guardedCount = @($paths | Where-Object { Test-GuardedPath -Path $_ }).Count
    if ($guardedCount -gt 0) { $lines += "checker-edit: `"checker-edit-acknowledged`" ref:test-approval paths:$guardedCount" }
    $lines += @('    vsa-audit: ran, fixture placement verified', 'evidence-tree: worktree-clean', 'slug-review: ran findings:0 fixed:0 routed:0')
    Set-Content -LiteralPath $receiptPath -Value $lines -Encoding UTF8
}
function Invoke-Checker { param([string[]] $ScriptArgs)
    if ($ScriptArgs -contains '-StagedMode' -and $ScriptArgs -notcontains '-WorktreeReceipt') { $ScriptArgs += '-WorktreeReceipt' }
    $checkerOutput = & pwsh -NoProfile -File $checkerPath @ScriptArgs 2>&1
    $checkerExit = $LASTEXITCODE
    if ($checkerExit -ne 0) { Write-Verbose ($checkerOutput -join "`n") }
    return $checkerExit }

try {
    TG init
    TG config user.email 'test@example.com'
    TG config user.name 'Test'
    TG config commit.gpgsign false
    TG config core.autocrlf false

    Write-RepoFile -Rel 'README.md' -Lines @('# repo')
    Write-RepoFile -Rel 'scripts/check-post-code-change.ps1' -Lines @('# anchor stub')
    Initialize-InstructionFixtureRepository -Directory $tmp
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

    TG rm $AUDIT
    Write-RepoFile -Rel '.gitignore' -Lines @('.github/pr-quality-gate/audits/')
    TG add .gitignore; TG commit -m 'Keep receipts local'
    $h = Head

    Write-RepoFile -Rel 'src/app.cs' -Lines @('class A { int Z; }')
    TG add src/app.cs
    $code = Invoke-Checker -ScriptArgs @('-StagedMode', '-RepoRoot', $tmp)
    Assert-Equal 1 $code 'staged: code change without fresh receipt -> violation'

    Write-Receipt -ParentSha $h -Subject 'staged ok'
    Set-StagedReceiptArtifact -Directory $tmp
    $code = Invoke-Checker -ScriptArgs @('-StagedMode', '-RepoRoot', $tmp)
    Assert-Equal 0 $code 'staged: code change WITH fresh valid receipt -> OK'

    TG reset --hard HEAD
    Write-RepoFile -Rel 'README.md' -Lines @('# repo', 'docs only staged')
    TG add README.md
    $code = Invoke-Checker -ScriptArgs @('-StagedMode', '-RepoRoot', $tmp)
    Assert-Equal 1 $code 'staged: instruction-repo docs-only change requires a full panel receipt'

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
    Set-StagedReceiptArtifact -Directory $tmp
    $env:PANEL_GATE_AMEND = '1'
    $code = Invoke-Checker -ScriptArgs @('-StagedMode', '-RepoRoot', $tmp)
    Remove-Item Env:PANEL_GATE_AMEND
    Assert-Equal 0 $code 'staged amend (PANEL_GATE_AMEND=1): HEAD^ accepted'
    Write-Receipt -ParentSha $h -Subject 'amend bound to replaced HEAD'
    Set-StagedReceiptArtifact -Directory $tmp
    $env:PANEL_GATE_AMEND = '1'
    $headBoundOutput = @(& pwsh -NoProfile -File $checkerPath -StagedMode -WorktreeReceipt -RepoRoot $tmp 2>&1)
    Remove-Item Env:PANEL_GATE_AMEND
    Assert-True ($LASTEXITCODE -eq 1 -and ($headBoundOutput -join ' ') -match 'parent_sha') 'staged amend rejects a HEAD-bound receipt even when its artifact uses HEAD'

    TG reset --hard HEAD
    $hHeadShort = $h.Substring(0, 8)
    $hParentShort = $hParent.Substring(0, 8)
    TG rm --cached --ignore-unmatch $AUDIT
    Remove-Item -LiteralPath (Join-Path $tmp $AUDIT) -Force -ErrorAction SilentlyContinue
    Write-RepoFile -Rel 'src/app.cs' -Lines @('class A { int R; }')
    TG add src/app.cs
    $env:PANEL_GATE_AMEND = '1'
    $hintOut = (& pwsh -NoProfile -File $checkerPath -StagedMode -WorktreeReceipt -RepoRoot $tmp 2>&1) -join "`n"
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
        Initialize-InstructionFixtureRepository -Directory $tmp2
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
        Assert-Equal 0 $code 'history walk: merge commit validated against its first parent (carried ledger binds it), feature commit valid -> OK'

        $mergeBase2 = Head2
        TG2 checkout -b feature2
        Set-Content (Join-Path $tmp2 'src/g.cs') 'class G{}'
        Set-Content (Join-Path $tmp2 $AUDIT) (New-Ledger -ParentSha $mergeBase2 -Subject 'feat2')
        TG2 add -A; TG2 commit -m 'feature2'
        TG2 checkout $mainB
        Set-Content (Join-Path $tmp2 'src/m.cs') 'class M{}'
        Set-Content (Join-Path $tmp2 $AUDIT) (New-Ledger -ParentSha $mergeBase2 -Subject 'main2')
        TG2 add -A; TG2 commit -m 'main2'
        TG2 merge --no-ff -X theirs -m 'merge feature2' feature2
        $code = Invoke-Checker -ScriptArgs @('-BaseRef', $mergeBase2, '-RepoRoot', $tmp2)
        Assert-Equal 1 $code 'history walk: merge commit whose ledger binds a non-first parent -> VIOLATION (merges are not skipped)'
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
        Initialize-InstructionFixtureRepository -Directory $tmp3
        Set-Content (Join-Path $tmp3 '.gitignore') '.github/pr-quality-gate/audits/'
        TG3 add -A
        Set-StagedReceiptArtifact -Directory $tmp3
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
    Initialize-InstructionFixtureRepository -Directory $tmp4
    Set-Content (Join-Path $tmp4 'README.md') '# r'; TG4 add -A; TG4 commit -m 'init'
    $h4 = Head4
    Set-Content (Join-Path $tmp4 'src/x.cs') 'class X{}'
    TG4 add src/x.cs
    Set-Content (Join-Path $tmp4 $AUDIT) (New-Ledger -ParentSha $h4 -Subject 'worktree-receipt')
    Set-StagedReceiptArtifact -Directory $tmp4
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
    Initialize-InstructionFixtureRepository -Directory $tmp5
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
    Initialize-InstructionFixtureRepository -Directory $tmp6
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
    Initialize-InstructionFixtureRepository -Directory $tmp7
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

$artifactScript = (Resolve-Path (Join-Path $PSScriptRoot '../Get-ReviewedArtifactId.ps1')).Path
function Get-TestArtifactHash {
    param([string] $Text)
    [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Text))).ToLowerInvariant()
}
try {
    $artifactSource = Get-Content -LiteralPath $artifactScript -Raw
    $writeTreePattern = '\bwrite-tree\b'
    Assert-True ('git write-tree' -match $writeTreePattern) 'write-tree pattern positive control matches the git command'
    Assert-False ($artifactSource -match $writeTreePattern) 'Staged artifact calculation never writes the index tree'
    Assert-True ($artifactSource.Contains('--no-optional-locks')) 'artifact git reads disable optional index locks'

    foreach ($objectFormat in @('sha1', 'sha256')) {
        $repo = New-TestTempDirectory -Prefix "artifact-commit-$objectFormat"
        $tmp = $repo
        TG init -q -b main "--object-format=$objectFormat"
        TG config user.email 'test@example.com'
        TG config user.name 'Test'
        TG config commit.gpgsign false
        TG config core.protectNTFS false
        $base = New-TestCommit -Directory $repo -File 'base.txt' -Content 'base' -Message 'base'
        Set-Content -LiteralPath (Join-Path $repo 'normal.txt') -Value 'normal' -NoNewline
        TG 'add' '--' 'normal.txt'
        $staged = @(& pwsh -NoProfile -File $artifactScript -RepoRoot $repo '-Staged' 2>&1)
        $stagedExitCode = $LASTEXITCODE
        Assert-Equal 0 $stagedExitCode "$objectFormat staged artifact before a normal commit succeeds"
        TG 'commit' '-q' '-m' 'normal'
        $normalSha = ((& git -C $repo rev-parse HEAD) | Out-String).Trim()
        $committed = @(& pwsh -NoProfile -File $artifactScript -RepoRoot $repo '-Commit' $normalSha 2>&1)
        $committedExitCode = $LASTEXITCODE
        Assert-Equal 0 $committedExitCode "$objectFormat committed artifact after a normal commit succeeds"
        Assert-Equal $staged[0] $committed[0] "$objectFormat staged-before equals commit-after for a normal commit"

        $unicodePath = 'unicode-' + [char]0x03bb + '.txt'
        Set-Content -LiteralPath (Join-Path $repo $unicodePath) -Value 'unicode' -NoNewline
        [IO.File]::WriteAllText((Join-Path $repo 'empty.txt'), '')
        TG 'add' '--' $unicodePath 'empty.txt'
        $quotedBlob = ([string]('quoted path' | & git -C $repo hash-object -w --stdin)).Trim()
        if ($LASTEXITCODE -ne 0) { throw 'cannot create C-quoted path fixture blob' }
        TG 'update-index' '--add' '--cacheinfo' ('100644,' + $quotedBlob + ',quoted"path.txt')
        $quotedIndex = @(& git -C $repo -c core.quotePath=false ls-files -s)
        if ($LASTEXITCODE -ne 0) { throw 'cannot list C-quoted index path' }
        Assert-True ([bool]($quotedIndex | Where-Object { $_ -cmatch '^[0-9]{6} [0-9a-f]+ 0\t"' })) "$objectFormat core.quotePath=false ls-files output C-quotes a literal double-quote path"
        $blob = ([string]('link target' | & git -C $repo hash-object -w --stdin)).Trim()
        if ($LASTEXITCODE -ne 0) { throw 'cannot create fixture blob' }
        TG 'update-index' '--add' '--cacheinfo' "120000,$blob,link-item"
        $childRepo = New-TestTempDirectory -Prefix "artifact-child-$objectFormat"
        $tmp = $childRepo
        TG init -q -b main "--object-format=$objectFormat"
        TG config user.email 'test@example.com'
        TG config user.name 'Test'
        TG config commit.gpgsign false
        $childSha = New-TestCommit -Directory $childRepo -File 'child.txt' -Content 'child' -Message 'child'
        $tmp = $repo
        TG 'update-index' '--add' '--cacheinfo' "160000,$childSha,modules/child"
        $specialStaged = @(& pwsh -NoProfile -File $artifactScript -RepoRoot $repo '-Staged' 2>&1)
        $specialStagedExitCode = $LASTEXITCODE
        Assert-Equal 0 $specialStagedExitCode "$objectFormat staged artifact with symlink, gitlink, unicode, and quoted paths succeeds"
        TG 'commit' '-q' '-m' 'special tree'
        $specialSha = ((& git -C $repo rev-parse HEAD) | Out-String).Trim()
        $specialCommit = @(& pwsh -NoProfile -File $artifactScript -RepoRoot $repo '-Commit' $specialSha 2>&1)
        $specialCommitExitCode = $LASTEXITCODE
        Assert-Equal 0 $specialCommitExitCode "$objectFormat special-tree commit artifact succeeds"
        Assert-Equal $specialStaged[0] $specialCommit[0] "$objectFormat staged-before equals commit-after for symlink, gitlink, unicode, and quoted paths"

        TG 'checkout' '-q' '-b' 'artifact-side'
        [void](New-TestCommit -Directory $repo -File 'side.txt' -Content 'side' -Message 'side')
        TG 'checkout' '-q' 'main'
        [void](New-TestCommit -Directory $repo -File 'main.txt' -Content 'main' -Message 'main')
        TG 'merge' '-q' '--no-ff' '--no-commit' 'artifact-side'
        $mergeParent = ((& git -C $repo rev-parse HEAD) | Out-String).Trim()
        $mergeStaged = @(& pwsh -NoProfile -File $artifactScript -RepoRoot $repo '-Staged' '-ParentSha' $mergeParent 2>&1)
        $mergeStagedExitCode = $LASTEXITCODE
        Assert-Equal 0 $mergeStagedExitCode "$objectFormat staged merge artifact succeeds"
        TG 'commit' '-q' '-m' 'merge'
        $mergeSha = ((& git -C $repo rev-parse HEAD) | Out-String).Trim()
        $mergeCommit = @(& pwsh -NoProfile -File $artifactScript -RepoRoot $repo '-Commit' $mergeSha 2>&1)
        $mergeCommitExitCode = $LASTEXITCODE
        Assert-Equal 0 $mergeCommitExitCode "$objectFormat merge commit artifact succeeds"
        Assert-Equal $mergeStaged[0] $mergeCommit[0] "$objectFormat merge artifact binds the first parent"

        $amendParent = ((& git -C $repo rev-parse HEAD^) | Out-String).Trim()
        Set-Content -LiteralPath (Join-Path $repo 'main.txt') -Value 'amended' -NoNewline
        TG 'add' '--' 'main.txt'
        $plainAmendStaged = @(& pwsh -NoProfile -File $artifactScript -RepoRoot $repo '-Staged' 2>&1)
        $plainAmendStagedExitCode = $LASTEXITCODE
        Assert-Equal 0 $plainAmendStagedExitCode "$objectFormat plain staged amend artifact succeeds"
        $parentBoundStaged = @(& pwsh -NoProfile -File $artifactScript -RepoRoot $repo '-Staged' '-ParentSha' $amendParent 2>&1)
        $parentBoundStagedExitCode = $LASTEXITCODE
        Assert-Equal 0 $parentBoundStagedExitCode "$objectFormat parent-bound staged amend artifact succeeds"
        $uppercaseParentBoundStaged = @(& pwsh -NoProfile -File $artifactScript -RepoRoot $repo '-Staged' '-ParentSha' $amendParent.ToUpperInvariant() 2>&1)
        Assert-Equal 0 $LASTEXITCODE "$objectFormat uppercase ParentSha succeeds"
        Assert-Equal $parentBoundStaged[0] $uppercaseParentBoundStaged[0] "$objectFormat ParentSha is normalized case-insensitively"
        Assert-True ($plainAmendStaged[0] -cne $parentBoundStaged[0]) "$objectFormat plain staged amend artifact differs from first-parent-bound artifact"
        TG 'commit' '-q' '--amend' '-m' 'amended'
        $amendSha = ((& git -C $repo rev-parse HEAD) | Out-String).Trim()
        $amendCommit = @(& pwsh -NoProfile -File $artifactScript -RepoRoot $repo '-Commit' $amendSha 2>&1)
        $amendCommitExitCode = $LASTEXITCODE
        Assert-Equal 0 $amendCommitExitCode "$objectFormat amended commit artifact succeeds"
        Assert-Equal $parentBoundStaged[0] $amendCommit[0] "$objectFormat staged parent-bound artifact equals commit artifact after amend"

        $clone = New-TestTempDirectory -Prefix "artifact-shallow-$objectFormat"
        $cloneUri = ([System.Uri]::new($repo)).AbsoluteUri
        TG clone -q --depth 1 $cloneUri $clone
        $shallowCommit = @(& pwsh -NoProfile -File $artifactScript -RepoRoot $clone '-Commit' $amendSha 2>&1)
        $shallowCommitExitCode = $LASTEXITCODE
        Assert-Equal 0 $shallowCommitExitCode "$objectFormat shallow clone artifact read succeeds"
        Assert-Equal $amendCommit[0] $shallowCommit[0] "$objectFormat raw commit parent header preserves artifact parity in a shallow clone"

        $invalidParent = @(& pwsh -NoProfile -File $artifactScript -RepoRoot $repo '-Staged' '-ParentSha' 'short' 2>&1)
        $invalidParentExitCode = $LASTEXITCODE
        Assert-True ($invalidParentExitCode -ne 0 -and ($invalidParent -join ' ') -match '-ParentSha requires') "$objectFormat rejects abbreviated ParentSha"
        Assert-ThrowsLike -Action { & $artifactScript -Commit $amendSha.Substring(0, 8) -RepoRoot $repo } -Pattern 'full 40- or 64-hex' -Name "$objectFormat Commit rejects abbreviated sha"
        Assert-ThrowsLike -Action { & $artifactScript -Commit ('z' * $amendSha.Length) -RepoRoot $repo } -Pattern 'full 40- or 64-hex' -Name "$objectFormat Commit rejects invalid sha"
    }

    $rootRepo = New-TestGitRepository -Prefix 'artifact-root'
    $tmp = $rootRepo
    Set-Content -LiteralPath (Join-Path $rootRepo 'root.txt') -Value 'root' -NoNewline
    TG 'add' '--' 'root.txt'
    $rootStaged = @(& pwsh -NoProfile -File $artifactScript -RepoRoot $rootRepo '-Staged' 2>&1)
    $rootStagedExitCode = $LASTEXITCODE
    Assert-Equal 0 $rootStagedExitCode 'root staged artifact succeeds without HEAD'
    TG 'commit' '-q' '-m' 'root'
    $rootSha = ((& git -C $rootRepo rev-parse HEAD) | Out-String).Trim()
    $rootCommit = @(& pwsh -NoProfile -File $artifactScript -RepoRoot $rootRepo '-Commit' $rootSha 2>&1)
    $rootCommitExitCode = $LASTEXITCODE
    Assert-Equal 0 $rootCommitExitCode 'root commit artifact succeeds'
    Assert-Equal $rootStaged[0] $rootCommit[0] 'root commit artifact uses the none parent marker'
}
finally { Remove-TestTempDirectories }

foreach ($objectFormat in @('sha1','sha256')) {
    $artifactRepo = New-TestTempDirectory -Prefix "artifact-$objectFormat"
    git -C $artifactRepo init -q -b main "--object-format=$objectFormat"
    if ($LASTEXITCODE -ne 0) { throw "cannot initialize $objectFormat artifact fixture" }
    git -C $artifactRepo config user.email 't@t.t'
    git -C $artifactRepo config user.name 'tester'
    git -C $artifactRepo config commit.gpgsign false
    $base = New-TestCommit -Directory $artifactRepo -File 'one.txt' -Content 'base' -Message 'base'
    $head = New-TestCommit -Directory $artifactRepo -File 'one.txt' -Content 'head' -Message 'head'
    $index = @(git -C $artifactRepo ls-files -s)
    $expected = Get-TestArtifactHash -Text ("head=$head`n" + ($index -join "`n") + "`n")
    Push-Location $artifactRepo
    try { $defaultRootOutput = @(& pwsh -NoProfile -File $artifactScript -Staged) } finally { Pop-Location }
    Assert-Equal 0 $LASTEXITCODE "$objectFormat default-root staged invocation succeeds"
    Assert-Equal $expected $defaultRootOutput[0] "$objectFormat staged artifact hashes full HEAD and singleton index record"
    Assert-Equal 'worktree_divergent=0' $defaultRootOutput[1] "$objectFormat clean fixture has no divergence"
    $rangeOutput = @(& pwsh -NoProfile -File $artifactScript -Range "$base..$head" -RepoRoot $artifactRepo)
    Assert-Equal 0 $LASTEXITCODE "$objectFormat range invocation succeeds"
    Assert-Equal (Get-TestArtifactHash -Text "base=$base`nhead=$head`n") $rangeOutput[0] "$objectFormat range artifact hashes full endpoint SHAs"
    Set-Content -LiteralPath (Join-Path $artifactRepo 'one.txt') -Value 'unstaged'
    Set-Content -LiteralPath (Join-Path $artifactRepo 'new.txt') -Value 'untracked'
    $divergentOutput = @(& pwsh -NoProfile -File $artifactScript -Staged -RepoRoot $artifactRepo)
    Assert-Equal $expected $divergentOutput[0] "$objectFormat worktree edits do not alter index artifact"
    Assert-Equal 'worktree_divergent=2' $divergentOutput[1] "$objectFormat singleton tracked and untracked paths remain separate"
    $receiptDirectory = Join-Path $artifactRepo '.github/pr-quality-gate/audits'
    New-Item -ItemType Directory -Force -Path $receiptDirectory | Out-Null
    foreach ($receiptName in @('signoff-receipt', 'publish-gate-receipt', 'post-code-change-last.md')) { Set-Content -LiteralPath (Join-Path $receiptDirectory $receiptName) -Value 'receipt' }
    Set-Content -LiteralPath (Join-Path $receiptDirectory 'signoff-last.md') -Value 'not a receipt'
    $receiptOutput = @(& pwsh -NoProfile -File $artifactScript -Staged -RepoRoot $artifactRepo)
    Assert-Equal 'worktree_divergent=3' $receiptOutput[1] "$objectFormat real audit receipt names are excluded from divergence"
    Remove-Item -LiteralPath $receiptDirectory -Recurse -Force
    git -C $artifactRepo add -- one.txt
    $changedOutput = @(& pwsh -NoProfile -File $artifactScript -Staged -RepoRoot $artifactRepo)
    Assert-True ($changedOutput[0] -ne $expected) "$objectFormat later index change invalidates artifact"
}
Assert-ThrowsLike -Action { & { function git { $global:LASTEXITCODE = 0; 'abc' }; & $artifactScript -Staged -RepoRoot $artifactRepo } } -Pattern 'full 40- or 64-hex' -Name 'staged artifact rejects abbreviated HEAD output'
Assert-ThrowsLike -Action { & { function git { $global:LASTEXITCODE = 0; 'abc' }; & $artifactScript -Range (('a' * 40) + '..' + ('b' * 40)) -RepoRoot $artifactRepo } } -Pattern 'full 40- or 64-hex' -Name 'range artifact rejects abbreviated endpoint output'
$artifactAst = [System.Management.Automation.Language.Parser]::ParseFile($artifactScript, [ref]$null, [ref]$null)
$converterAst = $artifactAst.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Convert-TreeLinesToIndexLines' }, $true)
. ([scriptblock]::Create($converterAst.Extent.Text))
Assert-ThrowsLike -Action { Convert-TreeLinesToIndexLines -TreeLines @('not an ls-tree entry') } -Pattern 'unrecognized entry' -Name 'tree converter rejects unrecognized ls-tree lines'
Remove-TestTempDirectories

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


Write-Host '=== object activation, adoption, and governing heavy-list regressions ==='
try {
    $activationRepo = New-TestGitRepository -Prefix 'sticky-panel'
    Initialize-InstructionFixtureRepository -Directory $activationRepo
    $helperFixture = Join-Path $activationRepo 'scripts/lib/panel-ledger-helpers.psm1'
    New-Item -ItemType Directory -Path (Split-Path $helperFixture) -Force | Out-Null
    Set-Content -LiteralPath $helperFixture -Value 'function Test-RequiresFullPanel {}'
    $adoptedSha = New-TestCommit -Directory $activationRepo -File 'seed.txt' -Content 'base' -Message 'adoption'
    Assert-True (Test-IsPostAdoption -RepoRoot $activationRepo -StagedMode) 'helper in staged/HEAD tree activates adoption'
    $policy = Get-HeavyModelPolicy -RepoRoot $activationRepo -CommitSha $adoptedSha
    Assert-Equal 0 $policy.Errors.Count 'initial pinned five ids accepted from commit blob'
    Remove-Item -LiteralPath (Join-Path $activationRepo '.github/pr-quality-gate/panel-policy.md')
    & git -C $activationRepo add -A 2>$null
    Assert-ThrowsLike { Test-RequiresFullPanel -RepoRoot $activationRepo } 'activation sentinel moved/removed; update checker constant' 'staged sentinel deletion fails closed even with helper remaining'
    Remove-Item -LiteralPath $helperFixture
    $deletedSha = New-TestCommit -Directory $activationRepo -File 'seed.txt' -Content 'deleted' -Message 'remove sentinel and helper'
    $laterSha = New-TestCommit -Directory $activationRepo -File 'seed.txt' -Content 'later' -Message 'after removal'
    foreach ($revision in @($deletedSha,$laterSha)) {
        Assert-True (Test-RequiresFullPanel -RepoRoot $activationRepo -CommitSha $revision) 'full-panel activation survives deletion and subsequent commits'
        Assert-True (Test-IsPostAdoption -RepoRoot $activationRepo -CommitSha $revision) 'post-adoption classification survives helper removal'
    }
    $heavyFile = Join-Path $activationRepo '.github/pr-quality-gate/data/heavy-allowlist.txt'
    Remove-Item -LiteralPath $heavyFile
    & git -C $activationRepo add -A 2>$null
    Assert-True ((Get-HeavyModelPolicy -RepoRoot $activationRepo -StagedMode).Errors.Count -gt 0) 'post-adoption missing indexed heavy list rejected'
    Set-Content -LiteralPath $heavyFile -Value @($approvedHeavyModels + 'gpt-6-sol')
    & git -C $activationRepo add -A 2>$null
    Assert-True (((Get-HeavyModelPolicy -RepoRoot $activationRepo -StagedMode).Errors -join ' ') -match 'retirement mapping') 'unmapped heavy addition rejected'
    Set-Content -LiteralPath $heavyFile -Value @(@($approvedHeavyModels | Where-Object { $_ -ne 'gpt-6.1-sol' }) + 'gpt-6-sol')
    & git -C $activationRepo add -A 2>$null
    $rotation = @('slate-substitution: slot:s tier:heavy-gpt-premium from:gpt-6.1-sol to:gpt-6-sol reason:model-superseded', 'registry-rotation: "registry-rotation-acknowledged" ref:approved map:heavy-gpt-premium=gpt-6.1-sol>gpt-6-sol')
    Assert-Equal 0 (Get-HeavyModelPolicy -RepoRoot $activationRepo -StagedMode -LedgerLines $rotation).Errors.Count 'same-vendor acknowledged retirement accepts heavy-list rotation'
    $spacedRotation = @($rotation[0], 'registry-rotation: "registry-rotation-acknowledged" ref:approved map: heavy-gpt-premium=gpt-6.1-sol>gpt-6-sol ')
    Assert-Equal 0 (Get-HeavyModelPolicy -RepoRoot $activationRepo -StagedMode -LedgerLines $spacedRotation).Errors.Count 'spaced rotation map accepted by heavy policy'
    $tightParse = Get-RegistryRotationMap -LedgerLines $rotation
    $spacedParse = Get-RegistryRotationMap -LedgerLines $spacedRotation
    Assert-Equal (($tightParse.Entries | ForEach-Object { "$($_.TierId)=$($_.From)>$($_.To)" }) -join ',') (($spacedParse.Entries | ForEach-Object { "$($_.TierId)=$($_.From)>$($_.To)" }) -join ',') 'spaced and tight rotation maps parse identically'
    Assert-True ($spacedParse.Errors.Count -eq 0 -and $spacedParse.RowCount -eq 1) 'spaced rotation map parses without errors'
    Assert-True (@((Get-RegistryRotationMap -LedgerLines @($rotation[1], $rotation[1])).Errors).Count -gt 0) 'duplicate rotation rows rejected'
    Assert-True (@((Get-RegistryRotationMap -LedgerLines @('registry-rotation: "registry-rotation-acknowledged" ref:approved map:heavy-gpt-premium=gpt-6.1-sol')).Errors).Count -gt 0) 'malformed rotation entry rejected'
    Assert-Equal 0 (Get-HeavyModelPolicy -RepoRoot $activationRepo -StagedMode -MembershipOnly).Errors.Count 'membership-only policy accepts a well-formed rotated list without ledger'
    $wrongVendor = @($rotation | ForEach-Object { $_ -replace 'gpt-6.1-sol','claude-opus-5.5' })
    Assert-True ((Get-HeavyModelPolicy -RepoRoot $activationRepo -StagedMode -LedgerLines $wrongVendor).Errors.Count -gt 0) 'cross-vendor retirement cannot authorize heavy-list addition'
    Remove-Item -LiteralPath $heavyFile
    [void](New-TestCommit -Directory $activationRepo -File 'seed.txt' -Content 'missing policy' -Message 'delete heavy list')
    Set-Content -LiteralPath $heavyFile -Value $approvedHeavyModels
    & git -C $activationRepo add -A 2>$null
    Assert-True (((Get-HeavyModelPolicy -RepoRoot $activationRepo -StagedMode).Errors -join ' ') -match 'deleted and re-added') 'post-adoption delete and re-add cannot reset heavy-list introduction rule'
    $mergeRepo = New-TestGitRepository -Prefix 'merge-adoption'
    Initialize-InstructionFixtureRepository -Directory $mergeRepo
    [void](New-TestCommit -Directory $mergeRepo -File 'seed.txt' -Content 'base' -Message 'pre-adoption')
    & git -C $mergeRepo checkout -q -b adoption-side
    [void](New-TestCommit -Directory $mergeRepo -File 'side.txt' -Content 'side' -Message 'side without helper')
    & git -C $mergeRepo checkout -q main
    [void](New-TestCommit -Directory $mergeRepo -File 'main.txt' -Content 'main' -Message 'main without helper')
    & git -C $mergeRepo merge -q --no-ff --no-commit adoption-side 2>$null
    $mergeHelper = Join-Path $mergeRepo 'scripts/lib/panel-ledger-helpers.psm1'
    New-Item -ItemType Directory -Path (Split-Path $mergeHelper) -Force | Out-Null
    Set-Content -LiteralPath $mergeHelper -Value 'function Test-RequiresFullPanel {}'
    $mergeSha = New-TestCommit -Directory $mergeRepo -File 'main.txt' -Content 'helper added by merge resolution' -Message 'merge-only adoption'
    Assert-True (Test-IsPostAdoption -RepoRoot $mergeRepo -CommitSha $mergeSha) 'helper introduced only by merge resolution is post-adoption'
    & git -C $mergeRepo checkout -q -b removal-side
    [void](New-TestCommit -Directory $mergeRepo -File 'side.txt' -Content 'side retains helper' -Message 'side retains helper')
    & git -C $mergeRepo checkout -q main
    [void](New-TestCommit -Directory $mergeRepo -File 'main.txt' -Content 'main retains helper' -Message 'main retains helper')
    & git -C $mergeRepo merge -q --no-ff --no-commit removal-side 2>$null
    Remove-Item -LiteralPath $mergeHelper
    [void](New-TestCommit -Directory $mergeRepo -File 'main.txt' -Content 'merge removes helper' -Message 'merge-only removal')
    $afterMerge = New-TestCommit -Directory $mergeRepo -File 'main.txt' -Content 'descendant without helper' -Message 'after merge-only removal'
    Assert-True (Test-IsPostAdoption -RepoRoot $mergeRepo -CommitSha $afterMerge) 'full-history separate merge diffs detect merge-only introduction and removal in helper-free descendant'
} finally { Remove-TestTempDirectories }

try {
    $amendRepo = New-TestGitRepository -Prefix 'guarded-amend'
    Initialize-InstructionFixtureRepository -Directory $amendRepo
    New-Item -ItemType Directory -Path (Join-Path $amendRepo 'scripts') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $amendRepo 'src') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $amendRepo 'scripts/check-post-code-change.ps1') -Value 'fixture anchor'
    $amendBase = New-TestCommit -Directory $amendRepo -File 'README.md' -Content 'base' -Message 'base'
    [void](New-TestCommit -Directory $amendRepo -File 'scripts/check-md-size.ps1' -Content 'one' -Message 'inherited guarded edit')
    Set-Content -LiteralPath (Join-Path $amendRepo 'scripts/check-instructions-refs.ps1') -Value 'two'
    & git -C $amendRepo add scripts/check-instructions-refs.ps1 2>$null
    $amendReceipt = Join-Path $amendRepo $AUDIT
    New-Item -ItemType Directory -Path (Split-Path $amendReceipt) -Force | Out-Null
    Set-Content -LiteralPath $amendReceipt -Value (New-Ledger -ParentSha $amendBase -G5 'panel-ran')
    Set-StagedReceiptArtifact -Directory $amendRepo
    $env:PANEL_GATE_AMEND = '1'
    $badCountOutput = @(& pwsh -NoProfile -File $checkerPath -RepoRoot $amendRepo -StagedMode -WorktreeReceipt 2>&1)
    Assert-True ($LASTEXITCODE -eq 1 -and ($badCountOutput -join ' ') -match 'paths:2') 'amend includes inherited and newly staged guarded paths from matched HEAD parent'
    Set-Content -LiteralPath $amendReceipt -Value @((Get-Content -LiteralPath $amendReceipt) -replace 'paths:1$', 'paths:2')
    $goodCountOutput = @(& pwsh -NoProfile -File $checkerPath -RepoRoot $amendRepo -StagedMode -WorktreeReceipt 2>&1)
    Assert-True ($LASTEXITCODE -eq 0) "amend accepts matched-parent guarded count ($($goodCountOutput -join ' '))"

    & git -C $amendRepo reset --hard HEAD 2>$null
    Remove-Item Env:PANEL_GATE_AMEND -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path (Join-Path $amendRepo 'src') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $amendRepo 'src/empty.cs'), '')
    & git -C $amendRepo add src/empty.cs 2>$null
    $emptyParent = (git -C $amendRepo rev-parse HEAD).Trim()
    Set-Content -LiteralPath $amendReceipt -Value (New-Ledger -ParentSha $emptyParent -Subject 'staged empty source file')
    Set-StagedReceiptArtifact -Directory $amendRepo
    $emptyOutput = @(& pwsh -NoProfile -File $checkerPath -StagedMode -WorktreeReceipt -RepoRoot $amendRepo 2>&1)
    Assert-Equal 0 $LASTEXITCODE "staged empty file is not classified as intent-to-add ($($emptyOutput -join ' '))"
    $env:PANEL_GATE_AMEND = '1'
    foreach ($intentCase in @('present', 'deleted', 'moved')) {
        & git -C $amendRepo reset --hard HEAD 2>$null
        New-Item -ItemType Directory -Path (Join-Path $amendRepo 'src') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $amendRepo 'src/intent-guard.cs') -Value 'class IntentGuard {}'
        & git -C $amendRepo add src/intent-guard.cs 2>$null
        $intentPath = Join-Path $amendRepo "src/intent-$intentCase.txt"
        Set-Content -LiteralPath $intentPath -Value 'intent'
        & git -C $amendRepo add -N "src/intent-$intentCase.txt" 2>$null
        if ($intentCase -eq 'deleted') { Remove-Item -LiteralPath $intentPath }
        if ($intentCase -eq 'moved') { Move-Item -LiteralPath $intentPath -Destination (Join-Path $amendRepo 'src/intent-moved-renamed.txt') }
        Set-Content -LiteralPath $amendReceipt -Value (New-Ledger -ParentSha $amendBase -Subject "intent-to-add $intentCase")
        Set-StagedReceiptArtifact -Directory $amendRepo
        $intentOutput = @(& pwsh -NoProfile -File $checkerPath -StagedMode -WorktreeReceipt -RepoRoot $amendRepo 2>&1)
        Assert-True ($LASTEXITCODE -eq 1 -and ($intentOutput -join ' ') -match 'intent-to-add paths must be staged or removed') "staged amend rejects $intentCase intent-to-add paths"
    }
    $unmergedRepo = New-TestGitRepository -Prefix 'unmerged-index'
    Initialize-InstructionFixtureRepository -Directory $unmergedRepo
    New-Item -ItemType Directory -Path (Join-Path $unmergedRepo 'scripts') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $unmergedRepo 'scripts/check-post-code-change.ps1') -Value 'fixture anchor'
    [void](New-TestCommit -Directory $unmergedRepo -File 'scripts/check-post-code-change.ps1' -Content 'fixture anchor' -Message 'checker anchor')
    [void](New-TestCommit -Directory $unmergedRepo -File 'src/conflict.cs' -Content 'base' -Message 'conflict base')
    & git -C $unmergedRepo checkout -q -b side
    [void](New-TestCommit -Directory $unmergedRepo -File 'src/conflict.cs' -Content 'side' -Message 'side conflict')
    & git -C $unmergedRepo checkout -q main
    $unmergedParent = New-TestCommit -Directory $unmergedRepo -File 'src/conflict.cs' -Content 'main' -Message 'main conflict'
    & git -C $unmergedRepo merge -q --no-commit side 2>$null
    $mergeExitCode = $LASTEXITCODE
    Assert-True ($mergeExitCode -ne 0) 'unmerged index fixture creates a merge conflict'
    $unmergedReceipt = Join-Path $unmergedRepo $AUDIT
    New-Item -ItemType Directory -Path (Split-Path $unmergedReceipt) -Force | Out-Null
    Set-Content -LiteralPath $unmergedReceipt -Value (New-Ledger -ParentSha $unmergedParent -Subject 'unmerged index check')
    Set-StagedReceiptArtifact -Directory $unmergedRepo
    $unmergedOutput = @(& pwsh -NoProfile -File $checkerPath -StagedMode -WorktreeReceipt -RepoRoot $unmergedRepo 2>&1)
    Assert-True ($LASTEXITCODE -eq 2 -and ($unmergedOutput -join ' ') -match 'index contains unmerged entries') 'staged checker returns invocation error for an unmerged index'

    & git -C $amendRepo add $AUDIT 2>$null
    $stagedAuditOutput = @(& pwsh -NoProfile -File $checkerPath -RepoRoot $amendRepo -StagedMode -WorktreeReceipt 2>&1)
    Assert-True ($LASTEXITCODE -eq 1 -and ($stagedAuditOutput -join ' ') -match 'audit|receipt') 'staged audit path fails closed'
    & pwsh -NoProfile -File $checkerPath -RepoRoot $amendRepo -StagedMode 2>&1 | Out-Null
    Assert-Equal 2 $LASTEXITCODE 'staged invocation without WorktreeReceipt is an invocation error'
} finally { Remove-Item Env:PANEL_GATE_AMEND -ErrorAction SilentlyContinue; Remove-TestTempDirectories }

Write-Host '=== negative ledger policy branches ==='
foreach ($guardRow in @('', 'checker-edit: "checker-edit-acknowledged" ref:approval paths:2')) {
    $r = Test-PanelLedger -LedgerLines @((New-BoundLedger) + @($guardRow | Where-Object { $_ })) -ExpectedParentSha $tParent -GovernanceTier 1 -BoundStaged -GuardedPathCount 1
    Assert-False $r.Valid 'missing or mismatched checker-edit acknowledgement rejected'
    Assert-True (($r.Errors -join ' ') -match 'checker-edit') 'guarded-path failure names acknowledgement'
}
$r = Test-PanelLedger -LedgerLines @((New-BoundLedger) + 'checker-edit: "checker-edit-acknowledged" ref:approval paths:1') -ExpectedParentSha $tParent -GovernanceTier 1 -BoundStaged -GuardedPathCount 1
Assert-True $r.Valid 'matching guarded-path acknowledgement accepted'
$r = Test-PanelLedger -LedgerLines (New-BoundLedger) -ExpectedParentSha $tParent -GovernanceTier 1 -BoundStaged -WorktreeDivergentCount 1
Assert-False $r.Valid 'worktree-clean evidence rejected for divergent worktree'
$export = @(New-BoundLedger | ForEach-Object { $_ -replace 'evidence-tree: worktree-clean', ('evidence-tree: index-export tree:' + ('b' * 64)) })
$r = Test-PanelLedger -LedgerLines $export -ExpectedParentSha $tParent -GovernanceTier 1 -BoundStaged -ExpectedIndexTree ('a' * 64)
Assert-False $r.Valid 'SHA-256 index-export mismatched tree rejected'
$r = Test-PanelLedger -LedgerLines $export -ExpectedParentSha $tParent -GovernanceTier 1 -BoundStaged -ExpectedIndexTree ('b' * 64)
Assert-True $r.Valid 'SHA-256 index-export matched tree accepted'
$triageLines = @('profile: triage', 'panel-transcript:', '- slot:c model:claude-haiku-5.5 family:claude role:code-review tier:light verdict:CODE_REVIEW_READY rounds:1', '- slot:g model:gpt-5-mini family:gpt role:code-review tier:light verdict:CODE_REVIEW_READY rounds:1', '- findings: light reviewers verified the fixture')
Assert-True (@(Test-PanelTranscript -LedgerLines $triageLines -PostAdoption $true).Count -gt 0) 'triage without same-turn triage acknowledgement rejected'
Assert-Equal 0 @(Test-PanelTranscript -LedgerLines ($triageLines + 'triage-ack: "triage-acknowledged" ref:turn-1') -PostAdoption $true).Count 'valid acknowledged light cross-family triage passes outside instruction repo'
Assert-True (@(Test-PanelTranscript -LedgerLines ($triageLines + 'triage-ack: "triage-acknowledged" ref:turn-1') -PostAdoption $true -RequiresFull $true).Count -gt 0) 'triage forbidden for instruction-set full-panel activation'
Assert-True (@(Test-PanelTranscript -LedgerLines ($triageLines + 'triage-ack: "triage-acknowledged" ref:turn-1') -RequiresFull $true).Count -gt 0) 'triage forbidden whenever full panel is required, even before adoption'

$parentRegistry = @(& git -C (Join-Path $PSScriptRoot '../..') show ':.github/playbooks/multi-model-review/current-model-registry.md') -join "`n"
$reviewer = [pscustomobject]@{ Slot='s'; Model='gpt-6.1-sol'; Family='gpt'; Tier='heavy' }
$unnecessary = @('slate-substitution: slot:s tier:heavy-gpt-premium from:gpt-6.1-sol to:gpt-6.1-sol reason:model-superseded','registry-rotation: "registry-rotation-acknowledged" ref:ok map:heavy-gpt-premium=gpt-6.1-sol>gpt-6.1-sol')
Assert-True (@(Test-PanelRegistryBinding -LedgerLines $unnecessary -Reviewers @($reviewer) -RegistryText $parentRegistry -StagedRegistryText $parentRegistry -HeavyModels $approvedHeavyModels).Count -gt 0) 'unnecessary model substitution rejected'
$replacementRegistry = $parentRegistry.Replace('gpt-6.1-sol','gpt-6-sol')
$reviewer.Model = 'gpt-6-sol'
Assert-True (@(Test-PanelRegistryBinding -LedgerLines @() -Reviewers @($reviewer) -RegistryText $parentRegistry -StagedRegistryText $replacementRegistry -HeavyModels @($approvedHeavyModels + 'gpt-6-sol')).Count -gt 0) 'new model without slate-substitution rejected'
$subRow = 'slate-substitution: slot:s tier:heavy-gpt-premium from:gpt-6.1-sol to:gpt-6-sol reason:model-superseded'
Assert-True (@(Test-PanelRegistryBinding -LedgerLines @($subRow) -Reviewers @($reviewer) -RegistryText $parentRegistry -StagedRegistryText $replacementRegistry -HeavyModels @($approvedHeavyModels + 'gpt-6-sol')).Count -gt 0) 'model substitution without registry rotation map rejected'
$reviewer.Model = 'gpt-5.3-codex'
$fallback = @('slate-substitution: slot:s tier:heavy-grok-premium from:grok-4.7 to:gpt-5.3-codex reason:family-unavailable','registry-rotation: "registry-rotation-acknowledged" ref:ok map:heavy-grok-premium=grok-4.7>gpt-5.3-codex')
Assert-Equal 0 @(Test-PanelRegistryBinding -LedgerLines $fallback -Reviewers @($reviewer) -RegistryText $parentRegistry -StagedRegistryText $parentRegistry -HeavyModels $approvedHeavyModels).Count 'named Grok-to-codex family-unavailable fallback accepted'
$badFallback = @($fallback | ForEach-Object { $_ -replace 'gpt-5.3-codex','gpt-6.1-sol' }); $reviewer.Model = 'gpt-6.1-sol'
Assert-True (@(Test-PanelRegistryBinding -LedgerLines $badFallback -Reviewers @($reviewer) -RegistryText $parentRegistry -StagedRegistryText $parentRegistry -HeavyModels $approvedHeavyModels).Count -gt 0) 'family-unavailable cannot target a different GPT model'


$addedTierRegistry = $parentRegistry.Replace('<!-- registry:mapping:end -->', '| `heavy-gpt-added` | `gpt-6-sol` | high | default | added | - |' + "`n<!-- registry:mapping:end -->")
$reviewer.Model = 'gpt-6-sol'
$tierAddedRows = @('slate-substitution: slot:s tier:heavy-gpt-added from:none to:gpt-6-sol reason:tier-added','registry-rotation: "registry-rotation-acknowledged" ref:ok map:heavy-gpt-added=none>gpt-6-sol')
Assert-Equal 0 @(Test-PanelRegistryBinding -LedgerLines $tierAddedRows -Reviewers @($reviewer) -RegistryText $parentRegistry -StagedRegistryText $addedTierRegistry -HeavyModels @($approvedHeavyModels + 'gpt-6-sol')).Count 'tier-added requires and accepts explicit none predecessor with rotation acknowledgement'
$badAddedRows = @($tierAddedRows | ForEach-Object { $_ -replace 'from:none','from:gpt-6.1-sol' -replace 'none>','gpt-6.1-sol>' })
Assert-True (@(Test-PanelRegistryBinding -LedgerLines $badAddedRows -Reviewers @($reviewer) -RegistryText $parentRegistry -StagedRegistryText $addedTierRegistry -HeavyModels @($approvedHeavyModels + 'gpt-6-sol')).Count -gt 0) 'tier-added with invented predecessor rejected'
$crossVendorRegistry = $parentRegistry.Replace('gpt-6.1-sol','claude-opus-new')
$reviewer.Model = 'claude-opus-new'
$crossVendorRows = @('slate-substitution: slot:s tier:heavy-gpt-premium from:gpt-6.1-sol to:claude-opus-new reason:model-superseded','registry-rotation: "registry-rotation-acknowledged" ref:ok map:heavy-gpt-premium=gpt-6.1-sol>claude-opus-new')
Assert-True (@(Test-PanelRegistryBinding -LedgerLines $crossVendorRows -Reviewers @($reviewer) -RegistryText $parentRegistry -StagedRegistryText $crossVendorRegistry -HeavyModels @($approvedHeavyModels + 'claude-opus-new')).Count -gt 0) 'registry retirement cannot switch model vendor'
Assert-True (@(Test-PanelTranscript -LedgerLines ($triageLines + 'triage-ack: "triage-acknowledged" ref:<call-ref>') -PostAdoption $true).Count -gt 0) 'unsubstituted triage-ack ref placeholder rejected'
$placeholderSlot = @(($triageLines + 'triage-ack: "triage-acknowledged" ref:turn-1') | ForEach-Object { $_ -replace '^(\s*-\s*slot:)\S+', '$1<id>' })
Assert-True (@(Test-PanelTranscript -LedgerLines $placeholderSlot -PostAdoption $true).Count -gt 0) 'unsubstituted slot placeholder rejected'
$placeholderModel = @(($triageLines + 'triage-ack: "triage-acknowledged" ref:turn-1') | ForEach-Object { $_ -replace '(\smodel:)\S+', '$1<model-id>' })
Assert-True (@(Test-PanelTranscript -LedgerLines $placeholderModel -PostAdoption $true).Count -gt 0) 'unsubstituted model placeholder rejected'
Assert-True (@((Get-RegistryRotationMap -LedgerLines @('registry-rotation: "registry-rotation-acknowledged" ref:ok map:heavy-gpt-premium=<from>><to>')).Errors).Count -gt 0) 'unsubstituted registry-rotation map placeholder rejected'
Assert-Equal 0 (Get-RegistryRotationMap -LedgerLines @('registry-rotation: "registry-rotation-acknowledged" ref:<call-ref> map:heavy-gpt-premium=gpt-6.1-sol>gpt-6-sol')).RowCount 'unsubstituted registry-rotation ref placeholder rejected'
$placeholderSub = @('slate-substitution: slot:<id> tier:heavy-gpt-premium from:gpt-6.1-sol to:gpt-6-sol reason:model-superseded','registry-rotation: "registry-rotation-acknowledged" ref:ok map:heavy-gpt-premium=gpt-6.1-sol>gpt-6-sol')
$reviewer.Model = 'gpt-6-sol'
Assert-True (@(Test-PanelRegistryBinding -LedgerLines $placeholderSub -Reviewers @($reviewer) -RegistryText $parentRegistry -StagedRegistryText $replacementRegistry -HeavyModels @($approvedHeavyModels + 'gpt-6-sol')).Count -gt 0) 'unsubstituted slate-substitution slot placeholder rejected'

$moduleSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../lib/panel-ledger-helpers.psm1') -Raw
$profileRegex = [regex]::Match($moduleSource, "'(\^profile:\\s\*\(full\|triage\)\\s\*\$)'").Groups[1].Value
$triageAckRegex = [regex]::Match($moduleSource, "'(\^triage-ack:[^']+)'").Groups[1].Value
$substitutionRegex = [regex]::Match($moduleSource, "'(\^slate-substitution:\\s\*slot:[^']+)'").Groups[1].Value
Assert-True ($profileRegex -and $triageAckRegex -and $substitutionRegex) 'checker row regexes extracted from panel-ledger-helpers'
$schemaKeys = @('profile', 'checker-edit', 'triage-ack', 'slate-substitution', 'registry-rotation')
$placeholderValues = [ordered]@{ '<call-ref>' = 'turn-1'; '<n>' = '2'; '<id>' = 's1'; '<tier-id>' = 'heavy-gpt-premium'; '<model|none>' = 'gpt-6.1-sol'; '<model>' = 'gpt-6-sol'; '<from>' = 'gpt-6.1-sol'; '<to>' = 'gpt-6-sol'; '[,...]' = '' }
$schemaRowSets = @{}
foreach ($schemaDoc in @('.github/pr-quality-gate/panel-policy.md', '.github/playbooks/review-workflow-gates-sweeps.md', '.github/playbooks/post-code-change.md')) {
    $docRows = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot "../../$schemaDoc") | Where-Object { $line = $_; @($schemaKeys | Where-Object { $line.StartsWith("${_}: ") }).Count -gt 0 })
    $schemaRowSets[$schemaDoc] = $docRows -join "`n"
    Assert-Equal $schemaKeys.Count $docRows.Count "$schemaDoc documents each checker-enforced row once at column 0"
    foreach ($templateRow in $docRows) {
        $alternativeMatch = [regex]::Match($templateRow, '<((?:[a-z-]+\|)+[a-z-]+)>')
        $alternatives = if ($alternativeMatch.Success -and $templateRow -notmatch '<model\|none>') { @($alternativeMatch.Groups[1].Value -split '\|') } else { @($null) }
        foreach ($alternative in $alternatives) {
            $row = if ($alternative) { $templateRow.Replace($alternativeMatch.Value, $alternative) } else { $templateRow }
            foreach ($placeholder in $placeholderValues.Keys) { $row = $row.Replace($placeholder, $placeholderValues[$placeholder]) }
            Assert-False ($row -match '[<>]\S*$' -and $row -notmatch 'map:') "$schemaDoc row '$row' has no unresolved placeholder"
            switch -Regex ($row) {
                '^profile:' { Assert-True ($row -cmatch $profileRegex) "$schemaDoc profile row '$row' matches checker" }
                '^triage-ack:' { Assert-True ($row -cmatch $triageAckRegex) "$schemaDoc triage-ack row matches checker" }
                '^slate-substitution:' { Assert-True ($row -cmatch $substitutionRegex) "$schemaDoc slate-substitution row '$row' matches checker" }
                '^registry-rotation:' {
                    $parsedMap = Get-RegistryRotationMap -LedgerLines @($row)
                    Assert-True ($parsedMap.RowCount -eq 1 -and $parsedMap.Errors.Count -eq 0 -and $parsedMap.Entries.Count -eq 1 -and $parsedMap.Entries[0].To -eq 'gpt-6-sol') "$schemaDoc registry-rotation row parses via Get-RegistryRotationMap"
                }
                '^checker-edit:' { Assert-True (Test-PanelLedger -LedgerLines @((New-BoundLedger) + $row) -ExpectedParentSha $tParent -GovernanceTier 1 -BoundStaged -GuardedPathCount 2).Valid "$schemaDoc checker-edit row validates in Test-PanelLedger" }
            }
        }
    }
}
Assert-Equal 1 @($schemaRowSets.Values | Sort-Object -Unique).Count 'panel-policy, review-workflow-gates-sweeps, and post-code-change agree on checker-enforced rows'

$launcherPath = (Resolve-Path (Join-Path $PSScriptRoot '../../.github/pr-quality-gate/invoke-panel.ps1')).Path
$launcherText = Get-Content -LiteralPath $launcherPath -Raw
Assert-True ($launcherText.Contains('[string] $ParentSha = ')) 'ParentSha remains optional'
Assert-True ($launcherText.Contains("`$artifactArguments = if (`$Staged) { @('-Staged') }")) 'staged default keeps the literal -Staged argument'
Assert-True ($launcherText.Contains("if (`$Staged -and `$ParentSha) { `$artifactArguments += @('-ParentSha', `$ParentSha) }")) 'staged ParentSha is forwarded to artifact calculation'
Assert-True ($launcherText.Contains('if ($Staged -and $ParentSha) { $artifactCommand += " -ParentSha $ParentSha" }')) 'staged ParentSha is included in the displayed artifact command'
Assert-True ($launcherText -match '\^\(none\|\[0-9a-f\]\{40\}\|\[0-9a-f\]\{64\}\)\$') 'ParentSha accepts only none or a full lowercase SHA'
Assert-False ($launcherText -match 're-fetch git rev-parse HEAD|consuming-project worktree') 'reviewer launcher contains no HEAD-only or consumer-worktree preamble'
Assert-True ($launcherText -match "@\('-Staged'\)" -and $launcherText.Contains("@('-Range', `"`$BaseSha..`$HeadSha`")")) 'launcher resolves staged and range reviewed artifacts using mode-specific arguments'
Assert-True ($launcherText.Contains("if (`$Staged -and `$ParentSha) { `$artifactArguments += @('-ParentSha', `$ParentSha) }") -and $launcherText.Contains('if ($Staged -and $ParentSha) { $artifactCommand +=')) 'launcher forwards staged parent sha to both artifact calculation and reviewer command'
Assert-Equal 2 ([regex]::Matches($launcherText, 'At review start and before verdict').Count) 'triage and full reviewer preambles require artifact verification at both boundaries'
$launcherRepo = New-TestTempDirectory -Prefix 'launcher-range'
& git -C $launcherRepo init -q 2>$null | Out-Null
$previousClone = $env:COPILOT_INSTRUCTIONS_CLONE
$env:COPILOT_INSTRUCTIONS_CLONE = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Push-Location $launcherRepo
try {
    $launcherOutput = & pwsh -NoProfile -File (Join-Path $PSScriptRoot '../../.github/pr-quality-gate/invoke-panel.ps1') -BaseSha ('a' * 40) -HeadSha 'HEAD' 2>&1 | Out-String
    Assert-Equal 2 $LASTEXITCODE 'range launcher rejects symbolic HEAD instead of captured panelHeadSha'
    Assert-True ($launcherOutput -match 'full lowercase hex') 'range launcher names the full-SHA requirement'
} finally {
    Pop-Location
    $env:COPILOT_INSTRUCTIONS_CLONE = $previousClone
}
$previousClone = $env:COPILOT_INSTRUCTIONS_CLONE
$env:COPILOT_INSTRUCTIONS_CLONE = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
try {
    $shortOutput = @(& pwsh -NoProfile -File $launcherPath -BaseSha ('a' * 40) -HeadSha ('b' * 40) -Staged -ParentSha 'abc' 2>&1)
    Assert-True ($LASTEXITCODE -eq 2 -and ($shortOutput -join ' ') -match 'full lowercase 40- or 64-hex SHA') 'short staged ParentSha fails closed'
    $rangeOutput = @(& pwsh -NoProfile -File $launcherPath -BaseSha ('a' * 40) -HeadSha ('b' * 40) -ParentSha ('a' * 40) 2>&1)
    Assert-True ($LASTEXITCODE -eq 2 -and ($rangeOutput -join ' ') -match 'only for -Staged panels') 'ParentSha on a range panel fails closed'
} finally {
    if ($null -eq $previousClone) { Remove-Item Env:COPILOT_INSTRUCTIONS_CLONE -ErrorAction SilentlyContinue }
    else { $env:COPILOT_INSTRUCTIONS_CLONE = $previousClone }
}

$rangeDocHits = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot '../../.github') -Recurse -File -Include '*.md' | Select-String -Pattern '-Range\s+"?<?[A-Za-z]*>?\.\.HEAD|panelBaseSha>?\.\.HEAD|-HeadSha HEAD')
Assert-Equal 0 $rangeDocHits.Count "playbooks bind range artifacts to captured panelHeadSha, never HEAD: $($rangeDocHits -join '; ')"

$runnerText = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../.github/pr-quality-gate/gate-runner.ps1') -Raw
$extractStart = $runnerText.IndexOf('if ($PrRef -and (Test-Path -LiteralPath $panelMissesCsvPath)) {')
$extractEnd = $runnerText.IndexOf('# =====', $extractStart)
if ($extractEnd -lt 0) { $extractEnd = $runnerText.IndexOf('"gate:', $extractStart) }
$extractText = $runnerText.Substring($extractStart, $extractEnd - $extractStart)
$extractBlock = [scriptblock]::Create('param([string] $PrRef)' + "`n" + $extractText)
try {
    $extractDirectory = New-TestTempDirectory -Prefix 'anti-recidivism'
    $PrRef = '1'
    $panelMissesCsvPath = Join-Path $extractDirectory 'broken.csv'
    Set-Content -LiteralPath $panelMissesCsvPath -Value 'wrong,header'
    function Exit-Runner { param([int] $Code, [string] $Reason) throw "exit:${Code}:$Reason" }
    Assert-ThrowsLike { & $extractBlock -PrRef $PrRef } 'exit:4:anti-recidivism extraction failed' 'malformed anti-recidivism CSV fails closed in PowerShell runner'
    $shellRunnerText = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../.github/pr-quality-gate/gate-runner.sh') -Raw
    Assert-True ($shellRunnerText -match 'command -v python3' -and $shellRunnerText -match 'if ! PRIOR_SLUGS=' -and $shellRunnerText -notmatch 'PANEL_MISSES_CSV" "\$PR_REF" 2>/dev/null \|\| true') 'shell runner requires python and fails on extraction error rather than suppressing it'
    Assert-True ($shellRunnerText -match "FILE_COUNT=.*\[\^\[:space:\]\]") 'shell diff count ignores empty/blank lines'
} finally { Remove-TestTempDirectories }

try {
    $rangeRepo = New-TestGitRepository -Prefix 'artifact-input'
    $fullSha = New-TestCommit -Directory $rangeRepo -File 'one.txt' -Content 'one' -Message 'initial'
    $artifactPath = Join-Path $PSScriptRoot '../Get-ReviewedArtifactId.ps1'
    foreach ($badRange in @("origin/main..$fullSha", "refs/remotes/origin/main..$fullSha", "HEAD..$fullSha", "$($fullSha.Substring(0,8))..$fullSha")) {
        $badRangeOutput = @(& pwsh -NoProfile -File $artifactPath -RepoRoot $rangeRepo -Range $badRange 2>&1)
        Assert-True ($LASTEXITCODE -ne 0 -and ($badRangeOutput -join ' ') -match 'full 40- or 64-hex') 'range artifacts reject remote refs, symbolic refs and abbreviated SHAs'
    }
    $missingObject = @(& pwsh -NoProfile -File $artifactPath -RepoRoot $rangeRepo -Range "$fullSha..$('f' * 40)" 2>&1)
    Assert-True ($LASTEXITCODE -ne 0 -and ($missingObject -join ' ') -match 'failed:.*fatal:') 'native Git failure diagnostics are preserved on the error path'
    & git -C $rangeRepo config core.autocrlf true
    [IO.File]::WriteAllText((Join-Path $rangeRepo 'one.txt'), "one`ntwo`n")
    $warningArtifact = @(& pwsh -NoProfile -File $artifactPath -RepoRoot $rangeRepo -Staged 2>&1)
    Assert-True ($LASTEXITCODE -eq 0 -and $warningArtifact.Count -eq 2 -and $warningArtifact[1] -ceq 'worktree_divergent=1') 'native CRLF warnings never pollute artifact stdout or divergent path count'
} finally { Remove-TestTempDirectories }

try {
    $shellFixture = New-TestGitRepository -Prefix 'runner-shell'
    [void](New-TestCommit -Directory $shellFixture -File 'seed.txt' -Content 'base' -Message 'base')
    New-Item -ItemType Directory -Path (Join-Path $shellFixture '.githooks'), (Join-Path $shellFixture '.github/pr-quality-gate/data') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $shellFixture '.github/pr-quality-gate/data/panel-misses.csv') -Value 'wrong,header'
    $shellBlockStart = $shellRunnerText.IndexOf('if [[ -n "$PR_REF" ]]')
    $shellBlockEnd = $shellRunnerText.IndexOf('# rg_flagged_sites:', $shellBlockStart)
    $shellExtract = $shellRunnerText.Substring($shellBlockStart, $shellBlockEnd - $shellBlockStart)
    $shellHook = Join-Path $shellFixture '.githooks/pre-commit'
    $shellPrefix = "#!/usr/bin/env bash`nset -e`nCLONE=`"`$PWD`"`nPR_REF=fixture`nfunction die() { echo `"`$2`"; exit `"`$1`"; }`n"
    [IO.File]::WriteAllText($shellHook, ($shellPrefix + $shellExtract).Replace("`r`n","`n"))
    if ($env:OS -ne 'Windows_NT') { & chmod +x $shellHook }
    $shellError = @(& git -C $shellFixture -c core.hooksPath=.githooks commit --allow-empty -m probe 2>&1)
    Assert-True ($LASTEXITCODE -ne 0 -and ($shellError -join ' ') -match 'anti-recidivism extraction failed|python3 is required') "shell anti-recidivism extraction failure cannot be reported as no prior findings (exit=$LASTEXITCODE; $($shellError -join ' '))"
    $countLine = @($shellRunnerText -split "`n" | Where-Object { $_ -cmatch '^FILE_COUNT=' })[0]
    [IO.File]::WriteAllText($shellHook, ("#!/usr/bin/env bash`nDIFF_FILES=''`n" + $countLine + "`nprintf 'count=%s\\n' `"`$FILE_COUNT`"`nexit 1`n").Replace("`r`n","`n"))
    $emptyCount = @(& git -C $shellFixture -c core.hooksPath=.githooks commit --allow-empty -m probe 2>&1)
    Assert-True ($LASTEXITCODE -eq 1 -and ($emptyCount -join ' ') -match 'count=0') 'empty shell diff has file_count zero'
} finally { Remove-TestTempDirectories }

try {
    $versionFixture = New-TestGitRepository -Prefix 'setup-version'
    [void](New-TestCommit -Directory $versionFixture -File 'seed.txt' -Content 'base' -Message 'base')
    New-Item -ItemType Directory -Path (Join-Path $versionFixture '.githooks'), (Join-Path $versionFixture 'home') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../../setup.sh') -Destination (Join-Path $versionFixture 'setup.sh')
    foreach ($badVersion in @('git version foo.31','git version 2.beta','git version .31','git version 2.')) {
        $versionHook = "#!/usr/bin/env bash`nexport HOME=`"`$PWD/home`"`nfunction git() { printf '%s\\n' '$badVersion'; }`nsource ./setup.sh`n"
        [IO.File]::WriteAllText((Join-Path $versionFixture '.githooks/pre-commit'), $versionHook.Replace("`r`n","`n"))
        if ($env:OS -ne 'Windows_NT') { & chmod +x (Join-Path $versionFixture '.githooks/pre-commit') }
        $versionOutput = @(& git -C $versionFixture -c core.hooksPath=.githooks commit --allow-empty -m probe 2>&1)
        Assert-True ($LASTEXITCODE -ne 0 -and ($versionOutput -join ' ') -match 'could not parse git --version' -and ($versionOutput -join ' ') -notmatch 'integer expression expected') 'setup rejects malformed dotted git version before numeric comparison'
    }
} finally { Remove-TestTempDirectories }

$localCiLines = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot '../run-local-ci.ps1'))
$baseAssignment = @($localCiLines | Where-Object { $_ -cmatch '^\$resolvedBaseRef = ' })
$fetchGuard = @($localCiLines | Where-Object { $_ -cmatch '^if \(-not \$PSBoundParameters.ContainsKey\(''BaseRef''\)\)' })
Assert-Equal 1 $baseAssignment.Count 'local CI resolves base in a variable distinct from BaseRef parameter'
Assert-Equal 1 $fetchGuard.Count 'local CI fetch is controlled by explicit parameter binding'
$baseProbeText = @('param([string] $BaseRef = '''', [string] $BaseBranch = ''main'')', '$RepoRoot = ''.''', '$fetchCalls = [Collections.Generic.List[string]]::new()', 'function git { $fetchCalls.Add(($args -join '' '')) }') + $baseAssignment + $fetchGuard + @('[pscustomobject]@{ Base = $resolvedBaseRef; Fetches = $fetchCalls.Count }')
$baseProbe = [scriptblock]::Create(($baseProbeText -join "`n"))
$implicitBase = & $baseProbe
Assert-Equal 'origin/main' $implicitBase.Base 'unbound BaseRef resolves configured remote branch'
Assert-Equal 1 $implicitBase.Fetches 'unbound BaseRef fetches configured branch exactly once'
$explicitBase = & $baseProbe -BaseRef ('a' * 40)
Assert-Equal ('a' * 40) $explicitBase.Base 'explicit BaseRef preserves caller SHA'
Assert-Equal 0 $explicitBase.Fetches 'explicit BaseRef does not fetch remote'
Write-Host ""
Write-Host "===================================" -ForegroundColor Cyan
Write-Host "PASS: $script:Pass   FAIL: $script:Fail" -ForegroundColor $(if ($script:Fail -gt 0) { 'Red' } else { 'Green' })
if ($script:Fail -gt 0) { exit 1 } else { exit 0 }
