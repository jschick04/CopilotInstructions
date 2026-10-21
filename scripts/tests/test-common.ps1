#Requires -Version 5.1

if (-not (Get-Variable -Name Temps -Scope Script -ErrorAction SilentlyContinue)) {
    $script:Temps = New-Object System.Collections.ArrayList
}

function Assert-True {
    param([bool] $Condition, [string] $Name)
    if ($Condition) { Write-Host "  [PASS] $Name"; $script:Pass++ }
    else { Write-Host "  [FAIL] $Name" -ForegroundColor Red; $script:Fail++ }
}

function Assert-False {
    param([bool] $Condition, [string] $Name)
    Assert-True (-not $Condition) $Name
}

function Assert-Equal {
    param($Expected, $Actual, [string] $Name, [switch] $CaseSensitive)
    if ((($Expected -is [System.Collections.IEnumerable]) -and ($Expected -isnot [string])) -or
        (($Actual -is [System.Collections.IEnumerable]) -and ($Actual -isnot [string]))) {
        throw "Assert-Equal does not support enumerable (array/collection) operands; use a dedicated sequence assertion or compare scalar projections. Test: $Name"
    }
    $equal = if ($CaseSensitive) { $Expected -ceq $Actual } else { $Expected -eq $Actual }
    if ($equal) { Write-Host "  [PASS] $Name"; $script:Pass++ }
    else { Write-Host "  [FAIL] $Name (expected '$Expected', got '$Actual')" -ForegroundColor Red; $script:Fail++ }
}

function Assert-ThrowsLike {
    param([scriptblock] $Action, [string] $Pattern, [string] $Name)
    try {
        & $Action | Out-Null
        Assert-True $false $Name
    } catch {
        Assert-True ($_.Exception.Message -match $Pattern) $Name
    }
}

function Get-TestPwshExe {
    if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }
}

function New-TestTempDirectory {
    param([string] $Prefix)
    $directory = Join-Path ([IO.Path]::GetTempPath()) ("$Prefix-" + [Guid]::NewGuid().ToString('N').Substring(0, 12))
    New-Item -ItemType Directory -Path $directory | Out-Null
    [void]$script:Temps.Add($directory)
    return $directory
}

function Initialize-TestGitRepository {
    param([string] $Directory)
    git -C $Directory init -q -b main 2>$null
    git -C $Directory config user.email 't@t.t'
    git -C $Directory config user.name 'tester'
    git -C $Directory config commit.gpgsign false
}

function New-TestGitRepository {
    param([string] $Prefix)
    $directory = New-TestTempDirectory -Prefix $Prefix
    Initialize-TestGitRepository -Directory $directory
    return $directory
}

function Initialize-InstructionFixtureRepository {
    param([Parameter(Mandatory)] [string] $Directory)
    $policyDirectory = Join-Path $Directory '.github/pr-quality-gate'
    $registryDirectory = Join-Path $Directory '.github/playbooks/multi-model-review'
    New-Item -ItemType Directory -Path $policyDirectory, $registryDirectory -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $policyDirectory 'panel-policy.md') -Value 'Instruction fixture panel policy'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../../.github/playbooks/multi-model-review/current-model-registry.md') -Destination (Join-Path $registryDirectory 'current-model-registry.md')
    New-Item -ItemType Directory -Path (Join-Path $policyDirectory 'data') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../../.github/pr-quality-gate/data/heavy-allowlist.txt') -Destination (Join-Path $policyDirectory 'data/heavy-allowlist.txt')
}

function New-TestCommit {
    param([string] $Directory, [string] $File, [string] $Content, [string] $Message)
    $fullPath = Join-Path $Directory $File
    New-Item -ItemType Directory -Path (Split-Path -Parent $fullPath) -Force | Out-Null
    Set-Content -LiteralPath $fullPath -Value $Content
    git -C $Directory add -A 2>$null
    git -C $Directory commit -q -m $Message
    return (git -C $Directory rev-parse HEAD).Trim()
}

function Get-ValidPanelTranscript {
    return @(
        '    panel-transcript:',
        '      - slot:duck model:claude-opus-5.5 family:claude role:rubber-duck tier:heavy verdict:CODE_REVIEW_READY rounds:2',
        '      - slot:enforce model:gpt-6.1-sol family:gpt role:code-review tier:heavy verdict:CODE_REVIEW_READY rounds:2',
        '      - slot:integ model:gemini-4-argon family:gemini role:code-review tier:heavy verdict:CODE_REVIEW_READY rounds:2',
        '      - slot:scripts model:grok-4.7 family:grok role:code-review tier:heavy verdict:CODE_REVIEW_READY rounds:2',
        '      - slot:arch model:gpt-5.3-codex family:gpt role:code-review tier:heavy verdict:CODE_REVIEW_READY rounds:2',
        '      - findings: converged after closing a fail-open and tightening a regex'
    )
}

function Get-ValidPreTranscript {
    return @(
        '    pre-panel-transcript:',
        '      - slot:pduck model:claude-opus-5.5 family:claude role:rubber-duck tier:heavy verdict:DESIGN_READY rounds:2',
        '      - slot:penforce model:gpt-6.1-sol family:gpt role:code-review tier:heavy verdict:DESIGN_READY rounds:2',
        '      - slot:pinteg model:gemini-4-argon family:gemini role:code-review tier:heavy verdict:DESIGN_READY rounds:2',
        '      - slot:pscripts model:grok-4.7 family:grok role:code-review tier:heavy verdict:DESIGN_READY rounds:2',
        '      - slot:parch model:gpt-5.3-codex family:gpt role:code-review tier:heavy verdict:DESIGN_READY rounds:2',
        '      - findings: converged after correcting the diagnosis and the approach'
    )
}

function Get-ValidImplementationCheckpoint {
    return @(
        '    implementation-checkpoint:',
        '      status: complete',
        '      design_ready: yes',
        '      diff_matches_design: yes'
    )
}

function Get-ValidPreRows {
    param([string] $PrePanel = 'ran, unanimous', [string] $G5 = 'not-applicable', [switch] $OmitImplementationCheckpoint)
    $rows = @("    pre-code-change-panel: $PrePanel")
    if ($PrePanel -cmatch '^ran,\s*unanimous\s*$') {
        $rows += (Get-ValidPreTranscript)
        if (-not $OmitImplementationCheckpoint) { $rows += (Get-ValidImplementationCheckpoint) }
    }
    return $rows + @(
        '    diagnosis-repro-ref: reproduction-locked: tests/Repro.cs',
        '    approach-selection-G3: fix-cause',
        "    safety-critical-eval-G5: $G5",
        '    pre-impl-trigger-detections:',
        '      implementation-planning: no',
        '      library-restructure: no',
        '      design-exploration: no',
        '      performance-comparison: no',
        '      scope-planning: no',
        '      system-framing: no',
        '      project-vocabulary: no',
        '    pre-impl-playbook-decisions:',
        '      implementation-planning: not-required-trigger-not-detected',
        '      library-restructure: not-required-trigger-not-detected',
        '      design-exploration: not-applicable',
        '      performance-comparison: not-applicable',
        '      scope-planning: not-applicable',
        '      system-framing: not-applicable',
        '      project-vocabulary: not-applicable',
        '    playbook-invocations:',
        '      implementation-planning: N/A: trigger not detected',
        '      library-restructure: N/A: trigger not detected',
        '      design-exploration: N/A: trigger not detected',
        '      performance-comparison: N/A: trigger not detected'
    )
}

function Remove-TestTempDirectories {
    foreach ($directory in $script:Temps) {
        if (Test-Path $directory) {
            Remove-Item -LiteralPath $directory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Complete-TestRun {
    foreach ($summaryLine in @("`n=== Summary ===", "Passes:   $script:Pass", "Failures: $script:Fail")) {
        Write-Host $summaryLine
    }
    if ($script:Fail -gt 0) { exit 1 }
    exit 0
}
