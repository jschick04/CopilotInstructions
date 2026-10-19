#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Standalone pwsh self-test (Assert-* helpers, not Pester) for Test-PreCommitGateBlock (the 4th-receipt
# validator) + scripts/check-pre-commit-gate.ps1. Run: pwsh -File <this file>

Import-Module (Join-Path $PSScriptRoot '../lib/panel-ledger-helpers.psm1') -Force
. (Join-Path $PSScriptRoot 'test-common.ps1')
$checkerPath = Join-Path $PSScriptRoot '../check-pre-commit-gate.ps1'

$script:Fail = 0
$script:Pass = 0

$ValidParent = '1234567890abcdef1234567890abcdef12345678'

function New-Block {
    param(
        [string] $Parent = $ValidParent,
        [string] $Subject = 'mechanize the pre-commit gate',
        [string] $DiffShown = 'yes:t3',
        [string] $DiffApproved = 'yes:t5:"looks good"',
        [string] $StagedVerified = 'yes:(2 files,+9/-1)matches-enumerated',
        [string] $Ownership = 'agent',
        [string] $RuleCoverage = 'true',
        [string] $ProposedSubject = 'mechanize the pre-commit gate',
        [string] $SubjectApproved = 'yes:t5',
        [string] $FormatCheck = 'single_line:yes,co_authored_by_trailer:no,body:no,conventional_commit_prefix:no,subject_length_chars:42',
        [string[]] $Slugs = @('  - slug:comment-necessity status:applied sites:[a.ps1:1] metric:rg=0/0 disp:keep'),
        [string[]] $Staged = @('  - scripts/check-pre-commit-gate.ps1'),
        [switch] $NoHeader, [switch] $NoGate, [switch] $NoSubjectLine, [switch] $NoCra, [switch] $NoStaged
    )
    $lines = @("parent_sha: $Parent", "commit_subject: $Subject")
    if (-not $NoHeader) { $lines += 'PRE-COMMIT GATE PASSED' }
    if (-not $NoGate) {
        $lines += "gate|diff_shown=$DiffShown|diff_approved=$DiffApproved|staged_diff_verified=$StagedVerified|profile=full|author_identity=Jane <j@x.io>|commit_ownership=$Ownership|rule_coverage_passed=$RuleCoverage|pr_creation=deferred"
    }
    if (-not $NoSubjectLine) {
        $lines += "subject|proposed_subject=`"$ProposedSubject`"|subject_approved=$SubjectApproved|format_check=$FormatCheck"
    }
    if (-not $NoCra) { $lines += 'core_rules_acknowledged:'; $lines += $Slugs }
    if (-not $NoStaged) { $lines += 'staged_files:'; $lines += $Staged }
    return $lines
}

function Test-Valid { param([string[]] $Block, [int] $Tier = 2, [string] $Parent = $ValidParent)
    return (Test-PreCommitGateBlock -BlockLines $Block -ExpectedParentSha $Parent -GovernanceTier $Tier).Valid }

Write-Host "`n=== Test-PreCommitGateBlock: valid ===" -ForegroundColor Cyan
Assert-True  (Test-Valid (New-Block))                                    'a complete valid block (tier 2) passes'
Assert-True  (Test-Valid (New-Block -Slugs @() -RuleCoverage 'false') 0) 'tier 0 relaxes the slug + rule_coverage sub-checks'
Assert-True  (Test-Valid (New-Block -Parent 'NONE') 2 $GitEmptyTreeSha)  'root commit: parent_sha NONE matches empty-tree sentinel'

foreach ($profileName in @('full-default','lite')) {
    $legacyBlock = @(New-Block | ForEach-Object { $_ -replace '\|profile=full\|', "|profile=$profileName|" })
    Assert-True ((Test-PreCommitGateBlock -BlockLines $legacyBlock -ExpectedParentSha $ValidParent -GovernanceTier 2).Valid) 'legacy profile remains accepted before adoption'
    Assert-False ((Test-PreCommitGateBlock -BlockLines $legacyBlock -ExpectedParentSha $ValidParent -GovernanceTier 2 -PostAdoption $true).Valid) 'obsolete profile rejected after adoption'
}
foreach ($nonFull in @('lite','triage')) {
    $nonFullBlock = @(New-Block | ForEach-Object { $_ -replace '\|profile=full\|', "|profile=$nonFull|" })
    Assert-False ((Test-PreCommitGateBlock -BlockLines $nonFullBlock -ExpectedParentSha $ValidParent -GovernanceTier 2 -RequiresFull $true).Valid) "profile $nonFull rejected whenever full panel is required, even before adoption"
}
Assert-True ((Test-PreCommitGateBlock -BlockLines (New-Block) -ExpectedParentSha $ValidParent -GovernanceTier 2 -RequiresFull $true).Valid) 'profile full accepted when full panel is required before adoption'
Write-Host "`n=== parent_sha freshness ===" -ForegroundColor Cyan
$sha256Parent = 'ab' * 32
Assert-True (Test-Valid (New-Block -Parent $sha256Parent) 2 $sha256Parent) '64-hex parent_sha accepted'
Assert-False (Test-Valid (New-Block -Parent $sha256Parent) 2 ('cd' * 32)) 'stale 64-hex parent_sha rejected'
Assert-False (Test-Valid (New-Block -Parent ('ab' * 26)) 2 ('ab' * 26)) '52-hex parent_sha rejected'
Assert-False (Test-Valid (New-Block) 2 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa') 'stale parent_sha -> invalid'
Assert-False (Test-Valid (New-Block -Parent 'NONE') 2 $ValidParent)      'root placeholder but a real parent expected -> invalid'
Assert-False ((Test-PreCommitGateBlock -BlockLines (New-Block | Where-Object { $_ -notmatch '^parent_sha:' }) -ExpectedParentSha $ValidParent -GovernanceTier 2).Valid) 'missing parent_sha header -> invalid'
Assert-False (Test-Valid (New-Block -Parent '<sha>'))                    'placeholder parent_sha -> invalid'

Write-Host "`n=== required headers ===" -ForegroundColor Cyan
Assert-False ((Test-PreCommitGateBlock -BlockLines (New-Block | Where-Object { $_ -notmatch '^commit_subject:' }) -ExpectedParentSha $ValidParent -GovernanceTier 2).Valid) 'missing commit_subject -> invalid'
Assert-False (Test-Valid (New-Block -NoHeader))                          'missing PRE-COMMIT GATE PASSED header -> invalid'
Assert-False (Test-Valid (New-Block -Subject '   '))                    'whitespace-only commit_subject -> invalid (PR#89 Copilot)'
Assert-False (Test-Valid (New-Block -NoGate))                            'missing gate| line -> invalid'
Assert-False (Test-Valid (New-Block -NoSubjectLine))                     'missing subject| line -> invalid'
Assert-False (Test-Valid (New-Block -NoCra))                             'missing core_rules_acknowledged -> invalid'
Assert-False (Test-Valid (New-Block -NoStaged))                          'missing staged_files -> invalid'

Write-Host "`n=== gate| load-bearing keys (presence-first + affirmative) ===" -ForegroundColor Cyan
Assert-False (Test-Valid (New-Block -DiffApproved 'no'))                 'diff_approved=no -> invalid'
Assert-False (Test-Valid (New-Block -DiffShown 'no'))                   'diff_shown=no -> invalid (PR#89 Copilot)'
Assert-False ((Test-PreCommitGateBlock -BlockLines ((New-Block) | ForEach-Object { $_ -replace '\|diff_shown=[^|]*','' }) -ExpectedParentSha $ValidParent -GovernanceTier 2).Valid) 'missing diff_shown key -> invalid (PR#89 Copilot)'
Assert-False (Test-Valid (New-Block -DiffApproved ''))                   'empty diff_approved -> invalid (fail-open closed)'
Assert-False (Test-Valid (New-Block -DiffApproved 'maybe'))             'diff_approved=maybe -> invalid (affirmative required)'
Assert-False (Test-Valid (New-Block -DiffApproved 'yesX'))              'diff_approved=yesX -> invalid (^yes\b word boundary, not a prefix match)'
Assert-False (Test-Valid (New-Block -StagedVerified 'no - divergence'))  'staged_diff_verified=no -> invalid'
Assert-False (Test-Valid (New-Block -Ownership 'robot'))                 'commit_ownership=robot -> invalid'
Assert-True  (Test-Valid (New-Block -Ownership 'user'))                  'commit_ownership=user -> valid'
Assert-False (Test-Valid (New-Block -RuleCoverage 'false'))              'rule_coverage_passed=false at tier 2 -> invalid'
Assert-False (Test-Valid (New-Block -RuleCoverage 'nope'))               'rule_coverage_passed=nope -> invalid'

Write-Host "`n=== subject| ===" -ForegroundColor Cyan
Assert-False (Test-Valid (New-Block -ProposedSubject ''))                'empty proposed_subject -> invalid'
Assert-True  (Test-Valid (New-Block -ProposedSubject 'add List<T> support')) 'proposed_subject containing List<T> (angle brackets) is NOT a placeholder false-positive'
Assert-False (Test-Valid (New-Block -ProposedSubject '<exact -m string>'))  'proposed_subject that IS the unsubstituted template placeholder -> invalid'
Assert-True  (Test-Valid (New-Block -ProposedSubject 'Revert "add app"'))   'proposed_subject with a quoted revert subject -> valid (parser not truncated at the inner quote; PR#89 Copilot)'
Assert-True  (Test-Valid (New-Block -ProposedSubject '"Fix" the parser'))   'proposed_subject starting with a quoted word -> valid (old [^"]* captured empty and false-blocked; PR#89 Copilot)'
Assert-False ((Test-PreCommitGateBlock -BlockLines ((New-Block -SubjectApproved 'yes:t5:"looks good"') | ForEach-Object { if ($_ -cmatch '^subject\|') { $_ -creplace 'proposed_subject="[^"]*"', 'proposed_subject="unclosed-subject' } else { $_ } }) -ExpectedParentSha $ValidParent -GovernanceTier 2).Valid) 'proposed_subject with no closing quote, later field carries a quoted phrase -> invalid (anchored to |subject_approved=; old .*? would latch the later quote and fail-open; PR#89)'
Assert-False (Test-Valid (New-Block -SubjectApproved 'no'))              'subject_approved=no -> invalid'
Assert-False (Test-Valid (New-Block -FormatCheck 'single_line:no,co_authored_by_trailer:no,body:no,conventional_commit_prefix:no,subject_length_chars:42'))     'format_check single_line:no -> invalid (PR#89 rr-integ)'
Assert-False (Test-Valid (New-Block -FormatCheck 'single_line:yesX,co_authored_by_trailer:no,body:no,conventional_commit_prefix:no,subject_length_chars:42')) 'format_check single_line:yesX (unanchored) -> invalid (PR#89 rr-integ)'
Assert-False (Test-Valid (New-Block -FormatCheck 'single_line:yes,co_authored_by_trailer:yes,body:no,conventional_commit_prefix:no,subject_length_chars:42')) 'format_check trailer:yes -> invalid (declares a format violation)'
Assert-False (Test-Valid (New-Block -FormatCheck 'single_line:yes,co_authored_by_trailer:no,body:yes,conventional_commit_prefix:no,subject_length_chars:42')) 'format_check body:yes -> invalid (PR#89 rr-integ)'
Assert-False (Test-Valid (New-Block -FormatCheck 'single_line:yes,co_authored_by_trailer:no,body:no,conventional_commit_prefix:yes,subject_length_chars:42')) 'format_check conventional_commit_prefix:yes -> invalid (PR#89 rr-integ)'
Assert-False (Test-Valid (New-Block -FormatCheck 'single_line:yes,body:no,conventional_commit_prefix:no,subject_length_chars:42')) 'format_check missing co_authored_by_trailer subfield -> invalid (PR#89 rr-integ)'
Assert-False (Test-Valid (New-Block -FormatCheck 'single_line:yes,co_authored_by_trailer:no,body:no,conventional_commit_prefix:no,subject_length_chars:999')) 'format_check subject_length_chars 999 (> 72) -> invalid (PR#89 rr-integ)'
Assert-False (Test-Valid (New-Block -FormatCheck 'single_line:yes,co_authored_by_trailer:no,body:no,conventional_commit_prefix:no')) 'format_check missing subject_length_chars -> invalid (PR#89 rr-integ)'
Assert-False (Test-Valid (New-Block -FormatCheck 'single_line:yes,co_authored_by_trailer:no,body:no,conventional_commit_prefix:no,subject_length_chars:x')) 'format_check non-integer subject_length_chars -> invalid (PR#89 rr-integ)'
Assert-True  (Test-Valid (New-Block -FormatCheck 'single_line:yes,co_authored_by_trailer:no,body:no,conventional_commit_prefix:no,subject_length_chars:72')) 'format_check subject_length_chars 72 (boundary) -> valid (PR#89 rr-integ)'
Assert-False (Test-Valid (New-Block -FormatCheck 'not_single_line:yes,co_authored_by_trailer:no,body:no,conventional_commit_prefix:no,subject_length_chars:42')) 'format_check prefixed key not_single_line -> invalid (left token boundary; PR#89 rr-integ)'
Assert-False (Test-Valid (New-Block -FormatCheck 'single_line:yes,co_authored_by_trailer:no,body:no,conventional_commit_prefix:no,subject_length_chars:99999999999999999999')) 'format_check subject_length_chars overflow -> invalid, no throw (PR#89 rr-integ)'
Assert-False (Test-Valid (New-Block -FormatCheck 'single_line:yes,co_authored_by_trailer:no,body:yes,body:no,conventional_commit_prefix:no,subject_length_chars:42')) 'format_check contradictory duplicate body:yes,body:no -> invalid (PR#89 rr-integ)'
Assert-False (Test-Valid (New-Block -FormatCheck 'single_line:no,single_line:yes,co_authored_by_trailer:no,body:no,conventional_commit_prefix:no,subject_length_chars:42')) 'format_check duplicate single_line -> invalid (PR#89 rr-integ)'
Assert-False (Test-Valid (New-Block -FormatCheck 'single_line:yes,co_authored_by_trailer:no,body:no,conventional_commit_prefix:no,subject_length_chars:42,extra:foo')) 'format_check unknown subfield -> invalid (PR#89 rr-integ)'
Assert-False ((Test-PreCommitGateBlock -BlockLines ((New-Block) | ForEach-Object { $_ -replace '\|format_check=[^|]*','' }) -ExpectedParentSha $ValidParent -GovernanceTier 2).Valid) 'missing format_check key -> invalid (PR#89 rr-integ)'

Assert-True  (Test-Valid (New-Block -Subject 'Revert "add app"' -FormatCheck 'single_line:no,co_authored_by_trailer:no,body:yes,conventional_commit_prefix:no,subject_length_chars:16')) 'format_check revert subject: single_line:no,body:yes -> valid (revert carve-out)'
Assert-True  (Test-Valid (New-Block -Subject 'Revert "add app"' -FormatCheck 'single_line:yes,co_authored_by_trailer:no,body:no,conventional_commit_prefix:no,subject_length_chars:16')) 'format_check revert subject: single_line:yes,body:no -> valid (no false-block for a single-line revert subject)'
Assert-False (Test-Valid (New-Block -Subject 'Revert "add app"' -FormatCheck 'single_line:no,co_authored_by_trailer:yes,body:yes,conventional_commit_prefix:no,subject_length_chars:16')) 'format_check revert subject: co_authored_by_trailer:yes still -> invalid (trailer stays strict)'
Assert-False (Test-Valid (New-Block -Subject 'Revert "add app"' -FormatCheck 'single_line:no,co_authored_by_trailer:no,body:yes,conventional_commit_prefix:yes,subject_length_chars:16')) 'format_check revert subject: conventional_commit_prefix:yes still -> invalid (prefix stays strict)'
Assert-True  (Test-Valid (New-Block -Subject 'Revert "add app"' -FormatCheck 'single_line:no,co_authored_by_trailer:no,body:yes,conventional_commit_prefix:no,subject_length_chars:81')) 'format_check revert subject: subject_length_chars 81 (>72) -> valid (ceiling waived for genuine reverts, aligns with check-commit-message)'
Assert-False (Test-Valid (New-Block -Subject 'Revert "add app"' -FormatCheck 'single_line:no,co_authored_by_trailer:no,body:yes,conventional_commit_prefix:no,subject_length_chars:99999999999999999999')) 'format_check revert subject: subject_length_chars overflow -> invalid (non-negative integer still required)'
Assert-False (Test-Valid (New-Block -Subject 'mechanize the pre-commit gate' -FormatCheck 'single_line:no,co_authored_by_trailer:no,body:yes,conventional_commit_prefix:no,subject_length_chars:16')) 'format_check non-revert subject: single_line:no,body:yes still -> invalid (relaxation is revert-only)'

Write-Host "`n=== bounded sub-block scan (no over-read) + placeholder ===" -ForegroundColor Cyan
Assert-False (Test-Valid (New-Block -Slugs @()))                         'tier2 core_rules with no slug bullets -> invalid'
Assert-True  (Test-Valid (New-Block -Slugs @()) 0)                       'tier0 core_rules with no slug bullets -> valid (relaxed)'
Assert-False (Test-Valid (New-Block -Slugs @('  - slug:<slug> status:applied'))) 'placeholder slug -> invalid'
# over-read: empty core_rules_acknowledged header followed by staged_files bullets must NOT satisfy the empty header
$overread = @("parent_sha: $ValidParent", 'commit_subject: x', 'PRE-COMMIT GATE PASSED',
    'gate|diff_shown=yes|diff_approved=yes|staged_diff_verified=yes|commit_ownership=agent|rule_coverage_passed=true',
    'subject|proposed_subject="x"|subject_approved=yes', 'core_rules_acknowledged:', 'staged_files:', '  - a.cs')
Assert-False ((Test-PreCommitGateBlock -BlockLines $overread -ExpectedParentSha $ValidParent -GovernanceTier 2).Valid) 'empty core_rules header cannot be satisfied by a later section bullet'
Assert-True  (Test-Valid (New-Block -Slugs @('  - slug:x status:applied sites:[a.cs:1] metric:rg=0/0 disp:keep keep_reason:"guards List<T> path"'))) 'quoted List<T> in keep_reason does NOT false-trigger placeholder'
Assert-False (Test-Valid (New-Block -Slugs @('  - slug:x status:applied sites:[a.cs:1] metric:rg=0/0 disp:keep keep_reason:"<rationale>"'))) 'unsubstituted keep_reason placeholder INSIDE quotes -> invalid (strip-quotes fail-open closed; PR#89 Copilot)'
Assert-False (Test-Valid (New-Block -Staged @()))                        'empty staged_files -> invalid'
Assert-False (Test-Valid (New-Block -Staged @('  - <path>')))            'placeholder staged path -> invalid'

function New-CheckerRepo {
    # A repo that CONTAINS the checker anchor so Resolve-RepoRoot resolves + staged diffs can be built.
    $dir = New-TestGitRepository -Prefix 'pcg'
    Initialize-InstructionFixtureRepository -Directory $dir
    New-Item -ItemType Directory -Path (Join-Path $dir 'scripts') -Force | Out-Null
    Copy-Item $checkerPath (Join-Path $dir 'scripts/check-pre-commit-gate.ps1')
    Set-Content -LiteralPath (Join-Path $dir 'seed.txt') -Value 'seed'
    git -C $dir add -A 2>$null; git -C $dir commit -q -m 'seed'
    return $dir
}
function Write-Receipt { param([string] $Dir, [string[]] $Block)
    $p = Join-Path $Dir '.github/pr-quality-gate/audits'
    New-Item -ItemType Directory -Path $p -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $p 'pre-commit-gate-last.md') -Value $Block }
function Invoke-Checker { param([string] $Dir, [string[]] $CheckerArgs)
    $out = & pwsh -NoProfile -File $checkerPath -RepoRoot $Dir @CheckerArgs 2>&1
    return [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Output = ($out | Out-String) } }

Write-Host "`n=== check-pre-commit-gate.ps1 -StagedMode -WorktreeReceipt ===" -ForegroundColor Cyan
$repo = New-CheckerRepo
$head = (git -C $repo rev-parse HEAD).Trim()
$rc = Invoke-Checker -Dir $repo -CheckerArgs @('-StagedMode', '-WorktreeReceipt')
Assert-True ($rc.ExitCode -eq 0) 'no staged changes -> exit 0'
Set-Content -LiteralPath (Join-Path $repo 'code.cs') -Value 'class C {}'; git -C $repo add code.cs
$rc = Invoke-Checker -Dir $repo -CheckerArgs @('-StagedMode', '-WorktreeReceipt')
Assert-True ($rc.ExitCode -eq 1) 'staged code, no receipt -> exit 1 (block)'
Write-Receipt -Dir $repo -Block (New-Block -Parent $head -Staged @('  - code.cs'))
$rc = Invoke-Checker -Dir $repo -CheckerArgs @('-StagedMode', '-WorktreeReceipt')
Assert-True ($rc.ExitCode -eq 0) 'staged code, valid receipt -> exit 0'
Write-Receipt -Dir $repo -Block (New-Block -Parent 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' -Staged @('  - code.cs'))
$rc = Invoke-Checker -Dir $repo -CheckerArgs @('-StagedMode', '-WorktreeReceipt')
Assert-True ($rc.ExitCode -eq 1) 'staged code, stale receipt (wrong parent) -> exit 1'
Write-Receipt -Dir $repo -Block (New-Block -Parent $head -Staged @('  - code.cs'))
$rc = Invoke-Checker -Dir $repo -CheckerArgs @('-StagedMode')
Assert-True ($rc.ExitCode -eq 2 -and $rc.Output -match 'staged mode requires -WorktreeReceipt') 'staged mode without -WorktreeReceipt -> exit 2 even with a valid receipt (index receipts never read)'

Write-Host "`n=== amend path: PANEL_GATE_AMEND (PR#89 Copilot) ===" -ForegroundColor Cyan
Remove-Item Env:\PANEL_GATE_AMEND -ErrorAction SilentlyContinue
$amendRepo = New-CheckerRepo
Set-Content -LiteralPath (Join-Path $amendRepo 'x.txt') -Value 'x'; git -C $amendRepo add x.txt; git -C $amendRepo commit -q -m 'second'
$aHeadShort = (git -C $amendRepo rev-parse HEAD).Substring(0, 8)
$aParent = (git -C $amendRepo rev-parse HEAD^).Trim(); $aParentShort = $aParent.Substring(0, 8)
Set-Content -LiteralPath (Join-Path $amendRepo 'code.cs') -Value 'class C {}'; git -C $amendRepo add code.cs
$env:PANEL_GATE_AMEND = '1'
try { $rc = Invoke-Checker -Dir $amendRepo -CheckerArgs @('-StagedMode', '-WorktreeReceipt') } finally { Remove-Item Env:\PANEL_GATE_AMEND }
Assert-True ($rc.ExitCode -eq 1 -and $rc.Output -match $aParentShort -and $rc.Output -notmatch $aHeadShort) 'missing-receipt hint under PANEL_GATE_AMEND shows HEAD^, not HEAD'
Write-Receipt -Dir $amendRepo -Block (New-Block -Parent $aParent -Staged @('  - code.cs'))
$rc = Invoke-Checker -Dir $amendRepo -CheckerArgs @('-StagedMode', '-WorktreeReceipt')
Assert-True ($rc.ExitCode -eq 1) 'HEAD^-bound receipt without PANEL_GATE_AMEND -> exit 1 (stale)'
$env:PANEL_GATE_AMEND = '1'
try { $rc = Invoke-Checker -Dir $amendRepo -CheckerArgs @('-StagedMode', '-WorktreeReceipt') } finally { Remove-Item Env:\PANEL_GATE_AMEND }
Assert-True ($rc.ExitCode -eq 0) 'HEAD^-bound receipt with PANEL_GATE_AMEND=1 -> exit 0 (amend path accepted)'
$rootRepo = New-CheckerRepo
Set-Content -LiteralPath (Join-Path $rootRepo 'code.cs') -Value 'class C {}'; git -C $rootRepo add code.cs
Write-Receipt -Dir $rootRepo -Block (New-Block -Parent 'NONE' -Staged @('  - code.cs'))
$env:PANEL_GATE_AMEND = '1'
try { $rc = Invoke-Checker -Dir $rootRepo -CheckerArgs @('-StagedMode', '-WorktreeReceipt') } finally { Remove-Item Env:\PANEL_GATE_AMEND }
Assert-True ($rc.ExitCode -eq 0) 'root-commit amend: EMPTY_TREE-bound receipt (parent_sha:NONE) with PANEL_GATE_AMEND -> exit 0'

# tier-0 (pure docs) still requires the receipt (no tier-0 early-exit)
$docsRepo = New-CheckerRepo
$dHead = (git -C $docsRepo rev-parse HEAD).Trim()
Set-Content -LiteralPath (Join-Path $docsRepo 'README.md') -Value 'docs'; git -C $docsRepo add README.md
$rc = Invoke-Checker -Dir $docsRepo -CheckerArgs @('-StagedMode', '-WorktreeReceipt')
Assert-True ($rc.ExitCode -eq 1) 'tier-0 docs-only staged diff still requires the receipt (no tier-0 skip)'
Write-Receipt -Dir $docsRepo -Block (New-Block -Parent $dHead -Slugs @() -RuleCoverage 'true' -Staged @('  - README.md'))
$rc = Invoke-Checker -Dir $docsRepo -CheckerArgs @('-StagedMode', '-WorktreeReceipt')
Assert-True ($rc.ExitCode -eq 0) 'tier-0 docs with a valid (slug-relaxed) receipt -> exit 0'

Write-Host "`n=== check-pre-commit-gate.ps1 history mode (test-only) ===" -ForegroundColor Cyan
$hRepo = New-CheckerRepo
$base = (git -C $hRepo rev-parse HEAD).Trim()
# a commit that COMMITS a valid receipt into the tree (history mode reads it from the tree)
Set-Content -LiteralPath (Join-Path $hRepo 'f.cs') -Value 'class F {}'
$rpath = Join-Path $hRepo '.github/pr-quality-gate/audits'; New-Item -ItemType Directory -Path $rpath -Force | Out-Null
Set-Content -LiteralPath (Join-Path $rpath 'pre-commit-gate-last.md') -Value (New-Block -Parent $base -Staged @('  - f.cs'))
git -C $hRepo add -A 2>$null; git -C $hRepo commit -q -m 'with receipt'
$rc = Invoke-Checker -Dir $hRepo -CheckerArgs @('-BaseRef', $base)
Assert-True ($rc.ExitCode -eq 0) 'history mode: commit carrying a valid in-tree receipt -> exit 0'
Set-Content -LiteralPath (Join-Path $hRepo 'g.cs') -Value 'class G {}'; git -C $hRepo rm -q --cached --ignore-unmatch .github/pr-quality-gate/audits/pre-commit-gate-last.md 2>$null | Out-Null
Remove-Item -LiteralPath (Join-Path $rpath 'pre-commit-gate-last.md') -Force
git -C $hRepo add -A 2>$null; git -C $hRepo commit -q -m 'no receipt'
$rc = Invoke-Checker -Dir $hRepo -CheckerArgs @('-BaseRef', $base)
Assert-True ($rc.ExitCode -eq 1) 'history mode: a commit missing the in-tree receipt -> exit 1'

Remove-TestTempDirectories

try {
    $hookRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $hookRepo = New-TestGitRepository -Prefix 'enforcement-hook'
    foreach ($folder in @('.githooks','scripts/lib','.github/instructions')) { New-Item -ItemType Directory -Path (Join-Path $hookRepo $folder) -Force | Out-Null }
    Copy-Item -LiteralPath (Join-Path $hookRoot '.githooks/pre-commit') -Destination (Join-Path $hookRepo '.githooks/pre-commit')
    if ($env:OS -ne 'Windows_NT') { & chmod +x (Join-Path $hookRepo '.githooks/pre-commit') }
    Copy-Item -LiteralPath (Join-Path $hookRoot 'scripts/check-instructions-refs.ps1') -Destination (Join-Path $hookRepo 'scripts/check-instructions-refs.ps1')
    Copy-Item -LiteralPath (Join-Path $hookRoot 'scripts/lib/repo-root.psm1') -Destination (Join-Path $hookRepo 'scripts/lib/repo-root.psm1')
    Set-Content -LiteralPath (Join-Path $hookRepo 'scripts/check-post-code-change.ps1') -Value 'exit 0'
    [void](New-TestCommit -Directory $hookRepo -File '.github/instructions/valid.instructions.md' -Content 'fixture' -Message 'hook fixture')
    Set-Content -LiteralPath (Join-Path $hookRepo '.github/instructions/active-profile.instructions.md') -Value 'stale profile'
    $hookOutput = @(& git -C $hookRepo -c core.hooksPath=.githooks commit --allow-empty -m probe 2>&1)
    Assert-True ($LASTEXITCODE -ne 0 -and ($hookOutput -join ' ') -match 'active-profile.instructions.md') 'precommit hook runs instruction refs checker and rejects stale local profile'
    Remove-Item -LiteralPath (Join-Path $hookRepo '.github/instructions/active-profile.instructions.md')
    Remove-Item -LiteralPath (Join-Path $hookRepo 'scripts/check-instructions-refs.ps1')
    & git -C $hookRepo add scripts/check-instructions-refs.ps1 2>$null
    $missingCheckerOutput = @(& git -C $hookRepo -c core.hooksPath=.githooks commit --allow-empty -m probe 2>&1)
    Assert-True ($LASTEXITCODE -ne 0 -and ($missingCheckerOutput -join ' ') -match 'cannot run required scripts/check-instructions-refs.ps1') 'hook fails closed when committed instruction refs checker is missing from worktree'
    Copy-Item -LiteralPath (Join-Path $hookRoot 'scripts/check-instructions-refs.ps1') -Destination (Join-Path $hookRepo 'scripts/check-instructions-refs.ps1')
    & git -C $hookRepo add scripts/check-instructions-refs.ps1 2>$null
    Set-Content -LiteralPath (Join-Path $hookRepo 'scripts/check-post-code-change.ps1') -Value 'exit 1'
    $divergentOutput = @(& git -C $hookRepo -c core.hooksPath=.githooks commit --allow-empty -m probe 2>&1)
    Assert-True ($LASTEXITCODE -ne 0 -and ($divergentOutput -join ' ') -match 'unstaged hook or checker edits.*scripts/check-post-code-change\.ps1') 'hook rejects unstaged hook-invoked checker before executing it'
    Set-Content -LiteralPath (Join-Path $hookRepo 'scripts/check-post-code-change.ps1') -Value 'exit 0'
    foreach ($guardedScript in @('scripts/Get-ReviewedArtifactId.ps1','scripts/sync-critical-rules.sh')) {
        Set-Content -LiteralPath (Join-Path $hookRepo $guardedScript) -Value 'original'
        & git -C $hookRepo add $guardedScript 2>$null
        & git -C $hookRepo -c core.hooksPath= commit -q --no-verify -m "seed $guardedScript" 2>$null
        Set-Content -LiteralPath (Join-Path $hookRepo $guardedScript) -Value 'unstaged edit'
        $scriptOutput = @(& git -C $hookRepo -c core.hooksPath=.githooks commit --allow-empty -m probe 2>&1)
        Assert-True ($LASTEXITCODE -ne 0 -and ($scriptOutput -join ' ') -match "unstaged hook or checker edits.*$([regex]::Escape($guardedScript))") "hook rejects unstaged $guardedScript"
        Set-Content -LiteralPath (Join-Path $hookRepo $guardedScript) -Value 'original'
    }
    Add-Content -LiteralPath (Join-Path $hookRepo 'scripts/lib/repo-root.psm1') -Value "`nWrite-Output 'changed'"
    $libraryOutput = @(& git -C $hookRepo -c core.hooksPath=.githooks commit --allow-empty -m probe 2>&1)
    Assert-True ($LASTEXITCODE -ne 0 -and ($libraryOutput -join ' ') -match 'unstaged hook or checker edits.*scripts/lib/repo-root\.psm1') 'hook rejects unstaged enforcement library'
    Add-Content -LiteralPath (Join-Path $hookRepo '.githooks/pre-commit') -Value "`nprintf 'changed hook'"
    $hookChangedOutput = @(& git -C $hookRepo -c core.hooksPath=.githooks commit --allow-empty -m probe 2>&1)
    Assert-True ($LASTEXITCODE -ne 0 -and ($hookChangedOutput -join ' ') -match 'unstaged hook or checker edits.*\.githooks/pre-commit') 'hook rejects its own unstaged changes'
    & git -C $hookRepo checkout -q -- .githooks/pre-commit scripts/lib/repo-root.psm1
    & git -C $hookRepo add -A 2>$null
    & git -C $hookRepo -c core.hooksPath= commit -q --no-verify -m 'settle hook fixture' 2>$null
    foreach ($flag in '--skip-worktree', '--assume-unchanged') {
        & git -C $hookRepo update-index $flag -- scripts/check-post-code-change.ps1
        Set-Content -LiteralPath (Join-Path $hookRepo 'scripts/check-post-code-change.ps1') -Value 'exit 0 # hidden edit'
        Assert-True ([string]::IsNullOrWhiteSpace((git -C $hookRepo status --porcelain -- scripts/check-post-code-change.ps1 | Out-String))) "fixture: $flag hides the checker edit from git status"
        $hiddenOutput = @(& git -C $hookRepo -c core.hooksPath=.githooks commit --allow-empty -m probe 2>&1)
        Assert-True ($LASTEXITCODE -ne 0 -and ($hiddenOutput -join ' ') -match 'unstaged hook or checker edits.*scripts/check-post-code-change\.ps1') "hook rejects a $flag-hidden checker edit"
        & git -C $hookRepo update-index ($flag -replace '^--', '--no-') -- scripts/check-post-code-change.ps1
        & git -C $hookRepo checkout -q -- scripts/check-post-code-change.ps1
    }
} finally { Remove-TestTempDirectories }

Complete-TestRun
