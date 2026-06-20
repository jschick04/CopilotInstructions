#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Standalone pwsh self-test (Assert-* helpers, not Pester) for check-pr-text.ps1.
# Run: pwsh -File scripts/tests/check-pr-text.tests.ps1

$checkerPath = (Resolve-Path (Join-Path $PSScriptRoot '../check-pr-text.ps1')).Path
. (Join-Path $PSScriptRoot 'test-common.ps1')
$pwshExe = Get-TestPwshExe

$script:Fail = 0
$script:Pass = 0

# Dot-source for direct Get-PrTextFindings unit tests (the main block returns early when dot-sourced).
. $checkerPath

function Get-HardFailCount {
    param([string] $Title = '', [string] $Body = '')
    return @(Get-PrTextFindings -TitleText $Title -BodyText $Body | Where-Object { $_.Severity -eq 'hard-fail' }).Count
}
function Get-WarnCount {
    param([string] $Title = '', [string] $Body = '')
    return @(Get-PrTextFindings -TitleText $Title -BodyText $Body | Where-Object { $_.Severity -eq 'warn' }).Count
}

# Invoke the checker as a subprocess; returns the exit code. Mode = param (-Title) or env (PR_TITLE/PR_BODY).
function Invoke-Checker {
    param([string] $Title, [string] $Body, [switch] $UseEnv, [switch] $NoInput, [string[]] $ExtraArgs)
    if ($NoInput) {
        & $pwshExe -NoProfile -File $checkerPath *> $null
        return $LASTEXITCODE
    }
    if ($UseEnv) {
        $prev = $env:PR_TITLE; $prevB = $env:PR_BODY
        try {
            $env:PR_TITLE = $Title; $env:PR_BODY = $Body
            & $pwshExe -NoProfile -File $checkerPath *> $null
            return $LASTEXITCODE
        } finally { $env:PR_TITLE = $prev; $env:PR_BODY = $prevB }
    }
    $callArgs = @('-NoProfile', '-File', $checkerPath, '-Title', $Title)
    if ($PSBoundParameters.ContainsKey('Body')) { $callArgs += @('-Body', $Body) }
    if ($ExtraArgs) { $callArgs += $ExtraArgs }
    & $pwshExe @callArgs *> $null
    return $LASTEXITCODE
}

Write-Host 'Get-PrTextFindings - CLEAN titles must yield 0 hard-fails (the FP battery):'
$cleanTitles = @(
    'A4 paper size', 'T2 diabetes mellitus', 'Phase 1 of the migration', 'step 3 of the wizard',
    'Fix A1 notation parsing', 'fix C2065 compiler errors', 'see D3 docs for the API', 'C# 12 features',
    'per section A1 of the spec', 'Add C4 codec support', 'Upgrade D3 to v7', 'A1-A6 pins',
    'option e-mail notifications', 'option x-axis scaling', 'option a-la-carte billing', 'support u-turn gestures'
)
foreach ($clean in $cleanTitles) {
    Assert-True ((Get-HardFailCount -Title $clean) -eq 0) "clean: '$clean' -> 0 hard-fail"
}

Write-Host 'Get-PrTextFindings - LEAK shapes must yield >=1 hard-fail (tier-1):'
$leakTitles = @(
    'Refactor parser (T1)', 'Address per F16e-2 cascade', 'Finish task A2 migration', 'plan: C2 rollout',
    'Phase 5.5 convergence', 'Wire step 7c handler', 'Pick option B-hybrid'
)
foreach ($leak in $leakTitles) {
    Assert-True ((Get-HardFailCount -Title $leak) -ge 1) "leak: '$leak' -> hard-fail"
}

Write-Host 'Get-PrTextFindings - body-surface leaks (workspace artifacts):'
Assert-True ((Get-HardFailCount -Title 'Clean title' -Body 'Carries out the audit from files/f3-audit.md') -ge 1) 'body files/<x>.md -> hard-fail'
Assert-True ((Get-HardFailCount -Title 'Clean title' -Body 'Carries out the audit from files\f3-audit.md') -ge 1) 'body files\<x>.md (Windows separator) -> hard-fail'
Assert-True ((Get-HardFailCount -Title 'Clean title' -Body 'see .copilot/session-state/abcd1234/plan.md') -ge 1) 'body session-state path -> hard-fail'
Assert-True ((Get-HardFailCount -Title 'Clean title' -Body 'per the 1aaddd3a-b2b8-4df2-87f5-bf1cbf12a685/plan.md notes') -ge 1) 'body <uuid>/plan.md -> hard-fail'

Write-Host 'Get-PrTextFindings - TIER 2 = warn, NOT hard-fail:'
Assert-True ((Get-HardFailCount -Title 'T1 milestone shipped') -eq 0) 'bare short-id "T1 milestone" -> 0 hard-fail'
Assert-True ((Get-WarnCount -Title 'T1 milestone shipped') -ge 1) 'bare short-id "T1 milestone" -> >=1 warn'
Assert-True ((Get-HardFailCount -Title 'Done; already shipped upstream by d3fcfa9aa1') -eq 0) 'context-SHA -> 0 hard-fail'
Assert-True ((Get-WarnCount -Title 'Done; already shipped upstream by d3fcfa9aa1') -ge 1) 'context-SHA -> >=1 warn'

Write-Host 'Subprocess exit codes (param mode):'
Assert-True ((Invoke-Checker -Title 'Add a clean feature') -eq 0) 'clean title -> exit 0'
Assert-True ((Invoke-Checker -Title 'Refactor parser (T1)') -eq 1) 'leak title -> exit 1'
Assert-True ((Invoke-Checker -Title 'Clean title' -Body 'audit from files/f3-audit.md') -eq 1) 'clean title + body leak -> exit 1'
Assert-True ((Invoke-Checker -Title 'Finish task A2 migration' -Body '') -eq 1) 'title-only leak + EMPTY body -> exit 1 (body-empty does not short-circuit)'
Assert-True ((Invoke-Checker -Title '') -eq 2) 'empty -Title (param mode) -> exit 2 (invocation error, not a silent skip)'
Assert-True ((Invoke-Checker -Title 'T1 milestone shipped') -eq 0) 'tier-2-only (bare id) -> exit 0 (warn, not block)'

Write-Host 'Subprocess exit codes (env mode + dispatch):'
Assert-True ((Invoke-Checker -Title 'Finish task A2 migration' -Body '' -UseEnv) -eq 1) 'env-mode leak -> exit 1'
Assert-True ((Invoke-Checker -Title 'Clean env title' -Body 'no markers here' -UseEnv) -eq 0) 'env-mode clean -> exit 0'
Assert-True ((Invoke-Checker -Title '' -Body 'audit from files/f3-audit.md' -UseEnv) -eq 1) 'env-mode empty title + body leak -> exit 1 (body scanned despite empty title)'
Assert-True ((Invoke-Checker -NoInput) -eq 0) 'no input source (local mirror) -> exit 0'
Assert-True ((Invoke-Checker -Title 'X' -Body 'y' -ExtraArgs @('-BodyFile', (Join-Path ([System.IO.Path]::GetTempPath()) 'nonexistent-xyz.md'))) -eq 2) 'both -Body and -BodyFile -> exit 2'
Assert-True ((Invoke-Checker -Title 'X' -ExtraArgs @('-BodyFile', '')) -eq 2) 'empty -BodyFile (param mode) -> exit 2 (not a silent fall-back to -Body)'
Assert-True ((Invoke-Checker -Title 'X' -ExtraArgs @('-BodyFile', '   ')) -eq 2) 'whitespace -BodyFile -> exit 2'
Assert-True ((Invoke-Checker -Title 'X' -Body 'y' -ExtraArgs @('-BodyFile', '')) -eq 2) 'empty -BodyFile + -Body -> exit 2 (ambiguity caught via ContainsKey, not truthiness)'
& $pwshExe -NoProfile -File $checkerPath -Body 'see files/f3-audit.md' *> $null
Assert-True ($LASTEXITCODE -eq 2) '-Body without -Title -> exit 2 (a body source is not scanned without the title source)'
$btFile = Join-Path ([System.IO.Path]::GetTempPath()) ('pbt-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.md')
Set-Content -LiteralPath $btFile -Value 'see files/f3-audit.md' -NoNewline
& $pwshExe -NoProfile -File $checkerPath -BodyFile $btFile *> $null
Assert-True ($LASTEXITCODE -eq 2) '-BodyFile without -Title -> exit 2 (body source requires title source)'
Remove-Item -LiteralPath $btFile -Force

# ambiguous param+env: set PR_TITLE while also passing -Title
$prevTitle = $env:PR_TITLE
try {
    $env:PR_TITLE = 'env title'
    & $pwshExe -NoProfile -File $checkerPath -Title 'param title' *> $null
    Assert-True ($LASTEXITCODE -eq 2) 'both -Title param AND PR_TITLE env -> exit 2 (ambiguous)'
} finally { $env:PR_TITLE = $prevTitle }

# nonexistent -BodyFile alone
Assert-True ((Invoke-Checker -Title 'X' -ExtraArgs @('-BodyFile', (Join-Path ([System.IO.Path]::GetTempPath()) 'nope-abc.md'))) -eq 2) 'nonexistent -BodyFile -> exit 2'

Write-Host ''
Write-Host "check-pr-text.tests: $script:Pass passed, $script:Fail failed."
if ($script:Fail -gt 0) { exit 1 }
exit 0
