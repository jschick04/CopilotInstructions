<#
  check-lint.ps1 - PSScriptAnalyzer gate over the repo's PowerShell (.ps1/.psm1).

  Zero-tolerance: any Warning/Error finding (after the deliberate, documented ExcludeRules below)
  fails closed. This is the mechanical backstop the multi-round PR review kept needing by hand -
  unused variables, dead code, unapproved verbs, etc. are caught here, not by a human reviewer.

  Self-installs PSScriptAnalyzer when absent: the run-local-ci coverage gate requires every CI
  workflow run-line to be a clean single scripts/ invocation, so there is NO separate CI install
  step - the checker owns its own dependency. Identity-free: lints whatever repo it runs in.

  Exit: 0 = clean; 1 = finding(s); 2 = cannot compute (no analyzer, git enumeration failed, or
  no files) - a config/anti-vacuous failure, never a silent pass.
#>
[CmdletBinding()]
param(
    [string] $RepoRoot = '',
    [string[]] $Path,          # explicit files to lint (tests pass temp fixtures); default = all tracked PS files
    [switch] $Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'lib/repo-root.psm1') -Force -DisableNameChecking

$ExitOk = 0; $ExitViolation = 1; $ExitConfig = 2

if ($RepoRoot) {
    $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
} else {
    $RepoRoot = Resolve-RepoRoot -Explicit '' -ScriptRoot $PSScriptRoot -Anchors @('scripts/check-lint.ps1') -RequireGitWorkTree
}

# Deliberate rule exclusions, co-located with the checker (NOT a separate settings file - that would
# need its own structure-manifest pattern). Each carries the rationale so the policy is reviewable here.
$excludeRules = @(
    'PSAvoidUsingWriteHost'                        # gate/installer scripts print to the console by design (not a data pipeline)
    'PSUseShouldProcessForStateChangingFunctions'  # these are scripts, not cmdlets that expose -WhatIf/-Confirm
    'PSUseSingularNouns'                            # domain nouns (Flush-Audits, Add-Windows) read correctly as plural
    'PSReviewUnusedParameter'                       # param contracts (e.g. -Quiet/-RepoRoot) are an intentional surface
    'PSAvoidAssignmentToAutomaticVariable'          # setup.ps1 -Profile is a deliberate, documented public CLI flag
    'PSUseBOMForUnicodeEncodedFile'                 # the repo is intentionally UTF-8 NO-BOM (git/hash-parity friendly)
)
$settings = @{ Severity = @('Warning', 'Error'); ExcludeRules = $excludeRules }

# Ensure a PINNED PSScriptAnalyzer is available so local == CI and a future PSSA release cannot
# silently change the rule set under an unrelated PR. Self-install (no separate CI step exists -
# the coverage gate forbids non-script run lines) and fail closed if that is impossible.
$requiredVersion = '1.25.0'
if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer | Where-Object { $_.Version -eq [version]$requiredVersion })) {
    try {
        Install-Module PSScriptAnalyzer -RequiredVersion $requiredVersion -Scope CurrentUser -Force -Repository PSGallery -ErrorAction Stop
    } catch {
        Write-Host "check-lint: PSScriptAnalyzer $requiredVersion is not installed and auto-install failed: $($_.Exception.Message)"
        Write-Host "           Install it manually (Install-Module PSScriptAnalyzer -RequiredVersion $requiredVersion -Scope CurrentUser), then re-run. Failing closed."
        exit $ExitConfig
    }
}
Import-Module PSScriptAnalyzer -RequiredVersion $requiredVersion -ErrorAction Stop

# File set: explicit -Path (tests), else every tracked .ps1/.psm1. A git failure fails closed
# (do not silently lint nothing), consistent with the other diff-detector gates.
if ($PSBoundParameters.ContainsKey('Path')) {
    $missing = @($Path | Where-Object { $_ -and -not (Test-Path -LiteralPath $_ -PathType Leaf) })
    if ($missing.Count -gt 0) {
        Write-Host "check-lint: -Path names $($missing.Count) path(s) that are not existing files: $($missing -join ', '). Failing closed."
        exit $ExitConfig
    }
    $files = @($Path | Where-Object { $_ } | ForEach-Object { (Resolve-Path -LiteralPath $_).Path })
} else {
    $tracked = @(& git -C $RepoRoot ls-files '*.ps1' '*.psm1')
    if ($LASTEXITCODE -ne 0) {
        Write-Host "check-lint: 'git ls-files' failed (exit $LASTEXITCODE); cannot enumerate PowerShell files. Failing closed."
        exit $ExitConfig
    }
    $files = @($tracked | ForEach-Object { Join-Path $RepoRoot $_ } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })
}

if ($files.Count -eq 0) {
    Write-Host "check-lint: found 0 PowerShell files to analyze. Failing closed (a repo of pwsh scripts must have files to lint)."
    exit $ExitConfig
}

function ConvertTo-RepoRelativePath { param([string] $FullPath) (($FullPath -replace [regex]::Escape($RepoRoot), '').TrimStart('\', '/')) -replace '\\', '/' }

# Parse pre-pass: Invoke-ScriptAnalyzer does NOT surface a syntax error as a finding (it returns
# zero findings for an unparseable file), so a broken script would otherwise pass the gate. Catch
# parse errors explicitly here - a mechanical lint gate must not fail open on a file it cannot parse.
$parseFailures = New-Object System.Collections.Generic.List[string]
foreach ($file in $files) {
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$null, [ref]$parseErrors)
    if ($parseErrors -and $parseErrors.Count -gt 0) {
        foreach ($pe in $parseErrors) {
            $parseFailures.Add(("  {0}:{1} [PSParseError] {2}" -f (ConvertTo-RepoRelativePath $file), $pe.Extent.StartLineNumber, $pe.Message))
        }
    }
}

$findings = @($files | ForEach-Object { Invoke-ScriptAnalyzer -Path $_ -Settings $settings })

if ($parseFailures.Count -gt 0 -or $findings.Count -gt 0) {
    Write-Host "check-lint: FAIL - $($parseFailures.Count) parse error(s) + $($findings.Count) PSScriptAnalyzer finding(s) (Warning+Error; documented exclusions applied):"
    foreach ($pf in $parseFailures) { Write-Host $pf }
    foreach ($f in ($findings | Sort-Object ScriptPath, Line)) {
        Write-Host ("  {0}:{1} [{2}] {3}" -f (ConvertTo-RepoRelativePath $f.ScriptPath), $f.Line, $f.RuleName, $f.Message)
    }
    Write-Host "       Fix the finding(s) above, or (if a rule is genuinely wrong for this repo) add it to `$excludeRules in scripts/check-lint.ps1 with a rationale."
    exit $ExitViolation
}

if (-not $Quiet) {
    Write-Host "check-lint: PASS - $($files.Count) PowerShell file(s) clean (PSScriptAnalyzer Warning+Error, documented exclusions)."
}
exit $ExitOk
