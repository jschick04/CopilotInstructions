#Requires -Version 5.1
# Pure validators for the post-code-change panel LEDGER gate. Isolated from comment-audit
# (no shared code); asserts only load-bearing §2B keys, opaque to other rows to avoid drift.

Set-StrictMode -Version Latest

$script:GitEmptyTreeSha = '4b825dc642cb6eb9a060e54bf8d69288fbee4904'

function Get-GitEmptyTreeSha { $script:GitEmptyTreeSha }

$script:PanelSlateFloor = @{
    MinReviewers  = 4
    MinClaude     = 1
    MinGpt        = 2
    MinGemini     = 1
    MinRubberDuck = 1
    MinCodeReview = 2
    MinHeavy      = 1
}
function Get-PanelSlateFloor { $script:PanelSlateFloor.Clone() }

$script:CodeExtensions = @(
    'cs','csx','ps1','psm1','psd1','sh','bash','zsh','ts','tsx','mts','cts','js','jsx','mjs','cjs',
    'cpp','h','hpp','c','cc','cxx','py','go','rs','java','kt','swift','rb','razor','cshtml','aspx',
    'css','scss','sass','less','html','htm','sql','bicep','tf',
    'csproj','props','targets','vcxproj','proj','sln'
)

$script:GovTierNone = 0
$script:GovTierPanelRequired = 1
$script:GovTierSafetyCritical = 2
$script:SafetyCriticalSegments = @(
    'auth', 'authentication', 'authorization', 'crypto', 'cryptography', 'security',
    'interop', 'pinvoke', 'native', 'payment', 'payments', 'billing', 'financial'
)

function Test-PathSafetyCriticalSegment {
    param([Parameter(Mandatory)] [string] $NormalizedPath)
    $p = $NormalizedPath
    if ($p -ceq 'AGENTS.md') { return $true }
    if ($p -like '.githooks/*') { return $true }
    if ($p -like '.github/workflows/*') { return $true }
    if ($p -like '*/panel-policy.md' -or $p -ceq '.github/pr-quality-gate/panel-policy.md') { return $true }
    $leaf = $p.Substring($p.LastIndexOf('/') + 1)
    if ($p -like 'scripts/check-*' -and $leaf -like 'check-*') { return $true }
    if ($p -like 'scripts/lib/*-helpers.psm1') { return $true }

    $segs = $p.ToLowerInvariant() -split '/'
    foreach ($seg in $segs) {
        $bare = if ($seg -match '^(.+?)\.[^.]+$') { $matches[1] } else { $seg }
        if ($script:SafetyCriticalSegments -contains $seg -or $script:SafetyCriticalSegments -contains $bare) {
            return $true
        }
    }
    return $false
}

function Get-PathGovernanceTier {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    $p = ($Path -replace '\\', '/').Trim()
    if (-not $p) { return $script:GovTierNone }
    if ($p -like '.github/pr-quality-gate/audits/*') { return $script:GovTierNone }

    $panelRequired = $false
    if ($p -ceq 'AGENTS.md') { $panelRequired = $true }
    elseif ($p -ceq 'setup.ps1' -or $p -ceq 'setup.sh') { $panelRequired = $true }
    elseif ($p -ceq '.gitattributes' -or $p -ceq '.gitignore' -or $p -ceq '.github/copilot-instructions.md') { $panelRequired = $true }
    elseif ($p -like '.github/instructions/*' -or
        $p -like '.github/playbooks/*' -or
        $p -like '.github/workflows/*' -or
        $p -like '.github/pr-quality-gate/*' -or
        $p -like '.githooks/*' -or
        $p -like 'profiles/*' -or
        $p -like 'scripts/*') { $panelRequired = $true }
    else {
        $ext = [System.IO.Path]::GetExtension($p).TrimStart('.').ToLowerInvariant()
        if ($ext -and ($script:CodeExtensions -contains $ext)) { $panelRequired = $true }
    }

    if (-not $panelRequired) { return $script:GovTierNone }
    if (Test-PathSafetyCriticalSegment -NormalizedPath $p) { return $script:GovTierSafetyCritical }
    return $script:GovTierPanelRequired
}

function Test-PathPanelRequired {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    return ((Get-PathGovernanceTier -Path $Path) -ge $script:GovTierPanelRequired)
}

function Get-ChangedGovernanceTier {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [AllowNull()] [string[]] $ChangedPaths,
        [AllowEmptyCollection()] [AllowNull()] [string[]] $NameStatusLines = @()
    )
    $maxTier = $script:GovTierNone
    foreach ($path in @($ChangedPaths)) {
        if (-not $path) { continue }
        $tier = Get-PathGovernanceTier -Path $path
        if ($tier -gt $maxTier) { $maxTier = $tier }
        if ($maxTier -ge $script:GovTierSafetyCritical) { return $maxTier }
    }
    foreach ($line in @($NameStatusLines)) {
        if (-not $line) { continue }
        if ([string]$line -cmatch '^R\d+\t([^\t]+)\t([^\t]+)$') {
            $oldPath = ($matches[1] -replace '\\', '/').Trim()
            $newPath = ($matches[2] -replace '\\', '/').Trim()
            $oldDir = if ($oldPath -match '^(.*)/[^/]+$') { $matches[1] } else { '' }
            $newDir = if ($newPath -match '^(.*)/[^/]+$') { $matches[1] } else { '' }
            $isMove = $oldDir -ne $newDir
            $touchesTest = ($oldPath -match '(^|/)tests?(/|$)' -or $newPath -match '(^|/)tests?(/|$)')
            if ($isMove -and ($touchesTest -or (Get-PathGovernanceTier -Path $newPath) -ge $script:GovTierPanelRequired -or (Get-PathGovernanceTier -Path $oldPath) -ge $script:GovTierPanelRequired)) {
                return $script:GovTierSafetyCritical
            }
        }
    }
    return $maxTier
}

function Get-PanelRequired {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $ChangedPaths)
    foreach ($path in $ChangedPaths) {
        if (-not $path) { continue }
        if (Test-PathPanelRequired -Path $path) { return $true }
    }
    return $false
}

function Test-Transcript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $LedgerLines,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $HeaderName,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $ReadyVerdict,
        [hashtable] $Floor,
        [string] $ErrorPrefix
    )
    if (@('READY', 'READY_TO_IMPLEMENT') -notcontains $ReadyVerdict) {
        throw "Test-Transcript: -ReadyVerdict must be READY or READY_TO_IMPLEMENT (got '$ReadyVerdict')"
    }
    if (-not $Floor) { $Floor = $script:PanelSlateFloor }
    if (-not $ErrorPrefix) { $ErrorPrefix = $HeaderName }

    $errors = New-Object System.Collections.Generic.List[string]
    $lines = @($LedgerLines)

    $headerRx = '^\s*' + [regex]::Escape($HeaderName) + ':\s*$'
    $headerIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if (([string]$lines[$i]) -cmatch $headerRx) { $headerIdx = $i; break }
    }
    if ($headerIdx -lt 0) {
        $errors.Add("$ErrorPrefix but no '$HeaderName`:' block is present (the multi-model slate must be recorded)")
        return $errors.ToArray()
    }

    $verdictRx = [regex]::Escape($ReadyVerdict)
    $grammar = '^\s*-\s*slot:(\S+)\s+model:(\S+)\s+family:(claude|gpt|gemini)\s+role:(rubber-duck|code-review)\s+tier:(heavy|light)\s+verdict:(' + $verdictRx + '|NEEDS_REWORK)\s+rounds:([0-9]{1,3})\s*$'
    $candidates = New-Object System.Collections.Generic.List[string]
    for ($i = $headerIdx + 1; $i -lt $lines.Count; $i++) {
        $ln = [string]$lines[$i]
        if ($ln -cmatch '^\s*[A-Za-z][\w-]*:') { break }
        if ($ln -cmatch '^\s*-\s*slot:') { $candidates.Add($ln) }
    }
    $candidates = $candidates.ToArray()
    $reviewers = New-Object System.Collections.Generic.List[object]
    foreach ($line in $candidates) {
        if ($line -cmatch $grammar) {
            $reviewers.Add([PSCustomObject]@{
                Slot = $matches[1]; Model = $matches[2]; Family = $matches[3]
                Role = $matches[4]; Tier = $matches[5]; Verdict = $matches[6]; Rounds = [int] $matches[7]
            })
        } else {
            $errors.Add("malformed $HeaderName reviewer line: '$(([string]$line).Trim())'")
        }
    }

    $reviewerArr = $reviewers.ToArray()
    if ($reviewerArr.Count -eq 0) {
        $errors.Add("$HeaderName block present but has no valid reviewer lines")
        return $errors.ToArray()
    }

    foreach ($g in @($reviewerArr | Group-Object -Property Slot | Where-Object { $_.Count -gt 1 })) {
        $errors.Add("duplicate reviewer slot '$($g.Name)' in $HeaderName (each reviewer must have a unique slot)")
    }
    foreach ($r in $reviewerArr) {
        if ($r.Verdict -cne $ReadyVerdict) {
            $errors.Add("reviewer slot '$($r.Slot)' verdict is '$($r.Verdict)', not $ReadyVerdict (panel not converged to unanimous)")
        }
        if ($r.Rounds -lt 1) {
            $errors.Add("reviewer slot '$($r.Slot)' rounds must be >= 1 (got $($r.Rounds))")
        }
    }

    $distinct = @($reviewerArr | Group-Object -Property Slot | ForEach-Object { $_.Group | Select-Object -First 1 })
    $nClaude = @($distinct | Where-Object { $_.Family -eq 'claude' }).Count
    $nGpt    = @($distinct | Where-Object { $_.Family -eq 'gpt' }).Count
    $nGemini = @($distinct | Where-Object { $_.Family -eq 'gemini' }).Count
    $nDuck   = @($distinct | Where-Object { $_.Role -eq 'rubber-duck' }).Count
    $nReview = @($distinct | Where-Object { $_.Role -eq 'code-review' }).Count
    $nHeavy  = @($distinct | Where-Object { $_.Tier -eq 'heavy' }).Count

    if ($distinct.Count -lt $Floor.MinReviewers) { $errors.Add("$HeaderName has $($distinct.Count) distinct reviewer(s); the full slate floor requires >= $($Floor.MinReviewers)") }
    if ($nClaude -lt $Floor.MinClaude)           { $errors.Add("$HeaderName has $nClaude Claude-family reviewer(s); full floor requires >= $($Floor.MinClaude)") }
    if ($nGpt -lt $Floor.MinGpt)                 { $errors.Add("$HeaderName has $nGpt GPT-family reviewer(s); full floor requires >= $($Floor.MinGpt)") }
    if ($nGemini -lt $Floor.MinGemini)           { $errors.Add("$HeaderName has $nGemini Gemini-family reviewer(s); full floor requires >= $($Floor.MinGemini)") }
    if ($nDuck -lt $Floor.MinRubberDuck)         { $errors.Add("$HeaderName has $nDuck rubber-duck reviewer(s); full floor requires >= $($Floor.MinRubberDuck)") }
    if ($nReview -lt $Floor.MinCodeReview)       { $errors.Add("$HeaderName has $nReview code-review reviewer(s); full floor requires >= $($Floor.MinCodeReview)") }
    if ($nHeavy -lt $Floor.MinHeavy)             { $errors.Add("$HeaderName has $nHeavy heavy-tier reviewer(s); full floor requires >= $($Floor.MinHeavy)") }

    return $errors.ToArray()
}

function Test-PanelTranscript {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $LedgerLines)
    return Test-Transcript -LedgerLines $LedgerLines -HeaderName 'panel-transcript' -ReadyVerdict 'READY' -ErrorPrefix "post-code-change-panel is 'ran, unanimous'"
}

function Test-PrePanelTranscript {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $LedgerLines)
    return Test-Transcript -LedgerLines $LedgerLines -HeaderName 'pre-panel-transcript' -ReadyVerdict 'READY_TO_IMPLEMENT' -ErrorPrefix "pre-code-change-panel is 'ran, unanimous'"
}

function Test-LedgerDisclosureRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $LedgerLines,
        [Parameter(Mandatory)] [string] $RowKey,
        [Parameter(Mandatory)] [string[]] $AllowedRegexes,
        [Parameter(Mandatory)] [bool] $Required
    )
    $errs = New-Object System.Collections.Generic.List[string]
    $keyRx = '^\s*' + [regex]::Escape($RowKey) + ':\s*\S'
    $line = $LedgerLines | Where-Object { $_ -cmatch $keyRx } | Select-Object -First 1
    if (-not $line) {
        if ($Required) { $errs.Add("missing required '$RowKey`:' row") }
        return $errs.ToArray()
    }
    $val = ($line -replace ('^\s*' + [regex]::Escape($RowKey) + ':\s*'), '').Trim()
    if ($val -cmatch '<[^>]*>') {
        $errs.Add("unsubstituted template placeholder for $RowKey")
        return $errs.ToArray()
    }
    $ok = $false
    foreach ($rx in $AllowedRegexes) { if ($val -cmatch $rx) { $ok = $true; break } }
    if (-not $ok) { $errs.Add("$RowKey value is not one of the allowed forms (got: '$val')") }
    return $errs.ToArray()
}

function Get-LedgerSubBlockMap {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $LedgerLines, [Parameter(Mandatory)] [string] $ParentKey)
    $lines = @($LedgerLines)
    $parentIdx = -1; $parentIndent = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if (([string]$lines[$i]) -cmatch ('^(\s*)' + [regex]::Escape($ParentKey) + ':\s*$')) {
            $parentIdx = $i; $parentIndent = $matches[1].Length; break
        }
    }
    if ($parentIdx -lt 0) { return $null }
    $map = [ordered]@{}
    for ($i = $parentIdx + 1; $i -lt $lines.Count; $i++) {
        $ln = [string]$lines[$i]
        if ($ln -match '^\s*$' -or $ln -match '^\s*#') { continue }
        $indent = ($ln -replace '^(\s*).*$', '$1').Length
        if ($indent -le $parentIndent) { break }
        if ($ln -cmatch '^\s*([\w-]+):\s*(.*?)\s*$') { $map[[string]$matches[1]] = [string]$matches[2] }
    }
    return $map
}

function Test-LedgerG6 {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $LedgerLines)
    $errs = New-Object System.Collections.Generic.List[string]
    $triggers = @('implementation-planning', 'library-restructure', 'design-exploration', 'performance-comparison', 'scope-planning', 'system-framing', 'project-vocabulary')
    $requiredClass = @('implementation-planning', 'library-restructure')
    $invokePlaybooks = @('implementation-planning', 'library-restructure', 'design-exploration', 'performance-comparison')

    $td = Get-LedgerSubBlockMap -LedgerLines $LedgerLines -ParentKey 'pre-impl-trigger-detections'
    $pd = Get-LedgerSubBlockMap -LedgerLines $LedgerLines -ParentKey 'pre-impl-playbook-decisions'
    $pv = Get-LedgerSubBlockMap -LedgerLines $LedgerLines -ParentKey 'playbook-invocations'
    if ($null -eq $td) { $errs.Add("missing required 'pre-impl-trigger-detections:' block") }
    if ($null -eq $pd) { $errs.Add("missing required 'pre-impl-playbook-decisions:' block") }
    if ($null -eq $pv) { $errs.Add("missing required 'playbook-invocations:' block") }
    if ($errs.Count -gt 0) { return $errs.ToArray() }

    foreach ($t in $triggers) {
        $tv = if ($td.Contains($t)) { [string]$td[$t] } else { $null }
        if ($null -eq $tv) { $errs.Add("pre-impl-trigger-detections missing '$t'"); continue }
        if ($tv -notmatch '^(yes|no)$') { $errs.Add("pre-impl-trigger-detections '$t' must be yes|no (got '$tv')"); continue }

        $dv = if ($pd.Contains($t)) { [string]$pd[$t] } else { $null }
        if ($null -eq $dv) { $errs.Add("pre-impl-playbook-decisions missing '$t'"); continue }
        if ($dv -cmatch '<[^>]*>') { $errs.Add("unsubstituted template placeholder in pre-impl-playbook-decisions '$t'"); continue }
        if ($requiredClass -contains $t) {
            if ($tv -eq 'yes') {
                if (-not (($dv -cmatch '^invoked$') -or ($dv -cmatch '^required-but-skipped:\s*"[^"\s][^"]*"\s*$'))) {
                    $errs.Add("pre-impl-playbook-decisions '$t' (REQUIRED class, trigger=yes) must be invoked / required-but-skipped:`"...`" (got '$dv')")
                }
            } elseif ($dv -cne 'not-required-trigger-not-detected') {
                $errs.Add("pre-impl-playbook-decisions '$t' (REQUIRED class, trigger=no) must be not-required-trigger-not-detected (got '$dv')")
            }
        } elseif ($tv -eq 'yes') {
            if (-not (($dv -cmatch '^invoked$') -or ($dv -cmatch '^offered-and-declined:\s*"[^"\s][^"]*"\s*$') -or ($dv -cmatch '^required-but-skipped:\s*"[^"\s][^"]*"\s*$'))) {
                $errs.Add("pre-impl-playbook-decisions '$t' (OFFERED, trigger=yes) must be invoked / offered-and-declined:`"...`" / required-but-skipped:`"...`" (got '$dv')")
            }
        } else {
            if ($dv -cne 'not-applicable') { $errs.Add("pre-impl-playbook-decisions '$t' (OFFERED, trigger=no) must be not-applicable (got '$dv')") }
        }
    }
    foreach ($t in $invokePlaybooks) {
        $iv = if ($pv.Contains($t)) { [string]$pv[$t] } else { $null }
        if ($null -eq $iv) { $errs.Add("playbook-invocations missing '$t'"); continue }
        if ($iv -cmatch '<[^>]*>') { $errs.Add("unsubstituted template placeholder in playbook-invocations '$t'"); continue }
        if (-not (($iv -cmatch '^ran\b') -or ($iv -cmatch '^N/A:\s*\S'))) { $errs.Add("playbook-invocations '$t' must be 'ran (...)' or 'N/A: <reason>' (got '$iv')") }
    }
    return $errs.ToArray()
}

function Test-PanelLedger {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $LedgerLines,
        [Parameter(Mandatory)] [string] $ExpectedParentSha,
        [Parameter(Mandatory)] [ValidateRange(0, 2)] [int] $GovernanceTier
    )
    $result = [PSCustomObject]@{ Valid = $true; Errors = @(); ParentSha = $null }
    $panelRequired = $GovernanceTier -ge 1
    $safetyCritical = $GovernanceTier -ge 2

    $LedgerLines = @($LedgerLines)
    if ($LedgerLines.Count -gt 0 -and $LedgerLines[0]) { $LedgerLines[0] = ([string]$LedgerLines[0]).TrimStart([char]0xFEFF) }

    $parentShaLine = $LedgerLines | Where-Object { $_ -cmatch '^parent_sha:\s*(.+?)\s*$' } | Select-Object -First 1
    if (-not $parentShaLine) {
        $result.Valid = $false; $result.Errors += "missing required 'parent_sha:' header"; return $result
    }
    $commitSubjectLine = $LedgerLines | Where-Object { $_ -cmatch '^commit_subject:\s*(.+?)\s*$' } | Select-Object -First 1
    if (-not $commitSubjectLine) {
        $result.Valid = $false; $result.Errors += "missing required 'commit_subject:' header"; return $result
    }
    if ($commitSubjectLine -cmatch '^commit_subject:\s*<') {
        $result.Valid = $false; $result.Errors += "unsubstituted template placeholder for commit_subject"; return $result
    }
    if ($parentShaLine -cmatch '^parent_sha:\s*<') {
        $result.Valid = $false; $result.Errors += "unsubstituted template placeholder for parent_sha"; return $result
    }
    if ($parentShaLine -cmatch '^parent_sha:\s*([a-fA-F0-9]{40})\s*$') {
        $result.ParentSha = $matches[1]
        if ($ExpectedParentSha -eq $script:GitEmptyTreeSha) {
            $result.Valid = $false
            $result.Errors += "ledger declares hex parent_sha '$($result.ParentSha)' but expected root-commit empty-tree sentinel"
        } elseif (-not $ExpectedParentSha.Equals($result.ParentSha, [System.StringComparison]::OrdinalIgnoreCase)) {
            $result.Valid = $false
            $result.Errors += "ledger parent_sha '$($result.ParentSha)' does not match expected '$ExpectedParentSha' (stale ledger)"
        }
    } elseif ($parentShaLine -cmatch '^parent_sha:\s*(NONE|EMPTY_TREE)\s*$') {
        if ($ExpectedParentSha -ne $script:GitEmptyTreeSha) {
            $result.Valid = $false
            $result.Errors += "ledger declares root-commit placeholder '$($matches[1])' but commit has a real parent '$ExpectedParentSha'"
        } else {
            $result.ParentSha = $matches[1]
        }
    } else {
        $result.Valid = $false
        $result.Errors += "ledger parent_sha value is invalid (must be a full 40-char hex SHA, NONE, or EMPTY_TREE): $parentShaLine"
        return $result
    }

    # post-code-change-panel: the load-bearing row (na invalid when the diff is panel-required).
    $panelLine = $LedgerLines | Where-Object { $_ -cmatch '^\s*post-code-change-panel:\s*\S' } | Select-Object -First 1
    if (-not $panelLine) {
        $result.Valid = $false; $result.Errors += "missing required 'post-code-change-panel:' row"
    } else {
        $panelVal = ($panelLine -replace '^\s*post-code-change-panel:\s*', '').Trim()
        if ($panelVal -cmatch '<[^>]*>') {
            $result.Valid = $false; $result.Errors += "unsubstituted template placeholder for post-code-change-panel"
        } else {
            $ran    = $panelVal -cmatch '^ran,\s*unanimous\s*$'
            $waived = $panelVal -cmatch '^user-waived:\s*"panel-waive-acknowledged"\s+ref:[^\s<>]+\s*$'
            $na     = $panelVal -cmatch '^N/A:\s*\S'
            if ($safetyCritical) {
                if (-not $ran) {
                    $result.Valid = $false
                    $result.Errors += "post-code-change-panel must be 'ran, unanimous' (a user-waive or N/A is NOT permitted for a path-detectable safety-critical change); got: '$panelVal'"
                }
            } elseif ($panelRequired) {
                if (-not ($ran -or $waived)) {
                    $result.Valid = $false
                    $result.Errors += "post-code-change-panel must be 'ran, unanimous' or a tightened 'user-waived' (panel-waive-acknowledged token + ref:<call-ref>) because the diff touches code/governance paths; got: '$panelVal'"
                }
            } else {
                if (-not ($ran -or $waived -or $na)) {
                    $result.Valid = $false
                    $result.Errors += "post-code-change-panel must be 'ran, unanimous', 'N/A: <reason>', or a tightened 'user-waived' (panel-waive-acknowledged token + ref:<call-ref>); got: '$panelVal'"
                }
            }
            if ($ran) {
                foreach ($transcriptError in (Test-PanelTranscript -LedgerLines $LedgerLines)) {
                    $result.Valid = $false; $result.Errors += $transcriptError
                }
            }
        }
    }

    $prePanelLine = $LedgerLines | Where-Object { $_ -cmatch '^\s*pre-code-change-panel:\s*\S' } | Select-Object -First 1
    if (-not $prePanelLine) {
        if ($panelRequired) { $result.Valid = $false; $result.Errors += "missing required 'pre-code-change-panel:' row (the diff touches code/governance paths)" }
    } else {
        $preVal = ($prePanelLine -replace '^\s*pre-code-change-panel:\s*', '').Trim()
        if ($preVal -cmatch '<[^>]*>') {
            $result.Valid = $false; $result.Errors += "unsubstituted template placeholder for pre-code-change-panel"
        } else {
            $preRan    = $preVal -cmatch '^ran,\s*unanimous\s*$'
            $preWaived = $preVal -cmatch '^user-waived:\s*"panel-waive-acknowledged"\s+ref:[^\s<>]+\s*$'
            $preNa     = $preVal -cmatch '^N/A:\s*\S'
            if ($safetyCritical) {
                if (-not $preRan) {
                    $result.Valid = $false
                    $result.Errors += "pre-code-change-panel must be 'ran, unanimous' (a user-waive or N/A is NOT permitted for a path-detectable safety-critical change); got: '$preVal'"
                }
            } elseif ($panelRequired) {
                if (-not ($preRan -or $preWaived)) {
                    $result.Valid = $false
                    $result.Errors += "pre-code-change-panel must be 'ran, unanimous' or a tightened 'user-waived' (panel-waive-acknowledged token + ref:<call-ref>) because the diff touches code/governance paths; got: '$preVal'"
                }
            } else {
                if (-not ($preRan -or $preWaived -or $preNa)) {
                    $result.Valid = $false
                    $result.Errors += "pre-code-change-panel must be 'ran, unanimous', 'N/A: <reason>', or a tightened 'user-waived'; got: '$preVal'"
                }
            }
            if ($preRan) {
                foreach ($e in (Test-PrePanelTranscript -LedgerLines $LedgerLines)) {
                    $result.Valid = $false; $result.Errors += $e
                }
            }
        }
    }

    foreach ($e in (Test-LedgerDisclosureRow -LedgerLines $LedgerLines -RowKey 'diagnosis-repro-ref' -Required $panelRequired -AllowedRegexes @('^reproduction-locked:\s*\S', '^benchmark:\s*\S', '^N/A:\s*\S'))) {
        $result.Valid = $false; $result.Errors += $e
    }
    foreach ($e in (Test-LedgerDisclosureRow -LedgerLines $LedgerLines -RowKey 'approach-selection-G3' -Required $panelRequired -AllowedRegexes @('^fix-cause\s*$', '^document-symptom:\s*"[^"\s][^"]*"\s*$', '^N/A:\s*\S'))) {
        $result.Valid = $false; $result.Errors += $e
    }
    $g5Allowed = if ($safetyCritical) { @('^panel-ran\s*$') } else { @('^not-applicable\s*$', '^panel-ran\s*$', '^safety-critical-confirmed-skip:\s*ref:[^\s<>]+\s*$') }
    foreach ($e in (Test-LedgerDisclosureRow -LedgerLines $LedgerLines -RowKey 'safety-critical-eval-G5' -Required $panelRequired -AllowedRegexes $g5Allowed)) {
        $result.Valid = $false; $result.Errors += $e
    }

    if ($panelRequired) {
        foreach ($e in (Test-LedgerG6 -LedgerLines $LedgerLines)) { $result.Valid = $false; $result.Errors += $e }
    }

    $buildLine = $LedgerLines | Where-Object { $_ -cmatch '^\s*build:\s*\S' } | Select-Object -First 1
    if (-not $buildLine) {
        $result.Valid = $false; $result.Errors += "missing required 'build:' row"
    } elseif ($buildLine -cmatch '^\s*build:\s*<') {
        $result.Valid = $false; $result.Errors += "unsubstituted template placeholder for build"
    } else {
        $buildVal = ($buildLine -replace '^\s*build:\s*', '').Trim()
        if ($buildVal -imatch '^failed') {
            $result.Valid = $false; $result.Errors += "build row reports failure"
        } elseif (-not ($buildVal -imatch '^passed\b' -or $buildVal -imatch '^N/A:\s*\S')) {
            $result.Valid = $false; $result.Errors += "build row must be 'passed[, <details>]', 'failed: <reason>', or 'N/A: <reason>' (got: '$buildVal')"
        }
    }

    $testsLine = $LedgerLines | Where-Object { $_ -cmatch '^\s*tests:\s*\S' } | Select-Object -First 1
    if (-not $testsLine) {
        $result.Valid = $false; $result.Errors += "missing required 'tests:' row"
    } elseif ($testsLine -cmatch '^\s*tests:\s*<') {
        $result.Valid = $false; $result.Errors += "unsubstituted template placeholder for tests"
    } else {
        $testsVal = ($testsLine -replace '^\s*tests:\s*', '').Trim()
        if ($testsVal -imatch '^failed') {
            $result.Valid = $false; $result.Errors += "tests row reports failure"
        } elseif (-not ($testsVal -imatch '^passed\b' -or $testsVal -imatch '^N/A:\s*\S')) {
            $result.Valid = $false; $result.Errors += "tests row must be 'passed[, <details>]', 'failed: <reason>', or 'N/A: <reason>' (got: '$testsVal')"
        }
    }

    if (@($result.Errors).Count -gt 0) { $result.Valid = $false }
    return $result
}

Export-ModuleMember -Function Test-PathPanelRequired, Get-PanelRequired, Get-PathGovernanceTier, Get-ChangedGovernanceTier, Test-PanelLedger, Test-PanelTranscript, Test-PrePanelTranscript, Test-Transcript, Test-LedgerG6, Get-LedgerSubBlockMap, Get-PanelSlateFloor, Get-GitEmptyTreeSha -Variable GitEmptyTreeSha
