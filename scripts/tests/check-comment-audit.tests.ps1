#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$modulePath = Join-Path $PSScriptRoot '../lib/comment-audit-helpers.psm1'
Import-Module $modulePath -Force

$failures = 0
$passes = 0

function Assert-True {
    param([Parameter(Mandatory)] [bool] $Condition, [Parameter(Mandatory)] [string] $Description)
    if ($Condition) {
        $script:passes++
        Write-Host "  [PASS] $Description"
    } else {
        $script:failures++
        Write-Host "  [FAIL] $Description" -ForegroundColor Red
    }
}

function Assert-False {
    param([Parameter(Mandatory)] [bool] $Condition, [Parameter(Mandatory)] [string] $Description)
    Assert-True -Condition (-not $Condition) -Description $Description
}

function Assert-Equal {
    param([Parameter(Mandatory)] $Expected, [Parameter(Mandatory)] $Actual, [Parameter(Mandatory)] [string] $Description)
    if ($Expected -eq $Actual) {
        $script:passes++
        Write-Host "  [PASS] $Description"
    } else {
        $script:failures++
        Write-Host "  [FAIL] $Description" -ForegroundColor Red
        Write-Host "         Expected: $Expected"
        Write-Host "         Actual:   $Actual"
    }
}

Write-Host ""
Write-Host "NOTE: this is a STANDALONE pwsh self-test (Assert-* helpers, NOT Pester). Run directly via `pwsh -File scripts/tests/check-comment-audit.tests.ps1`. `Invoke-Pester` will find 0 tests here." -ForegroundColor Yellow

Write-Host ""
Write-Host "=== Test-IsNewCommentLine ===" -ForegroundColor Cyan

Assert-True (Test-IsNewCommentLine -Content '// foo' -FilePath 'src/Foo.cs') 'C# line-leading //'
Assert-True (Test-IsNewCommentLine -Content '    // indented' -FilePath 'src/Foo.cs') 'C# indented //'
Assert-True (Test-IsNewCommentLine -Content '/// <summary>' -FilePath 'src/Foo.cs') 'C# XML doc ///'
Assert-True (Test-IsNewCommentLine -Content '    var x = 0; // running total' -FilePath 'src/Foo.cs') 'C# inline trailing //'
Assert-True (Test-IsNewCommentLine -Content '    var x = 0; /* trailing block */' -FilePath 'src/Foo.cs') 'C# inline trailing /* (R4-MAJOR-3 fix)'
Assert-True (Test-IsNewCommentLine -Content '<div></div> <!-- trailing html -->' -FilePath 'app.html') 'HTML inline trailing <!-- (R4-MAJOR-3 fix)'
Assert-True (Test-IsNewCommentLine -Content 'var x=0;/*tight comment*/' -FilePath 'src/Foo.cs') 'C# inline tight /* (no whitespace) — R5-BLOCKING-1 fix'
Assert-True (Test-IsNewCommentLine -Content '<div></div><!--tight-->' -FilePath 'app.html') 'HTML inline tight <!-- (no whitespace) — R5-BLOCKING-1 fix'
Assert-True (Test-IsNewCommentLine -Content '$x=1;<#tight#>' -FilePath 'script.ps1') 'PS1 inline tight <# (no whitespace) — R5-BLOCKING-1 fix'
Assert-False (Test-IsNewCommentLine -Content '#region foo' -FilePath 'src/Foo.cs') 'C# #region excluded'
Assert-False (Test-IsNewCommentLine -Content '#pragma warning disable' -FilePath 'src/Foo.cs') 'C# #pragma excluded'
Assert-False (Test-IsNewCommentLine -Content 'var url = "http://example.com";' -FilePath 'src/Foo.cs') 'C# URL inside string is NOT comment'

Assert-False (Test-IsNewCommentLine -Content '# Heading' -FilePath 'README.md') 'MD heading is NOT comment'
Assert-False (Test-IsNewCommentLine -Content '* bullet' -FilePath 'README.md') 'MD bullet is NOT comment'
Assert-False (Test-IsNewCommentLine -Content '---' -FilePath 'README.md') 'MD hr is NOT comment'
Assert-True (Test-IsNewCommentLine -Content '<!-- comment -->' -FilePath 'README.md') 'MD HTML comment'
Assert-False (Test-IsNewCommentLine -Content '<!-- read-receipt-token: abc12345 -->' -FilePath 'README.md') 'read-receipt-token header is exempt metadata, not a prose comment'
Assert-True (Test-IsNewCommentLine -Content '<!-- read-receipt-token: abc12345 -->' -FilePath 'app.html') 'read-receipt-token exemption is markdown-only; non-md HTML comment still flagged (no comment-audit bypass)'
Assert-True (Test-IsNewCommentLine -Content '<!-- read-receipt-token: abc12345' -FilePath 'README.md') 'unterminated read-receipt-token opener is NOT exempt (must be the closed single-line form)'
Assert-True (Test-IsNewCommentLine -Content '<!-- read-receipt-token: abc12345 --> trailing prose' -FilePath 'README.md') 'read-receipt-token line with text after the closer is NOT exempt'
Assert-True (Test-IsNewCommentLine -Content '<!-- read-receipt-token: abc12345 sneaky -->' -FilePath 'README.md') 'read-receipt-token with extra content before the closer is NOT exempt'

Assert-True (Test-IsNewCommentLine -Content '# python comment' -FilePath 'app.py') 'Python #'
Assert-True (Test-IsNewCommentLine -Content '    # indented' -FilePath 'app.py') 'Python indented #'
Assert-False (Test-IsNewCommentLine -Content '#!/usr/bin/env python' -FilePath 'app.py') 'Python shebang excluded (R4-BLOCKING-6)'
Assert-False (Test-IsNewCommentLine -Content '#!/bin/bash' -FilePath 'script.sh') 'Bash shebang excluded (R4-BLOCKING-6)'
Assert-True (Test-IsNewCommentLine -Content '#! real comment text without slash' -FilePath 'app.py') 'Python "#! " without slash IS still a comment (R5 tightening — only #!/ excluded)'

Assert-False (Test-IsNewCommentLine -Content '#region foo' -FilePath 'script.ps1') 'PS1 #region excluded'
Assert-False (Test-IsNewCommentLine -Content '#endregion' -FilePath 'script.ps1') 'PS1 #endregion excluded'
Assert-False (Test-IsNewCommentLine -Content '#Requires -Version 5.1' -FilePath 'script.ps1') 'PS1 #Requires -Version excluded (R4-BLOCKING-6)'
Assert-False (Test-IsNewCommentLine -Content '#Requires -Module Pester' -FilePath 'script.psm1') 'PSM1 #Requires -Module excluded (R4-BLOCKING-6)'
Assert-True (Test-IsNewCommentLine -Content '#Requires more thought' -FilePath 'script.ps1') 'PS1 "#Requires" without -param IS still a comment (R5 tightening — only #Requires - excluded)'
Assert-True (Test-IsNewCommentLine -Content '# comment' -FilePath 'script.ps1') 'PS1 regular #'

Assert-False (Test-IsNewCommentLine -Content '--primary: #fff;' -FilePath 'style.css') 'CSS custom property is NOT comment'
Assert-True (Test-IsNewCommentLine -Content '/* comment */' -FilePath 'style.css') 'CSS block comment'
Assert-True (Test-IsNewCommentLine -Content '-- lua comment' -FilePath 'script.lua') 'Lua --'
Assert-True (Test-IsNewCommentLine -Content '-- sql comment' -FilePath 'query.sql') 'SQL --'
Assert-True (Test-IsNewCommentLine -Content '# ruby comment' -FilePath 'app.rb') 'Ruby #'
Assert-True (Test-IsNewCommentLine -Content '# dockerfile' -FilePath 'path/to/Dockerfile') 'Dockerfile (extensionless) #'
Assert-True (Test-IsNewCommentLine -Content '# makefile' -FilePath 'Makefile') 'Makefile (extensionless) #'

Assert-True (Test-IsNewCommentLine -Content '@moduledoc "module description"' -FilePath 'lib/app.ex') 'Elixir @moduledoc (R4-MAJOR-2)'
Assert-True (Test-IsNewCommentLine -Content '@doc "function description"' -FilePath 'lib/app.ex') 'Elixir @doc (R4-MAJOR-2)'
Assert-True (Test-IsNewCommentLine -Content '@typedoc "type description"' -FilePath 'lib/app.ex') 'Elixir @typedoc (R4-MAJOR-2)'

Assert-False (Test-IsNewCommentLine -Content 'anything' -FilePath 'unknown.xyz') 'Unknown extension'

Write-Host ""
Write-Host "=== Get-NewCommentSites ===" -ForegroundColor Cyan

$diff1 = @(
    'diff --git a/src/Foo.cs b/src/Foo.cs',
    '--- a/src/Foo.cs',
    '+++ b/src/Foo.cs',
    '@@ -1,3 +1,5 @@',
    ' public class Foo {',
    '+    // new comment 1',
    '+    public int X;',
    '+    // new comment 2',
    ' }'
)
$sites = Get-NewCommentSites -DiffLines $diff1
Assert-Equal 2 $sites.Count 'Diff with 2 new C# comments and 1 non-comment add'

$diff2 = @(
    'diff --git a/README.md b/README.md',
    '+++ b/README.md',
    '@@ -1,1 +1,4 @@',
    ' Title',
    '+# This is a markdown heading',
    '+* This is a bullet',
    '+<!-- This is an HTML comment -->'
)
$sites = Get-NewCommentSites -DiffLines $diff2
Assert-Equal 1 $sites.Count 'MD diff: heading + bullet ignored, only HTML comment counts'

$diff3 = @(
    'diff --git a/empty.txt b/empty.txt',
    '+++ b/empty.txt',
    '@@ -0,0 +1,2 @@',
    '+line1',
    '+line2'
)
$sites = Get-NewCommentSites -DiffLines $diff3
Assert-Equal 0 $sites.Count 'Unknown extension (.txt) silently skipped'

Write-Host ""
Write-Host "=== Test-AuditBulletShape ===" -ForegroundColor Cyan

$shape = Test-AuditBulletShape -BulletLine '- src/Foo.cs:42: approval_turn: 17 | allowed-case: non-obvious invariant | justification: bcl quirk'
Assert-Equal 'approved' $shape.Form 'Approved with allowed-case AND justification is valid'
Assert-True $shape.Valid 'Approved bullet valid=true'

$shape = Test-AuditBulletShape -BulletLine '- src/Foo.cs:42: approval_turn: 17 | allowed-case: trade-off |'
Assert-False $shape.Valid 'Approved WITHOUT justification is invalid (R4-MAJOR-1)'

$shape = Test-AuditBulletShape -BulletLine '- src/Foo.cs:42: approval_turn: 17'
Assert-False $shape.Valid 'Approved without allowed-case is invalid'

$shape = Test-AuditBulletShape -BulletLine '- src/Foo.cs:42: approval_turn: n/a — exempt: typo'
Assert-Equal 'exempt' $shape.Form 'Exempt with canonical token is valid'
Assert-True $shape.Valid 'Exempt typo bullet valid=true'

$shape = Test-AuditBulletShape -BulletLine '- src/Foo.cs:42: approval_turn: n/a — exempt: it-was-obvious'
Assert-False $shape.Valid 'Non-canonical exempt category is invalid'

$shape = Test-AuditBulletShape -BulletLine '- src/Foo.cs:42: approval_turn: n/a — degraded-mode-drop'
Assert-Equal 'degraded-mode-drop' $shape.Form 'Degraded mode disposition'
Assert-True $shape.Valid 'Degraded mode valid=true'

$shape = Test-AuditBulletShape -BulletLine '- src/Foo.cs:42: approval_turn: n/a — no-response-drop'
Assert-Equal 'no-response-drop' $shape.Form 'No-response disposition'
Assert-True $shape.Valid 'No-response valid=true'

$shape = Test-AuditBulletShape -BulletLine '- src/Foo.cs:42: deleted (per protocol step-3 rejection)'
Assert-Equal 'deleted' $shape.Form 'Deleted disposition'
Assert-True $shape.Valid 'Deleted valid=true'

$shape = Test-AuditBulletShape -BulletLine '- src/Foo.cs:42: approval_turn: n/a — made-up-reason'
Assert-False $shape.Valid 'Unknown n/a disposition is invalid'

$shape = Test-AuditBulletShape -BulletLine '- src/Foo.cs:42: approval_turn: bogus'
Assert-False $shape.Valid 'Bare bogus approval_turn is invalid'

Write-Host ""
Write-Host "=== Test-AuditFile (array vs string parameter - regression for R3-BLOCKING-1) ===" -ForegroundColor Cyan

$auditLines = @(
    'parent_sha: a5da51f4f3dcdbffda9f2b5d5aad03f2554ebd74',
    'commit_subject: Add foo',
    'Comment audit: scope=src/Foo.cs, 2 new lines, 2 approved.',
    '- src/Foo.cs:42: approval_turn: 17 | allowed-case: non-obvious invariant | justification: explains race-handling',
    '- src/Foo.cs:55: approval_turn: 17 | allowed-case: trade-off | justification: lock-vs-lockfree benchmark loss'
)
$result = Test-AuditFile -AuditLines $auditLines -ExpectedParentSha 'a5da51f4f3dcdbffda9f2b5d5aad03f2554ebd74'
Assert-True $result.Valid 'Audit with 2 valid approved bullets is valid'
Assert-Equal 2 $result.ApprovedCount 'ApprovedCount correctly counts to 2 (regression for R3-BLOCKING-1 array coercion)'

$auditLines = @(
    'parent_sha: abc1234567890',
    'commit_subject: Add bar',
    'Comment audit: ...',
    '- src/Foo.cs:42: approval_turn: bogus',
    '- src/Foo.cs:43: approval_turn: n/a — exempt: not-canonical'
)
$result = Test-AuditFile -AuditLines $auditLines -ExpectedParentSha 'abc1234567890def0987654321abcdef12345678'
Assert-False $result.Valid 'Audit with invalid bullets is invalid'
Assert-Equal 2 $result.InvalidBullets.Count 'InvalidBullets count matches'

$auditLines = @(
    'parent_sha: <git rev-parse HEAD>',
    'Comment audit: ...'
)
$result = Test-AuditFile -AuditLines $auditLines -ExpectedParentSha 'abc1234567890'
Assert-False $result.Valid 'Audit with unsubstituted template placeholder is invalid (R3-BLOCKING-5)'

$auditLines = @(
    'parent_sha: NONE',
    'Comment audit: ...'
)
$result = Test-AuditFile -AuditLines $auditLines -ExpectedParentSha 'abc1234567890'
Assert-False $result.Valid 'NONE accepted only for true root commit (real parent exists → invalid)'

$auditLines = @(
    'parent_sha: NONE',
    'commit_subject: Initial commit',
    'Comment audit: ...'
)
$result = Test-AuditFile -AuditLines $auditLines -ExpectedParentSha '4b825dc642cb6eb9a060e54bf8d69288fbee4904'
Assert-True $result.Valid 'NONE accepted when commit is true root (parent = empty-tree)'

$auditLines = @(
    'parent_sha: deadbeef0000111122223333444455556666aaaa',
    'commit_subject: Add baz',
    'Comment audit: ...'
)
$result = Test-AuditFile -AuditLines $auditLines -ExpectedParentSha 'abc1234567890def0987654321abcdef12345678'
Assert-False $result.Valid 'Mismatched parent_sha is invalid (stale audit)'

$auditLines = @('parent_sha: abc1', 'Comment audit: ...')
$result = Test-AuditFile -AuditLines $auditLines -ExpectedParentSha 'abc1234567890def0987654321abcdef12345678'
Assert-False $result.Valid 'parent_sha < 7 chars is invalid'

$auditLines = @(
    'parent_sha: a5da51f4',
    'Comment audit: ...'
)
$result = Test-AuditFile -AuditLines $auditLines -ExpectedParentSha 'a5da51f4f3dcdbffda9f2b5d5aad03f2554ebd74'
Assert-False $result.Valid 'Audit missing required commit_subject: header is invalid (R6 Slot D fix)'

$auditLines = @(
    'parent_sha: a5da51f4',
    'commit_subject: <proposed commit subject>',
    'Comment audit: ...'
)
$result = Test-AuditFile -AuditLines $auditLines -ExpectedParentSha 'a5da51f4f3dcdbffda9f2b5d5aad03f2554ebd74'
Assert-False $result.Valid 'Audit with unsubstituted commit_subject placeholder is invalid (R6 Slot D fix)'

$auditLines = @('parent_sha: a5da51f4', 'commit_subject: Add foo', 'Comment audit: zero count')
$result = Test-AuditFile -AuditLines $auditLines -ExpectedParentSha 'a5da51f4f3dcdbffda9f2b5d5aad03f2554ebd74'
Assert-True $result.Valid '7-char hex prefix valid'

Write-Host ""
Write-Host "=== Get-CoveredCommentCount (R4-BLOCKING-5 regression) ===" -ForegroundColor Cyan

$result = [PSCustomObject]@{
    ApprovedCount = 3; ExemptCount = 2; DegradedCount = 1; NoResponseCount = 1; DeletedCount = 5
}
Assert-Equal 5 (Get-CoveredCommentCount -AuditResult $result) 'Covered count = approved + exempt ONLY (drops + deleted excluded — R4-BLOCKING-5 regression)'

$result = [PSCustomObject]@{
    ApprovedCount = 0; ExemptCount = 0; DegradedCount = 10; NoResponseCount = 10; DeletedCount = 10
}
Assert-Equal 0 (Get-CoveredCommentCount -AuditResult $result) 'All-drops audit covers 0 real diff comments (R4-BLOCKING-5)'

Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host "Passes:   $passes" -ForegroundColor Green
if ($failures -gt 0) {
    Write-Host "Failures: $failures" -ForegroundColor Red
    exit 1
}
Write-Host "Failures: $failures" -ForegroundColor Green
exit 0
