#Requires -Version 7.0
<#
  check-encoding-loss.ps1 - fail-closed gate: a committed change must not lossily re-encode a tracked
  TEXT file (e.g. PowerShell `Set-Content -Encoding ascii` mapping section-sign / arrow / any non-ASCII
  character to '?'). Detects the ascii-fold LINE signature: a line that was non-ASCII at base reappears
  at head with every character run through .NET ASCIIEncoding (non-ASCII -> '?'). Standalone hygiene
  checker; mechanizes the `edited-file-drops-non-ascii-encoding-loss` slug (checker-registry.tsv).

  HONEST CEILING: this RAISES the floor on the ascii-fold signature; it does NOT guarantee no-loss.
  MISSES: a re-encode mapping non-ASCII to something other than '?' (U+FFFD, ANSI high bytes,
  double-encoding); UTF-16 / any 0x00-containing blob (skipped as binary); a corrupted line that is
  ALSO edited so its fold is not a verbatim head line; rename+re-encode in one commit (--no-renames
  degrades it to D+A, unpaired); a new ASCII-saved file whose intended non-ASCII never reached base;
  a loss masked by a later commit at branch scope (-Staged validates each commit's exact content).
  FALSE POSITIVES (both waiver-able): a deliberate exact non-ASCII->'?' edit; an unrelated delete-of-L
  plus add-of-fold(L) with matching counts. Bypass: `git commit/push --no-verify` (pre-commit only) or
  pwsh-absent, same honest ceiling as the sibling hygiene gates.

  TWO GIT MODES (one scan path):
    -Staged        pre-commit: `git diff --raw -z --cached` (base = HEAD blob, head = index blob).
    -BaseRef <ref>    CI + run-local-ci: `git diff --raw -z <ref>...HEAD` (base = merge-base blob).
  Exact pre/post blob OIDs come from `--raw` (snapshot-pinned, no TOCTOU); each blob's raw BYTES are
  read via `git cat-file blob <oid>` through a redirected Process (no console decoding - the fixer must
  not itself be encoding-fragile). `--no-renames` precludes two-path R/C records; `--abbrev=64` yields
  full cat-file-resolvable OIDs.

  Exit: 0 clean (or nothing to scan), 1 violation(s), 2 invocation / git / framing error.
#>
[CmdletBinding()]
param(
    [switch] $Staged,
    [string] $BaseRef,
    [string] $RepoRoot = '',
    [switch] $Json
)
if ($MyInvocation.InvocationName -ne '.') {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
}

$script:ExitOk = 0
$script:ExitViolation = 1
$script:ExitInvocation = 2

$script:WaiverRelPath = '.github/pr-quality-gate/data/encoding-loss-waivers.txt'
$script:ZeroOidPattern = '^0+$'
$script:RegularModes = @('100644', '100755')

function Get-AsciiFold {
    # Reproduce `Set-Content -Encoding ascii` exactly: encode to ASCII (every non-ASCII char -> '?' via
    # the default replacement fallback, a surrogate pair -> two '?') then decode back to a string.
    param([string] $Line)
    return [System.Text.Encoding]::ASCII.GetString([System.Text.Encoding]::ASCII.GetBytes($Line))
}

function Get-NormalizedLines {
    # UTF-8 decode (invalid sequences -> U+FFFD identically both sides), strip a leading BOM (the real
    # re-encode consumes it before writing, so a line-0 loss would otherwise be masked), and normalize
    # CRLF / bare-CR / LF all to LF so a re-encode that changes the line ending still line-matches.
    param([byte[]] $Bytes)
    $text = [System.Text.Encoding]::UTF8.GetString($Bytes)
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    $text = $text.Replace("`r`n", "`n").Replace("`r", "`n")
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($line in $text.Split([char]10)) { $lines.Add($line) }
    return $lines
}

function Test-HasNulByte {
    param([byte[]] $Bytes)
    foreach ($byte in $Bytes) { if ($byte -eq 0) { return $true } }
    return $false
}

function ConvertTo-AsciiSafe {
    # Render a sampled non-ASCII line for the console/JSON without emitting raw non-ASCII: printable
    # ASCII verbatim, everything else as \uXXXX (keeps this checker's own output ASCII-only).
    param([string] $Text)
    $builder = New-Object System.Text.StringBuilder
    foreach ($char in $Text.ToCharArray()) {
        $code = [int] $char
        if ($code -ge 0x20 -and $code -le 0x7E) { [void] $builder.Append($char) }
        else { [void] $builder.AppendFormat('\u{0:X4}', $code) }
    }
    if ($builder.Length -gt 120) { return $builder.ToString(0, 120) + '...' }
    return $builder.ToString()
}

function Get-EncodingLossFindings {
    <#
      Pure signature: input file records @{ Path; BaseOid; HeadOid; BaseBytes; HeadBytes }; output one
      finding per file matching the ascii-fold multiset signature. A 0x00-containing blob is binary ->
      skipped. FLAG a file iff some base line L (fold F != L, i.e. L held a non-ASCII char) satisfies
      baseCount(L) > headCount(L) AND headCount(F) > baseCount(F): an L disappeared and its fold F
      appeared. Multiset counts (not set membership) catch duplicate lines and pre-existing folds.
    #>
    param([object[]] $Files)
    $findings = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Files) { return $findings }
    foreach ($file in $Files) {
        $baseBytes = [byte[]] $file.BaseBytes
        $headBytes = [byte[]] $file.HeadBytes
        if ((Test-HasNulByte -Bytes $baseBytes) -or (Test-HasNulByte -Bytes $headBytes)) { continue }
        $baseCount = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::Ordinal)
        $headCount = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::Ordinal)
        foreach ($line in (Get-NormalizedLines -Bytes $baseBytes)) {
            $current = 0; [void] $baseCount.TryGetValue($line, [ref] $current); $baseCount[$line] = $current + 1
        }
        foreach ($line in (Get-NormalizedLines -Bytes $headBytes)) {
            $current = 0; [void] $headCount.TryGetValue($line, [ref] $current); $headCount[$line] = $current + 1
        }
        $sample = $null
        foreach ($entry in $baseCount.GetEnumerator()) {
            $lineL = $entry.Key
            $foldF = Get-AsciiFold -Line $lineL
            if ($foldF -ceq $lineL) { continue }
            $baseL = $entry.Value
            $headL = 0; [void] $headCount.TryGetValue($lineL, [ref] $headL)
            $headF = 0; [void] $headCount.TryGetValue($foldF, [ref] $headF)
            $baseF = 0; [void] $baseCount.TryGetValue($foldF, [ref] $baseF)
            if (($baseL -gt $headL) -and ($headF -gt $baseF)) { $sample = $lineL; break }
        }
        if ($null -ne $sample) {
            $findings.Add([pscustomobject]@{
                Path    = $file.Path
                BaseOid = $file.BaseOid
                HeadOid = $file.HeadOid
                Sample  = (ConvertTo-AsciiSafe -Text $sample)
            })
        }
    }
    return $findings
}

function Get-RawDiffRecords {
    <#
      Pure parse of a `git diff --raw -z` byte stream into records
      { OldMode; NewMode; OldOid; NewOid; Status; Path }. 0x00-terminated fields alternate meta / path;
      --no-renames guarantees one path per record. Fail closed (throw) on any malformed framing: a stream
      not ending in 0x00, a meta not matching `:mode mode oid oid status` exactly, an empty path, or a
      segment that is not valid UTF-8 (STRICT decode - so a waiver key cannot be forged by a
      replacement-character path collision).
    #>
    param([byte[]] $RawBytes)
    $records = New-Object System.Collections.Generic.List[object]
    if ($null -eq $RawBytes -or $RawBytes.Length -eq 0) { return $records }
    if ($RawBytes[$RawBytes.Length - 1] -ne 0) { throw "'git diff --raw -z' stream is not 0x00-terminated (truncated output)" }
    $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
    $segments = New-Object System.Collections.Generic.List[string]
    $segmentStart = 0
    for ($index = 0; $index -lt $RawBytes.Length; $index++) {
        if ($RawBytes[$index] -eq 0) {
            try { $segments.Add($strictUtf8.GetString($RawBytes, $segmentStart, $index - $segmentStart)) }
            catch { throw "'git diff --raw -z' segment is not valid UTF-8" }
            $segmentStart = $index + 1
        }
    }
    $metaPattern = '^(000000|100644|100755|120000|160000) (000000|100644|100755|120000|160000) ([0-9a-f]{40}|[0-9a-f]{64}) ([0-9a-f]{40}|[0-9a-f]{64}) ([ABCDMRTUX])$'
    $cursor = 0
    while ($cursor -lt $segments.Count) {
        $meta = $segments[$cursor]
        if ([string]::IsNullOrEmpty($meta)) { throw "'git diff --raw -z' has an empty record segment (malformed framing)" }
        if (-not $meta.StartsWith(':')) { throw "unexpected 'git diff --raw -z' framing at segment ${cursor}: '$meta'" }
        if ($cursor + 1 -ge $segments.Count) { throw "'git diff --raw -z' record is missing its path field" }
        $recordPath = $segments[$cursor + 1]
        $cursor += 2
        if ([string]::IsNullOrEmpty($recordPath)) { throw "'git diff --raw -z' record has an empty path" }
        $match = [regex]::Match($meta.Substring(1), $metaPattern)
        if (-not $match.Success) { throw "malformed 'git diff --raw' record meta: '$meta'" }
        $records.Add([pscustomobject]@{
                OldMode = $match.Groups[1].Value; NewMode = $match.Groups[2].Value
                OldOid  = $match.Groups[3].Value; NewOid = $match.Groups[4].Value
                Status  = $match.Groups[5].Value; Path = $recordPath
            })
    }
    return $records
}

function Test-ScannableRecord {
    # Scannable iff both sides are regular files (100644/100755), both blob OIDs are present (non-zero),
    # and the status is a plain modify / type-change. Gitlink (160000), symlink (120000), a pure add
    # (zero old-oid) and a delete (zero new-oid) are out of scope.
    param([string] $OldMode, [string] $NewMode, [string] $OldOid, [string] $NewOid, [string] $Status)
    if ($Status -ne 'M' -and $Status -ne 'T') { return $false }
    if ($script:RegularModes -notcontains $OldMode -or $script:RegularModes -notcontains $NewMode) { return $false }
    if ($OldOid -match $script:ZeroOidPattern -or $NewOid -match $script:ZeroOidPattern) { return $false }
    return $true
}

# ---- main (skipped when dot-sourced by the tests) -----------------------------------------------
if ($MyInvocation.InvocationName -eq '.') { return }

Import-Module (Join-Path $PSScriptRoot 'lib/repo-root.psm1') -Force
if ($RepoRoot) {
    try { $repoRoot = (Resolve-Path -LiteralPath $RepoRoot -ErrorAction Stop).Path }
    catch { Write-Host "::error::INVOCATION_FAILED: -RepoRoot '$RepoRoot' does not resolve: $($_.Exception.Message)"; exit $script:ExitInvocation }
} else {
    try { $repoRoot = Resolve-RepoRoot -Explicit '' -ScriptRoot $PSScriptRoot -Anchors @('scripts/check-encoding-loss.ps1') -RequireGitWorkTree }
    catch { Write-Host "::error::$($_.Exception.Message)"; exit $script:ExitInvocation }
}

$stagedMode = $Staged.IsPresent
$baseMode = -not [string]::IsNullOrWhiteSpace($BaseRef)
if ($stagedMode -and $baseMode) { Write-Host "::error::INVOCATION_FAILED: supply at most one of -Staged / -BaseRef, not both"; exit $script:ExitInvocation }
if (-not $stagedMode -and -not $baseMode) { Write-Host "::error::INVOCATION_FAILED: supply -Staged (pre-commit) or -BaseRef <ref> (CI / branch diff)"; exit $script:ExitInvocation }

function Invoke-GitBytes {
    # Run git with args passed ATOMICALLY (ArgumentList, never a space-join - a space-bearing -BaseRef
    # must not inject extra tokens) and stdout captured as raw BYTES (no console decoding); stderr is
    # drained async so a large blob cannot deadlock. A launch/stream failure returns a non-zero ExitCode
    # so every caller fails closed (never a false pass or exit 1). The repo path goes via WorkingDirectory.
    param([string[]] $GitArgs)
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = 'git'
    foreach ($token in $GitArgs) { $startInfo.ArgumentList.Add($token) }
    $startInfo.WorkingDirectory = $repoRoot
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.UseShellExecute = $false
    $memory = New-Object System.IO.MemoryStream
    $process = $null
    try {
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        [void] $process.Start()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.StandardOutput.BaseStream.CopyTo($memory)
        $process.WaitForExit()
        return [pscustomobject]@{ Bytes = $memory.ToArray(); ExitCode = $process.ExitCode; StdErr = $stderrTask.GetAwaiter().GetResult() }
    } catch {
        return [pscustomobject]@{ Bytes = [byte[]] @(); ExitCode = -1; StdErr = $_.Exception.Message }
    } finally {
        $memory.Dispose()
        if ($null -ne $process) { $process.Dispose() }
    }
}

# Waivers are read from the REVIEWED snapshot (index in -Staged, HEAD in -BaseRef), never the worktree,
# so a waiver is itself part of the committed/staged change. Existence is probed with ls-files / ls-tree
# so a genuinely absent file (exit 0, empty output) is distinguished from a git/repo error (non-zero ->
# fail closed). The path column is matched EXACTLY (only the oid columns are trimmed).
$waiverSpec = if ($stagedMode) { ":$script:WaiverRelPath" } else { "HEAD:$script:WaiverRelPath" }
$waiverProbeArgs = if ($stagedMode) { @('ls-files', '-z', '--', $script:WaiverRelPath) } else { @('ls-tree', '-z', 'HEAD', '--', $script:WaiverRelPath) }
$waiverSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
$waiverProbe = Invoke-GitBytes -GitArgs $waiverProbeArgs
if ($waiverProbe.ExitCode -ne 0) {
    Write-Host "::error::INVOCATION_FAILED: cannot probe the waiver file (git exit $($waiverProbe.ExitCode)); failing closed. $($waiverProbe.StdErr.Trim())"
    exit $script:ExitInvocation
}
if ($waiverProbe.Bytes.Length -gt 0) {
    $waiverBlob = Invoke-GitBytes -GitArgs @('cat-file', 'blob', $waiverSpec)
    if ($waiverBlob.ExitCode -ne 0) {
        Write-Host "::error::INVOCATION_FAILED: the waiver file '$waiverSpec' exists but is unreadable (exit $($waiverBlob.ExitCode)); failing closed."
        exit $script:ExitInvocation
    }
    foreach ($waiverLine in ([System.Text.Encoding]::UTF8.GetString($waiverBlob.Bytes) -split "`n")) {
        $noCr = $waiverLine -replace "`r", ''
        if ($noCr.Trim() -eq '' -or $noCr.StartsWith('#')) { continue }
        $columns = $noCr -split "`t"
        if ($columns.Count -ge 3) {
            [void] $waiverSet.Add($columns[0] + "`t" + $columns[1].Trim() + "`t" + $columns[2].Trim())
        }
    }
}

if ($stagedMode) {
    $rangeArg = '--cached'
} else {
    # Resolve -BaseRef to a commit OID (fail-closed) so a dash-bearing ref (e.g. --src-prefix=foo) can
    # never reach the diff as an option; --end-of-options makes rev-parse treat it strictly as a rev.
    $resolved = Invoke-GitBytes -GitArgs @('rev-parse', '--verify', '--quiet', '--end-of-options', ($BaseRef + '^{commit}'))
    if ($resolved.ExitCode -ne 0) {
        Write-Host "::error::INVOCATION_FAILED: -BaseRef '$BaseRef' does not resolve to a commit; failing closed."
        exit $script:ExitInvocation
    }
    $rangeArg = ([System.Text.Encoding]::ASCII.GetString($resolved.Bytes)).Trim() + '...HEAD'
}
$rawResult = Invoke-GitBytes -GitArgs @('-c', 'core.quotePath=false', 'diff', '--raw', '-z', '--no-renames', '--abbrev=64', $rangeArg, '--')
if ($rawResult.ExitCode -ne 0) {
    Write-Host "::error::INVOCATION_FAILED: 'git diff --raw' failed (exit $($rawResult.ExitCode)) for '$rangeArg'; failing closed. $($rawResult.StdErr.Trim())"
    exit $script:ExitInvocation
}

try { $records = Get-RawDiffRecords -RawBytes $rawResult.Bytes }
catch { Write-Host "::error::INVOCATION_FAILED: $($_.Exception.Message); failing closed."; exit $script:ExitInvocation }

# Scan each record incrementally (read a file's two blobs, fold-correlate, release) so memory stays
# bounded to one file rather than the whole diff.
$findings = New-Object System.Collections.Generic.List[object]
foreach ($record in $records) {
    if (-not (Test-ScannableRecord -OldMode $record.OldMode -NewMode $record.NewMode -OldOid $record.OldOid -NewOid $record.NewOid -Status $record.Status)) { continue }
    if ($waiverSet.Contains($record.Path + "`t" + $record.OldOid + "`t" + $record.NewOid)) { continue }
    $baseBlob = Invoke-GitBytes -GitArgs @('cat-file', 'blob', $record.OldOid)
    if ($baseBlob.ExitCode -ne 0) { Write-Host "::error::INVOCATION_FAILED: cannot read base blob $($record.OldOid) for '$($record.Path)'; failing closed."; exit $script:ExitInvocation }
    $headBlob = Invoke-GitBytes -GitArgs @('cat-file', 'blob', $record.NewOid)
    if ($headBlob.ExitCode -ne 0) { Write-Host "::error::INVOCATION_FAILED: cannot read head blob $($record.NewOid) for '$($record.Path)'; failing closed."; exit $script:ExitInvocation }
    foreach ($finding in @(Get-EncodingLossFindings -Files @(@{ Path = $record.Path; BaseOid = $record.OldOid; HeadOid = $record.NewOid; BaseBytes = $baseBlob.Bytes; HeadBytes = $headBlob.Bytes }))) {
        $findings.Add($finding)
    }
}
$modeLabel = if ($stagedMode) { 'staged diff' } else { "$BaseRef...HEAD range" }
$modeName = if ($stagedMode) { 'staged' } else { "$BaseRef...HEAD" }

if ($Json) {
    [pscustomobject]@{
        checker       = 'check-encoding-loss'
        scope         = $modeName
        finding_count = $findings.Count
        status        = if ($findings.Count -gt 0) { 'fail' } else { 'pass' }
        findings      = @($findings | ForEach-Object { [pscustomobject]@{ path = $_.Path; base_oid = $_.BaseOid; head_oid = $_.HeadOid; sample = $_.Sample } })
    } | ConvertTo-Json -Depth 5
    if ($findings.Count -gt 0) { exit $script:ExitViolation }
    exit $script:ExitOk
}

if ($findings.Count -gt 0) {
    Write-Host "check-encoding-loss: $($findings.Count) file(s) show the lossy ascii re-encode signature (a non-ASCII line reappears with characters mapped to '?'):" -ForegroundColor Red
    foreach ($finding in $findings) {
        Write-Host "  ::error::$($finding.Path): a non-ASCII line was ascii-folded (sample: '$($finding.Sample)'). If this replacement is intentional, waive it with this exact line in ${script:WaiverRelPath}:"
        Write-Host "      $($finding.Path)`t$($finding.BaseOid)`t$($finding.HeadOid)"
    }
    exit $script:ExitViolation
}

Write-Host "check-encoding-loss: OK - no lossy ascii re-encode signature in the $modeLabel." -ForegroundColor Green
exit $script:ExitOk
