<#
  check-diff-consistency-ci.ps1 - CI wrapper that owns its own setup + per-commit loop so the pr-gate-check workflow step
  is a single script invocation (no inline multi-command run: block). Fail-closed fetches the PR base (when -FetchBranch
  is given), enumerates every PR commit, and runs check-diff-consistency.ps1 -Mode commit against each. A HARD finding in
  ANY commit fails the job. In CI an empty commit range is a failure (a real PR has >= 1 commit); locally it passes.
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
        Write-Host "::error::check-diff-consistency-ci: git fetch of base ref '$FetchBranch' failed - refusing to run fail-open"
        exit 2
    }
}

$commits = @(& git -C $RepoRoot rev-list --reverse "$BaseRef..HEAD" 2>$null | Where-Object { $_ })
if ($LASTEXITCODE -ne 0) {
    Write-Host "::error::check-diff-consistency-ci: git rev-list failed (could not enumerate commits in $BaseRef..HEAD)"
    exit 2
}
if ($commits.Count -eq 0) {
    if ($CiMode) {
        Write-Host "::error::check-diff-consistency-ci: no commits in $BaseRef..HEAD; refusing to pass without checking"
        exit 2
    }
    Write-Host "check-diff-consistency-ci: PASS (0 commits in $BaseRef..HEAD)" -ForegroundColor Green
    exit 0
}

$checker = Join-Path $PSScriptRoot 'check-diff-consistency.ps1'
$pwshExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }
$failed = $false
foreach ($commitSha in $commits) {
    Write-Host "::group::diff-consistency $commitSha"
    & $pwshExe -NoProfile -File $checker -RepoRoot $RepoRoot -Mode commit -HeadRef $commitSha
    if ($LASTEXITCODE -ne 0) { $failed = $true }
    Write-Host "::endgroup::"
}
if ($failed) {
    Write-Host "::error::check-diff-consistency-ci: a HARD finding was reported in one or more commits"
    exit 1
}
Write-Host "check-diff-consistency-ci: PASS over $($commits.Count) commit(s)" -ForegroundColor Green
exit 0
