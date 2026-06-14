<#
.SYNOPSIS
    One-time setup for Copilot CLI custom instructions hosted in this repo.

.DESCRIPTION
    Configures the COPILOT_CUSTOM_INSTRUCTIONS_DIRS user-level environment
    variable to point the Copilot CLI at this cloned repo, so AGENTS.md plus
    the .github/instructions/*.instructions.md files load automatically.

    Idempotent: safe to re-run. Will not auto-delete the existing
    ~/.copilot/copilot-instructions.md monolith - backs it up only.

    Hardened:
      * Inspects Process / User / Machine env-var scopes; warns if a
        Machine-scope value would be shadowed by a new User-scope write.
      * Normalizes paths (full path + trim trailing separators + case-
        insensitive compare on Windows) so equivalent forms don't duplicate.
      * Records the prior env-var value and prints exact restore commands.
      * Prompt is bounded - invalid input retries up to 5 times, then aborts.

.NOTES
    Windows-only helper. macOS/Linux users follow README.md manual instructions.
#>

[CmdletBinding()]
param(
    [ValidateSet('full', 'lite')] [string] $Profile
)

$ErrorActionPreference = 'Stop'

if (-not $Profile) {
    throw "Required parameter -Profile <full|lite> was not supplied. Re-run, e.g.: .\setup.ps1 -Profile full"
}

function Write-Heading {
    param([string]$Text)
    Write-Host ""
    Write-Host "=== $Text ===" -ForegroundColor Cyan
}

function Get-NormalizedPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    try {
        $full = [System.IO.Path]::GetFullPath($Path)
    } catch {
        return $Path.Trim()
    }
    # Preserve roots like C:\ - TrimEnd would collapse to C:
    $root = [System.IO.Path]::GetPathRoot($full)
    if ($full -eq $root) { return $full }
    return $full.TrimEnd('\', '/')
}

function ConvertTo-EntryList {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
    return @(
        $Value -split ',' |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ }
    )
}

function Test-PathInList {
    param(
        [string[]]$Entries,
        [string]$Target
    )
    $normalizedTarget = Get-NormalizedPath -Path $Target
    foreach ($entry in $Entries) {
        if ((Get-NormalizedPath -Path $entry) -ieq $normalizedTarget) {
            return $true
        }
    }
    return $false
}

function Read-Choice {
    param(
        [string]$Prompt,
        [string[]]$ValidChoices,
        [int]$MaxAttempts = 5
    )
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $response = $null
        try {
            $response = Read-Host $Prompt
        } catch {
            throw "Read-Host failed (host may be non-interactive). Error: $_"
        }
        if ($null -eq $response) {
            throw "Read-Host returned null (likely non-interactive host or EOF on stdin). Aborting."
        }
        $trimmed = $response.Trim().ToUpperInvariant()
        if ($ValidChoices -contains $trimmed) { return $trimmed }
        Write-Host "Invalid choice '$response'. Expected one of: $($ValidChoices -join ', ') (attempt $attempt of $MaxAttempts)" -ForegroundColor Red
    }
    throw "No valid choice received after $MaxAttempts attempts. Aborting."
}

function Format-EnvValue {
    param([object]$Value)
    if ($null -eq $Value) { return '<unset>' }
    if ($Value -eq '') { return '<empty string>' }
    return [string]$Value
}

$repoRoot = Get-NormalizedPath -Path $PSScriptRoot
$envVarName = 'COPILOT_CUSTOM_INSTRUCTIONS_DIRS'
$homeFile = Join-Path $HOME '.copilot\copilot-instructions.md'

Write-Heading "Copilot CLI custom instructions setup"
Write-Host "Repo root: $repoRoot"

# --- 1. Validate repo layout ---------------------------------------------------

$agentsFile = Join-Path $repoRoot 'AGENTS.md'
$instructionsDir = Join-Path $repoRoot '.github\instructions'

if (-not (Test-Path $agentsFile)) {
    throw "Expected AGENTS.md at '$agentsFile'. Are you running setup.ps1 from the repo root?"
}
if (-not (Test-Path $instructionsDir)) {
    throw "Expected '$instructionsDir' to exist. Repo layout looks wrong."
}

$topicFiles = Get-ChildItem -Path $instructionsDir -Filter '*.instructions.md' -File -ErrorAction SilentlyContinue
Write-Host "Found AGENTS.md and $($topicFiles.Count) topic file(s) in .github/instructions/"

# --- 2. Inspect existing env var across all scopes -----------------------------

Write-Heading "Inspecting existing $envVarName"

$processValue = [Environment]::GetEnvironmentVariable($envVarName, 'Process')
$userValue    = [Environment]::GetEnvironmentVariable($envVarName, 'User')
$machineValue = [Environment]::GetEnvironmentVariable($envVarName, 'Machine')

Write-Host "  Process scope: $(Format-EnvValue $processValue)"
Write-Host "  User scope:    $(Format-EnvValue $userValue)"
Write-Host "  Machine scope: $(Format-EnvValue $machineValue)"

# Effective value seen by a fresh process: User overlays Machine.
# Treat $null as unset; treat empty string as a real (if unusual) value.
$effectiveValue = if ($null -ne $userValue) { $userValue } else { $machineValue }
Write-Host "  Effective for new processes: $(Format-EnvValue $effectiveValue)" -ForegroundColor Yellow

# Capture prior value for rollback messaging.
$priorUserValue = $userValue

if (($null -ne $machineValue) -and ($null -eq $userValue)) {
    Write-Host ""
    Write-Host "WARNING: A Machine-scope value exists but no User-scope value." -ForegroundColor Yellow
    Write-Host "         Writing a User-scope value below will SHADOW the Machine-scope value." -ForegroundColor Yellow
    Write-Host "         If that is not what you want, exit now (Ctrl+C) and edit the Machine value instead." -ForegroundColor Yellow
}

# --- 3. Configure the env var (User scope) -------------------------------------

Write-Heading "Configuring $envVarName (User scope)"

$entries = ConvertTo-EntryList -Value $userValue

if (Test-PathInList -Entries $entries -Target $repoRoot) {
    Write-Host "Already set to include this repo (after path normalization). No change needed." -ForegroundColor Green
} elseif ($entries.Count -eq 0) {
    Write-Host "Variable is unset at User scope. Setting to: $repoRoot"
    [Environment]::SetEnvironmentVariable($envVarName, $repoRoot, 'User')
    Write-Host "Set." -ForegroundColor Green
} else {
    Write-Host "Variable is currently set (User scope) to:" -ForegroundColor Yellow
    foreach ($entry in $entries) { Write-Host "  - $entry" }
    Write-Host ""
    Write-Host "Choose how to handle the existing value:" -ForegroundColor Yellow
    Write-Host "  [A] Append this repo to the existing list (comma-separated)"
    Write-Host "  [O] Overwrite with just this repo"
    Write-Host "  [S] Skip (no change)"
    $choice = Read-Choice -Prompt "Selection (A/O/S)" -ValidChoices @('A', 'O', 'S')
    switch ($choice) {
        'A' {
            $newValue = (($entries + $repoRoot) -join ',')
            [Environment]::SetEnvironmentVariable($envVarName, $newValue, 'User')
            Write-Host "Appended. New User-scope value: $newValue" -ForegroundColor Green
        }
        'O' {
            [Environment]::SetEnvironmentVariable($envVarName, $repoRoot, 'User')
            Write-Host "Overwrote. New User-scope value: $repoRoot" -ForegroundColor Green
        }
        'S' {
            Write-Host "Skipped - env var unchanged." -ForegroundColor Yellow
        }
    }
}

# --- 4. Print env-var rollback command ----------------------------------------

Write-Heading "Rollback (env var)"

if ($null -eq $priorUserValue) {
    Write-Host "Prior User-scope value was <unset>. To roll back, run:" -ForegroundColor Yellow
    Write-Host "  [Environment]::SetEnvironmentVariable('$envVarName', `$null, 'User')"
} else {
    Write-Host "Prior User-scope value was:" -ForegroundColor Yellow
    Write-Host "  $(Format-EnvValue $priorUserValue)"
    Write-Host "To roll back to that value, run:" -ForegroundColor Yellow
    $escapedPrior = $priorUserValue -replace "'", "''"
    Write-Host "  [Environment]::SetEnvironmentVariable('$envVarName', '$escapedPrior', 'User')"
}

# --- 5. Back up (do NOT delete) the legacy home-file monolith -----------------

Write-Heading "Checking for legacy ~/.copilot/copilot-instructions.md"

if (Test-Path $homeFile) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupPath = "$homeFile.backup-$stamp"
    Copy-Item -Path $homeFile -Destination $backupPath -Force
    Write-Host "Backed up to:" -ForegroundColor Green
    Write-Host "  $backupPath"
    Write-Host ""
    Write-Host "IMPORTANT - context-cost caveat during validation:" -ForegroundColor Yellow
    Write-Host "  The legacy file is STILL IN PLACE. Until you remove it, the Copilot CLI" -ForegroundColor Yellow
    Write-Host "  will load BOTH the legacy monolith AND the new AGENTS.md + topic files," -ForegroundColor Yellow
    Write-Host "  which means:" -ForegroundColor Yellow
    Write-Host "    * No always-loaded-context reduction yet (that's the whole point of the" -ForegroundColor Yellow
    Write-Host "      split - it only kicks in once the legacy file is gone)." -ForegroundColor Yellow
    Write-Host "    * Possibly conflicting / duplicate rules in the same session (the docs" -ForegroundColor Yellow
    Write-Host "      describe conflict resolution as non-deterministic)." -ForegroundColor Yellow
    Write-Host "    * /instructions can show the new files loading correctly while you're" -ForegroundColor Yellow
    Write-Host "      still paying the old context cost." -ForegroundColor Yellow
    Write-Host "  Use this validation window to confirm routing only, then remove the" -ForegroundColor Yellow
    Write-Host "  legacy file with:" -ForegroundColor Yellow
    Write-Host "    Remove-Item '$homeFile'"
    Write-Host "  (Restore from the backup above if anything goes wrong.)" -ForegroundColor Yellow
} else {
    Write-Host "No legacy file found. Nothing to back up." -ForegroundColor Green
}

# --- 6. Print validation steps -------------------------------------------------

Write-Heading "Validation steps"
Write-Host @"
1. Close all open 'copilot' terminal sessions.
   (Environment variables do not propagate to already-running processes.)

2. Open a fresh PowerShell window.

3. cd into a project folder of your choice (or stay in this repo).

4. Launch the CLI:
       copilot

5. Inside the session, run:
       /instructions

   Confirm:
     - AGENTS.md from '$repoRoot' is listed.
     - When the cwd contains *.cs files, csharp.instructions.md appears.
     - When the cwd contains *.css files, css.instructions.md appears.
     - And so on for the other topic files.

6. Once verified, remove the legacy file (if it existed):
       Remove-Item '$homeFile'
"@

# --- Configure active profile (full | lite) -----------------------------------

Write-Heading "Configuring active profile: $Profile"

$profileTemplate  = Join-Path $repoRoot "profiles\$Profile\profile.instructions.md"
$activeProfileFile = Join-Path $repoRoot '.github\instructions\active-profile.instructions.md'

if (-not (Test-Path $profileTemplate)) {
    throw "Profile template not found: '$profileTemplate'. Expected profiles\full\ and profiles\lite\ in the repo."
}

if (Test-Path $activeProfileFile) {
    $sameContent = (Get-FileHash -Path $activeProfileFile -Algorithm SHA256).Hash -eq (Get-FileHash -Path $profileTemplate -Algorithm SHA256).Hash
    if ($sameContent) {
        Write-Host "Active profile already '$Profile' and current. No change." -ForegroundColor Green
    } else {
        Copy-Item -Path $profileTemplate -Destination $activeProfileFile -Force
        Write-Host "Refreshed active profile to '$Profile' (was a different or stale profile)." -ForegroundColor Green
    }
} else {
    Copy-Item -Path $profileTemplate -Destination $activeProfileFile -Force
    Write-Host "Active profile set to '$Profile'." -ForegroundColor Green
}

Write-Host "  Wrote $activeProfileFile (gitignored; per-machine; never committed)."
Write-Host "  After 'git pull', re-run this script to refresh the active file if the template changed." -ForegroundColor Yellow
Write-Host "  To revert to full-default behavior, delete it: Remove-Item '$activeProfileFile'" -ForegroundColor Yellow

# --- 7. Configure git hook path (catalog-sync drift safeguard) ----------------

Write-Heading "Configuring git hooks path"

$gitDir = Join-Path $repoRoot '.git'
if (-not (Test-Path $gitDir)) {
    Write-Host "WARNING: .git directory not found at '$gitDir'. Skipping hooks config - this script is not running inside a git clone." -ForegroundColor Yellow
} else {
    $hooksDir = Join-Path $repoRoot '.githooks'
    if (-not (Test-Path $hooksDir)) {
        Write-Host "WARNING: .githooks directory not found at '$hooksDir'. Skipping hooks config - the committed hook directory is missing." -ForegroundColor Yellow
    } else {
        $currentHooksPath = & git -C $repoRoot config --get core.hooksPath 2>$null
        $hooksPathScope = $null
        if ($LASTEXITCODE -eq 0 -and $currentHooksPath) {
            $currentHooksPath = $currentHooksPath.Trim()
            # Detect the scope so we can surface where the existing setting lives.
            $scopeOutput = & git -C $repoRoot config --show-scope --get core.hooksPath 2>$null
            if ($LASTEXITCODE -eq 0 -and $scopeOutput) {
                $hooksPathScope = ($scopeOutput -split '\s+', 2)[0]
            }
        }
        if ($currentHooksPath -and $currentHooksPath -ne '.githooks') {
            Write-Host "WARNING: core.hooksPath is already set:" -ForegroundColor Yellow
            Write-Host "  Current value: $currentHooksPath"
            if ($hooksPathScope) { Write-Host "  Set at scope:  $hooksPathScope" }
            Write-Host "  Repo expects:  .githooks"
            Write-Host ""
            Write-Host "Choose how to handle this:" -ForegroundColor Yellow
            Write-Host "  [O] Overwrite (set --local .githooks; this repo's hook will run; other scopes preserved but shadowed for this repo)"
            Write-Host "  [S] Skip (existing value preserved; catalog-sync hook will NOT run on commit)"
            $choice = Read-Choice -Prompt "Selection (O/S)" -ValidChoices @('O', 'S')
            switch ($choice) {
                'O' {
                    & git -C $repoRoot config --local core.hooksPath .githooks 2>&1 | Out-Null
                    if ($LASTEXITCODE -eq 0) { Write-Host "Set core.hooksPath = .githooks (local scope)." -ForegroundColor Green }
                    else { Write-Host "ERROR: git config failed. Run manually: git config --local core.hooksPath .githooks" -ForegroundColor Red }
                }
                'S' {
                    Write-Host "Skipped. Existing core.hooksPath preserved. CI workflow catalog-sync-check.yml will still verify on PR." -ForegroundColor Yellow
                }
            }
        } else {
            & git -C $repoRoot config --local core.hooksPath .githooks 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Set core.hooksPath = .githooks (local scope)." -ForegroundColor Green
                Write-Host "  Pre-commit hook will verify HIGH-TIER-SLUGS.md stays in sync with pattern-catalog.md." -ForegroundColor Green
            } else {
                Write-Host "ERROR: git config failed. Run manually: git -C `"$repoRoot`" config --local core.hooksPath .githooks" -ForegroundColor Red
            }
        }
    }
}

Write-Heading "Done"
