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

function Test-PathPanelRequired {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    $p = ($Path -replace '\\', '/').Trim()
    if (-not $p) { return $false }

    # Receipts are excluded so staging one never self-trips the gate.
    if ($p -like '.github/pr-quality-gate/audits/*') { return $false }

    if ($p -ceq 'AGENTS.md') { return $true }
    if ($p -ceq 'setup.ps1' -or $p -ceq 'setup.sh') { return $true }
    if ($p -ceq '.gitattributes' -or $p -ceq '.gitignore' -or $p -ceq '.github/copilot-instructions.md') { return $true }
    if ($p -like '.github/instructions/*' -or
        $p -like '.github/playbooks/*' -or
        $p -like '.github/workflows/*' -or
        $p -like '.github/pr-quality-gate/*' -or
        $p -like '.githooks/*' -or
        $p -like 'profiles/*' -or
        $p -like 'scripts/*') { return $true }

    $ext = [System.IO.Path]::GetExtension($p).TrimStart('.').ToLowerInvariant()
    if ($ext -and ($script:CodeExtensions -contains $ext)) { return $true }

    return $false
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

function Test-PanelTranscript {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $LedgerLines)

    $errors = New-Object System.Collections.Generic.List[string]
    $lines = @($LedgerLines)

    $headerIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if (([string]$lines[$i]) -cmatch '^\s*panel-transcript:\s*$') { $headerIdx = $i; break }
    }
    if ($headerIdx -lt 0) {
        $errors.Add("post-code-change-panel is 'ran, unanimous' but no 'panel-transcript:' block is present (the multi-model slate must be recorded)")
        return $errors.ToArray()
    }

    $grammar = '^\s*-\s*slot:(\S+)\s+model:(\S+)\s+family:(claude|gpt|gemini)\s+role:(rubber-duck|code-review)\s+tier:(heavy|light)\s+verdict:(READY|NEEDS_REWORK)\s+rounds:([0-9]{1,3})\s*$'
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
            $errors.Add("malformed panel-transcript reviewer line: '$(([string]$line).Trim())'")
        }
    }

    $reviewerArr = $reviewers.ToArray()
    if ($reviewerArr.Count -eq 0) {
        $errors.Add("panel-transcript block present but has no valid reviewer lines")
        return $errors.ToArray()
    }

    foreach ($g in @($reviewerArr | Group-Object -Property Slot | Where-Object { $_.Count -gt 1 })) {
        $errors.Add("duplicate reviewer slot '$($g.Name)' in panel-transcript (each reviewer must have a unique slot)")
    }
    foreach ($r in $reviewerArr) {
        if ($r.Verdict -cne 'READY') {
            $errors.Add("reviewer slot '$($r.Slot)' verdict is '$($r.Verdict)', not READY (panel not converged to unanimous)")
        }
        if ($r.Rounds -lt 1) {
            $errors.Add("reviewer slot '$($r.Slot)' rounds must be >= 1 (got $($r.Rounds))")
        }
    }

    $distinct = @($reviewerArr | Group-Object -Property Slot | ForEach-Object { $_.Group | Select-Object -First 1 })
    $floor = $script:PanelSlateFloor
    $nClaude = @($distinct | Where-Object { $_.Family -eq 'claude' }).Count
    $nGpt    = @($distinct | Where-Object { $_.Family -eq 'gpt' }).Count
    $nGemini = @($distinct | Where-Object { $_.Family -eq 'gemini' }).Count
    $nDuck   = @($distinct | Where-Object { $_.Role -eq 'rubber-duck' }).Count
    $nReview = @($distinct | Where-Object { $_.Role -eq 'code-review' }).Count
    $nHeavy  = @($distinct | Where-Object { $_.Tier -eq 'heavy' }).Count

    if ($distinct.Count -lt $floor.MinReviewers) { $errors.Add("panel-transcript has $($distinct.Count) distinct reviewer(s); the full slate floor requires >= $($floor.MinReviewers)") }
    if ($nClaude -lt $floor.MinClaude)           { $errors.Add("panel-transcript has $nClaude Claude-family reviewer(s); full floor requires >= $($floor.MinClaude)") }
    if ($nGpt -lt $floor.MinGpt)                 { $errors.Add("panel-transcript has $nGpt GPT-family reviewer(s); full floor requires >= $($floor.MinGpt)") }
    if ($nGemini -lt $floor.MinGemini)           { $errors.Add("panel-transcript has $nGemini Gemini-family reviewer(s); full floor requires >= $($floor.MinGemini)") }
    if ($nDuck -lt $floor.MinRubberDuck)         { $errors.Add("panel-transcript has $nDuck rubber-duck reviewer(s); full floor requires >= $($floor.MinRubberDuck)") }
    if ($nReview -lt $floor.MinCodeReview)       { $errors.Add("panel-transcript has $nReview code-review reviewer(s); full floor requires >= $($floor.MinCodeReview)") }
    if ($nHeavy -lt $floor.MinHeavy)             { $errors.Add("panel-transcript has $nHeavy heavy-tier reviewer(s); full floor requires >= $($floor.MinHeavy)") }

    return $errors.ToArray()
}

function Test-PanelLedger {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $LedgerLines,
        [Parameter(Mandatory)] [string] $ExpectedParentSha,
        [Parameter(Mandatory)] [bool] $PanelRequired
    )
    $result = [PSCustomObject]@{ Valid = $true; Errors = @(); ParentSha = $null }

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
            if ($PanelRequired) {
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

Export-ModuleMember -Function Test-PathPanelRequired, Get-PanelRequired, Test-PanelLedger, Test-PanelTranscript, Get-PanelSlateFloor, Get-GitEmptyTreeSha -Variable GitEmptyTreeSha
