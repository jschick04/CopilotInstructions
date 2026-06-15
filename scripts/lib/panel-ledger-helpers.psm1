#Requires -Version 5.1
# Pure validators for the post-code-change panel LEDGER gate. Isolated from comment-audit
# (no shared code); asserts only load-bearing §2B keys, opaque to other rows to avoid drift.

Set-StrictMode -Version Latest

$script:GitEmptyTreeSha = '4b825dc642cb6eb9a060e54bf8d69288fbee4904'

function Get-GitEmptyTreeSha { $script:GitEmptyTreeSha }

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
    if ($parentShaLine -cmatch '^parent_sha:\s*([a-fA-F0-9]{7,40})\s*$') {
        $result.ParentSha = $matches[1]
        if ($ExpectedParentSha -eq $script:GitEmptyTreeSha) {
            $result.Valid = $false
            $result.Errors += "ledger declares hex parent_sha '$($result.ParentSha)' but expected root-commit empty-tree sentinel"
        } elseif ($ExpectedParentSha -notlike "$($result.ParentSha)*" -and $result.ParentSha -notlike "$ExpectedParentSha*") {
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
        $result.Errors += "ledger parent_sha value is invalid (must be >=7-char hex SHA, NONE, or EMPTY_TREE): $parentShaLine"
        return $result
    }

    # post-code-change-panel: the load-bearing row (na invalid when the diff is panel-required).
    $panelLine = $LedgerLines | Where-Object { $_ -cmatch '^\s*post-code-change-panel:\s*\S' } | Select-Object -First 1
    if (-not $panelLine) {
        $result.Valid = $false; $result.Errors += "missing required 'post-code-change-panel:' row"
    } else {
        $panelVal = ($panelLine -replace '^\s*post-code-change-panel:\s*', '').Trim()
        if ($panelVal -cmatch '^<') {
            $result.Valid = $false; $result.Errors += "unsubstituted template placeholder for post-code-change-panel"
        } else {
            $ran    = $panelVal -cmatch '^ran,\s*unanimous\s*$'
            $waived = $panelVal -cmatch '^user-waived:\s*".+"\s*$'
            $na     = $panelVal -cmatch '^N/A:\s*\S'
            if ($PanelRequired) {
                if (-not ($ran -or $waived)) {
                    $result.Valid = $false
                    $result.Errors += "post-code-change-panel must be 'ran, unanimous' (or user-waived) because the diff touches code/governance paths; got: '$panelVal'"
                }
            } else {
                if (-not ($ran -or $waived -or $na)) {
                    $result.Valid = $false
                    $result.Errors += "post-code-change-panel must be 'ran, unanimous', 'N/A: <reason>', or user-waived; got: '$panelVal'"
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

    return $result
}

Export-ModuleMember -Function Test-PathPanelRequired, Get-PanelRequired, Test-PanelLedger, Get-GitEmptyTreeSha -Variable GitEmptyTreeSha
