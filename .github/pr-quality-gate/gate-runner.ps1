# PR Quality Gate Runner (PowerShell)
# Cross-platform via pwsh. See gate-runner.sh for bash twin.
# Spec: ../README.md (PR Quality Gate v5 design doc)

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $BaseSha,
    [Parameter(Mandatory)] [string] $HeadSha,
    [ValidateSet('full', 'triage', 'lint-only')] [string] $Mode = 'full',
    [string] $AllowedCloneUrlPattern = '^https?://.+/CopilotInstructions(\.git)?$',
    [switch] $AutoFetchCatalog,
    [int] $LockTimeoutSeconds = 30,
    [string] $ProjectRoot = (Get-Location).Path,
    [switch] $Verify,
    [string] $PrRef = ''
)

$ErrorActionPreference = 'Stop'
$script:RunnerVersion = '0.1.0'
$script:ExitCode = 0

function Write-Diag { param([string] $Msg) Write-Host -ForegroundColor Yellow "[gate-runner] $Msg" -NoNewline; Write-Host '' }
function Write-Err  { param([string] $Msg) [Console]::Error.WriteLine("[gate-runner ERROR] $Msg") }

function Exit-Runner { param([int] $Code, [string] $Reason)
    if ($Reason) { Write-Err $Reason }
    exit $Code
}

function Test-CloneValid {
    $clone = $env:COPILOT_INSTRUCTIONS_CLONE
    if (-not $clone) { Exit-Runner 3 'COPILOT_INSTRUCTIONS_CLONE env var not set. Set to your CopilotInstructions clone path.' }
    if (-not (Test-Path -PathType Container -LiteralPath $clone)) { Exit-Runner 3 "COPILOT_INSTRUCTIONS_CLONE points to '$clone' which is not a directory." }
    if (-not (Test-Path -PathType Container -LiteralPath (Join-Path $clone '.git'))) { Exit-Runner 3 "'$clone' does not contain a .git/ subdirectory; not a git clone." }
    $remoteUrl = & git -C $clone remote get-url origin 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $remoteUrl) { Exit-Runner 3 "Cannot read 'origin' remote URL from '$clone'." }
    if ($remoteUrl -notmatch $AllowedCloneUrlPattern) { Exit-Runner 3 "Remote URL '$remoteUrl' does not match AllowedCloneUrlPattern '$AllowedCloneUrlPattern'." }
    return $clone
}

function Invoke-AutoFetch { param([string] $Clone)
    if (-not $AutoFetchCatalog) { return }
    $dirty = & git -C $Clone status --porcelain '.github/pr-quality-gate/' 2>$null
    if ($dirty) { Exit-Runner 4 "Auto-fetch refused: uncommitted local changes in $Clone/.github/pr-quality-gate/:`n$dirty`nCommit, stash, or discard before -AutoFetchCatalog." }
    $currentBranch = & git -C $Clone rev-parse --abbrev-ref HEAD 2>$null
    & git -C $Clone fetch origin $currentBranch --depth 1 --quiet 2>$null
    & git -C $Clone checkout "origin/$currentBranch" -- '.github/pr-quality-gate/' 2>$null
}

function Get-FileRevision { param([string] $Clone, [string] $RelPath)
    $sha = & git -C $Clone log -1 --format=%H -- $RelPath 2>$null
    if (-not $sha) { Exit-Runner 2 "Cannot resolve revision for '$RelPath' in clone '$Clone'." }
    return $sha.Trim()
}

function Read-CatalogTable { param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) { Exit-Runner 2 "Catalog file not found: $Path" }
    $lines = Get-Content -LiteralPath $Path
    $entries = @()
    $slugs = @{}
    $lineNum = 0
    foreach ($line in $lines) {
        $lineNum++
        if ($line -match '^\s*<!--' -or $line -notmatch '^\|') { continue }
        if ($line -match '^\|\s*slug\s*\|' -or $line -match '^\|\s*-+\s*\|') { continue }
        $cells = ($line -split '(?<!\\)\|')
        # Drop leading + trailing empty from outer | delimiters; trim each cell. DO NOT filter empties (trailing columns may be intentionally empty).
        if ($cells.Count -lt 2) { Exit-Runner 2 "Malformed catalog row at line ${lineNum}: $line" }
        $cells = $cells[1..($cells.Count - 2)] | ForEach-Object { $_.Trim() }
        if ($cells.Count -lt 5) { Exit-Runner 2 "Malformed catalog row at line ${lineNum}: expected at least 5 cells (slug|scope_mode|params|review_pass_only_prompt|fp_slug[|tier]), got $($cells.Count)" }
        $slug = $cells[0]
        $scope = $cells[1]
        $paramsRaw = $cells[2] -replace '\\\|', '|'
        $reviewPrompt = $cells[3]
        $fpSlug = $cells[4]
        if ($cells.Count -ge 6 -and $cells[5]) {
            $tier = $cells[5]
            if ($tier -notin 'HIGH','MEDIUM','LOW') { Exit-Runner 2 "Invalid tier '$tier' at line ${lineNum}: expected HIGH | MEDIUM | LOW" }
        } else {
            [Console]::Error.WriteLine("[gate-runner WARNING] Catalog row '$slug' at line ${lineNum} uses legacy 5-cell schema (no tier column); defaulting to tier=MEDIUM. Add explicit tier in next catalog edit (sunset by next lightweight-gate-v5 catalog edit).")
            $tier = 'MEDIUM'
        }
        if ($slugs.ContainsKey($slug)) { Exit-Runner 2 "Duplicate slug '$slug' at line $lineNum" }
        $slugs[$slug] = $true
        if ($scope -notin 'diff-scoped','tree-scoped','hybrid','review-pass-only','checker-scoped') { Exit-Runner 2 "Invalid scope_mode '$scope' at line $lineNum" }
        try { $params = $paramsRaw | ConvertFrom-Json -ErrorAction Stop }
        catch { Exit-Runner 2 "Malformed JSON in params at line ${lineNum}: $($_.Exception.Message)" }
        # Cross-field validity
        switch ($scope) {
            'review-pass-only' { if (-not $reviewPrompt) { Exit-Runner 2 "scope_mode=review-pass-only requires non-empty review_pass_only_prompt at line $lineNum" } }
            'checker-scoped'   { if (-not $params.checker_id) { Exit-Runner 2 "scope_mode=checker-scoped requires params.checker_id at line $lineNum" }; if ($reviewPrompt) { Exit-Runner 2 "scope_mode=checker-scoped MUST have empty review_pass_only_prompt at line $lineNum" } }
            'diff-scoped'      { if (-not $params.pattern -or -not $params.glob -or $params.glob.Count -eq 0) { Exit-Runner 2 "scope_mode=diff-scoped requires non-empty params.pattern and params.glob at line $lineNum" }; if ($reviewPrompt) { Exit-Runner 2 "scope_mode=diff-scoped MUST have empty review_pass_only_prompt at line $lineNum" } }
            'tree-scoped'      { if (-not $params.pattern) { Exit-Runner 2 "scope_mode=tree-scoped requires non-empty params.pattern at line $lineNum" }; if ($reviewPrompt) { Exit-Runner 2 "scope_mode=tree-scoped MUST have empty review_pass_only_prompt at line $lineNum" } }
            'hybrid'           {
                if (-not $params.tree -or -not $params.tree.pattern) { Exit-Runner 2 "scope_mode=hybrid requires params.tree.pattern at line $lineNum" }
                if (-not $params.diff -or -not $params.diff.pattern -or -not $params.diff.glob -or $params.diff.glob.Count -eq 0) { Exit-Runner 2 "scope_mode=hybrid requires params.diff.pattern AND non-empty params.diff.glob at line $lineNum" }
                if ($reviewPrompt) { Exit-Runner 2 "scope_mode=hybrid MUST have empty review_pass_only_prompt at line $lineNum" }
            }
        }
        $entries += [pscustomobject]@{ Slug = $slug; ScopeMode = $scope; Params = $params; ReviewPrompt = $reviewPrompt; FpSlug = $fpSlug; Tier = $tier; Line = $lineNum }
    }
    return $entries
}

function Get-RgHits { param([string[]] $RgArgs, [string] $Pattern)
    $errFile = [System.IO.Path]::GetTempFileName()
    try {
        $out = & rg @RgArgs 2>$errFile
        if ($LASTEXITCODE -gt 1) {
            $rgErr = ((Get-Content -Raw -LiteralPath $errFile -ErrorAction SilentlyContinue) | Out-String).Trim()
            Exit-Runner 4 "rg exited with code $LASTEXITCODE for pattern '$Pattern': $rgErr"
        }
        if ($out) { return @($out -split "`n" | Where-Object { $_ }) }
        return @()
    } finally { Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue }
}

function Invoke-RgPattern { param([string[]] $Files, [string] $Pattern, [string[]] $Globs, [string] $TreeRoot)
    if (-not (Get-Command rg -ErrorAction SilentlyContinue)) { Exit-Runner 3 'ripgrep (rg) not found on PATH.' }
    if ($Files -and $Files.Count -gt 0) {
        # Filter by glob match AND by file-still-exists-at-HEAD (git diff includes deleted files which rg cannot read).
        $matched = $Files | Where-Object {
            $f = $_
            if (($Globs | Where-Object { $f -like $_ -or [System.IO.Path]::GetFileName($f) -like $_ }).Count -eq 0) { return $false }
            return (Test-Path -PathType Leaf -LiteralPath (Join-Path $TreeRoot $f))
        }
        if ($matched.Count -eq 0) { return @() }
        # Convert to full paths so rg can find them regardless of $PWD.
        $matched = $matched | ForEach-Object { Join-Path $TreeRoot $_ }
        return Get-RgHits -RgArgs (@('--line-number', '--no-heading', '--color', 'never', '--', $Pattern) + @($matched)) -Pattern $Pattern
    }
    $rgArgs = @('--line-number', '--no-heading', '--color', 'never')
    foreach ($g in $Globs) { $rgArgs += @('--glob', $g) }
    $rgArgs += @('--', $Pattern, $TreeRoot)
    return Get-RgHits -RgArgs $rgArgs -Pattern $Pattern
}

function Request-Lock { param([string] $LockPath, [int] $TimeoutSec)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $jitter = Get-Random -Minimum 50 -Maximum 250
    while ((Get-Date) -lt $deadline) {
        try {
            $fs = [System.IO.File]::Open($LockPath, 'CreateNew', 'Write', 'None')
            $meta = @{ pid = $PID; host = $env:COMPUTERNAME; session_id = [Guid]::NewGuid().ToString(); acquired_at = (Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json -Compress
            $bytes = [Text.Encoding]::UTF8.GetBytes($meta)
            $fs.Write($bytes, 0, $bytes.Length)
            $fs.Close()
            return $true
        } catch [System.IO.IOException] {
            if (Test-Path -LiteralPath $LockPath) {
                $age = (Get-Date) - (Get-Item -LiteralPath $LockPath).CreationTimeUtc
                if ($age.TotalMinutes -gt 5) {
                    $existing = Get-Content -LiteralPath $LockPath -Raw | ConvertFrom-Json
                    if ($existing.host -eq $env:COMPUTERNAME -and -not (Get-Process -Id $existing.pid -ErrorAction SilentlyContinue)) {
                        Write-Diag "Stale lock from pid $($existing.pid) at $($existing.acquired_at); breaking"
                        Remove-Item -LiteralPath $LockPath -Force
                        continue
                    }
                }
            }
            Start-Sleep -Milliseconds $jitter
            $jitter = [Math]::Min($jitter * 2, 5000)
        }
    }
    return $false
}

function Add-FindingsRows { param([string] $DataDir, [array] $Rows)
    $csv = Join-Path $DataDir 'findings.csv'
    $lock = "$csv.lock"
    if (-not (Request-Lock -LockPath $lock -TimeoutSec $LockTimeoutSeconds)) { Exit-Runner 4 "Could not acquire findings.csv lock within ${LockTimeoutSeconds}s" }
    try {
        if (-not (Test-Path -LiteralPath $csv)) { 'timestamp,revision,pattern_slug,classification,finding_brief,slate_mode,finding_type' | Out-File -LiteralPath $csv -Encoding utf8NoBOM -NoNewline; "`n" | Out-File -LiteralPath $csv -Encoding utf8NoBOM -Append -NoNewline }
        foreach ($r in $Rows) {
            $line = "$($r.timestamp),$($r.revision),$($r.pattern_slug),$($r.classification),`"$($r.finding_brief -replace '"', '""')`",$($r.slate_mode),$($r.finding_type)`n"
            $line | Out-File -LiteralPath $csv -Encoding utf8NoBOM -Append -NoNewline
        }
    } finally { Remove-Item -LiteralPath $lock -Force -ErrorAction SilentlyContinue }
}

# ===== main =====

$clone = Test-CloneValid
Invoke-AutoFetch -Clone $clone

# ===== Drift-safeguard: verify HIGH-TIER-SLUGS.md is in sync with pattern-catalog.md =====
# Panel-time secondary defense (primary is the .githooks/pre-commit hook).
# Catches stale clones where a contributor pulled an interim commit with stale ack file.
$syncScript = Join-Path $clone 'scripts/sync-critical-rules.ps1'
$catalogInClone = Join-Path $clone '.github/pr-quality-gate/pattern-catalog.md'
$outputInClone = Join-Path $clone '.github/pr-quality-gate/HIGH-TIER-SLUGS.md'
if (Test-Path -LiteralPath $syncScript) {
    & pwsh -NoProfile -File $syncScript -Verify -CatalogPath $catalogInClone -OutputPath $outputInClone 2>&1 | Out-String -Stream | ForEach-Object { Write-Diag $_ }
    if ($LASTEXITCODE -ne 0) {
        Exit-Runner 4 "HIGH-TIER-SLUGS.md is out of sync with pattern-catalog.md in clone '$clone'. Run: pwsh -File '$syncScript'"
    }
} else {
    Write-Diag "sync-critical-rules.ps1 not found in clone; skipping ack-sync drift check (clone may be at an older revision)."
}

$catalogPath = Join-Path $clone '.github/pr-quality-gate/pattern-catalog.md'
$catalogRevision = Get-FileRevision -Clone $clone -RelPath '.github/pr-quality-gate/pattern-catalog.md'
$prefsRevision = Get-FileRevision -Clone $clone -RelPath '.github/pr-quality-gate/coding-preferences.md'

$entries = Read-CatalogTable -Path $catalogPath
$diffFiles = & git -C $ProjectRoot diff --name-only "$BaseSha..$HeadSha" 2>$null
if ($LASTEXITCODE -ne 0) { Exit-Runner 4 "git diff failed for $BaseSha..$HeadSha" }
$diffFiles = $diffFiles -split "`n" | Where-Object { $_ }
$fileCount = $diffFiles.Count

$findings = @()
foreach ($e in $entries) {
    # Tier filter applies to ALL rule types: full runs everything; triage skips LOW; lint-only keeps HIGH only.
    if ($Mode -eq 'lint-only' -and $e.Tier -ne 'HIGH') { continue }
    if ($Mode -eq 'triage' -and $e.Tier -eq 'LOW') { continue }
    if ($e.ScopeMode -eq 'review-pass-only') {
        $findings += [pscustomobject]@{ slug = $e.Slug; hits = 'review-required'; sites = @(); scope_mode = $e.ScopeMode; review_prompt = $e.ReviewPrompt; tier = $e.Tier }
        continue
    }
    if ($e.ScopeMode -eq 'checker-scoped') {
        # Mechanized by a registry checker (run separately); emit a marker, not an rg pass.
        $findings += [pscustomobject]@{ slug = $e.Slug; hits = 'checker-mechanized'; sites = @(); scope_mode = $e.ScopeMode; review_prompt = $e.ReviewPrompt; tier = $e.Tier }
        continue
    }
    $rawHits = @()
    if ($e.ScopeMode -eq 'diff-scoped') {
        $rawHits = Invoke-RgPattern -Files $diffFiles -Pattern $e.Params.pattern -Globs $e.Params.glob -TreeRoot $ProjectRoot
    } elseif ($e.ScopeMode -eq 'tree-scoped') {
        $rawHits = Invoke-RgPattern -Files @() -Pattern $e.Params.pattern -Globs $e.Params.glob -TreeRoot $ProjectRoot
    } elseif ($e.ScopeMode -eq 'hybrid') {
        $treeHits = Invoke-RgPattern -Files @() -Pattern $e.Params.tree.pattern -Globs $e.Params.tree.glob -TreeRoot $ProjectRoot
        $diffHits = Invoke-RgPattern -Files $diffFiles -Pattern $e.Params.diff.pattern -Globs $e.Params.diff.glob -TreeRoot $ProjectRoot
        $rawHits = @($treeHits) + @($diffHits)
    }
    $sites = $rawHits | Sort-Object | Select-Object -Unique
    $findings += [pscustomobject]@{ slug = $e.Slug; hits = $sites.Count; sites = $sites; scope_mode = $e.ScopeMode; review_prompt = $e.ReviewPrompt; tier = $e.Tier }
}

# ===== Emit QUALITY GATE block =====
$ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$diffLine = "$BaseSha..$HeadSha ($fileCount files)"
$gateStatus = if ($findings | Where-Object { ($_.hits -is [int]) -and $_.hits -gt 0 }) { 'BLOCKED - findings present' } else { 'READY' }

# ===== Build HIGH-tier required-ack slug list (filtered by Mode) =====
$tierForMode = switch ($Mode) {
    'full'      { @('HIGH','MEDIUM','LOW') }
    'triage'    { @('HIGH','MEDIUM') }
    'lint-only' { @('HIGH') }
}
$requiredRuleAckSlugs = @($entries | Where-Object { $_.Tier -in $tierForMode -and $_.ScopeMode -eq 'review-pass-only' } | ForEach-Object { $_.Slug })

# ===== Build rg_flagged_sites map per slug (for reviewers' cross-reference) =====
$rgFlaggedSites = @{}
foreach ($f in $findings) {
    if ($f.scope_mode -eq 'review-pass-only') { continue }
    if (-not $f.sites -or $f.sites.Count -eq 0) { continue }
    $rgFlaggedSites[$f.slug] = $f.sites
}

# ===== Build anti-recidivism preamble (when -PrRef supplied) =====
$antiRecidivismSlugs = @()
$panelMissesCsvPath = Join-Path $clone '.github/pr-quality-gate/data/panel-misses.csv'
if ($PrRef -and (Test-Path -LiteralPath $panelMissesCsvPath)) {
    $priorRows = Import-Csv -LiteralPath $panelMissesCsvPath -Encoding UTF8 | Where-Object { $_.pr_ref -eq $PrRef }
    $antiRecidivismSlugs = @($priorRows | ForEach-Object { $_.proposed_catalog_slug } | Sort-Object -Unique | Where-Object { $_ })
}

@"
QUALITY GATE
  catalog_revision: $catalogRevision
  prefs_revision: $prefsRevision
  runner_version: $script:RunnerVersion
  panel_mode: $Mode
  base_sha: $BaseSha
  head_sha: $HeadSha
  diff_scope: $diffLine
  patterns_run: $($entries.Count)
  pr_ref: $PrRef
  required_rule_ack: [$(($requiredRuleAckSlugs | ForEach-Object { $_ }) -join ', ')]
"@

if ($antiRecidivismSlugs.Count -gt 0) {
    "  anti_recidivism_preamble:"
    "    pr_ref: $PrRef"
    "    prior_slugs:"
    foreach ($s in $antiRecidivismSlugs) { "      - $s" }
    "    reviewer_action_required: 'For each prior_slug, emit verified-no-recurrence: <slug> with fix_evidence (commit_sha or diff_hunk).'"
}

if ($rgFlaggedSites.Count -gt 0) {
    "  rg_flagged_sites:"
    foreach ($slug in $rgFlaggedSites.Keys | Sort-Object) {
        "    ${slug}:"
        foreach ($site in $rgFlaggedSites[$slug]) { "      - $site" }
    }
}

"  findings:"

foreach ($f in $findings) {
    $hitDisplay = if ($f.scope_mode -eq 'review-pass-only') { 'review-required' } else { $f.hits }
    "    - pattern: $($f.slug)`n      scope_mode: $($f.scope_mode)`n      tier: $($f.tier)`n      hits: $hitDisplay"
    if ($f.sites -and $f.sites.Count -gt 0) {
        "      sites:"
        foreach ($s in $f.sites) { "        - $s" }
    }
}

"  same_state_recheck: not-yet-rechecked"
"  gate_status: $gateStatus"

# ===== Append to findings.csv (skipped in -Verify read-only mode) =====
if (-not $Verify) {
    $dataDir = Join-Path $clone '.github/pr-quality-gate/data'
    $rows = @()
    foreach ($f in $findings) {
        if (-not ($f.hits -is [int]) -or $f.hits -le 0) { continue }
        foreach ($s in $f.sites) {
            $rows += @{ timestamp = $ts; revision = $catalogRevision; pattern_slug = $f.slug; classification = 'pending'; finding_brief = "$($f.slug) hit"; slate_mode = $Mode; finding_type = 'pattern' }
        }
    }
    if ($rows.Count -gt 0) {
        if (-not (Test-Path -LiteralPath $dataDir)) { New-Item -ItemType Directory -Force -Path $dataDir | Out-Null }
        Add-FindingsRows -DataDir $dataDir -Rows $rows
    }
}

if ($gateStatus -ne 'READY') { exit 1 } else { exit 0 }
