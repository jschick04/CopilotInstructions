[CmdletBinding(DefaultParameterSetName = 'Staged')]
param(
    [Parameter(ParameterSetName = 'Staged', Mandatory)] [switch] $Staged,
    [Parameter(ParameterSetName = 'Staged')] [string] $ParentSha,
    [Parameter(ParameterSetName = 'Commit', Mandatory)] [string] $Commit,
    [Parameter(ParameterSetName = 'Paths', Mandatory)] [string[]] $Paths,
    [Parameter(ParameterSetName = 'Range', Mandatory)] [string] $Range,
    [string] $RepoRoot = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-ReadOnlyGit {
    param([Parameter(Mandatory)] [string[]] $GitArgs)
    $records = @(& git --no-optional-locks -C $RepoRoot @GitArgs 2>&1)
    $exitCode = $LASTEXITCODE
    $standardOutput = @($records | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } | ForEach-Object { [string]$_ })
    $standardError = @($records | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { [string]$_ })
    if ($exitCode -ne 0) { throw "git $($GitArgs -join ' ') failed: $($standardError -join "`n")" }
    return $standardOutput
}

function Get-Sha256Text {
    param([Parameter(Mandatory)] [string] $Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return ([Convert]::ToHexString($hash)).ToLowerInvariant()
}

function Get-CanonicalArtifactId {
    param([Parameter(Mandatory)] [string] $Parent, [string[]] $IndexLines = @())
    $ordinalLines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $IndexLines) { $ordinalLines.Add($line) }
    $ordinalLines.Sort([System.StringComparer]::Ordinal)
    return Get-Sha256Text -Text ("head=$Parent`n" + (($ordinalLines.ToArray() -join "`n") + "`n"))
}

function Convert-TreeLinesToIndexLines {
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $TreeLines)
    $indexLines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $TreeLines) {
        if ($line -cnotmatch '^(?<mode>\d{6}) (?<type>blob|commit) (?<oid>[0-9a-f]{40}|[0-9a-f]{64})\t(?<path>.*)$') {
            throw "git ls-tree returned an unrecognized entry: $line"
        }
        $indexLines.Add("$($matches['mode']) $($matches['oid']) 0`t$($matches['path'])")
    }
    return $indexLines.ToArray()
}

if (-not $RepoRoot) {
    $rootLines = @(& git --no-optional-locks rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or $rootLines.Count -ne 1) { throw 'cannot resolve repository root' }
    $RepoRoot = ([string]$rootLines[0]).Trim()
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

switch ($PSCmdlet.ParameterSetName) {
    'Staged' {
        if ($PSBoundParameters.ContainsKey('ParentSha')) {
            if ($ParentSha -cnotmatch '^(?:none|[0-9a-fA-F]{40}|[0-9a-fA-F]{64})$') { throw '-ParentSha requires none or a full 40- or 64-hex commit SHA' }
            $head = $ParentSha.ToLowerInvariant()
        } else {
            $headLines = @(& git --no-optional-locks -C $RepoRoot rev-parse --verify HEAD 2>$null)
            $head = if ($LASTEXITCODE -eq 0) {
                if ($headLines.Count -ne 1 -or $headLines[0] -cnotmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$') { throw 'HEAD must resolve to one full 40- or 64-hex commit SHA' }
                ([string]$headLines[0]).Trim()
            } else { 'none' }
        }
        $indexLines = @(Invoke-ReadOnlyGit -GitArgs @('-c', 'core.quotePath=false', 'ls-files', '-s'))
        $artifact = Get-CanonicalArtifactId -Parent $head -IndexLines $indexLines
        $divergentPaths = @(Invoke-ReadOnlyGit -GitArgs @('-c', 'core.quotePath=false', 'diff', '--name-only'))
        $untrackedPaths = @(Invoke-ReadOnlyGit -GitArgs @('-c', 'core.quotePath=false', 'ls-files', '-o', '--exclude-standard'))
        $receiptPattern = '^\.github/pr-quality-gate/audits/(?:last|post-code-change-last|pre-commit-gate-last|read-receipts-last)\.md$|^\.github/pr-quality-gate/audits/(?:signoff-receipt|publish-gate-receipt)$'
        $divergent = @($divergentPaths + $untrackedPaths | Where-Object { $_ -and $_ -notmatch $receiptPattern } | Sort-Object -Unique -CaseSensitive)
        [Console]::Out.WriteLine($artifact)
        [Console]::Out.WriteLine("worktree_divergent=$($divergent.Count)")
    }
    'Commit' {
        if ($Commit -cnotmatch '^(?:[0-9a-fA-F]{40}|[0-9a-fA-F]{64})$') { throw '-Commit requires a full 40- or 64-hex commit SHA' }
        $resolvedLines = @(Invoke-ReadOnlyGit -GitArgs @('rev-parse', '--verify', "$Commit^{commit}"))
        if ($resolvedLines.Count -ne 1 -or $resolvedLines[0] -cnotmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$') { throw '-Commit must resolve to one full 40- or 64-hex commit SHA' }
        $commitSha = ([string]$resolvedLines[0]).ToLowerInvariant()
        $commitLines = @(Invoke-ReadOnlyGit -GitArgs @('cat-file', 'commit', $commitSha))
        $parent = 'none'
        foreach ($line in $commitLines) {
            if ($line -ceq '') { break }
            if ($line -cmatch '^parent ([0-9a-f]{40}|[0-9a-f]{64})$') { $parent = $matches[1]; break }
        }
        $treeLines = @(Invoke-ReadOnlyGit -GitArgs @('-c', 'core.quotePath=false', 'ls-tree', '-r', '--full-tree', $commitSha))
        $indexLines = @(Convert-TreeLinesToIndexLines -TreeLines $treeLines)
        [Console]::Out.WriteLine((Get-CanonicalArtifactId -Parent $parent -IndexLines $indexLines))
    }
    'Range' {
        if ($Range -notmatch '^([0-9a-fA-F]{40}|[0-9a-fA-F]{64})\.\.([0-9a-fA-F]{40}|[0-9a-fA-F]{64})$') { throw '-Range requires full 40- or 64-hex base and head SHAs; remote refs are forbidden' }
        $rangeBase = $matches[1]
        $rangeHead = $matches[2]
        $baseLines = @(Invoke-ReadOnlyGit -GitArgs @('rev-parse', '--verify', "$rangeBase^{commit}"))
        $headLines = @(Invoke-ReadOnlyGit -GitArgs @('rev-parse', '--verify', "$rangeHead^{commit}"))
        foreach ($shaLines in @(@{ Lines = $baseLines }, @{ Lines = $headLines })) {
            if ($shaLines.Lines.Count -ne 1 -or $shaLines.Lines[0] -cnotmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$') { throw 'range endpoints must resolve to full 40- or 64-hex commit SHAs' }
        }
        $baseSha = $baseLines[0]
        $headSha = $headLines[0]
        [Console]::Out.WriteLine((Get-Sha256Text -Text "base=$baseSha`nhead=$headSha`n"))
    }
    'Paths' {
        $records = [System.Collections.Generic.List[string]]::new()
        foreach ($inputPath in $Paths) {
            $absolute = if ([System.IO.Path]::IsPathRooted($inputPath)) { [System.IO.Path]::GetFullPath($inputPath) } else { [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $inputPath)) }
            if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) { throw "reviewed file does not exist: $inputPath" }
            $relative = [System.IO.Path]::GetRelativePath($RepoRoot, $absolute).Replace('\','/')
            $canonicalPath = if (-not $relative.StartsWith('../') -and $relative -ne '..') { $relative } else { $absolute.Replace('\','/') }
            if ($canonicalPath -match '^[A-Z]:') { $canonicalPath = $canonicalPath.Substring(0,1).ToLowerInvariant() + $canonicalPath.Substring(1) }
            $fileHash = (Get-FileHash -LiteralPath $absolute -Algorithm SHA256).Hash.ToLowerInvariant()
            $records.Add("$canonicalPath $fileHash")
        }
        $records.Sort([System.StringComparer]::Ordinal)
        [Console]::Out.WriteLine((Get-Sha256Text -Text (($records.ToArray() -join "`n") + "`n")))
    }
}
