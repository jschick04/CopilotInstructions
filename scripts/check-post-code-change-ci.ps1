<#
  check-post-code-change-ci.ps1 - CI wrapper that owns its own setup so the pr-gate-check workflow step is a single script
  invocation (no inline multi-command run: block). Fail-closed fetches the PR base (when -FetchBranch is given), then
  delegates to the pure check-post-code-change.ps1 against -BaseRef. Locally, run-local-ci omits -FetchBranch and uses the
  existing origin ref.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $BaseRef,
    [string] $FetchBranch,
    [string] $RepoRoot = '',
    [switch] $CiMode
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/repo-root.psm1') -Force
try {
    $RepoRoot = Resolve-RepoRoot -Explicit $RepoRoot -ScriptRoot $PSScriptRoot -Anchors @('scripts/check-post-code-change-ci.ps1') -RequireGitWorkTree
} catch {
    Write-Host "::error::$($_.Exception.Message)"
    exit 2
}

if ($FetchBranch) {
    & git -C $RepoRoot fetch origin $FetchBranch 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "::error::check-post-code-change-ci: git fetch of base ref '$FetchBranch' failed - refusing to run fail-open"
        exit 2
    }
}

& (Join-Path $PSScriptRoot 'check-post-code-change.ps1') -BaseRef $BaseRef -RepoRoot $RepoRoot
exit $LASTEXITCODE
