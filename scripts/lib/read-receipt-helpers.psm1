#Requires -Version 5.1
# Shared logic for the code-topic read-receipt gate, imported by check-read-receipts.ps1 (staged,
# pre-commit) and check-audit-notes-prepush.ps1 (history, pre-push) so gated-set resolution + glob
# matching + token extraction never drift between the two. GATED SET = every
# .github/instructions/*.instructions.md whose applyTo is a NON-**/* (code-specific) glob: the 15
# language topic files + coding-standards-code; the universal **/* file is excluded. applyTo may use
# brace alternation - git wildmatch does NOT brace-expand, so Expand-Brace does it (else
# coding-standards-code's .py/.go/.rs linchpin matches nothing). A gated file MUST carry a valid
# [0-9a-f]{8} token (tokenless = fail-closed). Honest ceiling: forces a current-token citation on the
# commit; does NOT prove the file was read.
Set-StrictMode -Version Latest

$script:TokenRegex   = '<!--\s*read-receipt-token:\s*([0-9a-f]{8})\s*-->'
$script:ReadsLineRx  = '^\s*reads=(?<file>.+?)@(?<token>[0-9a-f]{8})\s*$'
$script:InstrGlob    = '.github/instructions/*.instructions.md'

function Split-ApplyToTopLevel {
    param([Parameter(Mandatory)][string] $Value)
    $parts = New-Object System.Collections.Generic.List[string]
    $depth = 0
    $cur = ''
    foreach ($ch in $Value.ToCharArray()) {
        switch ($ch) {
            '{' { $depth++; $cur += $ch }
            '}' { $depth--; if ($depth -lt 0) { throw "Split-ApplyToTopLevel: unbalanced '}' in applyTo: $Value" }; $cur += $ch }
            ',' { if ($depth -eq 0) { [void]$parts.Add($cur); $cur = '' } else { $cur += $ch } }
            default { $cur += $ch }
        }
    }
    if ($depth -ne 0) { throw "Split-ApplyToTopLevel: unbalanced '{' in applyTo: $Value" }
    [void]$parts.Add($cur)
    return $parts.ToArray()
}

function Expand-Brace {
    param([Parameter(Mandatory)][string] $Pattern)
    $m = [regex]::Match($Pattern, '\{([^{}]*)\}')
    if (-not $m.Success) { return ,@($Pattern) }
    $pre  = $Pattern.Substring(0, $m.Index)
    $post = $Pattern.Substring($m.Index + $m.Length)
    $alts = $m.Groups[1].Value -split ','
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($alt in $alts) {
        $alt = $alt.Trim()
        if ($alt -eq '') { throw "Expand-Brace: empty alternation in pattern: $Pattern" }
        foreach ($expanded in (Expand-Brace ($pre + $alt + $post))) { [void]$out.Add($expanded) }
    }
    return $out.ToArray()
}

function Expand-ApplyToPatterns {
    param([Parameter(Mandatory)][string] $ApplyTo)
    $val = $ApplyTo.Trim()
    if ($val.StartsWith('"') -and $val.EndsWith('"')) { $val = $val.Substring(1, $val.Length - 2) }
    elseif ($val.StartsWith("'") -and $val.EndsWith("'")) { $val = $val.Substring(1, $val.Length - 2) }
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($tok in (Split-ApplyToTopLevel $val)) {
        $t = $tok.Trim()
        if ($t -eq '') { continue }
        foreach ($p in (Expand-Brace $t)) { if ($p.Trim() -ne '') { [void]$out.Add($p.Trim()) } }
    }
    return ($out | Select-Object -Unique)
}

function Get-ApplyToFromContent {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Content)
    $m = [regex]::Match($Content, '(?m)^\s*applyTo:\s*(.+?)\s*$')
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return ''
}

function Get-TokenFromContent {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Content)
    $m = [regex]::Match($Content, $script:TokenRegex)
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

function Resolve-TopicGate {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][AllowEmptyString()][string] $Content
    )
    $applyTo = Get-ApplyToFromContent -Content $Content
    if ([string]::IsNullOrWhiteSpace($applyTo)) {
        return [pscustomobject]@{ Path = $Path; Kind = 'absent'; Patterns = @(); Token = $null }
    }
    if ($applyTo.Trim('"', "'", ' ') -eq '**/*') {
        return [pscustomobject]@{ Path = $Path; Kind = 'universal'; Patterns = @(); Token = $null }
    }
    return [pscustomobject]@{
        Path     = $Path
        Kind     = 'gate'
        Patterns = @(Expand-ApplyToPatterns -ApplyTo $applyTo)
        Token    = Get-TokenFromContent -Content $Content
    }
}

function Get-GatedTopicsFromBlobs {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $Paths,
        [Parameter(Mandatory)][scriptblock] $ReadBlob
    )
    $result = New-Object System.Collections.Generic.List[object]
    foreach ($p in $Paths) {
        $rel = ([string]$p).TrimEnd("`r").Trim()
        if ($rel -notmatch '^\.github/instructions/[^/]+\.instructions\.md$') { continue }
        $content = [string](& $ReadBlob $rel)
        $result.Add((Resolve-TopicGate -Path $rel -Content $content))
    }
    return $result.ToArray()
}

function Get-WorktreeGatedTopicFiles {
    param([Parameter(Mandatory)][string] $RepoRoot)
    $dir = Join-Path $RepoRoot '.github/instructions'
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    $result = New-Object System.Collections.Generic.List[object]
    foreach ($f in (Get-ChildItem -LiteralPath $dir -Filter '*.instructions.md' -File | Sort-Object Name)) {
        $content = [string](Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8)
        $rel = '.github/instructions/' + $f.Name
        $classification = Resolve-TopicGate -Path $rel -Content $content
        if ($classification.Kind -ne 'gate') { continue }
        $result.Add([pscustomobject]@{
            Path     = $classification.Path
            Patterns = $classification.Patterns
            Token    = $classification.Token
        })
    }
    return $result.ToArray()
}

function Get-MatchedGatedFiles {
    param(
        [Parameter(Mandatory)][object[]] $GatedSet,
        [Parameter(Mandatory)][string[]] $DiffArgs,
        [Parameter(Mandatory)][scriptblock] $GitInvoke
    )
    $matched = New-Object System.Collections.Generic.List[object]
    foreach ($gf in $GatedSet) {
        $pathspecs = @($gf.Patterns | ForEach-Object { ":(glob,icase)$_" })
        $gitArgs = @('-c', 'core.quotePath=false') + $DiffArgs + @('--') + $pathspecs
        $out = & $GitInvoke $gitArgs
        $hit = @($out | ForEach-Object { ([string]$_).TrimEnd("`r") } | Where-Object { $_.Trim() -ne '' })
        if ($hit.Count -gt 0) { $matched.Add($gf) }
    }
    return $matched.ToArray()
}

function Read-ReadsReceipt {
    param([Parameter(Mandatory)][string[]] $Lines)
    $parent = $null
    $reads = @{}
    foreach ($line in $Lines) {
        $l = ([string]$line).TrimEnd("`r")
        $pm = [regex]::Match($l, '^\s*parent_sha:\s*([a-fA-F0-9]{7,40})\s*$')
        if ($pm.Success) { $parent = $pm.Groups[1].Value; continue }
        $rm = [regex]::Match($l, $script:ReadsLineRx)
        if ($rm.Success) { $reads[$rm.Groups['file'].Value.Trim()] = $rm.Groups['token'].Value }
    }
    return @{ ParentSha = $parent; Reads = $reads }
}

function ConvertFrom-ReadsLine {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Line)
    $l = ([string]$Line).TrimEnd("`r")
    $m = [regex]::Match($l, $script:ReadsLineRx)
    if ($m.Success) {
        $file = $m.Groups['file'].Value.Trim()
        if ($file) {
            return [pscustomobject]@{ IsReadsLine = $true; Ok = $true; File = $file; Token = $m.Groups['token'].Value }
        }
    }
    return [pscustomobject]@{ IsReadsLine = [regex]::IsMatch($l, '^\s*reads='); Ok = $false; File = $null; Token = $null }
}

Export-ModuleMember -Function Split-ApplyToTopLevel, Expand-Brace, Expand-ApplyToPatterns,
    Get-ApplyToFromContent, Get-TokenFromContent, Resolve-TopicGate, Get-GatedTopicsFromBlobs,
    Get-WorktreeGatedTopicFiles, Get-MatchedGatedFiles, Read-ReadsReceipt, ConvertFrom-ReadsLine
