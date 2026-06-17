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
    $normalizedPath = $FilePath -replace '\\', '/'
    if ($normalizedPath -cmatch '^\.github/pr-quality-gate/pattern-catalog\.md$' -or
        $normalizedPath -cmatch '^\.github/pr-quality-gate/pattern-catalog\.sources/[^/]*\.md$') { return $false }
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

function Get-CommentBlockSha {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $AddedCommentLines)
    $norm = @($AddedCommentLines | ForEach-Object { ([string]$_).Trim() })
    $joined = ($norm -join "`n")
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($joined)
        return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '')
    } finally {
        $sha.Dispose()
    }
}

function Get-NewCommentLineSites {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $DiffLines)
    $sites = New-Object System.Collections.Generic.List[object]
    $currentFile = $null
    $currentNewLine = 0
    $inHunk = $false
    foreach ($line in $DiffLines) {
        if ($line -cmatch '^diff\s+--git') {
            $currentFile = $null
            $currentNewLine = 0
            $inHunk = $false
            continue
        }
        if ($line -cmatch '^@@\s+-\d+(?:,\d+)?\s+\+(\d+)(?:,\d+)?\s+@@') {
            $currentNewLine = [int]$matches[1]
            $inHunk = $true
            continue
        }
        if (-not $inHunk) {
            if ($line -cmatch '^\+\+\+\s+b/(.+)$') {
                $currentFile = $matches[1]
                $currentNewLine = 0
            }
            continue
        }
        if (-not $currentFile) { continue }
        if ($line -cmatch '^\+') {
            $content = if ($line.Length -gt 1) { $line.Substring(1) } else { '' }
            if (Test-IsNewCommentLine -Content $content -FilePath $currentFile) {
                $sites.Add([PSCustomObject]@{ File = $currentFile; Line = $currentNewLine; Content = $content })
            }
            $currentNewLine++
        } elseif ($line -cmatch '^ ') {
            $currentNewLine++
        }
    }
    return $sites.ToArray()
}

function Get-NewCommentSites {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $DiffLines)
    $lineSites = @(Get-NewCommentLineSites -DiffLines $DiffLines)
    $blocks = New-Object System.Collections.Generic.List[object]
    $curFile = $null
    $curStart = 0
    $curEnd = 0
    $curLines = $null
    foreach ($site in $lineSites) {
        if ($null -ne $curLines -and $site.File -eq $curFile -and $site.Line -eq ($curEnd + 1)) {
            $curLines.Add($site.Content)
            $curEnd = $site.Line
        } else {
            if ($null -ne $curLines) {
                $blocks.Add((New-CommentBlock -File $curFile -StartLine $curStart -EndLine $curEnd -Lines $curLines.ToArray()))
            }
            $curFile = $site.File
            $curStart = $site.Line
            $curEnd = $site.Line
            $curLines = New-Object System.Collections.Generic.List[string]
            $curLines.Add($site.Content)
        }
    }
    if ($null -ne $curLines) {
        $blocks.Add((New-CommentBlock -File $curFile -StartLine $curStart -EndLine $curEnd -Lines $curLines.ToArray()))
    }
    return , $blocks.ToArray()
}

function New-CommentBlock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $File,
        [Parameter(Mandatory)] [int] $StartLine,
        [Parameter(Mandatory)] [int] $EndLine,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $Lines
    )
    return [PSCustomObject]@{
        File = $File
        StartLine = $StartLine
        EndLine = $EndLine
        Text = (($Lines | ForEach-Object { ([string]$_).Trim() }) -join "`n")
        Sha = (Get-CommentBlockSha -AddedCommentLines $Lines)
    }
}

function Get-NewCommentCount {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $DiffLines)
    return (Get-NewCommentSites -DiffLines $DiffLines).Count
}

function Get-UnparseableDiffPaths {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $DiffLines)
    $unparseable = New-Object System.Collections.Generic.List[string]
    $inHunk = $false
    foreach ($line in $DiffLines) {
        if ($line -cmatch '^diff\s+--git') { $inHunk = $false; continue }
        if ($line -cmatch '^@@\s+-\d+(?:,\d+)?\s+\+\d+(?:,\d+)?\s+@@') { $inHunk = $true; continue }
        if (-not $inHunk -and $line -cmatch '^\+\+\+\s+"') {
            $unparseable.Add(([string]$line).Trim())
        }
    }
    return $unparseable.ToArray()
}

function Test-AuditBulletShape {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $BulletLine)
    if ($BulletLine -cnotmatch '^\s*-\s+\S') { return $null }
    $exemptCatPattern = ($script:CanonicalExemptCategories | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $allowedCasePattern = ($script:CanonicalAllowedCases | ForEach-Object { [regex]::Escape($_) }) -join '|'
    if ($BulletLine -cnotmatch '^\s*-\s+(?<file>.+?):(?<line>\d+):\s*(?<rest>(?:approval_turn|deleted)\b.*)$') {
        return [PSCustomObject]@{ Form = 'unknown'; Valid = $false; File = $null; Line = $null; Reason = 'bullet missing a structural <file>:<line>: <approval_turn|deleted> prefix' }
    }
    $file = $matches['file']
    $line = [int]$matches['line']
    $rest = $matches['rest']
    if ($rest -cmatch '^deleted\s*\(') {
        return [PSCustomObject]@{ Form = 'deleted'; Valid = $true; File = $file; Line = $line }
    }
    if ($rest -cmatch "^approval_turn:\s*n/a\s+[-\u2014]\s+exempt:\s*($exemptCatPattern)\s*$") {
        return [PSCustomObject]@{ Form = 'exempt'; Valid = $true; File = $file; Line = $line; Category = $matches[1] }
    }
    if ($rest -cmatch "^approval_turn:\s*n/a\s+[-\u2014]\s+degraded-mode-drop\s*$") {
        return [PSCustomObject]@{ Form = 'degraded-mode-drop'; Valid = $true; File = $file; Line = $line }
    }
    if ($rest -cmatch "^approval_turn:\s*n/a\s+[-\u2014]\s+no-response-drop\s*$") {
        return [PSCustomObject]@{ Form = 'no-response-drop'; Valid = $true; File = $file; Line = $line }
    }
    if ($rest -cmatch "^approval_turn:\s*n/a\s+[-\u2014]\s+(?<prefix>exempt:\s*)?(?<token>\S+)(?<trail>.*)$") {
        $token = $matches['token']
        $trail = $matches['trail'].Trim()
        if ($matches['prefix']) {
            if ($token -cin $script:CanonicalExemptCategories) {
                $reason = "canonical exempt category has unexpected trailing content: $trail"
            } else {
                $reason = "non-canonical exempt category: $token"
            }
        } else {
            if ($token -cin @('degraded-mode-drop', 'no-response-drop')) {
                $reason = "canonical n/a disposition has unexpected trailing content: $trail"
            } else {
                $reason = "unknown n/a disposition: $token"
            }
        }
        return [PSCustomObject]@{ Form = 'na-other'; Valid = $false; File = $file; Line = $line; Reason = $reason }
    }
    if ($rest -cmatch "^approval_turn:\s*\S.*\|\s*allowed-case:\s*($allowedCasePattern)\s*\|\s*justification:\s*\S") {
        $allowedCase = $matches[1]
        if ($rest -cmatch '\|\s*comment_sha:\s*<') {
            return [PSCustomObject]@{ Form = 'approved'; Valid = $false; File = $file; Line = $line; Reason = 'comment_sha is an unsubstituted placeholder' }
        }
        if ($rest -cmatch '\|\s*comment_sha:\s*([0-9a-f]{64})\b') {
            return [PSCustomObject]@{ Form = 'approved'; Valid = $true; File = $file; Line = $line; AllowedCase = $allowedCase; Sha = $matches[1] }
        }
        return [PSCustomObject]@{ Form = 'approved'; Valid = $false; File = $file; Line = $line; Reason = 'approved bullet missing comment_sha:<64-hex>' }
    }
    if ($rest -cmatch "^approval_turn:\s*\S") {
        return [PSCustomObject]@{ Form = 'approved'; Valid = $false; File = $file; Line = $line; Reason = 'approval_turn ref present but missing/non-canonical allowed-case OR justification OR comment_sha' }
    }
    return [PSCustomObject]@{ Form = 'unknown'; Valid = $false; File = $file; Line = $line; Reason = 'no recognizable approval_turn or deleted form' }
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
        Bullets = @()
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
    if ($parentShaLine -cmatch '^parent_sha:\s*([a-fA-F0-9]{40})\s*$') {
        $result.ParentSha = $matches[1]
        if ($ExpectedParentSha -eq $script:GitEmptyTreeSha) {
            $result.Errors += "audit declares hex parent_sha '$($result.ParentSha)' but expected root-commit empty-tree sentinel"
            $result.Valid = $false
        } elseif (-not $ExpectedParentSha.Equals($result.ParentSha, [System.StringComparison]::OrdinalIgnoreCase)) {
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
        $result.Errors += "audit parent_sha value is invalid (must be a full 40-char hex SHA, NONE, or EMPTY_TREE): $parentShaLine"
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
        $result.Bullets += $shape
    }
    return $result
}

function Test-CommentCoverage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Sites,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Bullets
    )
    $errors = New-Object System.Collections.Generic.List[string]
    $cover = @($Bullets | Where-Object { $_.Valid -and ($_.Form -eq 'approved' -or $_.Form -eq 'exempt') })
    $byKey = @{}
    foreach ($bullet in $cover) {
        $key = "$($bullet.File):$($bullet.Line)"
        if ($byKey.ContainsKey($key)) {
            $errors.Add("ambiguous coverage: more than one approved/exempt bullet at $key")
        } else {
            $byKey[$key] = $bullet
        }
    }
    $siteKeys = @{}
    foreach ($site in $Sites) {
        $key = "$($site.File):$($site.StartLine)"
        $siteKeys[$key] = $true
        if (-not $byKey.ContainsKey($key)) {
            $errors.Add("uncovered new-comment site $key (no approved/exempt audit bullet for this block)")
        } elseif ($byKey[$key].Form -eq 'approved' -and $byKey[$key].Sha -cne $site.Sha) {
            $errors.Add("comment_sha mismatch at $key (the audited text differs from the committed comment)")
        }
    }
    foreach ($bullet in $cover) {
        $key = "$($bullet.File):$($bullet.Line)"
        if (-not $siteKeys.ContainsKey($key)) {
            $errors.Add("orphan audit bullet at $key (no detected new-comment block begins there)")
        }
    }
    return $errors.ToArray()
}

function Get-CoveredCommentCount {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [PSObject] $AuditResult)
    return $AuditResult.ApprovedCount + $AuditResult.ExemptCount
}

Export-ModuleMember -Function Get-CommentTokensForFile, Test-IsNewCommentLine, Get-CommentBlockSha, Get-NewCommentLineSites, Get-NewCommentSites, Get-NewCommentCount, Get-UnparseableDiffPaths, Test-AuditBulletShape, Test-AuditFile, Test-CommentCoverage, Get-CoveredCommentCount -Variable CanonicalExemptCategories, CanonicalAllowedCases, GitEmptyTreeSha
