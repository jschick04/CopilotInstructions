<#
  repo-root.psm1 - robust repo-root resolution shared by the CI checker scripts.

  Replaces the `$RepoRoot = (Get-Location).Path` default, which silently mis-resolved when a script
  was invoked from any directory other than the repo root (worst case: a checker scanned nothing and
  reported PASS). Resolution is candidate-validate-fall-through: the first candidate that satisfies the
  caller's machinery-specific anchor wins; cwd is NEVER a fallback (it was the bug). When no candidate
  validates, the resolver throws an INVOCATION_FAILED error so the caller can exit 2 (fail-closed) -
  it never returns a wrong-but-plausible root.

  Precedence:
    1. -Explicit (the script's -RepoRoot param) - validated; an invalid explicit value is a hard error
       (do not silently fall through a caller's deliberate choice).
    2. `git rev-parse --show-toplevel` from the current directory - handles CI, hooks, and any subdir.
    3. The script-suite parent (Split-Path $ScriptRoot -Parent, i.e. scripts/ -> repo root) - handles
       being invoked from outside the repo, and lets a wrong-but-valid outer git root (monorepo /
       vendored-without-own-.git) fall through to the script's own location.
    4. None validated -> throw INVOCATION_FAILED.

  Validation normalizes the candidate to an OS-native absolute path (no trailing separator), requires
  every -Anchors path to exist under it, and (when -RequireGitWorkTree) confirms it is inside a git
  work tree via `git -C <root> rev-parse --is-inside-work-tree` (worktree-safe; does NOT assume `.git`
  is a directory, which breaks linked worktrees where `.git` is a file).
#>
Set-StrictMode -Version Latest

function Resolve-RepoRoot {
    [CmdletBinding()]
    param(
        [AllowEmptyString()] [string] $Explicit = '',
        [Parameter(Mandatory)] [string] $ScriptRoot,
        [string[]] $Anchors = @(),
        [switch] $RequireGitWorkTree
    )

    $gitAvailable = [bool](Get-Command git -ErrorAction SilentlyContinue)

    function Test-RepoRootCandidate {
        param([string] $Candidate)
        if ([string]::IsNullOrWhiteSpace($Candidate)) { return $null }
        try { $normalized = (Resolve-Path -LiteralPath $Candidate -ErrorAction Stop).Path }
        catch { return $null }
        $trimmed = $normalized.TrimEnd('\', '/')
        if ($trimmed -and $trimmed -notmatch '^[A-Za-z]:$') { $normalized = $trimmed }
        foreach ($anchor in $Anchors) {
            if (-not (Test-Path -LiteralPath (Join-Path $normalized $anchor))) { return $null }
        }
        if ($RequireGitWorkTree) {
            if (-not $gitAvailable) { return $null }
            $inside = (& git -C $normalized rev-parse --is-inside-work-tree 2>$null)
            if ($LASTEXITCODE -ne 0 -or "$inside".Trim() -ne 'true') { return $null }
        }
        return $normalized
    }

    $anchorList = @($Anchors)
    $requirementParts = @()
    if ($anchorList.Count -gt 0) { $requirementParts += "anchor(s): $($anchorList -join ', ')" }
    if ($RequireGitWorkTree) { $requirementParts += 'a git work tree' }
    $requirementDesc = if ($requirementParts.Count -gt 0) { $requirementParts -join ' + ' } else { 'a resolvable repo root' }

    if (-not [string]::IsNullOrWhiteSpace($Explicit)) {
        $resolved = Test-RepoRootCandidate -Candidate $Explicit
        if ($resolved) { return $resolved }
        throw "INVOCATION_FAILED: -RepoRoot '$Explicit' is not a valid repo root (requires $requirementDesc)"
    }

    if ($gitAvailable) {
        $topLevel = (& git rev-parse --show-toplevel 2>$null)
        if ($LASTEXITCODE -eq 0 -and $topLevel) {
            $resolved = Test-RepoRootCandidate -Candidate ("$topLevel".Trim())
            if ($resolved) { return $resolved }
        }
    }

    $suiteParent = Split-Path -Parent $ScriptRoot
    $resolved = Test-RepoRootCandidate -Candidate $suiteParent
    if ($resolved) { return $resolved }

    throw "INVOCATION_FAILED: could not resolve a valid repo root from git top-level or the script location (requires $requirementDesc); pass -RepoRoot explicitly"
}

Export-ModuleMember -Function Resolve-RepoRoot
