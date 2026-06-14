<#
  check-comment-audit-ci.ps1 - CI wrapper that owns its own setup so the pr-gate-check workflow step is a single script
  invocation (no inline multi-command run: block). Fail-closed fetches the PR base (when -FetchBranch is given), then
  delegates to the pure check-comment-audit.ps1 against -BaseRef. Locally, run-local-ci omits -FetchBranch and uses the
  existing origin ref.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $BaseRef,
    [string] $FetchBranch,
    [string] $RepoRoot = (Get-Location).Path,
    [switch] $CiMode
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($FetchBranch) {
    & git -C $RepoRoot fetch origin $FetchBranch 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "::error::check-comment-audit-ci: git fetch of base ref '$FetchBranch' failed - refusing to run fail-open"
        exit 2
    }
}

& (Join-Path $PSScriptRoot 'check-comment-audit.ps1') -BaseRef $BaseRef -RepoRoot $RepoRoot
exit $LASTEXITCODE
