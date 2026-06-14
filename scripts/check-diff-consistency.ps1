<#
  check-diff-consistency.ps1 - D2 deterministic tier of the catalog-driven enforcement baseline (size-free; zero LLM
  context). Four LINE-LOCAL rules: receipt-numeric-claim-drift (HARD), shell-sed-exit-zero-fallback-unreachable,
  ci-shell-or-true-swallows-real-failures, ci-jq-arg-literal-backslash-n (last three ADVISORY). Cross-block YAML
  patterns (pwsh-LASTEXITCODE, github.sha-after-checkout) live in the lens tier (D3), not here. Ref contract:
  -Mode commit (parent..tip), -Mode pr-sweep (merge-base..HEAD), or explicit -BaseRef/-HeadRef (overrides -Mode).
#>
[CmdletBinding()]
param(
    [string] $RepoRoot = (Get-Location).Path,
    [ValidateSet('commit', 'pr-sweep', 'range')] [string] $Mode = 'range',
    [string] $BaseRef,
    [string] $HeadRef,
    [string] $DefaultBranch = 'main',
    [switch] $AdvisoryAsHard,
    [switch] $Json
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Git {
    param([string[]] $GitArgs)
    $out = & git -C $RepoRoot @GitArgs 2>$null
    if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed (exit $LASTEXITCODE) - refusing to run fail-open" }
    return $out
}

if (-not $HeadRef) { $HeadRef = 'HEAD' }
if (-not $BaseRef) {
    switch ($Mode) {
        'commit'   {
            $parent = & git -C $RepoRoot rev-parse --verify --quiet "$HeadRef^" 2>$null
            if ($LASTEXITCODE -eq 0 -and $parent) {
                $BaseRef = "$HeadRef~1"
            }
            else {
                # root commit (no parent): diff against the git empty-tree object, not the nonexistent HEAD~1.
                # 5.1-safe: short-circuit on PS version before touching $IsWindows (a PS6+ automatic var; undefined under StrictMode on 5.1).
                $nullDev = if ($PSVersionTable.PSVersion.Major -ge 6 -and -not $IsWindows) { '/dev/null' } else { 'NUL' }
                $emptyTree = & git -C $RepoRoot hash-object -t tree $nullDev 2>$null
                $BaseRef = if ($emptyTree) { $emptyTree.Trim() } else { '4b825dc642cb6eb9a060e54bf8d69288fbee4904' }
            }
        }
        'pr-sweep' { $BaseRef = @(Invoke-Git @('merge-base', $DefaultBranch, $HeadRef))[0] }
        default    { $BaseRef = $DefaultBranch }
    }
}

$findings = New-Object System.Collections.Generic.List[object]
function Add-Finding {
    param([string] $Slug, [string] $File, [int] $Line, [ValidateSet('hard', 'advisory')] [string] $Severity, [string] $Message)
    $findings.Add([pscustomobject]@{ Slug = $Slug; File = $File; Line = $Line; Severity = $Severity; Message = $Message })
}

$changed = @(@(Invoke-Git @('diff', '--name-only', '--no-renames', '--diff-filter=d', "$BaseRef..$HeadRef") | Where-Object { $_ }) | ForEach-Object { $_ -replace '\\', '/' })

$addedByFile = @{}
foreach ($f in $changed) {
    $patch = Invoke-Git @('diff', '--no-renames', "$BaseRef..$HeadRef", '--', $f)
    $ln = 0; $inHunk = $false; $addLines = New-Object System.Collections.Generic.List[object]
    foreach ($pl in $patch) {
        if ($pl -match '^@@ -\d+(?:,\d+)? \+(\d+)') { $ln = [int]$matches[1]; $inHunk = $true; continue }
        if (-not $inHunk) { continue }          # skip pre-hunk headers so a content line starting with +++ is not dropped
        if ($pl.StartsWith('\ ')) { continue }  # "\ No newline at end of file" is a marker, not a content line
        if ($pl.StartsWith('+')) { $addLines.Add([pscustomobject]@{ Line = $ln; Text = $pl.Substring(1) }); $ln++ }
        elseif ($pl.StartsWith('-')) { }
        else { $ln++ }
    }
    $addedByFile[$f] = $addLines
}
function Get-Added { param([string] $GlobRegex) $changed | Where-Object { $_ -match $GlobRegex } | ForEach-Object { $f = $_; $addedByFile[$f] | ForEach-Object { [pscustomobject]@{ File = $f; Line = $_.Line; Text = $_.Text } } } }

foreach ($a in (Get-Added '\.(sh|ya?ml)$')) {
    if ($a.Text -match '\bsed\b[^|]*\|\|' -and $a.Text -notmatch '(\{|;|&&|\|\|)\s*(exit|return|die|false|break|continue)\b') {
        Add-Finding 'shell-sed-exit-zero-fallback-unreachable' $a.File $a.Line 'advisory' "sed exits 0 even on no-match, so a '|| <default>' fallback may be unreachable (confirm it handles errors, not no-match): $($a.Text.Trim())"
    }
}
foreach ($a in (Get-Added '\.(sh|ya?ml)$')) {
    if ($a.Text -match "--arg\s+\S+\s+[`"'][^`"']*\\n") {
        Add-Finding 'ci-jq-arg-literal-backslash-n' $a.File $a.Line 'advisory' "jq --arg passes literal backslash-n, not a newline: $($a.Text.Trim())"
    }
}
foreach ($a in (Get-Added '\.(sh|ya?ml)$')) {
    if ($a.Text -match '\|\|\s*true\b' -and $a.Text -notmatch 'config\s+--get|grep\s+-q|rev-parse|cat-file\s+-e') {
        Add-Finding 'ci-shell-or-true-swallows-real-failures' $a.File $a.Line 'advisory' "'|| true' may mask real failures (not a known expected-nonzero command): $($a.Text.Trim())"
    }
}
if ($Mode -eq 'commit') {
    # Commit-cadence only; denominator excludes audits/** and is rename-blind (the panel-ledger files-touched convention).
    $tipFiles = @(Invoke-Git @('diff-tree', '--root', '--no-renames', '--no-commit-id', '--name-only', '-r', $HeadRef) |
        Where-Object { $_ -and $_ -notmatch '^\.github/pr-quality-gate/audits/' }).Count
    foreach ($a in (Get-Added 'pr-quality-gate/audits/post-code-change-last\.md$')) {
        $m = [regex]::Match($a.Text, 'files-touched:\s*(\d+)')
        if ($m.Success -and [int]$m.Groups[1].Value -ne $tipFiles) {
            Add-Finding 'receipt-numeric-claim-drift' $a.File $a.Line 'hard' "files-touched claims $($m.Groups[1].Value) but the tip commit ($HeadRef) touches $tipFiles"
        }
    }
}

$hard = @($findings | Where-Object { $_.Severity -eq 'hard' -or ($AdvisoryAsHard -and $_.Severity -eq 'advisory') })
$exitCode = if ($hard.Count -gt 0) { 1 } else { 0 }
if ($Json) {
    [pscustomobject]@{
        checker       = 'check-diff-consistency'
        mode          = $Mode
        base_ref      = $BaseRef
        head_ref      = $HeadRef
        changed_files = $changed.Count
        hard_count    = $hard.Count
        status        = if ($hard.Count -gt 0) { 'fail' } else { 'pass' }
        findings      = @($findings | ForEach-Object { [pscustomobject]@{ slug = $_.Slug; file = $_.File; line = $_.Line; severity = $_.Severity; message = $_.Message } })
    } | ConvertTo-Json -Depth 6
}
else {
    if ($findings.Count -eq 0) {
        Write-Host "check-diff-consistency: PASS (0 findings) over $($changed.Count) changed files [mode=$Mode $BaseRef..$HeadRef]" -ForegroundColor Green
    }
    else {
        Write-Host "check-diff-consistency: $($findings.Count) finding(s) ($($hard.Count) hard) [mode=$Mode $BaseRef..$HeadRef]" -ForegroundColor Yellow
        $findings | Sort-Object Severity, File, Line | ForEach-Object { "  [{0}] {1} {2}:{3}  {4}" -f $_.Severity.ToUpper(), $_.Slug, $_.File, $_.Line, $_.Message }
    }
}
exit $exitCode
