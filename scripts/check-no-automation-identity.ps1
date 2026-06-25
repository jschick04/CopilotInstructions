<#
  check-no-automation-identity.ps1 - fail-closed gate: a commit's AUTHOR and COMMITTER identity must NOT be a
  disallowed automation identity (AGENTS.md s4.1). This script is the CANONICAL source of truth for the deterministic
  disallowed-automation matcher; AGENTS.md s4 and pre-commit.md s3a defer to it.

  HONEST CEILING (modeled-only; mirrors check-no-machine-paths). PRE-COMMIT mode runs `git var GIT_AUTHOR_IDENT` +
  `git var GIT_COMMITTER_IDENT` from inside the hook. `git commit` exports the resolved GIT_AUTHOR_* (including a
  `--author` override or the `--amend`-preserved author) into the hook environment, and `git var` reads it - so
  pre-commit catches new commits, `--amend`, and EVERY injection vector (config / `[includeIf]` / `git -c` / env /
  `--author`); `--amend --reset-author` passes (the author is reset to the current identity). It does NOT fire on
  `git cherry-pick` / `git rebase` / `git am` (git does not run the pre-commit hook for those replays) or under
  `git commit --no-verify` (the hook is bypassed); those are caught by RANGE mode (`-BaseRef`, reading each commit's
  actual `%an/%ae/%cn/%ce`) at pre-push (run-local-ci) + CI (the non-bypassable backstop). The matcher is MODELED-only:
  `[bot]`-suffixed accounts, the bare `Copilot` / `github-actions` names, the Copilot noreply email, and empty
  name/email. Unmodeled service principals and GitHub-mechanism identities like `web-flow` (`GitHub <noreply@github.com>`)
  are NOT matched and remain a prose-judgment concern (AGENTS.md s4.1).

  TWO MODES (one predicate), fail-closed - any git error -> exit 2; a finding -> exit 1; clean -> exit 0:
    (default / pre-commit)            `git var GIT_AUTHOR_IDENT` + `git var GIT_COMMITTER_IDENT` (the identity the
                                      about-to-be-created commit will use).
    -BaseRef <ref> [-HeadRef HEAD]    per-commit author+committer over BaseRef..HeadRef (ALL commits, including merges -
                                      identity policy applies to every attribution).
  -FetchBranch <name> does a fail-closed `git fetch origin <name>` first (so CI owns its own setup). -CiMode treats a
  0-commit range as a failure (a real PR always has >= 1 commit; 0 means a bad base ref).
#>
[CmdletBinding()]
param(
    [string] $BaseRef,
    [string] $HeadRef = 'HEAD',
    [string] $RepoRoot = '',
    [string] $FetchBranch,
    [switch] $CiMode,
    [switch] $Json
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/repo-root.psm1') -Force
try {
    $RepoRoot = Resolve-RepoRoot -Explicit $RepoRoot -ScriptRoot $PSScriptRoot -Anchors @('scripts/check-no-automation-identity.ps1') -RequireGitWorkTree
} catch {
    Write-Host "::error::$($_.Exception.Message)"
    exit 2
}

$script:ExitOk = 0
$script:ExitViolation = 1
$script:ExitInvocation = 2

function Invoke-Git {
    param([string[]] $GitArgs, [switch] $AllowFailure)
    $out = & git -C $RepoRoot @GitArgs 2>$null
    if ($LASTEXITCODE -ne 0 -and -not $AllowFailure) {
        Write-Host "::error::INVOCATION_FAILED: git $($GitArgs -join ' ') failed (exit $LASTEXITCODE) - refusing to run fail-open"
        exit $script:ExitInvocation
    }
    return $out
}

# Disallowed-automation predicate (the canonical matcher). Case-insensitive; applied to BOTH author and committer,
# NAME and EMAIL. The bare-name checks are EXACT (so a legitimate human like "Jane Copilot" passes); the `[bot]`
# check is an anchored suffix on the name or the email local-part (so "Abbott" and a mid-string `[bot]` do not
# match). web-flow ("GitHub <noreply@github.com>") matches none of these by design.
function Get-IdentityFindings {
    param([string] $Name, [string] $Email, [string] $Role, [string] $Label)
    $result = New-Object System.Collections.Generic.List[object]
    $cleanName = if ($null -ne $Name) { $Name.Trim() } else { '' }
    $cleanEmail = if ($null -ne $Email) { $Email.Trim() } else { '' }
    if ($cleanName -eq '') { $result.Add([pscustomobject]@{ Rule = 'empty-name'; Message = "$Label $Role name is empty (cannot attribute to a human)" }) }
    if ($cleanEmail -eq '') { $result.Add([pscustomobject]@{ Rule = 'empty-email'; Message = "$Label $Role email is empty (cannot attribute to a human)" }) }
    if ($cleanName -match '\[bot\]$' -or $cleanEmail -match '\[bot\]@') { $result.Add([pscustomobject]@{ Rule = 'bot-suffix'; Message = "$Label $Role identity is a [bot]-suffixed account: '$cleanName <$cleanEmail>'" }) }
    if ($cleanName -ieq 'copilot') { $result.Add([pscustomobject]@{ Rule = 'copilot'; Message = "$Label $Role name is the Copilot automation identity: '$cleanName'" }) }
    if ($cleanName -ieq 'github-actions') { $result.Add([pscustomobject]@{ Rule = 'github-actions'; Message = "$Label $Role name is the github-actions automation identity: '$cleanName'" }) }
    if ($cleanEmail -imatch '^[0-9]+\+copilot@users\.noreply\.github\.com$') { $result.Add([pscustomobject]@{ Rule = 'copilot-noreply'; Message = "$Label $Role email is the Copilot noreply identity: '$cleanEmail'" }) }
    return $result
}

function ConvertFrom-GitVarIdent {
    param([string] $Ident)
    if ($Ident -match '^(.*) <([^>]*)> \d+ [-+]\d{4}$') {
        return [pscustomobject]@{ Name = $matches[1]; Email = $matches[2] }
    }
    return $null
}

$findings = New-Object System.Collections.Generic.List[object]

if (-not $BaseRef) {
    # Pre-commit mode: the identity the about-to-be-created commit will use. `git commit` exports GIT_AUTHOR_* (a
    # --author override or the --amend-preserved author) into the hook env, which `git var` reads.
    foreach ($field in @(
            [pscustomobject]@{ Var = 'GIT_AUTHOR_IDENT'; Role = 'author' },
            [pscustomobject]@{ Var = 'GIT_COMMITTER_IDENT'; Role = 'committer' }
        )) {
        $raw = [string]((Invoke-Git @('var', $field.Var)) | Select-Object -First 1)
        $parsed = ConvertFrom-GitVarIdent -Ident $raw
        if ($null -eq $parsed) {
            Write-Host "::error::INVOCATION_FAILED: could not parse 'git var $($field.Var)' output: '$raw'"
            exit $script:ExitInvocation
        }
        foreach ($finding in (Get-IdentityFindings -Name $parsed.Name -Email $parsed.Email -Role $field.Role -Label 'pending commit')) { $findings.Add($finding) }
    }
    $scope = 'pending commit (git var author + committer)'
}
else {
    if ($FetchBranch) { Invoke-Git @('fetch', 'origin', $FetchBranch) | Out-Null }
    $commits = @(Invoke-Git @('rev-list', '--reverse', "$BaseRef..$HeadRef") | Where-Object { $_ })
    if ($commits.Count -eq 0) {
        if ($CiMode) { Write-Host "::error::no commits found in $BaseRef..$HeadRef; refusing to pass without checking"; exit $script:ExitInvocation }
        if (-not $Json) { Write-Host "check-no-automation-identity: PASS (0 commits in range $BaseRef..$HeadRef)" -ForegroundColor Green }
        else { [pscustomobject]@{ checker = 'check-no-automation-identity'; scope = "$BaseRef..$HeadRef"; finding_count = 0; status = 'pass'; findings = @() } | ConvertTo-Json -Depth 5 }
        exit $script:ExitOk
    }
    foreach ($sha in $commits) {
        # Unit-separator-delimited so empty fields and ordering are preserved (a name never contains 0x1f).
        $record = [string]((Invoke-Git @('show', '-s', '--format=%an%x1f%ae%x1f%cn%x1f%ce', $sha)) | Select-Object -First 1)
        $parts = $record -split ([char]0x1f)
        if ($parts.Count -lt 4) {
            Write-Host "::error::INVOCATION_FAILED: could not parse author/committer for commit $sha"
            exit $script:ExitInvocation
        }
        $short = $sha.Substring(0, [Math]::Min(8, $sha.Length))
        foreach ($finding in (Get-IdentityFindings -Name $parts[0] -Email $parts[1] -Role 'author' -Label "commit $short")) { $findings.Add($finding) }
        foreach ($finding in (Get-IdentityFindings -Name $parts[2] -Email $parts[3] -Role 'committer' -Label "commit $short")) { $findings.Add($finding) }
    }
    $scope = "$BaseRef..$HeadRef"
}

$exitCode = if ($findings.Count -gt 0) { $script:ExitViolation } else { $script:ExitOk }
if ($Json) {
    [pscustomobject]@{
        checker       = 'check-no-automation-identity'
        scope         = $scope
        finding_count = $findings.Count
        status        = if ($findings.Count -gt 0) { 'fail' } else { 'pass' }
        findings      = @($findings | ForEach-Object { [pscustomobject]@{ rule = $_.Rule; message = $_.Message } })
    } | ConvertTo-Json -Depth 5
}
else {
    if ($findings.Count -eq 0) {
        Write-Host "check-no-automation-identity: PASS (0 findings) [$scope]" -ForegroundColor Green
    }
    else {
        Write-Host "check-no-automation-identity: $($findings.Count) finding(s) [$scope]" -ForegroundColor Yellow
        $findings | ForEach-Object { Write-Host ("  ::error::[{0}] {1}" -f $_.Rule, $_.Message) }
    }
}
exit $exitCode
