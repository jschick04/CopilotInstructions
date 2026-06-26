#Requires -Version 5.1
# Standalone pwsh self-test for scripts/lib/hygiene-signals.psm1 (B1 structural-hygiene diff-signal floor).
# Run: pwsh -File scripts/tests/hygiene-signals.tests.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'lib/hygiene-signals.psm1'
Import-Module $modulePath -Force
. (Join-Path $PSScriptRoot 'test-common.ps1')

$script:Pass = 0
$script:Fail = 0

# The actual P2a file cohort (flat in the EXISTING PublisherMetadata/ dir) - the motivating incident.
$p2aFiles = @(
    'src/EventLogExpert/PublisherMetadata/WevtTemplateReader.cs',
    'src/EventLogExpert/PublisherMetadata/WevtTemplateSynthesizer.cs',
    'src/EventLogExpert/PublisherMetadata/WevtTypeNames.cs',
    'src/EventLogExpert/PublisherMetadata/OfflineWevtProviderReader.cs',
    'src/EventLogExpert/PublisherMetadata/MessageTableSession.cs'
)

Write-Host '=== Test-IsCodeFile (scope: compiled-language source only) ==='
Assert-True  (Test-IsCodeFile 'a/B.cs')        'cs is a code file'
Assert-True  (Test-IsCodeFile 'a/B.ts')        'ts is a code file'
Assert-False (Test-IsCodeFile 'scripts/x.ps1') 'ps1 is NOT a code file (flat utility, not a VSA slice)'
Assert-False (Test-IsCodeFile 'docs/x.md')     'md is NOT a code file'
Assert-False (Test-IsCodeFile 'a/x.json')      'json is NOT a code file'

Write-Host '=== Get-DomainTokens (>=4 chars, role-suffix stop-list excluded) ==='
Assert-True  ((Get-DomainTokens 'WevtTemplateReader.cs') -contains 'Wevt')       'Wevt is a domain token'
Assert-True  ((Get-DomainTokens 'WevtTemplateReader.cs') -contains 'Template')   'Template is a domain token'
Assert-False ((Get-DomainTokens 'WevtTemplateReader.cs') -contains 'Reader')     'Reader is stop-listed (role suffix)'
Assert-False ((Get-DomainTokens 'ProviderMetadata.cs')   -contains 'Provider')   'Provider is stop-listed'
Assert-False ((Get-DomainTokens 'MtaProviderSource.cs')  -contains 'Source')     'Source is stop-listed'

Write-Host '=== Test-CohesiveSliceSignal (the (i) detector) ==='
$p2a = Test-CohesiveSliceSignal -AddedCodeFiles $p2aFiles
Assert-True  $p2a.Fired                         'P2a cohort fires (5 files, Wevt shared by >=2) - catches its own motivating case'
Assert-True  (($p2a.Token -split ',') -contains 'Wevt')  'P2a fires including the Wevt domain token'
# established token-dense dir: 6 *Provider files - Provider is stop-listed so NO domain-token cohesion -> no fire
$providerDir = 1..6 | ForEach-Object { "src/PublisherMetadata/X${_}Provider.cs" }
Assert-False (Test-CohesiveSliceSignal -AddedCodeFiles $providerDir).Fired 'established dir of *Provider files does NOT fire (stop-list defuses desensitization)'
# below threshold: 2 cohesive files -> no fire
Assert-False (Test-CohesiveSliceSignal -AddedCodeFiles @('a/WevtReader.cs','a/WevtWriter.cs')).Fired '2 files below the >=3 threshold do not fire'
# 3 role-named files with no shared domain token -> no fire (disclosed false-negative)
Assert-False (Test-CohesiveSliceSignal -AddedCodeFiles @('a/Handler.cs','a/Command.cs','a/Result.cs')).Fired '3 pure-role-named files (no shared domain token) do not fire (disclosed FN)'

Write-Host '=== Test-VisibilityDeltaSignal + Test-DiSignal (operate on pre-filtered visibility-relevant diff lines) ==='
Assert-True  (Test-VisibilityDeltaSignal @('+    public sealed class Foo'))       'added public class is a visibility delta'
Assert-True  (Test-VisibilityDeltaSignal @('-    internal int Bar()'))            'removed internal member is a visibility delta'
Assert-True  (Test-VisibilityDeltaSignal @('+[assembly: InternalsVisibleTo("X")]')) 'IVT is a visibility/friend-grant delta'
Assert-False (Test-VisibilityDeltaSignal @('+    var x = ComputeThing();'))        'a plain added line is not a visibility delta'
Assert-True  (Test-DiSignal @('+        services.AddSingleton<IFoo, Foo>();'))     'AddSingleton is a DI signal'
Assert-True  (Test-DiSignal @('+    public Foo([Inject] IBar bar) { }'))           '[Inject] is a DI signal'
Assert-True  (Test-DiSignal @('+    public Foo([FromKeyedServices("cache")] IBar bar) { }')) '[FromKeyedServices("...")] (with args) is a DI signal'
Assert-False (Test-DiSignal @('+    [FromKeyedServicesRegistry] private int _x;'))            'an attribute merely starting with FromKeyedServices does NOT false-fire (word-boundary anchor)'
Assert-False (Test-DiSignal @('-        services.AddSingleton<IFoo, Foo>();'))     'a REMOVED DI registration is not a new-DI signal'

Write-Host '=== Get-VisibilityRelevantDiffLines (code + project-file hunks; docs/script prose excluded) ==='
$mixedDiff = @(
    'diff --git a/x.cs b/x.cs', '+++ b/x.cs', '@@ -0,0 +1 @@', '+    public class Real',
    'diff --git a/README.md b/README.md', '+++ b/README.md', '@@ -0,0 +1 @@', '+the word public appears in prose'
)
$codeLines = Get-VisibilityRelevantDiffLines -DiffLines $mixedDiff
Assert-True  ($codeLines -contains '+    public class Real')                  'the .cs +line is included'
Assert-False ($codeLines -contains '+the word public appears in prose')      'the .md prose +line is EXCLUDED (no false-fire on docs)'
# csproj IVT (the PREFERRED .NET 5+ placement) must reach the visibility scope (regression: previously a dead path)
$csprojDiff = @('diff --git a/X.csproj b/X.csproj', '+++ b/X.csproj', '@@ -0,0 +1 @@', '+    <InternalsVisibleTo Include="X.Tests" />')
$csprojLines = Get-VisibilityRelevantDiffLines -DiffLines $csprojDiff
Assert-True  (Test-VisibilityDeltaSignal $csprojLines) 'csproj <InternalsVisibleTo> reaches + fires the visibility signal'

Write-Host '=== Test-FieldJustified (present-with-justified-value; bare/uncited N/A rejected) ==='
Assert-True  (Test-FieldJustified 'ran (3 placements checked, 0 misplaced)')   'ran (...) is justified'
Assert-True  (Test-FieldJustified 'N/A - library-restructure.md:80')           'cited N/A (playbook:line) is justified'
Assert-False (Test-FieldJustified 'N/A')                                       'bare N/A is NOT justified'
Assert-False (Test-FieldJustified 'N/A: small change')                         'uncited N/A reason is NOT justified'
Assert-False (Test-FieldJustified '')                                          'empty value is NOT justified'
Assert-False (Test-FieldJustified $null)                                       'absent value is NOT justified'

Write-Host '=== Get-StructuralHygieneViolations (end-to-end) ==='
$p2aNameStatus = $p2aFiles | ForEach-Object { "A`t$_" }
$ledgerMissing = @('POST-CODE-CHANGE LEDGER', '  gates:', '    build: passed')
$v1 = @(Get-StructuralHygieneViolations -NameStatusLines $p2aNameStatus -DiffLines @() -LedgerLines $ledgerMissing)
Assert-True ($v1.Count -ge 1) 'P2a cohort + a ledger lacking vsa-audit -> violation (the gap B1 would have caught)'
$ledgerJustified = @('POST-CODE-CHANGE LEDGER', '    vsa-audit: ran (5 placements, 5 moved to Wevt slice)', '    library-restructure: invoked')
$v2 = @(Get-StructuralHygieneViolations -NameStatusLines $p2aNameStatus -DiffLines @() -LedgerLines $ledgerJustified)
Assert-True ($v2.Count -eq 0) 'P2a cohort + a justified vsa-audit + invoked library-restructure -> clean'
# the library-restructure decision-record enforcement
$ledgerLrDefault = @('    vsa-audit: ran (placed)', '    library-restructure: not-required-trigger-not-detected')
$v3 = @(Get-StructuralHygieneViolations -NameStatusLines $p2aNameStatus -DiffLines @() -LedgerLines $ledgerLrDefault)
Assert-True ($v3.Count -ge 1) 'cohesive slice + library-restructure=not-required-trigger-not-detected -> violation (decision-record enforcement)'
# THIS PR's own shape: only .ps1 + .md changes -> NO violations even with an empty hygiene receipt (no self-fire)
$thisPrNameStatus = @("A`tscripts/lib/hygiene-signals.psm1", "A`tscripts/tests/hygiene-signals.tests.ps1", "M`t.github/playbooks/review-workflow-gates-sweeps.md")
$thisPrDiff = @('diff --git a/docs/x.md b/docs/x.md', '+++ b/docs/x.md', '+services.AddSingleton example in prose', '+public internal in prose')
$v4 = @(Get-StructuralHygieneViolations -NameStatusLines $thisPrNameStatus -DiffLines $thisPrDiff -LedgerLines @('build: passed'))
Assert-True ($v4.Count -eq 0) 'a docs/scripts-only diff (this PR) does NOT fire any signal (no self-trigger)'

Write-Host ''
if ($script:Fail -gt 0) { Write-Host "Failures: $script:Fail" -ForegroundColor Red; exit 1 }
Write-Host "ALL PASS ($script:Pass assertions)"
exit 0
