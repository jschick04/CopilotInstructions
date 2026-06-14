<#
  check-profile-invariants.ps1 - extracted from profile-invariants-check.yml (was inline bash) so the invariants live
  in ONE script the workflow and run-local-ci.ps1 both invoke. Enforces the profile-overlay invariants: exactly one
  always-loaded core AGENTS.md (none under profiles/), valid profile templates (id stamp + applyTo frontmatter), the
  per-machine active-profile file stays gitignored + uncommitted, and the two install scripts agree on the profile flag.
  Fail-closed: any broken invariant -> exit 1.
#>
[CmdletBinding()]
param(
    [string] $RepoRoot = (Get-Location).Path
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$failures = New-Object System.Collections.Generic.List[string]
function Add-Failure { param([string] $Message) $failures.Add($Message) }

function Get-NonCommentText {
    param([string] $RelPath)
    $full = Join-Path $RepoRoot $RelPath
    if (-not (Test-Path -LiteralPath $full)) { return $null }
    return (Get-Content -LiteralPath $full | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
}

$profilesDir = Join-Path $RepoRoot 'profiles'
if (Test-Path -LiteralPath $profilesDir) {
    $stray = Get-ChildItem -Recurse -LiteralPath $profilesDir -Filter 'AGENTS.md' -File -ErrorAction SilentlyContinue
    if ($stray) { Add-Failure "AGENTS.md found under profiles/ (the repo must have exactly one always-loaded core AGENTS.md, at the root)." }
}

foreach ($profile in @('full', 'lite')) {
    $rel = "profiles/$profile/profile.instructions.md"
    $full = Join-Path $RepoRoot $rel
    if (-not (Test-Path -LiteralPath $full)) { Add-Failure "missing profile template $rel"; continue }
    $content = Get-Content -LiteralPath $full -Raw
    if ($content -notmatch [regex]::Escape("<!-- profile-id: $profile -->")) { Add-Failure "$rel is missing the '<!-- profile-id: $profile -->' stamp." }
    if ($content -notmatch [regex]::Escape('applyTo: "**/*"')) { Add-Failure "$rel is missing the 'applyTo: ""**/*""' frontmatter." }
}

$gitignore = Join-Path $RepoRoot '.gitignore'
$activeLine = '/.github/instructions/active-profile.instructions.md'
$hasLine = $false
if (Test-Path -LiteralPath $gitignore) {
    $hasLine = @(Get-Content -LiteralPath $gitignore) -contains $activeLine
}
if (-not $hasLine) { Add-Failure "'.gitignore' must contain the exact line '$activeLine'." }

$tracked = & git -C $RepoRoot ls-tree -r HEAD --name-only 2>$null
if ($LASTEXITCODE -ne 0) { Add-Failure "could not run 'git ls-tree -r HEAD' to verify the active-profile file is uncommitted (fail-closed)." }
elseif (@($tracked) -contains '.github/instructions/active-profile.instructions.md') {
    Add-Failure "active-profile.instructions.md is committed; it must stay gitignored (per-machine only)."
}

$setupPs1 = Get-NonCommentText 'setup.ps1'
if ($null -eq $setupPs1) { Add-Failure "setup.ps1 not found." }
else {
    if ($setupPs1 -notmatch [regex]::Escape("ValidateSet('full', 'lite')")) { Add-Failure "setup.ps1 missing the -Profile ValidateSet('full', 'lite') on a non-comment line." }
    if ($setupPs1 -notmatch [regex]::Escape('active-profile.instructions.md')) { Add-Failure "setup.ps1 does not write active-profile.instructions.md." }
}

$setupSh = Get-NonCommentText 'setup.sh'
if ($null -eq $setupSh) { Add-Failure "setup.sh not found." }
else {
    if ($setupSh -notmatch [regex]::Escape('--profile')) { Add-Failure "setup.sh missing the --profile argument." }
    if ($setupSh -notmatch [regex]::Escape('active-profile.instructions.md')) { Add-Failure "setup.sh does not write active-profile.instructions.md." }
}

if ($failures.Count -gt 0) {
    Write-Host "check-profile-invariants: $($failures.Count) invariant(s) broken:" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  ::error::$_" }
    exit 1
}
Write-Host "check-profile-invariants: PASS - all profile overlay invariants hold." -ForegroundColor Green
exit 0
