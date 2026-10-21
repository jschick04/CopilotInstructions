param([string] $RepositoryRoot = '', [switch] $InventoryOnly)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$script:Pass = 0
$script:Fail = 0
. (Join-Path $PSScriptRoot 'test-common.ps1')
$repoRoot = if ($RepositoryRoot) { (Resolve-Path -LiteralPath $RepositoryRoot).Path } else { (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path }
Import-Module (Join-Path $PSScriptRoot '../lib/panel-ledger-helpers.psm1') -Force
$failures = [System.Collections.Generic.List[string]]::new()
$tracked = @(& git -C $repoRoot ls-files --cached 2>$null | ForEach-Object { ([string]$_).Replace('\','/') })
if ($LASTEXITCODE -ne 0) { throw 'git ls-files failed; cannot run the guarded-path inventory' }
$trackedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($path in $tracked) { [void]$trackedSet.Add($path) }

function Test-PathClassified {
    param([string] $Path)
    foreach ($pattern in $GuardedPathPatterns) { if ($Path -like $pattern) { return 'GUARDED' } }
    foreach ($pattern in $NonGuardedPathPatterns) { if ($Path -like $pattern) { return 'NON-GUARDED' } }
    return $null
}

function Resolve-RepoPath {
    param([string] $SourcePath, [string] $Literal, [switch] $RepoRelative)
    $candidate = $Literal.Replace('\','/')
    if ($candidate -match '^[A-Za-z]:|^/') { return [pscustomobject]@{ Path = $candidate; Escapes = $true } }
    $base = if ($RepoRelative) { $repoRoot } else { Split-Path -Parent (Join-Path $repoRoot $SourcePath) }
    $full = [System.IO.Path]::GetFullPath((Join-Path $base $candidate))
    $rootPrefix = $repoRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) { return [pscustomobject]@{ Path = $full; Escapes = $true } }
    $relative = $full.Substring($rootPrefix.Length).Replace('\','/')
    return [pscustomobject]@{ Path = $relative; Escapes = $false }
}

function Get-LiteralReferences {
    param([string] $RelPath, [string[]] $Lines)
    $references = [System.Collections.Generic.List[object]]::new()
    $rootCommandContext = ($RelPath -match '^\.githooks/' -or $RelPath -match '^\.github/workflows/')
    $joinedVariables = @{}
    $scriptRelativeVariables = @{}
    foreach ($line in $Lines) {
        if ($line -match '^\s*#' -or $line -match '^\s*(Write-Host|Write-Error|echo|printf)\b') { continue }
        if ($RelPath -match '^\.github/workflows/' -and $line -match '^\s*(paths|branches):') { continue }
        if ($line -match '\$(\w+)\s*=\s*Join-Path\s+(\$PSScriptRoot|\$scriptDir|\$here)\s+''([^'']+)''') { $joinedVariables[$matches[1]] = [pscustomobject]@{ Literal=$matches[3]; Anchor=$matches[2] } }
        if ($line -match '\$(\w+)\s*=\s*Split-Path\s+-Parent\s+(\$PSCommandPath|\$MyInvocation\.MyCommand\.Path|\$PSScriptRoot)') {
            $scriptRelativeVariables[$matches[1]] = if ($matches[2] -eq '$PSScriptRoot') { '..' } else { '.' }
        }
        foreach ($match in [regex]::Matches($line, '(?i)(?:pwsh|powershell)(?:\.exe)?\s+[^\r\n]*?-File\s+[''"]?((?:\./|\.\./|scripts/|\.github/|\.githooks/)[^\s)''"]+\.(?:ps1|psm1|sh))')) {
            $references.Add([pscustomobject]@{ Literal=$match.Groups[1].Value; RepoRelative=($rootCommandContext -or $match.Groups[1].Value.StartsWith('scripts/') -or $match.Groups[1].Value.StartsWith('.github/') -or $match.Groups[1].Value.StartsWith('.githooks/')); Invocation=$true })
        }
        foreach ($match in [regex]::Matches($line, '(?:^|[;&|]\s*|\s)(?:\./|\.\./|scripts/|\.github/|\.githooks/)[A-Za-z0-9_./-]+\.(?:ps1|psm1|sh)(?=$|[\s;|&''"])')) {
            $literal = $match.Value.Trim().Trim(';','&','|').Trim()
            if ($literal) { $references.Add([pscustomobject]@{ Literal=$literal; RepoRelative=($rootCommandContext -or $literal.StartsWith('scripts/') -or $literal.StartsWith('.github/') -or $literal.StartsWith('.githooks/')); Invocation=$true }) }
        }
        foreach ($match in [regex]::Matches($line, '(?:bash|source|\.\s+|&\s+)(?:[''"])?((?:\./|\.\./|scripts/|\.github/|\.githooks/)[^''"\s)]+\.(?:ps1|psm1|sh))')) {
            $literal=$match.Groups[1].Value
            $references.Add([pscustomobject]@{ Literal=$literal; RepoRelative=($rootCommandContext -or $literal.StartsWith('scripts/') -or $literal.StartsWith('.github/') -or $literal.StartsWith('.githooks/')); Invocation=$true })
        }
        foreach ($match in [regex]::Matches($line, 'Import-Module\s*\(Join-Path\s+(\$PSScriptRoot|\$scriptDir|\$here)\s+''([^'']+)''\)')) {
            $references.Add([pscustomobject]@{ Literal=$match.Groups[2].Value; RepoRelative=$false; Invocation=$true })
        }
        foreach ($match in [regex]::Matches($line, 'Join-Path\s+(\$PSScriptRoot|\$scriptDir|\$here)\s+[''"]([^''"]+)[''"]')) {
            $anchor = $match.Groups[1].Value.TrimStart('$')
            $literal = $match.Groups[2].Value
            if ($scriptRelativeVariables.ContainsKey($anchor)) { $literal = $scriptRelativeVariables[$anchor] + '/' + $literal }
            $references.Add([pscustomobject]@{ Literal=$literal; RepoRelative=$false; Invocation=($line -match '&|Import-Module') })
        }
        foreach ($match in [regex]::Matches($line, 'Script\s*=\s*''((?:scripts|\.github)/[^'']+\.(?:ps1|psm1|sh))''')) {
            $references.Add([pscustomobject]@{ Literal=$match.Groups[1].Value; RepoRelative=$true; Invocation=$true })
        }
        if ($line -match 'dirname\s+[''"]?\$\{BASH_SOURCE\[0\]\}') {
            foreach ($match in [regex]::Matches($line, '(?:\$\(dirname\s+[''"]?\$\{BASH_SOURCE\[0\]\}[''"]?\)|\$\(cd\s+\$\(dirname[^)]*\)[^)]*\))[/\\]([^''"\s]+\.(?:ps1|psm1|sh))')) {
                $references.Add([pscustomobject]@{ Literal=$match.Groups[1].Value; RepoRelative=$rootCommandContext; Invocation=$true })
            }
        }
        foreach ($match in [regex]::Matches($line, '[''"]((?:\.github|scripts|\.githooks)/[^''"]+)[''"]')) {
            $candidate=$match.Groups[1].Value.Replace('\','/')
            if ($candidate -match '[*?\[]|\\\.') { continue }
            $absolute = Join-Path $repoRoot $candidate
            if ((Test-Path -LiteralPath $absolute -PathType Container) -or $candidate.EndsWith('/')) { continue }
            if ([IO.Path]::HasExtension($candidate) -or $trackedSet.Contains($candidate)) {
                $references.Add([pscustomobject]@{ Literal=$candidate; RepoRelative=$true; Invocation=$false })
            }
        }
        foreach ($variable in $joinedVariables.Keys) {
            if ($line -match ('&\s*\$' + [regex]::Escape($variable) + '\b')) {
                $references.Add([pscustomobject]@{ Literal=$joinedVariables[$variable].Literal; RepoRelative=$false; Invocation=$true })
            }
        }
        foreach ($variable in $scriptRelativeVariables.Keys) {
            if ($line -match ('(?:&|\.)\s*\$' + [regex]::Escape($variable) + '\b')) {
                $references.Add([pscustomobject]@{ Literal=$scriptRelativeVariables[$variable]; RepoRelative=$false; Invocation=$true })
            }
        }
    }
    return @($references)
}

$entryFiles = [System.Collections.Generic.List[string]]::new()
foreach ($glob in @('.githooks/*','.github/workflows/*.yml','.github/workflows/*.yaml')) {
    foreach ($file in Get-ChildItem -Path (Join-Path $repoRoot $glob) -File -ErrorAction SilentlyContinue) { $entryFiles.Add($file.FullName.Substring($repoRoot.Length + 1).Replace('\','/')) }
}
foreach ($path in @('scripts/run-local-ci.ps1','scripts/run-quality-gate-ci.ps1','scripts/verify-pattern-catalog.ps1','.github/pr-quality-gate/gate-runner.ps1','.github/pr-quality-gate/gate-runner.sh')) {
    if (Test-Path -LiteralPath (Join-Path $repoRoot $path)) { $entryFiles.Add($path) }
}
$scanned = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$queue = [System.Collections.Generic.Queue[string]]::new()
foreach ($path in $entryFiles) { $queue.Enqueue($path) }
$results = [System.Collections.Generic.List[object]]::new()
while ($queue.Count -gt 0) {
    $source = $queue.Dequeue()
    if (-not $scanned.Add($source)) { continue }
    if ($source -match '^scripts/tests/') { continue }
    $sourceFull = Join-Path $repoRoot $source
    if (-not (Test-Path -LiteralPath $sourceFull -PathType Leaf)) { $failures.Add("scan source missing: $source"); continue }
    $lines = @(Get-Content -LiteralPath $sourceFull)
    foreach ($ref in (Get-LiteralReferences -RelPath $source -Lines $lines)) {
        $resolved = Resolve-RepoPath -SourcePath $source -Literal $ref.Literal -RepoRelative:$ref.RepoRelative
        if ($resolved.Escapes) { $failures.Add("$source resolves outside repo: $($ref.Literal)"); continue }
        $path = $resolved.Path
        if ($path -match '^scripts/tests/') { continue }
        $absolute = Join-Path $repoRoot $path
        if ((Test-Path -LiteralPath $absolute -PathType Container) -or $path.EndsWith('/')) { continue }
        $class = Test-PathClassified -Path $path
        if (-not $class) { $failures.Add("unclassified path: $path from $source") }
        else { $results.Add([pscustomobject]@{ Path = $path; Class = $class; Source = $source }) }
        if ($class -eq 'GUARDED' -and $path -match '\.(ps1|psm1|sh)$' -and $path -notmatch '^scripts/tests/') { $queue.Enqueue($path) }
    }
}

foreach ($path in $tracked) {
    $guardedMatch = $null; $nonGuardedMatch = $null
    foreach ($pattern in $GuardedPathPatterns) { if ($path -like $pattern) { $guardedMatch = $pattern; break } }
    foreach ($pattern in $NonGuardedPathPatterns) { if ($path -like $pattern) { $nonGuardedMatch = $pattern; break } }
    if ($guardedMatch -and $nonGuardedMatch) { $failures.Add("guarded/non-guarded lists overlap for tracked path: $path") }
}

if ($failures.Count -gt 0) {
    $failures | Sort-Object -Unique | ForEach-Object { Write-Host "FAIL: $_" }
    exit 1
}

if ($InventoryOnly) { exit 0 }

$results | Sort-Object Path,Source -Unique | Format-Table -AutoSize Path,Class,Source | Out-String | Write-Output
Assert-True ($results.Count -gt 0) 'real-tree extractor finds invocation and data references'
$unclassifiedScript = Test-PathClassified -Path 'scripts/unlisted.ps1'
Assert-True ($null -eq $unclassifiedScript) 'unclassified script invocation fails classification'
$unclassifiedData = Test-PathClassified -Path '.github/pr-quality-gate/data/unlisted.txt'
Assert-True ($null -eq $unclassifiedData) 'unclassified checker data fails classification'
$contained = Resolve-RepoPath -SourcePath 'scripts/checker.ps1' -Literal 'child.ps1'
Assert-False $contained.Escapes 'native platform separator preserves contained paths'
Assert-Equal 'scripts/child.ps1' $contained.Path 'contained path uses portable repository separators'
$siblingEscape = Resolve-RepoPath -SourcePath 'scripts/checker.ps1' -Literal ('../../' + (Split-Path -Leaf $repoRoot) + 'Other/child.ps1')
Assert-True $siblingEscape.Escapes 'repository name prefix does not permit a sibling directory'
$escape = Resolve-RepoPath -SourcePath '.githooks/pre-commit' -Literal '../../scripts/x.sh'
Assert-True $escape.Escapes 'source ../../scripts/x.sh escaping the repository is refused'
$hookInvocation = @(Get-LiteralReferences -RelPath '.githooks/pre-commit' -Lines @('./scripts/unlisted.ps1'))
$hookResolution = Resolve-RepoPath -SourcePath '.githooks/pre-commit' -Literal $hookInvocation[0].Literal -RepoRelative:$hookInvocation[0].RepoRelative
Assert-Equal 'scripts/unlisted.ps1' $hookResolution.Path 'hook invocation resolves from repository root'
Assert-True ($null -eq (Test-PathClassified -Path $hookResolution.Path)) 'unclassified hook invocation fails the inventory'
$hereResolved = Resolve-RepoPath -SourcePath 'scripts/checker.ps1' -Literal '../scripts/x.sh'
Assert-Equal 'scripts/x.sh' $hereResolved.Path '$here-anchored relative path resolves from source directory'
$directoryLiteral = @(Get-LiteralReferences -RelPath 'scripts/checker.ps1' -Lines @("`$path = '.github/pr-quality-gate'", "`$path = '.github'", "`$path = '.github/pr-quality-gate/pattern-catalog.sources'"))
Assert-Equal 0 $directoryLiteral.Count 'directory anchor literals are skipped before extension matching'
$newFileLiteral = @(Get-LiteralReferences -RelPath 'scripts/checker.ps1' -Lines @("`$path = '.github/pr-quality-gate/new.txt'"))
Assert-True ($newFileLiteral.Count -gt 0) 'unclassified file literal is extracted'
$newFileResolution = Resolve-RepoPath -SourcePath 'scripts/checker.ps1' -Literal $newFileLiteral[0].Literal -RepoRelative:$newFileLiteral[0].RepoRelative
Assert-True ($null -eq (Test-PathClassified -Path $newFileResolution.Path)) 'unclassified checker data fails the inventory'
Write-Host "guarded-paths: OK - $($results.Count) extracted references; no unclassified paths; sets are disjoint."


$dataRefs = @(Get-LiteralReferences -RelPath 'scripts/checker.ps1' -Lines @("Get-Content (Join-Path `$PSScriptRoot '../.github/pr-quality-gate/data/unlisted.txt')", "Import-Csv (Join-Path `$PSScriptRoot '../.github/pr-quality-gate/data/unlisted.csv')"))
Assert-Equal 2 $dataRefs.Count 'Join-Path data inputs are extracted without invocation operators'
$variableRefs = @(Get-LiteralReferences -RelPath 'scripts/checker.ps1' -Lines @(' $here = Split-Path -Parent $PSScriptRoot', "Get-Content (Join-Path `$here '.github/pr-quality-gate/data/unlisted.txt')"))
Assert-Equal '../.github/pr-quality-gate/data/unlisted.txt' $variableRefs[0].Literal 'script-relative directory variables resolve to their value'
try {
    $inventoryRepo = New-TestGitRepository -Prefix 'guarded-inventory'
    New-Item -ItemType Directory -Path (Join-Path $inventoryRepo '.githooks') | Out-Null
    Set-Content -LiteralPath (Join-Path $inventoryRepo '.githooks/pre-commit') -Value './scripts/unlisted.ps1'
    & git -C $inventoryRepo add .githooks/pre-commit
    $inventoryOutput = @(& pwsh -NoProfile -File $PSCommandPath -RepositoryRoot $inventoryRepo -InventoryOnly 2>&1)
    Assert-True ($LASTEXITCODE -eq 1 -and ($inventoryOutput -join ' ') -match 'unclassified path: scripts/unlisted.ps1') 'real hook inventory fails on unclassified script reference'
} finally { Remove-TestTempDirectories }
Complete-TestRun
