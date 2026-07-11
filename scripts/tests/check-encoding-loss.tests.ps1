#Requires -Version 7.0
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Standalone pwsh self-test (Assert-* helpers, not Pester) for check-encoding-loss.ps1.
# Run: pwsh -File scripts/tests/check-encoding-loss.tests.ps1
#
# INVARIANT: this file (and the checker) MUST stay ASCII-only. Every non-ASCII fixture is built from
# NUMERIC bytes (e.g. 0xC2,0xA7 = UTF-8 section-sign; 0xE2,0x86,0x92 = arrow; 0xF0,0x9F,0x98,0x80 =
# a 4-byte emoji), so the gate never trips on its own source and no self-exclusion is needed.

$checkerPath = (Resolve-Path (Join-Path $PSScriptRoot '../check-encoding-loss.ps1')).Path
. (Join-Path $PSScriptRoot 'test-common.ps1')
$pwshExe = Get-TestPwshExe

$script:Fail = 0
$script:Pass = 0

# Dot-source for direct pure-function tests (the main block returns early when dot-sourced).
. $checkerPath

$utf8 = [System.Text.Encoding]::UTF8
$SECTION = @(0xC2, 0xA7)                     # U+00A7 section-sign (2-byte UTF-8)
$ARROW = @(0xE2, 0x86, 0x92)                 # U+2192 rightwards arrow (3-byte UTF-8)
$EMOJI = @(0xF0, 0x9F, 0x98, 0x80)           # U+1F600 (4-byte UTF-8 -> UTF-16 surrogate pair)

function U { param([string] $Text) return $utf8.GetBytes($Text) }
function Find-Loss { param([byte[]] $Base, [byte[]] $Head) return , @(Get-EncodingLossFindings -Files @(@{ Path = 'f'; BaseOid = 'aa'; HeadOid = 'bb'; BaseBytes = $Base; HeadBytes = $Head })) }

Write-Host 'Get-EncodingLossFindings - lossy ascii re-encode MUST flag:'
$base = [byte[]]((U 'see ') + $SECTION + (U ' then ') + $ARROW + (U ' end') + (U "`nkeep`n"))
$headCorrupt = [byte[]]((U "see ? then ? end`nkeep`n"))
Assert-Equal 1 (Find-Loss -Base $base -Head $headCorrupt).Count 'section-sign + arrow line ascii-folded -> flag'

$baseEmoji = [byte[]]((U 'hi ') + $EMOJI + (U "!`nz`n"))
$headEmoji = [byte[]]((U "hi ??!`nz`n"))
Assert-Equal 1 (Find-Loss -Base $baseEmoji -Head $headEmoji).Count '4-byte emoji folds to two ? -> flag'

$dupBase = [byte[]]((U 'a ') + $SECTION + (U ' b') + (U "`n") + (U 'a ') + $SECTION + (U " b`n"))
$dupHead = [byte[]]((U 'a ') + $SECTION + (U ' b') + (U "`na ? b`n"))
Assert-Equal 1 (Find-Loss -Base $dupBase -Head $dupHead).Count 'duplicate non-ASCII line, one folded -> flag (multiset)'

$preBase = [byte[]]((U 'a ') + $SECTION + (U ' b') + (U "`na ? b`n"))
$preHead = [byte[]]((U "a ? b`na ? b`n"))
Assert-Equal 1 (Find-Loss -Base $preBase -Head $preHead).Count 'pre-existing folded twin at base -> still flag (multiset)'

$BOM = @(0xEF, 0xBB, 0xBF)
$bomBase = [byte[]]($BOM + (U 'row ') + $SECTION + (U " x`nkeep`n"))
$bomHead = [byte[]]((U "row ? x`nkeep`n"))
Assert-Equal 1 (Find-Loss -Base $bomBase -Head $bomHead).Count 'BOM-prefixed line-0 loss -> flag (BOM stripped)'

$crBase = [byte[]]((U 'row ') + $SECTION + (U ' x') + @(0x0D) + (U 'keep') + @(0x0D))
$crHead = [byte[]]((U "row ? x`nkeep`n"))
Assert-Equal 1 (Find-Loss -Base $crBase -Head $crHead).Count 'bare-CR base folded to LF head -> flag'

Write-Host 'Get-EncodingLossFindings - legitimate / non-signature edits must NOT flag:'
Assert-Equal 0 (Find-Loss -Base $base -Head $base).Count 'identical base==head -> no flag'

$delHead = [byte[]]((U "keep`n"))
Assert-Equal 0 (Find-Loss -Base $base -Head $delHead).Count 'non-ASCII line deleted (no fold added) -> no flag'

$addQHead = [byte[]]((U 'see ') + $SECTION + (U ' then ') + $ARROW + (U ' end') + (U "`nkeep`nwhat??`n"))
Assert-Equal 0 (Find-Loss -Base $base -Head $addQHead).Count "added '?' but non-ASCII line survives -> no flag"

$lfBase = [byte[]]((U "alpha`nbeta`n"))
$crlfHead = [byte[]]((U "alpha`r`nbeta`r`n"))
Assert-Equal 0 (Find-Loss -Base $lfBase -Head $crlfHead).Count 'LF->CRLF flip, no char loss -> no flag'

$binBase = [byte[]]((U 'x ') + $SECTION + @(0x00) + (U "`n"))
$binHead = [byte[]]((U "x ?") + @(0x00) + (U "`n"))
Assert-Equal 0 (Find-Loss -Base $binBase -Head $binHead).Count 'blob with NUL byte -> skipped as binary'

Assert-Equal 0 (@(Get-EncodingLossFindings -Files $null)).Count 'null files -> 0 findings'
Assert-Equal 0 (@(Get-EncodingLossFindings -Files @())).Count 'empty files -> 0 findings'

$sample = (Find-Loss -Base $base -Head $headCorrupt)[0].Sample
Assert-True ($sample -match '\\u00A7' -and $sample -match '\\u2192') 'sample renders high chars as \uXXXX'
Assert-True ($sample -notmatch "[^\x20-\x7E]") 'sample contains no raw non-ASCII'

Write-Host 'Get-RawDiffRecords - parse of the git diff --raw -z byte stream:'
$o40 = 'a' * 40; $n40 = 'b' * 40; $o64 = 'c' * 64; $n64 = 'd' * 64; $zero = '0' * 40
$stream = ":100644 100644 $o40 $n40 M`0data.csv`0:100644 100644 $o64 $n64 M`0big.txt`0:160000 160000 $zero $zero M`0sub`0"
$records = @(Get-RawDiffRecords -RawBytes ($utf8.GetBytes($stream)))
Assert-Equal 3 $records.Count 'three records parsed'
Assert-Equal 40 $records[0].OldOid.Length 'sha-1 (40-hex) oid parsed'
Assert-Equal 64 $records[1].OldOid.Length 'sha-256 (64-hex) oid parsed'
Assert-Equal 'data.csv' $records[0].Path 'record path decoded'
Assert-Equal '160000' $records[2].OldMode 'gitlink mode preserved'
Assert-Equal 0 (@(Get-RawDiffRecords -RawBytes ([byte[]]@()))).Count 'empty stream -> 0 records'
Assert-ThrowsLike { Get-RawDiffRecords -RawBytes ($utf8.GetBytes("nocolon`0p`0")) } 'framing' 'meta without leading colon -> throw'
Assert-ThrowsLike { Get-RawDiffRecords -RawBytes ($utf8.GetBytes(":100644 100644 $o40 $n40 M`0")) } 'missing its path' 'record missing path field -> throw'
Assert-ThrowsLike { Get-RawDiffRecords -RawBytes ($utf8.GetBytes(":100644 bad`0p`0")) } 'malformed' 'short meta -> throw'
Assert-ThrowsLike { Get-RawDiffRecords -RawBytes ($utf8.GetBytes(":100644 100644 $o40 $n40 M`0data.csv")) } 'not 0x00-terminated' 'stream missing terminal NUL -> throw'
Assert-ThrowsLike { Get-RawDiffRecords -RawBytes ($utf8.GetBytes(":100644 100644 $o40 $n40 M`0`0")) } 'empty path' 'empty path segment -> throw'
Assert-ThrowsLike { Get-RawDiffRecords -RawBytes ($utf8.GetBytes(":100648 100644 $o40 $n40 M`0p`0")) } 'malformed' 'non-octal mode digit -> throw'
Assert-ThrowsLike { Get-RawDiffRecords -RawBytes ($utf8.GetBytes(":100644 100644 $o40 XYZ M`0p`0")) } 'malformed' 'non-hex oid -> throw'
Assert-ThrowsLike { Get-RawDiffRecords -RawBytes ($utf8.GetBytes(":100600 100644 $o40 $n40 M`0p`0")) } 'malformed' 'valid-octal but invalid git mode (100600) -> throw'
Assert-ThrowsLike { Get-RawDiffRecords -RawBytes ($utf8.GetBytes(":100644 100644 abc123 $n40 M`0p`0")) } 'malformed' 'short (non 40/64) oid -> throw'
Assert-ThrowsLike { Get-RawDiffRecords -RawBytes ($utf8.GetBytes(":100644 100644 $o40 $n40 Q`0p`0")) } 'malformed' 'invalid status letter (Q) -> throw'
Assert-ThrowsLike { Get-RawDiffRecords -RawBytes ($utf8.GetBytes(":100644 100644 $o40 $n40 M`0p`0`0")) } 'empty record segment' 'extra trailing NUL (empty meta) -> throw'
Assert-ThrowsLike { Get-RawDiffRecords -RawBytes ([byte[]] @(0)) } 'empty record segment' 'a lone NUL stream -> throw'

Write-Host 'Test-ScannableRecord - scope filter:'
Assert-True  (Test-ScannableRecord -OldMode '100644' -NewMode '100644' -OldOid $o40 -NewOid $n40 -Status 'M') 'regular M -> scannable'
Assert-True  (Test-ScannableRecord -OldMode '100755' -NewMode '100644' -OldOid $o40 -NewOid $n40 -Status 'T') 'regular T (exec->plain) -> scannable'
Assert-False (Test-ScannableRecord -OldMode '160000' -NewMode '160000' -OldOid $o40 -NewOid $n40 -Status 'M') 'gitlink 160000 -> not scannable'
Assert-False (Test-ScannableRecord -OldMode '120000' -NewMode '120000' -OldOid $o40 -NewOid $n40 -Status 'M') 'symlink 120000 -> not scannable'
Assert-False (Test-ScannableRecord -OldMode '000000' -NewMode '100644' -OldOid $zero -NewOid $n40 -Status 'A') 'add (zero old-oid) -> not scannable'
Assert-False (Test-ScannableRecord -OldMode '100644' -NewMode '000000' -OldOid $o40 -NewOid $zero -Status 'D') 'delete (zero new-oid) -> not scannable'

function New-EncodingRepo {
    param([string] $Prefix)
    $repo = New-TestGitRepository -Prefix $Prefix
    git -C $repo config core.autocrlf false
    return $repo
}
function Set-RepoBytes {
    param([string] $Repo, [string] $File, [byte[]] $Bytes)
    $full = Join-Path $Repo $File
    New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
    [System.IO.File]::WriteAllBytes($full, $Bytes)
}
function Invoke-Gate {
    param([string] $Repo, [switch] $Staged, [string] $BaseRef)
    $callArgs = @('-NoProfile', '-File', $checkerPath, '-RepoRoot', $Repo)
    if ($Staged) { $callArgs += '-Staged' }
    if ($PSBoundParameters.ContainsKey('BaseRef')) { $callArgs += @('-BaseRef', $BaseRef) }
    & $pwshExe @callArgs *> $null
    return $LASTEXITCODE
}

Write-Host 'Integration - staged mode:'
$repo = New-EncodingRepo -Prefix 'encloss-staged'
Set-RepoBytes -Repo $repo -File 'data.csv' -Bytes ([byte[]]((U 'see ') + $SECTION + (U " x`nkeep`n")))
git -C $repo add -A 2>$null; git -C $repo commit -q -m seed
Assert-Equal 0 (Invoke-Gate -Repo $repo -Staged) 'staged: nothing staged -> exit 0'
Set-RepoBytes -Repo $repo -File 'data.csv' -Bytes ([byte[]]((U "see ? x`nkeep`n")))
git -C $repo add -A 2>$null
Assert-Equal 1 (Invoke-Gate -Repo $repo -Staged) 'staged: ascii-folded content -> exit 1'

Write-Host 'Integration - baseref mode + waiver:'
$repo2 = New-EncodingRepo -Prefix 'encloss-base'
Set-RepoBytes -Repo $repo2 -File 'data.csv' -Bytes ([byte[]]((U 'row ') + $SECTION + (U " v`nkeep`n")))
git -C $repo2 add -A 2>$null; git -C $repo2 commit -q -m seed
git -C $repo2 checkout -q -b feature
Set-RepoBytes -Repo $repo2 -File 'data.csv' -Bytes ([byte[]]((U "row ? v`nkeep`n")))
git -C $repo2 add -A 2>$null; git -C $repo2 commit -q -m corrupt
Assert-Equal 1 (Invoke-Gate -Repo $repo2 -BaseRef 'main') 'baseref: ascii-folded content -> exit 1'
$oldOid = (git -C $repo2 rev-parse 'main:data.csv').Trim()
$newOid = (git -C $repo2 rev-parse 'HEAD:data.csv').Trim()
$waiver = Join-Path $repo2 '.github/pr-quality-gate/data/encoding-loss-waivers.txt'
New-Item -ItemType Directory -Path (Split-Path -Parent $waiver) -Force | Out-Null
Set-Content -LiteralPath $waiver -Value "data.csv`t$oldOid`t$newOid`tintentional" -NoNewline
git -C $repo2 add -A 2>$null; git -C $repo2 commit -q -m waive
Assert-Equal 0 (Invoke-Gate -Repo $repo2 -BaseRef 'main') 'baseref: matching (path,base,head) waiver -> exit 0'

Write-Host 'Integration - clean branch + binary skip:'
$repo3 = New-EncodingRepo -Prefix 'encloss-clean'
New-TestCommit -Directory $repo3 -File 'a.txt' -Content 'hello' -Message 'seed' | Out-Null
git -C $repo3 checkout -q -b feature
New-TestCommit -Directory $repo3 -File 'a.txt' -Content 'hello world' -Message 'edit' | Out-Null
Assert-Equal 0 (Invoke-Gate -Repo $repo3 -BaseRef 'main') 'baseref: clean edit -> exit 0'
Set-RepoBytes -Repo $repo3 -File 'blob.bin' -Bytes ([byte[]]((U 'x ') + $SECTION + @(0x00) + (U "`n")))
git -C $repo3 add -A 2>$null; git -C $repo3 commit -q -m addbin
git -C $repo3 checkout -q -b feature2
Set-RepoBytes -Repo $repo3 -File 'blob.bin' -Bytes ([byte[]]((U 'x ?') + @(0x00) + (U "`n")))
git -C $repo3 add -A 2>$null; git -C $repo3 commit -q -m corruptbin
Assert-Equal 0 (Invoke-Gate -Repo $repo3 -BaseRef 'feature') 'baseref: NUL-containing (binary) blob -> skipped, exit 0'

Write-Host 'Integration - invocation / fail-closed:'
$repo4 = New-EncodingRepo -Prefix 'encloss-mode'
New-TestCommit -Directory $repo4 -File 'a.txt' -Content 'seed' -Message 'seed' | Out-Null
Assert-Equal 2 (Invoke-Gate -Repo $repo4) 'no mode -> exit 2'
Assert-Equal 2 (Invoke-Gate -Repo $repo4 -Staged -BaseRef 'main') 'both modes -> exit 2'
Assert-Equal 2 (Invoke-Gate -Repo $repo4 -BaseRef 'no-such-ref-xyz') 'unresolvable -BaseRef -> exit 2 (fail-closed)'
Assert-Equal 2 (Invoke-Gate -Repo $repo4 -BaseRef 'HEAD -- inject') 'space-bearing -BaseRef is one atomic arg -> exit 2 (no injection)'
Assert-Equal 2 (Invoke-Gate -Repo $repo4 -BaseRef '--src-prefix=x') 'leading-dash -BaseRef (git-option injection) -> exit 2 (resolved as a rev)'

Remove-TestTempDirectories
Complete-TestRun
