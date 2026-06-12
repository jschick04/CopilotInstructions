$script:ExtensionPatterns = @{
    'cs'       = @('//', '/\*', '\*', '///')
    'cshtml'   = @('//', '/\*', '\*', '///', '@\*', '<!--')
    'razor'    = @('//', '/\*', '\*', '///', '@\*', '<!--')
    'csx'      = @('//', '/\*', '\*', '///')
    'fs'       = @('//', '/\*', '\*', '///')
    'fsx'      = @('//', '/\*', '\*', '///')
    'java'     = @('//', '/\*', '\*')
    'kt'       = @('//', '/\*', '\*')
    'scala'    = @('//', '/\*', '\*')
    'groovy'   = @('//', '/\*', '\*')
    'c'        = @('//', '/\*', '\*')
    'cpp'      = @('//', '/\*', '\*')
    'h'        = @('//', '/\*', '\*')
    'hpp'      = @('//', '/\*', '\*')
    'cc'       = @('//', '/\*', '\*')
    'cxx'      = @('//', '/\*', '\*')
    'ts'       = @('//', '/\*', '\*')
    'tsx'      = @('//', '/\*', '\*')
    'mts'      = @('//', '/\*', '\*')
    'cts'      = @('//', '/\*', '\*')
    'js'       = @('//', '/\*', '\*')
    'jsx'      = @('//', '/\*', '\*')
    'mjs'      = @('//', '/\*', '\*')
    'cjs'      = @('//', '/\*', '\*')
    'go'       = @('//', '/\*', '\*')
    'rs'       = @('//', '/\*', '\*', '///', '//!')
    'swift'    = @('//', '/\*', '\*')
    'dart'     = @('//', '/\*', '\*', '///')
    'bicep'    = @('//', '/\*', '\*')
    'py'       = @('#', '"""')
    'rb'       = @('#')
    'ex'       = @('#', '@moduledoc', '@doc', '@typedoc')
    'exs'      = @('#', '@moduledoc', '@doc', '@typedoc')
    'sh'       = @('#')
    'bash'     = @('#')
    'zsh'      = @('#')
    'fish'     = @('#')
    'ps1'      = @('#', '<#')
    'psm1'     = @('#', '<#')
    'psd1'     = @('#')
    'yml'      = @('#')
    'yaml'     = @('#')
    'toml'     = @('#')
    'tf'       = @('#', '//', '/\*', '\*')
    'hcl'      = @('#', '//', '/\*', '\*')
    'sql'      = @('--', '/\*', '\*')
    'lua'      = @('--')
    'hs'       = @('--')
    'elm'      = @('--')
    'adb'      = @('--')
    'ads'      = @('--')
    'lisp'     = @(';')
    'clj'      = @(';')
    'cljs'     = @(';')
    'edn'      = @(';')
    'ini'      = @(';', '#')
    'css'      = @('/\*', '\*')
    'scss'     = @('//', '/\*', '\*')
    'sass'     = @('//', '/\*', '\*')
    'less'     = @('//', '/\*', '\*')
    'html'     = @('<!--')
    'htm'      = @('<!--')
    'xml'      = @('<!--')
    'svg'      = @('<!--')
    'md'       = @('<!--')
    'markdown' = @('<!--')
}

$script:ExtensionlessBasenames = @{
    'Dockerfile'      = @('#')
    'Containerfile'   = @('#')
    'Makefile'        = @('#')
    'Rakefile'        = @('#')
    'Gemfile'         = @('#')
    'CMakeLists.txt'  = @('#')
    'BUILD'           = @('#')
    'BUILD.bazel'     = @('#')
}

$script:CanonicalExemptCategories = @(
    'typo',
    'deletion',
    'stale-comment-fix-per-§3.9/§3.10',
    'generated',
    'vendored',
    'THROWAWAY-header'
)

$script:CanonicalAllowedCases = @(
    'non-obvious invariant',
    'external constraint',
    'trade-off'
)

$script:GitEmptyTreeSha = '4b825dc642cb6eb9a060e54bf8d69288fbee4904'

function Get-CommentTokensForFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $FilePath)
    $extension = [System.IO.Path]::GetExtension($FilePath).TrimStart('.').ToLowerInvariant()
    if ($script:ExtensionPatterns.ContainsKey($extension)) { return $script:ExtensionPatterns[$extension] }
    $basename = [System.IO.Path]::GetFileName($FilePath)
    if ($script:ExtensionlessBasenames.ContainsKey($basename)) { return $script:ExtensionlessBasenames[$basename] }
    return $null
}

function Test-IsNewCommentLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Content,
        [Parameter(Mandatory)] [string] $FilePath
    )
    $patterns = Get-CommentTokensForFile -FilePath $FilePath
    if (-not $patterns) { return $false }
    $extension = [System.IO.Path]::GetExtension($FilePath).TrimStart('.').ToLowerInvariant()
    $trimmed = $Content -replace '^\s+', ''
    if ($extension -in @('md','markdown') -and $trimmed -cmatch '^<!--\s*read-receipt-token:\s*[0-9a-f]{8}\s*-->\s*$') { return $false }
    foreach ($pattern in $patterns) {
        if ($trimmed -cmatch "^$pattern") {
            if ($pattern -eq '#' -and $extension -in @('c','cpp','h','hpp','cc','cxx')) { return $false }
            if ($pattern -eq '#' -and $extension -in @('ps1','psm1') -and $trimmed -cmatch '^#(region|endregion)\b') { return $false }
            if ($pattern -eq '#' -and $extension -in @('ps1','psm1') -and $trimmed -cmatch '^#Requires\s+-') { return $false }
            if ($pattern -eq '#' -and $extension -in @('cs','cshtml','razor','csx','fs','fsx') -and $trimmed -cmatch '^#(region|endregion|pragma|if|else|elif|endif|define|undef|warning|error|line|nullable|load|r|time|help|quit)\b') { return $false }
            if ($pattern -eq '#' -and $extension -in @('sh','bash','zsh','fish','py','rb','ex','exs') -and $trimmed -cmatch '^#!/') { return $false }
            return $true
        }
    }
    $lineStartOnlyPatterns = @('\*', '"""', '@\*', '@moduledoc', '@doc', '@typedoc')
    $blockOpenPatterns = @('/\*', '<!--', '<#')
    foreach ($pattern in $patterns) {
        if ($pattern -in $lineStartOnlyPatterns) { continue }
        if ($pattern -in $blockOpenPatterns) {
            if ($Content -cmatch "\S+\s*($pattern)") { return $true }
        } else {
            if ($Content -cmatch "\S+\s+($pattern)(\s|$)") { return $true }
        }
    }
    return $false
}

function Get-NewCommentSites {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string[]] $DiffLines)
    $sites = @()
    $currentFile = $null
    $currentNewLine = 0
    foreach ($line in $DiffLines) {
        if ($line -cmatch '^\+\+\+\s+b/(.+)$') {
            $currentFile = $matches[1]
            $currentNewLine = 0
            continue
        }
        if ($line -cmatch '^---\s+' -or $line -cmatch '^diff\s+--git') {
            $currentFile = $null
            $currentNewLine = 0
            continue
        }
        if ($line -cmatch '^@@\s+-\d+(?:,\d+)?\s+\+(\d+)(?:,\d+)?\s+@@') {
            $currentNewLine = [int]$matches[1]
            continue
        }
        if (-not $currentFile) { continue }
        if ($line -cmatch '^\+[^+]' -or $line -eq '+') {
            $content = if ($line.Length -gt 1) { $line.Substring(1) } else { '' }
            if (Test-IsNewCommentLine -Content $content -FilePath $currentFile) {
                $sites += [PSCustomObject]@{ File = $currentFile; Line = $currentNewLine }
            }
            $currentNewLine++
        } elseif ($line -cmatch '^[^-+\\]' -and -not ($line -cmatch '^@@')) {
            $currentNewLine++
        }
    }
    return ,$sites
}

function Get-NewCommentCount {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string[]] $DiffLines)
    return (Get-NewCommentSites -DiffLines $DiffLines).Count
}

function Test-AuditBulletShape {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $BulletLine)
    if ($BulletLine -cnotmatch '^\s*-\s+\S') { return $null }
    $exemptCatPattern = ($script:CanonicalExemptCategories | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $allowedCasePattern = ($script:CanonicalAllowedCases | ForEach-Object { [regex]::Escape($_) }) -join '|'
    if ($BulletLine -cmatch "^\s*-\s+\S.*?:\s*deleted\s*\(") {
        return [PSCustomObject]@{ Form = 'deleted'; Valid = $true }
    }
    if ($BulletLine -cmatch "^\s*-\s+\S.*?:\s*approval_turn:\s*n/a\s+—\s+exempt:\s*($exemptCatPattern)\s*$") {
        return [PSCustomObject]@{ Form = 'exempt'; Valid = $true; Category = $matches[1] }
    }
    if ($BulletLine -cmatch "^\s*-\s+\S.*?:\s*approval_turn:\s*n/a\s+—\s+exempt:\s*(\S+)") {
        return [PSCustomObject]@{ Form = 'exempt'; Valid = $false; Reason = "non-canonical exempt category: $($matches[1])" }
    }
    if ($BulletLine -cmatch "^\s*-\s+\S.*?:\s*approval_turn:\s*n/a\s+—\s+degraded-mode-drop\s*$") {
        return [PSCustomObject]@{ Form = 'degraded-mode-drop'; Valid = $true }
    }
    if ($BulletLine -cmatch "^\s*-\s+\S.*?:\s*approval_turn:\s*n/a\s+—\s+no-response-drop\s*$") {
        return [PSCustomObject]@{ Form = 'no-response-drop'; Valid = $true }
    }
    if ($BulletLine -cmatch "^\s*-\s+\S.*?:\s*approval_turn:\s*n/a\s+—\s+(\S+)") {
        return [PSCustomObject]@{ Form = 'na-other'; Valid = $false; Reason = "unknown n/a disposition: $($matches[1])" }
    }
    if ($BulletLine -cmatch "^\s*-\s+\S.*?:\s*approval_turn:\s*\S.+?\|\s*allowed-case:\s*($allowedCasePattern)\s*\|\s*justification:\s*\S") {
        return [PSCustomObject]@{ Form = 'approved'; Valid = $true; AllowedCase = $matches[1] }
    }
    if ($BulletLine -cmatch "^\s*-\s+\S.*?:\s*approval_turn:\s*\S") {
        return [PSCustomObject]@{ Form = 'approved'; Valid = $false; Reason = 'approval_turn ref present but missing or non-canonical allowed-case OR missing justification' }
    }
    return [PSCustomObject]@{ Form = 'unknown'; Valid = $false; Reason = 'no recognizable approval_turn or deleted form' }
}

function Test-AuditFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $AuditLines,
        [Parameter(Mandatory)] [string] $ExpectedParentSha
    )
    $result = [PSCustomObject]@{
        Valid = $true
        Errors = @()
        ParentSha = $null
        ApprovedCount = 0
        ExemptCount = 0
        DegradedCount = 0
        NoResponseCount = 0
        DeletedCount = 0
        InvalidBullets = @()
    }
    $parentShaLine = $AuditLines | Where-Object { $_ -cmatch '^parent_sha:\s*(.+?)\s*$' } | Select-Object -First 1
    if (-not $parentShaLine) {
        $result.Valid = $false
        $result.Errors += "missing required 'parent_sha:' header"
        return $result
    }
    $commitSubjectLine = $AuditLines | Where-Object { $_ -cmatch '^commit_subject:\s*(.+?)\s*$' } | Select-Object -First 1
    if (-not $commitSubjectLine) {
        $result.Valid = $false
        $result.Errors += "missing required 'commit_subject:' header"
        return $result
    }
    if ($commitSubjectLine -cmatch '^commit_subject:\s*<') {
        $result.Valid = $false
        $result.Errors += "audit file has unsubstituted template placeholder for commit_subject (line: $commitSubjectLine)"
        return $result
    }
    if ($parentShaLine -cmatch '^parent_sha:\s*<') {
        $result.Valid = $false
        $result.Errors += "audit file has unsubstituted template placeholder for parent_sha (line: $parentShaLine)"
        return $result
    }
    if ($parentShaLine -cmatch '^parent_sha:\s*([a-fA-F0-9]{7,40})\s*$') {
        $result.ParentSha = $matches[1]
        if ($ExpectedParentSha -eq $script:GitEmptyTreeSha) {
            $result.Errors += "audit declares hex parent_sha '$($result.ParentSha)' but expected root-commit empty-tree sentinel"
            $result.Valid = $false
        } elseif ($ExpectedParentSha -notlike "$($result.ParentSha)*" -and $result.ParentSha -notlike "$ExpectedParentSha*") {
            $result.Valid = $false
            $result.Errors += "audit parent_sha '$($result.ParentSha)' does not match expected '$ExpectedParentSha' (stale audit file)"
        }
    } elseif ($parentShaLine -cmatch '^parent_sha:\s*(NONE|EMPTY_TREE)\s*$') {
        if ($ExpectedParentSha -ne $script:GitEmptyTreeSha) {
            $result.Valid = $false
            $result.Errors += "audit declares root-commit placeholder '$($matches[1])' but commit has a real parent '$ExpectedParentSha'"
        } else {
            $result.ParentSha = $matches[1]
        }
    } else {
        $result.Valid = $false
        $result.Errors += "audit parent_sha value is invalid (must be ≥7-char hex SHA, NONE, or EMPTY_TREE): $parentShaLine"
        return $result
    }
    foreach ($line in $AuditLines) {
        if ($line -cnotmatch '^\s*-\s+\S') { continue }
        $shape = Test-AuditBulletShape -BulletLine $line
        if (-not $shape) { continue }
        if (-not $shape.Valid) {
            $result.Valid = $false
            $result.InvalidBullets += [PSCustomObject]@{ Line = $line.Trim(); Reason = $shape.Reason }
            continue
        }
        switch ($shape.Form) {
            'approved' { $result.ApprovedCount++ }
            'exempt' { $result.ExemptCount++ }
            'degraded-mode-drop' { $result.DegradedCount++ }
            'no-response-drop' { $result.NoResponseCount++ }
            'deleted' { $result.DeletedCount++ }
        }
    }
    return $result
}

function Get-CoveredCommentCount {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [PSObject] $AuditResult)
    return $AuditResult.ApprovedCount + $AuditResult.ExemptCount
}

Export-ModuleMember -Function Get-CommentTokensForFile, Test-IsNewCommentLine, Get-NewCommentSites, Get-NewCommentCount, Test-AuditBulletShape, Test-AuditFile, Get-CoveredCommentCount -Variable CanonicalExemptCategories, CanonicalAllowedCases, GitEmptyTreeSha
