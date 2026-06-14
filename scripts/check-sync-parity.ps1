<#
  check-sync-parity.ps1 - extracted from catalog-sync-check.yml's `parity` job (was 3 inline steps: gen pwsh, gen bash,
  cmp) into ONE script the workflow and run-local-ci.ps1 both invoke. Verifies that scripts/sync-critical-rules.ps1 and
  scripts/sync-critical-rules.sh produce byte-identical output (so the two implementations never drift).

  Exit contract: 0 = identical; 1 = DRIFT (the real violation); 2 = environment (the bash side could not be run here -
  e.g. a Windows machine whose only `bash` is WSL with a CRLF working tree); 3 = the pwsh generator itself failed (a
  hard, NON-skippable error - never an environment skip). CI (ubuntu, real bash, LF) always gets 0/1; run-local-ci
  treats ONLY a local exit 2 as a skip (the catalog-sync CI workflow is the authoritative gate).
#>
[CmdletBinding()]
param(
    [string] $RepoRoot = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/repo-root.psm1') -Force
try {
    $RepoRoot = Resolve-RepoRoot -Explicit $RepoRoot -ScriptRoot $PSScriptRoot -Anchors @('scripts/sync-critical-rules.ps1')
} catch {
    Write-Host "::error::$($_.Exception.Message)"
    exit 3
}

$ExitOk = 0; $ExitDrift = 1; $ExitEnv = 2; $ExitFail = 3
$pwshExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }

$tmpPwsh = [System.IO.Path]::GetTempFileName()
$tmpBash = [System.IO.Path]::GetTempFileName()
try {
    Push-Location $RepoRoot
    try {
        & $pwshExe -NoProfile -File (Join-Path $RepoRoot 'scripts/sync-critical-rules.ps1') -OutputPath $tmpPwsh | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "::error::check-sync-parity: the pwsh sync generator failed (exit $LASTEXITCODE)"
            exit $ExitFail
        }

        # bash side (relative invocation, proven on CI). On Windows/WSL the CRLF .sh yields no output -> reported as ENVIRONMENT below, not drift.
        if (-not (Get-Command bash -ErrorAction SilentlyContinue)) {
            Write-Host "check-sync-parity: SKIP - no 'bash' on PATH; the catalog-sync CI workflow is the authoritative gate." -ForegroundColor Yellow
            exit $ExitEnv
        }
        & bash ./scripts/sync-critical-rules.sh -OutputPath $tmpBash 2>$null | Out-Null
        $bashExit = $LASTEXITCODE
        $bashBytes = if (Test-Path -LiteralPath $tmpBash) { (Get-Item -LiteralPath $tmpBash).Length } else { 0 }
        if ($bashExit -ne 0 -or $bashBytes -eq 0) {
            Write-Host "check-sync-parity: SKIP - the local 'bash' produced no output (exit $bashExit, $bashBytes bytes); likely a Windows/WSL CRLF environment. CI is authoritative." -ForegroundColor Yellow
            exit $ExitEnv
        }
    } finally { Pop-Location }

    # Compare LF-normalized content (so a CRLF-writing pwsh can't masquerade as drift; the embedded hash is what matters).
    $pwshContent = ([System.IO.File]::ReadAllText($tmpPwsh)) -replace "`r`n", "`n"
    $bashContent = ([System.IO.File]::ReadAllText($tmpBash)) -replace "`r`n", "`n"
    if ($pwshContent -ne $bashContent) {
        Write-Host "::error::check-sync-parity: DRIFT - sync-critical-rules.ps1 and .sh produce different output." -ForegroundColor Red
        $pwshHash = (& git -C $RepoRoot hash-object $tmpPwsh 2>$null)
        $bashHash = (& git -C $RepoRoot hash-object $tmpBash 2>$null)
        Write-Host "  pwsh hash: $pwshHash"
        Write-Host "  bash hash: $bashHash"
        exit $ExitDrift
    }
    Write-Host "check-sync-parity: PASS - pwsh and bash sync outputs are byte-identical." -ForegroundColor Green
    exit $ExitOk
}
finally {
    Remove-Item -Force -LiteralPath $tmpPwsh, $tmpBash -ErrorAction SilentlyContinue
}
