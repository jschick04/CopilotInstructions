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

Write-Host '=== Test-VisibilityDeltaSignal (WIDENING-only: added exposed decl / added IVT; narrowing does NOT fire) ==='
Assert-True  (Test-VisibilityDeltaSignal @('+    public sealed class Foo'))       'added public class is a widening'
Assert-True  (Test-VisibilityDeltaSignal @('+    protected int Bar()'))           'added protected member is a widening'
Assert-True  (Test-VisibilityDeltaSignal @('+[assembly: InternalsVisibleTo("X")]')) 'added IVT friend-grant is a widening'
Assert-True  (Test-VisibilityDeltaSignal @('+[assembly: InternalsVisibleToAttribute("X")]')) 'the InternalsVisibleToAttribute full-name form is a widening'
Assert-False (Test-VisibilityDeltaSignal @('+    var InternalsVisibleTo = 5;'))   'an identifier named InternalsVisibleTo (no [assembly:) does NOT fire'
Assert-False (Test-VisibilityDeltaSignal @('+[assembly: InternalsVisibleToFoo("X")]')) 'a different attribute merely starting with InternalsVisibleTo does NOT fire (word boundary)'
Assert-False (Test-VisibilityDeltaSignal @('-    internal int Bar()'))            'a REMOVED internal member is narrowing - does NOT fire (LPA allows removals)'
Assert-False (Test-VisibilityDeltaSignal @('-[assembly: InternalsVisibleTo("X")]')) 'a REMOVED IVT is narrowing - does NOT fire'
Assert-False (Test-VisibilityDeltaSignal @('+    private int _x;'))               'an added PRIVATE member is not a widening (private is not exposed)'
Assert-False (Test-VisibilityDeltaSignal @('+    var x = ComputeThing();'))        'a plain added line is not a widening'
Assert-True  (Test-DiSignal @('+        services.AddSingleton<IFoo, Foo>();'))     'AddSingleton is a DI signal'
Assert-True  (Test-DiSignal @('+    public Foo([Inject] IBar bar) { }'))           '[Inject] is a DI signal'
Assert-True  (Test-DiSignal @('+    public Foo([FromKeyedServices("cache")] IBar bar) { }')) '[FromKeyedServices("...")] (with args) is a DI signal'
Assert-False (Test-DiSignal @('+    [FromKeyedServicesRegistry] private int _x;'))            'an attribute merely starting with FromKeyedServices does NOT false-fire (word-boundary anchor)'
Assert-False (Test-DiSignal @('-        services.AddSingleton<IFoo, Foo>();'))     'a REMOVED DI registration is not a new-DI signal'
Assert-False (Test-DiSignal @('+        // services.AddSingleton<IFoo, Foo>();'))  'a commented-out services.Add (// line) does NOT fire (comment-skip)'
Assert-False (Test-DiSignal @('+     * services.AddScoped<IBar, Bar>() example')) 'a block-comment continuation (* line) mentioning services.Add does NOT fire'

Write-Host '=== Get-VisibilityRelevantDiffLines (ADDED lines of code+project files; inHeader guard; docs excluded) ==='
$mixedDiff = @(
    'diff --git a/x.cs b/x.cs', '+++ b/x.cs', '@@ -0,0 +1 @@', '+    public class Real',
    'diff --git a/README.md b/README.md', '+++ b/README.md', '@@ -0,0 +1 @@', '+the word public appears in prose'
)
$codeLines = Get-VisibilityRelevantDiffLines -DiffLines $mixedDiff
Assert-True  ($codeLines -contains '+    public class Real')                  'the .cs +line is included'
Assert-False ($codeLines -contains '+the word public appears in prose')      'the .md prose +line is EXCLUDED (no false-fire on docs)'
# csproj IVT (the PREFERRED .NET 5+ placement) must reach the visibility scope (regression: previously a dead path)
$csprojDiff = @('diff --git a/X.csproj b/X.csproj', '+++ b/X.csproj', '@@ -0,0 +1 @@', '+    <InternalsVisibleTo Include="X.Tests" />')
Assert-True  (Test-VisibilityDeltaSignal (Get-VisibilityRelevantDiffLines -DiffLines $csprojDiff)) 'csproj <InternalsVisibleTo> reaches + fires the visibility signal'
# inHeader guard: a hunk CONTENT line that looks like a `+++ b/<path>` header must NOT mark a docs file relevant
$mimicDiff = @('diff --git a/notes.md b/notes.md', '+++ b/notes.md', '@@ -1,2 +1,2 @@', '+++ b/fake.cs', '+    public class NotCode { }')
Assert-False (Test-VisibilityDeltaSignal (Get-VisibilityRelevantDiffLines -DiffLines $mimicDiff)) 'a header-shaped content line in a .md hunk does not spuriously mark it visibility-relevant'
# additions-only: a DELETED .cs (only `-` lines, +++ is /dev/null) contributes nothing (deletion = narrowing)
$deletedCsDiff = @('diff --git a/Foo.cs b/Foo.cs', 'deleted file mode 100644', '--- a/Foo.cs', '+++ /dev/null', '@@ -1,1 +0,0 @@', '-public class Foo { }')
Assert-False (Test-VisibilityDeltaSignal (Get-VisibilityRelevantDiffLines -DiffLines $deletedCsDiff)) 'deleting a .cs file (pure narrowing) does NOT fire the widening signal'

Write-Host '=== Get-AddedIvtTargets / Test-IsTestAssemblyName / Test-NonTestIvtSignal (GATED non-test IVT) ==='
Assert-Equal 'My.Tests' ((Get-AddedIvtTargets @('+[assembly: InternalsVisibleTo("My.Tests")]')) -join ',') 'C# attribute IVT target extracted'
Assert-Equal 'My.App'   ((Get-AddedIvtTargets @('+    <InternalsVisibleTo Include="My.App" />')) -join ',')  'csproj IVT target extracted'
Assert-Equal 'My.Tests' ((Get-AddedIvtTargets @('+[assembly: System.Runtime.CompilerServices.InternalsVisibleToAttribute("My.Tests, PublicKey=00ab")]')) -join ',') 'qualified + Attribute + PublicKey form extracted (name before comma)'
Assert-Equal ''         ((Get-AddedIvtTargets @('-[assembly: InternalsVisibleTo("My.Tests")]')) -join ',')    'a REMOVED IVT is not an added target'
Assert-Equal ''         ((Get-AddedIvtTargets @('+// [assembly: InternalsVisibleTo("My.App")]')) -join ',')    'a commented-out IVT (not at line start) is NOT captured (anchored after +)'
Assert-True  (Test-IsTestAssemblyName 'Contoso.Tests')        'Foo.Tests is a test assembly'
Assert-True  (Test-IsTestAssemblyName 'Contoso.UnitTests')    'Foo.UnitTests is a test assembly'
Assert-True  (Test-IsTestAssemblyName 'Contoso.TestUtilities') 'Foo.TestUtilities is a test assembly'
Assert-True  (Test-IsTestAssemblyName 'Contoso.Specs')        'Foo.Specs (SpecFlow) is a test assembly'
Assert-True  (Test-IsTestAssemblyName 'Contoso.Fakes')        'Foo.Fakes is a test assembly'
Assert-True  (Test-IsTestAssemblyName 'Contoso.Benchmarks')   'Foo.Benchmarks is a test assembly'
Assert-False (Test-IsTestAssemblyName 'Contoso.Attestation')  'Attestation (lowercase test) is NOT a test assembly'
Assert-False (Test-IsTestAssemblyName 'Contoso.App')          'Foo.App is NOT a test assembly'
Assert-Equal 'Contoso.App' (Test-NonTestIvtSignal @('+[assembly: InternalsVisibleTo("Contoso.App")]'))   'non-test IVT target fires the gated signal'
Assert-True  ($null -eq (Test-NonTestIvtSignal @('+[assembly: InternalsVisibleTo("Contoso.Tests")]')))   'a test IVT target does NOT fire the gated signal'

Write-Host '=== Test-FieldJustified (present-with-justified-value; bare/uncited N/A rejected) ==='
Assert-True  (Test-FieldJustified 'ran (3 placements checked, 0 misplaced)')   'ran (...) is justified'
Assert-True  (Test-FieldJustified 'N/A - library-restructure.md:80')           'cited N/A (playbook:line) is justified'
Assert-False (Test-FieldJustified 'N/A')                                       'bare N/A is NOT justified'
Assert-False (Test-FieldJustified 'N/A: small change')                         'uncited N/A reason is NOT justified'
Assert-False (Test-FieldJustified '')                                          'empty value is NOT justified'
Assert-False (Test-FieldJustified $null)                                       'absent value is NOT justified'

Write-Host '=== Get-LedgerFieldValue -ParentKey (scoped read past a same-named shadowing key) ==='
$twoBlocks = @('    pre-impl-trigger-detections:', '      library-restructure: no', '    pre-impl-playbook-decisions:', '      library-restructure: invoked')
Assert-Equal 'no'      (Get-LedgerFieldValue -LedgerLines $twoBlocks -Key 'library-restructure')                                          'flat read returns the FIRST (trigger-detections) value'
Assert-Equal 'invoked' (Get-LedgerFieldValue -LedgerLines $twoBlocks -Key 'library-restructure' -ParentKey 'pre-impl-playbook-decisions') 'parent-scoped read returns the playbook-decisions value (skips the shadowing trigger-detections entry)'
Assert-True  ($null -eq (Get-LedgerFieldValue -LedgerLines $twoBlocks -Key 'library-restructure' -ParentKey 'absent-parent')) 'parent-scoped read with a missing parent block returns null'
Assert-True  ($null -eq (Get-LedgerFieldValue -LedgerLines @('    pre-impl-playbook-decisions:', '    next-sibling: x') -Key 'library-restructure' -ParentKey 'pre-impl-playbook-decisions')) 'parent-scoped read stops at the next sibling block (key absent in the parent -> null)'

Write-Host '=== Get-StructuralHygieneViolations (end-to-end) ==='
$p2aNameStatus = $p2aFiles | ForEach-Object { "A`t$_" }
$ledgerMissing = @('POST-CODE-CHANGE LEDGER', '  gates:', '    build: passed')
$v1 = @(Get-StructuralHygieneViolations -NameStatusLines $p2aNameStatus -DiffLines @() -LedgerLines $ledgerMissing)
Assert-True ($v1.Count -ge 1) 'P2a cohort + a ledger lacking vsa-audit -> violation (the gap B1 would have caught)'
$ledgerJustified = @('POST-CODE-CHANGE LEDGER', '    vsa-audit: ran (5 placements, 5 moved to Wevt slice)', '    pre-impl-trigger-detections:', '      library-restructure: yes', '    pre-impl-playbook-decisions:', '      library-restructure: invoked')
$v2 = @(Get-StructuralHygieneViolations -NameStatusLines $p2aNameStatus -DiffLines @() -LedgerLines $ledgerJustified)
Assert-True ($v2.Count -eq 0) 'P2a cohort + a justified vsa-audit + invoked library-restructure -> clean'
# the library-restructure decision-record enforcement reads pre-impl-PLAYBOOK-DECISIONS, not the same-named
# pre-impl-trigger-detections entry that shadows it earlier in a real ledger (here trigger says 'no')
$ledgerLrDefault = @('    vsa-audit: ran (placed)', '    pre-impl-trigger-detections:', '      library-restructure: no', '    pre-impl-playbook-decisions:', '      library-restructure: not-required-trigger-not-detected')
$v3 = @(Get-StructuralHygieneViolations -NameStatusLines $p2aNameStatus -DiffLines @() -LedgerLines $ledgerLrDefault)
Assert-True ($v3.Count -ge 1) 'cohesive slice + pre-impl-playbook-decisions.library-restructure=not-required-trigger-not-detected -> violation (decision-record enforcement, not shadowed by trigger-detections)'
# THIS PR's own shape: only .ps1 + .md changes -> NO violations even with an empty hygiene receipt (no self-fire)
$thisPrNameStatus = @("A`tscripts/lib/hygiene-signals.psm1", "A`tscripts/tests/hygiene-signals.tests.ps1", "M`t.github/playbooks/review-workflow-gates-sweeps.md")
$thisPrDiff = @('diff --git a/docs/x.md b/docs/x.md', '+++ b/docs/x.md', '+services.AddSingleton example in prose', '+public internal in prose')
$v4 = @(Get-StructuralHygieneViolations -NameStatusLines $thisPrNameStatus -DiffLines $thisPrDiff -LedgerLines @('build: passed'))
Assert-True ($v4.Count -eq 0) 'a docs/scripts-only diff (this PR) does NOT fire any signal (no self-trigger)'
# GATED non-test IVT: adding a production friend-grant requires the production-ivt recorded decision
$ivtName = @("M`tsrc/App.csproj")
$nonTestIvtDiff = @('diff --git a/src/App.csproj b/src/App.csproj', '+++ b/src/App.csproj', '@@ -1,1 +1,2 @@', '+    <InternalsVisibleTo Include="Other.App" />')
$v5 = @(Get-StructuralHygieneViolations -NameStatusLines $ivtName -DiffLines $nonTestIvtDiff -LedgerLines @('    touched-file-LPA: ran (reviewed)'))
Assert-True ($v5.Count -ge 1) 'added non-test IVT + touched-file-LPA WITHOUT a production-ivt marker -> violation'
$v6 = @(Get-StructuralHygieneViolations -NameStatusLines $ivtName -DiffLines $nonTestIvtDiff -LedgerLines @('    touched-file-LPA: ran (production-ivt: DI-seam unsuitable for the app-composition head)'))
Assert-True ($v6.Count -eq 0) 'the legacy standalone ran (production-ivt: <reason>) form is STILL accepted by B1 (backward-compat; the docs now prescribe the combined v6d shape) -> clean'
$v6b = @(Get-StructuralHygieneViolations -NameStatusLines $ivtName -DiffLines $nonTestIvtDiff -LedgerLines @('    touched-file-LPA: N/A - least-privilege-audit.md:44 production-ivt: foo'))
Assert-True ($v6b.Count -ge 1) 'a cited N/A that merely embeds the production-ivt token (not ran (...)) is REJECTED for a non-test IVT'
$v6c = @(Get-StructuralHygieneViolations -NameStatusLines $ivtName -DiffLines $nonTestIvtDiff -LedgerLines @('    touched-file-LPA: ran (production-ivt:)'))
Assert-True ($v6c.Count -ge 1) 'an EMPTY production-ivt marker (no reason) is REJECTED for a non-test IVT'
$v6d = @(Get-StructuralHygieneViolations -NameStatusLines $ivtName -DiffLines $nonTestIvtDiff -LedgerLines @('    touched-file-LPA: ran (3 findings, 1 unjustified; production-ivt: DI-seam unsuitable for the app-composition head)'))
Assert-True ($v6d.Count -eq 0) 'the canonical COMBINED shape ran (N findings, K unjustified; production-ivt: <reason>) the docs now prescribe -> clean (locks the doc-mechanism contract)'
$testIvtDiff = @('diff --git a/src/App.csproj b/src/App.csproj', '+++ b/src/App.csproj', '@@ -1,1 +1,2 @@', '+    <InternalsVisibleTo Include="App.Tests" />')
$v7 = @(Get-StructuralHygieneViolations -NameStatusLines $ivtName -DiffLines $testIvtDiff -LedgerLines @('    touched-file-LPA: ran (test friend-grant)'))
Assert-True ($v7.Count -eq 0) 'a TEST-target IVT + a justified touched-file-LPA (no production-ivt marker required) -> clean'

Write-Host '=== Completeness sweep: REAL git-diff fixtures (New-TestGitRepository) across the change taxonomy ==='
function Invoke-GitOk {
    param([string] $Repo, [Parameter(ValueFromRemainingArguments)] [string[]] $GitArgs)
    $out = git -C $Repo @GitArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed in ${Repo}: $out" }
    return $out
}
function New-B1SweepRepo {
    $repo = New-TestGitRepository -Prefix 'b1-sweep'
    Invoke-GitOk $repo config core.autocrlf false | Out-Null
    Invoke-GitOk $repo config core.filemode false | Out-Null
    return $repo
}
function Get-B1StagedDiff {
    param([string] $Repo)
    Invoke-GitOk $Repo add -A | Out-Null
    return @(git -C $Repo -c core.quotePath=false diff --cached -U0 --no-color)
}
function Assert-B1Viz {
    param([string] $Repo, [bool] $ExpectFire, [string] $Name)
    $diff = Get-B1StagedDiff $Repo
    Assert-True ($diff.Count -gt 0) "$Name [anti-vacuous: the change produced a real staged diff]"
    Assert-True ((Test-VisibilityDeltaSignal (Get-VisibilityRelevantDiffLines -DiffLines $diff)) -eq $ExpectFire) $Name
}

$r = New-B1SweepRepo; Set-Content -LiteralPath (Join-Path $r 'Foo.cs') -Value 'public class Foo { }'
Assert-B1Viz $r $true  'taxonomy ADD: a new .cs with public -> widening fires'
$r = New-B1SweepRepo; New-TestCommit -Directory $r -File 'Bar.cs' -Content "internal class Bar { }`n" -Message seed | Out-Null; Set-Content -LiteralPath (Join-Path $r 'Bar.cs') -Value "internal class Bar { }`npublic int N;`n"
Assert-B1Viz $r $true  'taxonomy MODIFY: adding a public member -> widening fires'
$r = New-B1SweepRepo; New-TestCommit -Directory $r -File 'Baz.cs' -Content "public class Baz { }`n" -Message seed | Out-Null; Set-Content -LiteralPath (Join-Path $r 'Baz.cs') -Value "internal class Baz { }`n"
Assert-B1Viz $r $true  'taxonomy MODIFY ->internal narrowing still fires via the +internal line (disclosed residual)'
$r = New-B1SweepRepo; New-TestCommit -Directory $r -File 'Del.cs' -Content "public class Del { }`n" -Message seed | Out-Null; Remove-Item -LiteralPath (Join-Path $r 'Del.cs')
Assert-B1Viz $r $false 'taxonomy DELETE: removing a .cs with public -> does NOT fire (narrowing)'
$r = New-B1SweepRepo; New-TestCommit -Directory $r -File 'Ren.cs' -Content "public class Ren { }`n" -Message seed | Out-Null; Invoke-GitOk $r mv 'Ren.cs' 'Ren2.cs' | Out-Null
Assert-B1Viz $r $false 'taxonomy RENAME (pure): -> does NOT fire (no added widening content)'
$r = New-B1SweepRepo; Set-Content -LiteralPath (Join-Path $r 'App.csproj') -Value "<Project>`n  <ItemGroup>`n    <InternalsVisibleTo Include=`"Prod.App`" />`n  </ItemGroup>`n</Project>`n"
$ivtDiff = Get-B1StagedDiff $r
Assert-True ($ivtDiff.Count -gt 0) 'taxonomy ADD csproj IVT [anti-vacuous: real staged diff]'
Assert-Equal 'Prod.App' (Test-NonTestIvtSignal (Get-VisibilityRelevantDiffLines -DiffLines $ivtDiff)) 'taxonomy ADD csproj non-test IVT (own line) -> gated signal fires with the target'
$r = New-B1SweepRepo; [System.IO.File]::WriteAllText((Join-Path $r 'NoNl.cs'), 'public class NoNl { }')
Assert-B1Viz $r $true  'taxonomy NO-NEWLINE-AT-EOF: a .cs with public and no trailing newline -> fires'
$r = New-B1SweepRepo; [System.IO.File]::WriteAllBytes((Join-Path $r 'blob.cs'), ([byte[]](0,1,2,3,255,254,0,10,13)))
Assert-B1Viz $r $false 'taxonomy BINARY: a binary .cs (git "Binary files differ") -> does NOT fire (no text content)'
$r = New-B1SweepRepo; New-TestCommit -Directory $r -File 'Mode.cs' -Content "public class Mode { }`n" -Message seed | Out-Null; Invoke-GitOk $r update-index --chmod=+x 'Mode.cs' | Out-Null
Assert-B1Viz $r $false 'taxonomy MODE-ONLY: a chmod with no content change -> does NOT fire'
$r = New-B1SweepRepo; Set-Content -LiteralPath (Join-Path $r 'Doc.md') -Value 'the word public appears here'
Assert-B1Viz $r $false 'taxonomy ADD docs (.md): -> does NOT fire (docs excluded from the visibility scope)'
# core.quotePath: a non-ASCII path is octal-escaped in the diff header WITHOUT core.quotePath=false (so the
# `+++ b/<path>` regex misses it) and literal WITH it. check-post-code-change.ps1 sets the flag on every B1 diff;
# assert the WITH/WITHOUT difference so that fix cannot silently regress.
$r = New-B1SweepRepo; Set-Content -LiteralPath (Join-Path $r ([string][char]0x00FC + 'ber.cs')) -Value 'public class U { }'
Invoke-GitOk $r add -A | Out-Null
$quotedDiff   = @(git -C $r diff --cached -U0 --no-color)
$unquotedDiff = @(git -C $r -c core.quotePath=false diff --cached -U0 --no-color)
Assert-True  ($quotedDiff.Count -gt 0 -and $unquotedDiff.Count -gt 0) 'core.quotePath fixture produced real diffs [anti-vacuous]'
Assert-False (Test-VisibilityDeltaSignal (Get-VisibilityRelevantDiffLines -DiffLines $quotedDiff))   'WITHOUT core.quotePath=false a non-ASCII .cs path is octal-escaped in the header -> MISSED (the bug the fix prevents)'
Assert-True  (Test-VisibilityDeltaSignal (Get-VisibilityRelevantDiffLines -DiffLines $unquotedDiff)) 'WITH core.quotePath=false the non-ASCII .cs path is literal -> the widening fires (the check-post-code-change fix)'
# space-path: git does NOT quote a space - it appends a disambiguation TAB to the `+++ b/<path>` header that
# core.quotePath=false does NOT strip; the `[^\t]+` capture (not `.+`) stops before it so GetExtension sees `.cs`.
$r = New-B1SweepRepo; Set-Content -LiteralPath (Join-Path $r 'my service.cs') -Value 'public class S { }'
$spaceDiff = Get-B1StagedDiff $r
Assert-True ($spaceDiff.Count -gt 0) 'space-path fixture produced a real staged diff [anti-vacuous]'
Assert-True (Test-VisibilityDeltaSignal (Get-VisibilityRelevantDiffLines -DiffLines $spaceDiff)) 'a space-containing .cs path (disambiguation-tab in the +++ header) -> the widening still fires'
Remove-TestTempDirectories

Write-Host ''
if ($script:Fail -gt 0) { Write-Host "Failures: $script:Fail" -ForegroundColor Red; exit 1 }
Write-Host "ALL PASS ($script:Pass assertions)"
exit 0
