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
Assert-True (Test-IsNewCommentLine -Content '    var x = 0; /* trailing block */' -FilePath 'src/Foo.cs') 'C# inline trailing /*'
Assert-True (Test-IsNewCommentLine -Content '<div></div> <!-- trailing html -->' -FilePath 'app.html') 'HTML inline trailing <!--'
Assert-True (Test-IsNewCommentLine -Content 'var x=0;/*tight comment*/' -FilePath 'src/Foo.cs') 'C# inline tight /* (no whitespace)'
Assert-True (Test-IsNewCommentLine -Content '<div></div><!--tight-->' -FilePath 'app.html') 'HTML inline tight <!-- (no whitespace)'
Assert-True (Test-IsNewCommentLine -Content '$x=1;<#tight#>' -FilePath 'script.ps1') 'PS1 inline tight <# (no whitespace)'
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

Assert-False (Test-IsNewCommentLine -Content '| rule | ... <!-- --> ... |' -FilePath '.github/pr-quality-gate/pattern-catalog.md') 'pattern-catalog.md is path-excluded (it enumerates comment syntax)'
Assert-False (Test-IsNewCommentLine -Content '| ... `//` `#` `/* */` ... |' -FilePath '.github/pr-quality-gate/pattern-catalog.sources/00-catalog.md') 'pattern-catalog source markdown is path-excluded'
Assert-True (Test-IsNewCommentLine -Content '<!-- a real comment -->' -FilePath 'docs/pattern-catalog.md') 'a like-named file outside the gate path is NOT excluded'
Assert-True (Test-IsNewCommentLine -Content '# real code comment' -FilePath '.github/pr-quality-gate/pattern-catalog.sources/helper.ps1') 'a non-markdown file under pattern-catalog.sources/ is NOT excluded (md-only carve-out)'
Assert-True (Test-IsNewCommentLine -Content '<!-- a real comment -->' -FilePath 'nested/.github/pr-quality-gate/pattern-catalog.md') 'a nested decoy path ending in the catalog name is NOT excluded (anchor is repo-root-relative)'

Assert-True (Test-IsNewCommentLine -Content '# python comment' -FilePath 'app.py') 'Python #'
Assert-True (Test-IsNewCommentLine -Content '    # indented' -FilePath 'app.py') 'Python indented #'
Assert-False (Test-IsNewCommentLine -Content '#!/usr/bin/env python' -FilePath 'app.py') 'Python shebang excluded'
Assert-False (Test-IsNewCommentLine -Content '#!/bin/bash' -FilePath 'script.sh') 'Bash shebang excluded'
Assert-True (Test-IsNewCommentLine -Content '#! real comment text without slash' -FilePath 'app.py') 'Python "#! " without slash IS still a comment (only #!/ excluded)'

Assert-False (Test-IsNewCommentLine -Content '#region foo' -FilePath 'script.ps1') 'PS1 #region excluded'
Assert-False (Test-IsNewCommentLine -Content '#endregion' -FilePath 'script.ps1') 'PS1 #endregion excluded'
Assert-False (Test-IsNewCommentLine -Content '#Requires -Version 5.1' -FilePath 'script.ps1') 'PS1 #Requires -Version excluded'
Assert-False (Test-IsNewCommentLine -Content '#Requires -Module Pester' -FilePath 'script.psm1') 'PSM1 #Requires -Module excluded'
Assert-True (Test-IsNewCommentLine -Content '#Requires more thought' -FilePath 'script.ps1') 'PS1 "#Requires" without -param IS still a comment (only #Requires - excluded)'
Assert-True (Test-IsNewCommentLine -Content '# comment' -FilePath 'script.ps1') 'PS1 regular #'

Assert-False (Test-IsNewCommentLine -Content '--primary: #fff;' -FilePath 'style.css') 'CSS custom property is NOT comment'
Assert-True (Test-IsNewCommentLine -Content '/* comment */' -FilePath 'style.css') 'CSS block comment'
Assert-True (Test-IsNewCommentLine -Content '-- lua comment' -FilePath 'script.lua') 'Lua --'
Assert-True (Test-IsNewCommentLine -Content '-- sql comment' -FilePath 'query.sql') 'SQL --'
Assert-True (Test-IsNewCommentLine -Content '# ruby comment' -FilePath 'app.rb') 'Ruby #'
Assert-True (Test-IsNewCommentLine -Content '# dockerfile' -FilePath 'path/to/Dockerfile') 'Dockerfile (extensionless) #'
Assert-True (Test-IsNewCommentLine -Content '# makefile' -FilePath 'Makefile') 'Makefile (extensionless) #'

Assert-True (Test-IsNewCommentLine -Content '@moduledoc "module description"' -FilePath 'lib/app.ex') 'Elixir @moduledoc'
Assert-True (Test-IsNewCommentLine -Content '@doc "function description"' -FilePath 'lib/app.ex') 'Elixir @doc'
Assert-True (Test-IsNewCommentLine -Content '@typedoc "type description"' -FilePath 'lib/app.ex') 'Elixir @typedoc'

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

$diffDashHeader = @(
    'diff --git a/q.sql b/q.sql',
    '--- a/q.sql',
    '+++ b/q.sql',
    '@@ -1 +1 @@',
    '--- approved wording',
    '+-- reworded comment never audited'
)
$sites = Get-NewCommentSites -DiffLines $diffDashHeader
Assert-Equal 1 $sites.Count 'a removed -- comment (renders as ---) does NOT null file tracking; the new -- comment is still detected'

$diffDashLower = @(
    'diff --git a/q.sql b/q.sql',
    '--- a/q.sql',
    '+++ b/q.sql',
    '@@ -1,3 +1,4 @@',
    '--- old top note',
    '+-- new top note',
    ' SELECT 1;',
    '+-- brand new comment lower in the file'
)
$sites = Get-NewCommentSites -DiffLines $diffDashLower
Assert-Equal 2 $sites.Count 'a removed -- comment higher up does not suppress a brand-new -- comment lower in the same file'

$diffPlusContent = @(
    'diff --git a/a.cs b/a.cs',
    '--- a/a.cs',
    '+++ b/a.cs',
    '@@ -1 +1,2 @@',
    ' code();',
    '+    // real comment after a context line'
)
$sites = Get-NewCommentSites -DiffLines $diffPlusContent
Assert-Equal 1 $sites.Count 'a comment added after a context line is detected (line counter tracks context lines)'

$diffQuotedPath = @(
    'diff --git "a/we\"ird.sql" "b/we\"ird.sql"',
    '--- "a/we\"ird.sql"',
    '+++ "b/we\"ird.sql"',
    '@@ -0,0 +1 @@',
    '+-- comment in a quoted-path file'
)
$bad = @(Get-UnparseableDiffPaths -DiffLines $diffQuotedPath)
Assert-Equal 1 $bad.Count 'a quoted +++ file-path header is flagged as unparseable (gate fails closed instead of silently 0-siting)'
$clean = @(Get-UnparseableDiffPaths -DiffLines $diffPlusContent)
Assert-Equal 0 $clean.Count 'a normal (unquoted) diff has no unparseable paths'
$inHunkPlus = @(
    'diff --git a/a.md b/a.md',
    '+++ b/a.md',
    '@@ -0,0 +1 @@',
    '++++ b/not-a-header content'
)
Assert-Equal 0 (@(Get-UnparseableDiffPaths -DiffLines $inHunkPlus)).Count 'a +++ -shaped line INSIDE a hunk is content, not flagged as a quoted header'

Write-Host ""
Write-Host "=== Test-AuditBulletShape ===" -ForegroundColor Cyan

$sha64 = 'a' * 64
$shape = Test-AuditBulletShape -BulletLine "- src/Foo.cs:42: approval_turn: 17 | allowed-case: non-obvious invariant | justification: bcl quirk | comment_sha: $sha64"
Assert-Equal 'approved' $shape.Form 'Approved with allowed-case AND justification AND comment_sha is valid'
Assert-True $shape.Valid 'Approved bullet valid=true'

$shape = Test-AuditBulletShape -BulletLine '- src/Foo.cs:42: approval_turn: 17 | allowed-case: non-obvious invariant | justification: bcl quirk'
Assert-False $shape.Valid 'Approved WITHOUT comment_sha is invalid'

$shape = Test-AuditBulletShape -BulletLine '- src/Foo.cs:42: approval_turn: 17 | allowed-case: non-obvious invariant | justification: bcl quirk | comment_sha: <64-hex>'
Assert-False $shape.Valid 'Approved with placeholder comment_sha is invalid'

$shape = Test-AuditBulletShape -BulletLine '- src/Foo.cs:42: approval_turn: 17 | allowed-case: trade-off |'
Assert-False $shape.Valid 'Approved WITHOUT justification is invalid'

$shape = Test-AuditBulletShape -BulletLine '- src/Foo.cs:42: approval_turn: 17'
Assert-False $shape.Valid 'Approved without allowed-case is invalid'

$shape = Test-AuditBulletShape -BulletLine '- src/Foo.cs:42: approval_turn: n/a - exempt: typo'
Assert-Equal 'exempt' $shape.Form 'Exempt with canonical token is valid'
Assert-True $shape.Valid 'Exempt typo bullet valid=true'

# Legacy em-dash separator is tolerated (backward-compat with ledgers committed before the ASCII migration).
$shape = Test-AuditBulletShape -BulletLine "- src/Foo.cs:42: approval_turn: n/a $([char]0x2014) exempt: generated"
Assert-Equal 'exempt' $shape.Form 'Legacy em-dash exempt separator is tolerated'
Assert-True $shape.Valid 'Legacy em-dash exempt bullet valid=true'

$shape = Test-AuditBulletShape -BulletLine '- src/Foo.cs:42: approval_turn: n/a - exempt: it-was-obvious'
Assert-False $shape.Valid 'Non-canonical exempt category is invalid'

$shape = Test-AuditBulletShape -BulletLine "- src/Foo.cs:42: approval_turn: n/a $([char]0x2014) degraded-mode-drop"
Assert-Equal 'degraded-mode-drop' $shape.Form 'Degraded mode disposition'
Assert-True $shape.Valid 'Degraded mode valid=true'

$shape = Test-AuditBulletShape -BulletLine "- src/Foo.cs:42: approval_turn: n/a $([char]0x2014) no-response-drop"
Assert-Equal 'no-response-drop' $shape.Form 'No-response disposition'
Assert-True $shape.Valid 'No-response valid=true'

$shape = Test-AuditBulletShape -BulletLine '- src/Foo.cs:42: deleted (per protocol step-3 rejection)'
Assert-Equal 'deleted' $shape.Form 'Deleted disposition'
Assert-True $shape.Valid 'Deleted valid=true'

$shape = Test-AuditBulletShape -BulletLine "- src/Foo.cs:42: approval_turn: n/a $([char]0x2014) made-up-reason"
Assert-False $shape.Valid 'Unknown n/a disposition is invalid'

$shape = Test-AuditBulletShape -BulletLine '- src/Foo.cs:42: approval_turn: bogus'
Assert-False $shape.Valid 'Bare bogus approval_turn is invalid'

Write-Host ""
Write-Host "=== Test-AuditFile (array vs string parameter - regression) ===" -ForegroundColor Cyan

$auditLines = @(
    'parent_sha: a5da51f4f3dcdbffda9f2b5d5aad03f2554ebd74',
    'commit_subject: Add foo',
    'Comment audit: scope=src/Foo.cs, 2 new lines, 2 approved.',
    "- src/Foo.cs:42: approval_turn: 17 | allowed-case: non-obvious invariant | justification: explains race-handling | comment_sha: $('a' * 64)",
    "- src/Foo.cs:55: approval_turn: 17 | allowed-case: trade-off | justification: lock-vs-lockfree benchmark loss | comment_sha: $('b' * 64)"
)
$result = Test-AuditFile -AuditLines $auditLines -ExpectedParentSha 'a5da51f4f3dcdbffda9f2b5d5aad03f2554ebd74'
Assert-True $result.Valid 'Audit with 2 valid approved bullets is valid'
Assert-Equal 2 $result.ApprovedCount 'ApprovedCount correctly counts to 2 (regression for array coercion)'

$auditLines = @(
    'parent_sha: abc1234567890def0987654321abcdef12345678',
    'commit_subject: Add bar',
    'Comment audit: ...',
    '- src/Foo.cs:42: approval_turn: bogus',
    '- src/Foo.cs:43: approval_turn: n/a - exempt: not-canonical'
)
$result = Test-AuditFile -AuditLines $auditLines -ExpectedParentSha 'abc1234567890def0987654321abcdef12345678'
Assert-False $result.Valid 'Audit with invalid bullets is invalid'
Assert-Equal 2 $result.InvalidBullets.Count 'InvalidBullets count matches'

$auditLines = @(
    'parent_sha: <git rev-parse HEAD>',
    'Comment audit: ...'
)
$result = Test-AuditFile -AuditLines $auditLines -ExpectedParentSha 'abc1234567890'
Assert-False $result.Valid 'Audit with unsubstituted template placeholder is invalid'

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
Assert-False $result.Valid 'parent_sha that is not a full 40-char SHA is invalid'

$auditLines = @(
    'parent_sha: a5da51f4f3dcdbffda9f2b5d5aad03f2554ebd74',
    'Comment audit: ...'
)
$result = Test-AuditFile -AuditLines $auditLines -ExpectedParentSha 'a5da51f4f3dcdbffda9f2b5d5aad03f2554ebd74'
Assert-False $result.Valid 'Audit missing required commit_subject: header is invalid'

$auditLines = @(
    'parent_sha: a5da51f4f3dcdbffda9f2b5d5aad03f2554ebd74',
    'commit_subject: <proposed commit subject>',
    'Comment audit: ...'
)
$result = Test-AuditFile -AuditLines $auditLines -ExpectedParentSha 'a5da51f4f3dcdbffda9f2b5d5aad03f2554ebd74'
Assert-False $result.Valid 'Audit with unsubstituted commit_subject placeholder is invalid'

$auditLines = @('parent_sha: a5da51f4f3dcdbffda9f2b5d5aad03f2554ebd74', 'commit_subject: Add foo', 'Comment audit: zero count')
$result = Test-AuditFile -AuditLines $auditLines -ExpectedParentSha 'a5da51f4f3dcdbffda9f2b5d5aad03f2554ebd74'
Assert-True $result.Valid 'full 40-char parent_sha exactly matching expected -> valid'

$auditLines = @('parent_sha: a5da51f4', 'commit_subject: Add foo', 'Comment audit: zero count')
$result = Test-AuditFile -AuditLines $auditLines -ExpectedParentSha 'a5da51f4f3dcdbffda9f2b5d5aad03f2554ebd74'
Assert-False $result.Valid '7-char hex prefix of expected -> INVALID (exact 40-char binding; no prefix match)'

Write-Host ""
Write-Host "=== Test-CommentCoverage (site + sha bijection) ===" -ForegroundColor Cyan

$covDiff = @(
    'diff --git a/src/Foo.cs b/src/Foo.cs',
    '--- a/src/Foo.cs',
    '+++ b/src/Foo.cs',
    '@@ -1,1 +1,5 @@',
    ' class Foo {',
    '+    // single line comment',
    '+    int x = 0;',
    '+    // block line one',
    '+    // block line two'
)
$covSites = Get-NewCommentSites -DiffLines $covDiff
Assert-Equal 2 $covSites.Count 'two sites: one single-line comment, one 2-line block'
$single = @($covSites | Where-Object { $_.StartLine -eq 2 })[0]
$block  = @($covSites | Where-Object { $_.StartLine -eq 4 })[0]
Assert-Equal 2 $single.EndLine 'single-line site spans one line (start 2, end 2)'
Assert-Equal 5 $block.EndLine '2-line block is ONE site (start 4, end 5)'

$bulletSingle = Test-AuditBulletShape -BulletLine "- src/Foo.cs:2: approval_turn: 9 | allowed-case: trade-off | justification: x | comment_sha: $($single.Sha)"
$bulletBlockExempt = Test-AuditBulletShape -BulletLine '- src/Foo.cs:4: approval_turn: n/a - exempt: generated'
$errs = @(Test-CommentCoverage -Sites $covSites -Bullets @($bulletSingle, $bulletBlockExempt))
Assert-Equal 0 $errs.Count 'matching approved (sha) + exempt-at-real-block-start -> no coverage errors'

$bulletBlockApproved = Test-AuditBulletShape -BulletLine "- src/Foo.cs:4: approval_turn: 9 | allowed-case: trade-off | justification: x | comment_sha: $($block.Sha)"
$errs = @(Test-CommentCoverage -Sites @($block) -Bullets @($bulletBlockApproved))
Assert-Equal 0 $errs.Count '2-line block covered by ONE approved bullet carrying the block sha'

$bulletWrongSha = Test-AuditBulletShape -BulletLine "- src/Foo.cs:2: approval_turn: 9 | allowed-case: trade-off | justification: x | comment_sha: $('c' * 64)"
$errs = @(Test-CommentCoverage -Sites @($single) -Bullets @($bulletWrongSha))
Assert-True (($errs -join ' ') -match 'mismatch') 'sha mismatch at a covered site -> error'

$bulletNoSha = Test-AuditBulletShape -BulletLine '- src/Foo.cs:2: approval_turn: 9 | allowed-case: trade-off | justification: x'
Assert-False $bulletNoSha.Valid 'approved bullet missing comment_sha is invalid'
$errs = @(Test-CommentCoverage -Sites @($single) -Bullets @($bulletNoSha))
Assert-True (($errs -join ' ') -match 'uncovered') 'invalid (no-sha) bullet does not cover its site -> uncovered'

$bulletPlaceholder = Test-AuditBulletShape -BulletLine '- src/Foo.cs:2: approval_turn: 9 | allowed-case: trade-off | justification: x | comment_sha: <64-hex>'
Assert-False $bulletPlaceholder.Valid 'placeholder comment_sha is invalid'
$errs = @(Test-CommentCoverage -Sites @($single) -Bullets @($bulletPlaceholder))
Assert-True (($errs -join ' ') -match 'uncovered') 'placeholder-sha bullet does not cover its site -> uncovered'

$errs = @(Test-CommentCoverage -Sites @($single) -Bullets @())
Assert-True (($errs -join ' ') -match 'uncovered') 'site with no bullet at all -> uncovered'

$orphan = Test-AuditBulletShape -BulletLine "- src/Foo.cs:99: approval_turn: 9 | allowed-case: trade-off | justification: x | comment_sha: $('a' * 64)"
$errs = @(Test-CommentCoverage -Sites @($single) -Bullets @($bulletSingle, $orphan))
Assert-True (($errs -join ' ') -match 'orphan') 'cover bullet whose line is not a site -> orphan error'

$exemptPhantom = Test-AuditBulletShape -BulletLine '- src/Foo.cs:77: approval_turn: n/a - exempt: generated'
$errs = @(Test-CommentCoverage -Sites @() -Bullets @($exemptPhantom))
Assert-True (($errs -join ' ') -match 'orphan') 'exempt bullet at a phantom line (no detected site) -> orphan'

$dup1 = Test-AuditBulletShape -BulletLine "- src/Foo.cs:2: approval_turn: 9 | allowed-case: trade-off | justification: x | comment_sha: $($single.Sha)"
$dup2 = Test-AuditBulletShape -BulletLine '- src/Foo.cs:2: approval_turn: n/a - exempt: generated'
$errs = @(Test-CommentCoverage -Sites @($single) -Bullets @($dup1, $dup2))
Assert-True (($errs -join ' ') -match 'ambiguous|more than one') 'two cover bullets at the same File:Line -> dup-key error'

$errs = @(Test-CommentCoverage -Sites @() -Bullets @())
Assert-Equal 0 $errs.Count 'zero sites + zero cover bullets -> no errors'

$shaPlain = Get-CommentBlockSha -AddedCommentLines @('// hello', '// world')
$shaReindented = Get-CommentBlockSha -AddedCommentLines @('        // hello', '   // world')
Assert-Equal $shaPlain $shaReindented 're-indent (leading/trailing whitespace) does NOT change the block sha'
$shaSyntaxChange = Get-CommentBlockSha -AddedCommentLines @('/* hello */', '// world')
Assert-True ($shaPlain -cne $shaSyntaxChange) 'changing // to /* */ DOES change the block sha (byte-exact wording bind)'

Write-Host ""
Write-Host "=== history-walk integration: first-add commit is validated, not bootstrap-skipped (dual-gate hardening) ===" -ForegroundColor Cyan

$checkerPath = Join-Path $PSScriptRoot '../check-comment-audit.ps1'
$tmpCA = Join-Path ([System.IO.Path]::GetTempPath()) ("ca-boot-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmpCA -Force | Out-Null
function TGCA { & git -C $tmpCA @args 2>&1 | Out-Null; if ($LASTEXITCODE -ne 0) { throw "gitCA failed: $($args -join ' ')" } }
function HeadCA { ((& git -C $tmpCA rev-parse HEAD) | Out-String).Trim() }
try {
    TGCA init; TGCA config user.email 't@e.com'; TGCA config user.name 'T'; TGCA config commit.gpgsign false; TGCA config core.autocrlf false
    New-Item -ItemType Directory -Path (Join-Path $tmpCA '.github/pr-quality-gate/audits') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tmpCA 'src') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tmpCA 'scripts') -Force | Out-Null
    Set-Content (Join-Path $tmpCA 'scripts/check-comment-audit.ps1') '# anchor stub'
    Set-Content (Join-Path $tmpCA 'README.md') '# r'; TGCA add -A; TGCA commit -m 'init'
    $caBase = HeadCA
    Set-Content (Join-Path $tmpCA 'src/code.cs') 'class C{}'
    Set-Content (Join-Path $tmpCA '.github/pr-quality-gate/audits/last.md') @('parent_sha: badf00d', 'commit_subject: first-add bootstrap', 'Comment audit: zero new comment sites')
    TGCA add -A; TGCA commit -m 'add gate + code'
    & pwsh -NoProfile -File $checkerPath -BaseRef $caBase -RepoRoot $tmpCA *> $null
    Assert-Equal 1 $LASTEXITCODE 'history walk: first-add last.md with a STALE parent_sha is CAUGHT (fail-closed; no bootstrap skip)'
}
finally {
    Set-Location $PSScriptRoot
    Remove-Item -LiteralPath $tmpCA -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "=== staged-mode integration (-StagedMode -WorktreeReceipt) ===" -ForegroundColor Cyan

$tmpSM = Join-Path ([System.IO.Path]::GetTempPath()) ("ca-staged-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmpSM -Force | Out-Null
function TGSM { & git -C $tmpSM @args 2>&1 | Out-Null; if ($LASTEXITCODE -ne 0) { throw "gitSM failed: $($args -join ' ')" } }
function HeadSM { ((& git -C $tmpSM rev-parse HEAD) | Out-String).Trim() }
function Invoke-Staged { & pwsh -NoProfile -File $checkerPath -StagedMode -WorktreeReceipt -RepoRoot $tmpSM *> $null; return $LASTEXITCODE }
try {
    TGSM init; TGSM config user.email 't@e.com'; TGSM config user.name 'T'; TGSM config commit.gpgsign false; TGSM config core.autocrlf false
    New-Item -ItemType Directory -Path (Join-Path $tmpSM '.github/pr-quality-gate/audits') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tmpSM 'src') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tmpSM 'scripts') -Force | Out-Null
    Set-Content (Join-Path $tmpSM 'scripts/check-comment-audit.ps1') '# anchor stub'
    Set-Content (Join-Path $tmpSM 'README.md') '# r'; TGSM add -A; TGSM commit -m 'init'
    $smHead = HeadSM
    $auditFile = Join-Path $tmpSM '.github/pr-quality-gate/audits/last.md'

    Set-Content -LiteralPath (Join-Path $tmpSM 'src/code.cs') "class C {`n    // block line one`n    // block line two`n}"
    TGSM add -A
    $blockSha = Get-CommentBlockSha -AddedCommentLines @('// block line one', '// block line two')

    Assert-Equal 1 (Invoke-Staged) 'staged comment block with NO receipt on disk -> violation (fail-closed)'

    Set-Content -LiteralPath $auditFile @("parent_sha: $smHead", 'commit_subject: add code', "- src/code.cs:2: approval_turn: 7 | allowed-case: trade-off | justification: x | comment_sha: $('d' * 64)")
    Assert-Equal 1 (Invoke-Staged) 'staged receipt with a mismatched comment_sha -> violation'

    Set-Content -LiteralPath $auditFile @("parent_sha: $smHead", 'commit_subject: add code', "- src/code.cs:2: approval_turn: 7 | allowed-case: trade-off | justification: x | comment_sha: $blockSha")
    Assert-Equal 0 (Invoke-Staged) 'staged receipt covering the block with the matching sha -> OK'

    Set-Content -LiteralPath $auditFile @('parent_sha: deadbeefdeadbeefdeadbeefdeadbeefdeadbeef', 'commit_subject: add code', "- src/code.cs:2: approval_turn: 7 | allowed-case: trade-off | justification: x | comment_sha: $blockSha")
    Assert-Equal 1 (Invoke-Staged) 'staged receipt with a stale parent_sha -> violation'
}
finally {
    Set-Location $PSScriptRoot
    Remove-Item -LiteralPath $tmpSM -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host "Passes:   $passes" -ForegroundColor Green
if ($failures -gt 0) {
    Write-Host "Failures: $failures" -ForegroundColor Red
    exit 1
}
Write-Host "Failures: $failures" -ForegroundColor Green
exit 0
