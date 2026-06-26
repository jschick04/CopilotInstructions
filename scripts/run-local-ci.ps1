<#
  run-local-ci.ps1 - Fix B local-CI mirror + anti-drift coverage gate.

  Two modes:
    (default)       LOOP-TIGHTENER: run every check the workflows run, locally, before push. Best-effort; surfaces
                    failures so you catch them BEFORE the CI round. Not the gate (CI is); just tightens the loop.
    -CoverageOnly   THE GATE (required CI job): verify mirror completeness WITHOUT running the checks. Structural rule
                    "checks are scripts": every step across .github/workflows/*.yml AND .github/actions/**/action.yml must
                    be EXACTLY ONE of (a) a single-line invocation of a scripts/ script this mirror also invokes, or
                    (b) a `uses:` on the anchored actions/-org scaffolding allowlist. Anything else FAILS. YAML-structure
                    aware (keys to the run:/uses: scalar; ignores name:/env:/comments). Fail-closed + manifest counts.

  $mirror is the SINGLE SOURCE of which scripts the workflows invoke: it both drives the local run AND is the allow-set
  the coverage gate checks workflow invocations against. Adding a CI check = adding a script here; otherwise coverage fails.
#>
[CmdletBinding()]
param(
    [string] $RepoRoot = '',
    [string] $BaseBranch = 'main',
    [switch] $CoverageOnly
)
# Only enable strict mode + stop-on-error when INVOKED, not when dot-sourced by tests (else they leak into the caller scope).
if ($MyInvocation.InvocationName -ne '.') {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
}

Import-Module (Join-Path $PSScriptRoot 'lib/repo-root.psm1') -Force
$pwshExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { 'pwsh' } else { 'powershell' }
$baseRef = "origin/$BaseBranch"

# --- SINGLE SOURCE OF TRUTH: every scripts/ entrypoint the workflows invoke (excl. this harness itself). -----------
$mirror = @(
    [pscustomobject]@{ Name = 'playbook path refs';          Script = 'scripts/check-playbook-refs.ps1';               LocalArgs = @();                     EnvSkippable = $false }
    [pscustomobject]@{ Name = 'playbook-refs unit tests';    Script = 'scripts/tests/check-playbook-refs.tests.ps1';    LocalArgs = @();                     EnvSkippable = $false }
    [pscustomobject]@{ Name = 'comment-audit unit tests';    Script = 'scripts/tests/check-comment-audit.tests.ps1';   LocalArgs = @();                     EnvSkippable = $false }
    [pscustomobject]@{ Name = 'panel-ledger unit tests';   Script = 'scripts/tests/check-post-code-change.tests.ps1';LocalArgs = @();                     EnvSkippable = $false }
    [pscustomobject]@{ Name = 'hygiene-signals unit tests';Script = 'scripts/tests/hygiene-signals.tests.ps1';      LocalArgs = @();                     EnvSkippable = $false }
    [pscustomobject]@{ Name = 'read-receipts unit tests';  Script = 'scripts/tests/check-read-receipts.tests.ps1';   LocalArgs = @();                     EnvSkippable = $false }
    [pscustomobject]@{ Name = 'diff-consistency (commits)';  Script = 'scripts/check-diff-consistency-ci.ps1';         LocalArgs = @('-BaseRef', $baseRef); EnvSkippable = $false }
    [pscustomobject]@{ Name = 'diff-consistency unit tests'; Script = 'scripts/tests/check-diff-consistency.tests.ps1';LocalArgs = @();                     EnvSkippable = $false }
    [pscustomobject]@{ Name = 'checker-registry parity';     Script = 'scripts/check-checker-registry.ps1';            LocalArgs = @();                     EnvSkippable = $false }
    [pscustomobject]@{ Name = 'commit-message format';       Script = 'scripts/check-commit-message.ps1';              LocalArgs = @('-BaseRef', $baseRef); EnvSkippable = $false }
    [pscustomobject]@{ Name = 'commit-message unit tests';   Script = 'scripts/tests/check-commit-message.tests.ps1';  LocalArgs = @();                     EnvSkippable = $false }
    [pscustomobject]@{ Name = 'markdown size budgets';       Script = 'scripts/check-md-size.ps1';                     LocalArgs = @();                     EnvSkippable = $false }
    [pscustomobject]@{ Name = 'smart-punctuation ban';       Script = 'scripts/check-no-smart-punctuation.ps1';        LocalArgs = @();                     EnvSkippable = $false }
    [pscustomobject]@{ Name = 'smart-punctuation unit tests'; Script = 'scripts/tests/check-no-smart-punctuation.tests.ps1'; LocalArgs = @();                EnvSkippable = $false }
    [pscustomobject]@{ Name = 'repo-root unit tests';         Script = 'scripts/tests/repo-root.tests.ps1';                    LocalArgs = @();                     EnvSkippable = $false }
    [pscustomobject]@{ Name = 'audit-note helpers unit tests'; Script = 'scripts/tests/audit-note-helpers.tests.ps1';           LocalArgs = @();                     EnvSkippable = $false }
    [pscustomobject]@{ Name = 'audit-notes prepush unit tests'; Script = 'scripts/tests/check-audit-notes-prepush.tests.ps1';    LocalArgs = @();                     EnvSkippable = $false }
    [pscustomobject]@{ Name = 'structural-conformance unit tests'; Script = 'scripts/tests/check-structural-conformance.tests.ps1'; LocalArgs = @();                  EnvSkippable = $false }
    [pscustomobject]@{ Name = 'signoff unit tests';       Script = 'scripts/tests/check-signoff.tests.ps1';              LocalArgs = @();                     EnvSkippable = $false }
    [pscustomobject]@{ Name = 'duplication unit tests';   Script = 'scripts/tests/check-duplication.tests.ps1';          LocalArgs = @();                     EnvSkippable = $false }
    [pscustomobject]@{ Name = 'local-CI harness unit tests'; Script = 'scripts/tests/run-local-ci.tests.ps1';            LocalArgs = @();                     EnvSkippable = $false }
    [pscustomobject]@{ Name = 'structural conformance';   Script = 'scripts/check-structural-conformance.ps1';           LocalArgs = @('-BaseRef', $baseRef); EnvSkippable = $false }
    [pscustomobject]@{ Name = 'duplication check';        Script = 'scripts/check-duplication.ps1';                      LocalArgs = @('-BaseRef', $baseRef); EnvSkippable = $false }
    [pscustomobject]@{ Name = 'profile invariants';          Script = 'scripts/check-profile-invariants.ps1';          LocalArgs = @();                     EnvSkippable = $false }
    [pscustomobject]@{ Name = 'critical-rules sync verify';  Script = 'scripts/sync-critical-rules.ps1';               LocalArgs = @('-Verify');            EnvSkippable = $false }
    [pscustomobject]@{ Name = 'sync pwsh==bash parity';      Script = 'scripts/check-sync-parity.ps1';                 LocalArgs = @();                     EnvSkippable = $true }
    [pscustomobject]@{ Name = 'catalog generator verify';    Script = 'scripts/verify-pattern-catalog.ps1';            LocalArgs = @();                     EnvSkippable = $false }
    [pscustomobject]@{ Name = 'lint (PSScriptAnalyzer)';      Script = 'scripts/check-lint.ps1';                        LocalArgs = @();                     EnvSkippable = $false }
    [pscustomobject]@{ Name = 'lint unit tests';             Script = 'scripts/tests/check-lint.tests.ps1';            LocalArgs = @();                     EnvSkippable = $false }
    [pscustomobject]@{ Name = 'panel-artifact scan';         Script = 'scripts/check-no-panel-artifacts.ps1';          LocalArgs = @();                     EnvSkippable = $false }
    [pscustomobject]@{ Name = 'panel-artifact unit tests';   Script = 'scripts/tests/check-no-panel-artifacts.tests.ps1'; LocalArgs = @();                  EnvSkippable = $false }
    [pscustomobject]@{ Name = 'pr-text leakage scan';        Script = 'scripts/check-pr-text.ps1';                     LocalArgs = @();                     EnvSkippable = $false }
    [pscustomobject]@{ Name = 'pr-text unit tests';          Script = 'scripts/tests/check-pr-text.tests.ps1';         LocalArgs = @();                     EnvSkippable = $false }
    [pscustomobject]@{ Name = 'machine-path scan';           Script = 'scripts/check-no-machine-paths.ps1';            LocalArgs = @('-BaseRef', $baseRef);    EnvSkippable = $false }
    [pscustomobject]@{ Name = 'machine-path unit tests';     Script = 'scripts/tests/check-no-machine-paths.tests.ps1'; LocalArgs = @();                    EnvSkippable = $false }
    [pscustomobject]@{ Name = 'automation-identity scan';    Script = 'scripts/check-no-automation-identity.ps1';       LocalArgs = @('-BaseRef', $baseRef); EnvSkippable = $false }
    [pscustomobject]@{ Name = 'automation-identity unit tests'; Script = 'scripts/tests/check-no-automation-identity.tests.ps1'; LocalArgs = @();            EnvSkippable = $false }
    [pscustomobject]@{ Name = 'PR quality gate rg-battery';   Script = 'scripts/run-quality-gate-ci.ps1';                LocalArgs = @('-BaseRef', $baseRef); EnvSkippable = $false }
)
# The harness invokes itself in the coverage CI job; it is not a check to mirror.
$harnessSelf = 'scripts/run-local-ci.ps1'
$allowedScripts = @($mirror.Script) + $harnessSelf
# Anchored scaffolding allowlist (exact actions/-org names; a local ./.github/actions/ masquerade is recursed, not allowlisted).
$scaffoldPatterns = @('^actions/checkout@', '^actions/setup-[a-z0-9-]+@')

function Get-Indent {
    param([string] $Line)
    $m = [regex]::Match($Line, '^[ \t]*')
    return $m.Value
}

function Test-ScriptInvocation {
    param([string] $Cmd)
    $t = $Cmd.Trim()
    if ($t -match '&&|\|\||;|\|') { return $null }   # chained / piped extra logic is not a clean single invocation
    $m = [regex]::Match($t, '^(?:(?:pwsh|pwsh\.exe|powershell|powershell\.exe|bash|sh)\s+(?:-\S+\s+)*)?(?:\./)?(scripts/[A-Za-z0-9_./-]+\.(?:ps1|sh))(?:\s|$)')
    if (-not $m.Success) { return $null }
    $path = $m.Groups[1].Value -replace '\\', '/'
    if (($path -split '/') -contains '..') { return $null }   # reject path traversal (scripts/../foo.ps1 escapes scripts/)
    return $path
}

function Test-MirrorCoverage {
    param(
        [object[]] $WorkflowFiles,
        [object[]] $CompositeFiles = @(),
        [string[]] $MirrorScripts,
        [string] $HarnessSelf,
        [string[]] $ScaffoldPatterns,
        [string] $RootForRel,
        [int] $MinWorkflows = 4,
        [int] $MinSteps = 8,
        [int] $MinInvocations = 6
    )
    $failures = New-Object System.Collections.Generic.List[string]
    $invokedScripts = New-Object System.Collections.Generic.List[string]
    $counts = [ordered]@{ workflow_files = 0; composite_actions = 0; steps = 0; scaffolding_uses = 0; script_invocations = 0 }
    $allowedScripts = @($MirrorScripts) + $HarnessSelf
    $counts.workflow_files = @($WorkflowFiles).Count
    $counts.composite_actions = @($CompositeFiles).Count

    if (@($WorkflowFiles).Count -eq 0) {
        $failures.Add("no workflow files found under .github/workflows (glob matched nothing) - refusing to pass")
        return [pscustomobject]@{ Failures = $failures; Counts = $counts }
    }

    foreach ($file in @($WorkflowFiles) + @($CompositeFiles)) {
        $rel = ($file.FullName -replace [regex]::Escape((Resolve-Path -LiteralPath $RootForRel).Path), '').TrimStart('\', '/') -replace '\\', '/'
        $text = [System.IO.File]::ReadAllText($file.FullName) -replace "`r`n", "`n"
        $lines = $text -split "`n"

        # Fail-closed on constructs a line-scan cannot safely scope.
        $bad = $false
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $ln = $lines[$i]
            if ($ln -match '^\s*---\s*$' -and $i -gt 0) { $failures.Add("${rel}: multi-document YAML (---) is not supported - fail-closed"); $bad = $true; break }
            if ($ln -match "`t") { $failures.Add("${rel}:$($i+1): tab character is not supported anywhere on the line (the structure scan is column-based; use spaces) - fail-closed"); $bad = $true; break }
            if ($ln -match ':\s+[&*][A-Za-z0-9_]') { $failures.Add("${rel}:$($i+1): YAML anchor/alias is not supported - fail-closed"); $bad = $true; break }
        }
        if ($bad) { continue }

        # Reconciliation counters: every raw uses:/run: key must be accounted for by a classified step.
        $rawUses = @($lines | Where-Object { $_ -match '^\s*(-\s+)?uses:\s*\S' }).Count
        $rawRun = @($lines | Where-Object { $_ -match '^\s*(-\s+)?run:\s*' }).Count
        $classifiedUses = 0; $classifiedRun = 0

        $idx = 0
        while ($idx -lt $lines.Count) {
            if ($lines[$idx] -match '^(\s*)steps:\s*$') {
                $stepsIndent = $matches[1].Length
                $idx++
                $itemIndent = $null
                while ($idx -lt $lines.Count) {
                    $line = $lines[$idx]
                    if ($line.Trim() -eq '' -or $line -match '^\s*#') { $idx++; continue }
                    $indent = (Get-Indent $line).Length
                    if ($indent -le $stepsIndent) { break }                      # left the steps block
                    if ($line -notmatch '^\s*-\s') {                              # content under a step but not a new item
                        if ($null -eq $itemIndent) { $failures.Add("${rel}: malformed steps block near line $($idx+1) - fail-closed"); }
                        $idx++; continue
                    }
                    if ($null -eq $itemIndent) { $itemIndent = $indent }
                    $stepLines = New-Object System.Collections.Generic.List[string]
                    $stepLines.Add($line); $idx++
                    while ($idx -lt $lines.Count) {
                        $l2 = $lines[$idx]
                        if ($l2.Trim() -eq '') { $stepLines.Add($l2); $idx++; continue }
                        $ind2 = (Get-Indent $l2).Length
                        if ($ind2 -le $itemIndent) { break }
                        $stepLines.Add($l2); $idx++
                    }
                    $counts.steps++

                    $stepText = $stepLines -join "`n"
                    $usesMatch = [regex]::Match($stepText, '(?m)^\s*(?:-\s+)?uses:\s*(\S+)')
                    $runMatch = [regex]::Match($stepText, '(?m)^\s*(?:-\s+)?run:\s*(.*)$')
                    $hasUses = $usesMatch.Success
                    $hasRun = $runMatch.Success
                    if ($hasUses -and $hasRun) { $failures.Add("${rel}: a step has BOTH uses: and run: - fail-closed"); continue }
                    if ($hasUses) {
                        $classifiedUses++
                        $usesVal = $usesMatch.Groups[1].Value
                        $isScaffold = $false
                        foreach ($p in $ScaffoldPatterns) { if ($usesVal -match $p) { $isScaffold = $true; break } }
                        if ($isScaffold) { $counts.scaffolding_uses++ }
                        else { $failures.Add("${rel}: 'uses: $usesVal' is not on the anchored scaffolding allowlist (checks must be scripts; local composite actions are recursed, not allowlisted)") }
                        continue
                    }
                    if ($hasRun) {
                        $classifiedRun++
                        $runHead = $runMatch.Groups[1].Value.Trim()
                        $cmdLines = @()
                        if ($runHead -eq '' -or $runHead -match '^[|>][-+]?\d*\s*$') {
                            $bodyLines = @()
                            $afterRun = $false
                            foreach ($sl in $stepLines) {
                                if (-not $afterRun) { if ($sl -match '^\s*(?:-\s+)?run:\s*') { $afterRun = $true }; continue }
                                if ($sl.Trim() -eq '' -or $sl -match '^\s*#') { continue }
                                $bodyLines += $sl.Trim()
                            }
                            $cmdLines = @($bodyLines)
                        }
                        else { $cmdLines = @($runHead) }

                        $stepScripts = New-Object System.Collections.Generic.List[string]
                        foreach ($cmdLine in $cmdLines) {
                            $script = Test-ScriptInvocation $cmdLine
                            if ($null -ne $script) { $stepScripts.Add($script); continue }
                            # Fail-closed: every executable line in a run step must be a
                            # clean mirrored scripts/ invocation. An inline shell/pwsh line would not be
                            # mirrored by run-local-ci, so CI could run logic the local gate never sees.
                            # Put any base-ref / setup in a step env: (ignored here) or in the script.
                            $failures.Add("${rel}: run step has a non-script executable line '$cmdLine' (checks must be a clean scripts/ invocation; move setup into the mirrored script or a step env:)")
                        }
                        if ($stepScripts.Count -eq 0) { $failures.Add("${rel}: run step has no clean scripts/ invocation"); continue }
                        foreach ($script in $stepScripts) {
                            $counts.script_invocations++
                            $invokedScripts.Add($script)
                            if ($script -ne $harnessSelf -and $allowedScripts -notcontains $script) {
                                $failures.Add("${rel}: invokes '$script' which run-local-ci.ps1 does NOT mirror (add it to `$mirror)")
                            }
                        }
                        continue
                    }
                    $failures.Add("${rel}: a step has neither uses: nor run: - fail-closed (unclassifiable)")
                }
                continue
            }
            $idx++
        }

        if ($rawUses -ne $classifiedUses) { $failures.Add("${rel}: $rawUses 'uses:' keys but $classifiedUses classified as steps (un-enumerated use - e.g. a job-level reusable workflow) - fail-closed") }
        if ($rawRun -ne $classifiedRun) { $failures.Add("${rel}: $rawRun 'run:' keys but $classifiedRun classified as steps - fail-closed") }
    }

    # Reverse direction: every script the mirror declares must actually be invoked by some workflow (no dead mirror rows).
    foreach ($ms in $MirrorScripts) {
        if (@($invokedScripts) -notcontains $ms) {
            $failures.Add("mirror row '$ms' is not invoked by any workflow (dead mirror entry or a workflow drifted)")
        }
    }

    # Anti-vacuous floors (prevent green-by-finding-nothing).
    if ($counts.workflow_files -lt $MinWorkflows) { $failures.Add("only $($counts.workflow_files) workflow files (expected >= $MinWorkflows) - suspicious, fail-closed") }
    if ($counts.steps -lt $MinSteps) { $failures.Add("only $($counts.steps) steps discovered (expected >= $MinSteps) - suspicious, fail-closed") }
    if ($counts.script_invocations -lt $MinInvocations) { $failures.Add("only $($counts.script_invocations) script invocations (expected >= $MinInvocations) - suspicious, fail-closed") }

    return [pscustomobject]@{ Failures = $failures; Counts = $counts }
}

# The file can be dot-sourced (e.g. by tests) to load the functions WITHOUT running either mode.
if ($MyInvocation.InvocationName -eq '.') { return }

try {
    $RepoRoot = Resolve-RepoRoot -Explicit $RepoRoot -ScriptRoot $PSScriptRoot -Anchors @('scripts/run-local-ci.ps1', '.github/workflows')
} catch {
    Write-Host "::error::$($_.Exception.Message)"
    exit 2
}

$wfDir = Join-Path $RepoRoot '.github/workflows'
$workflowFiles = @()
if (Test-Path -LiteralPath $wfDir) { $workflowFiles = @(Get-ChildItem -LiteralPath $wfDir -File | Where-Object { $_.Extension -in '.yml', '.yaml' }) }
$actionsDir = Join-Path $RepoRoot '.github/actions'
$compositeFiles = @()
if (Test-Path -LiteralPath $actionsDir) { $compositeFiles = @(Get-ChildItem -Recurse -LiteralPath $actionsDir -File | Where-Object { $_.Name -in 'action.yml', 'action.yaml' }) }

if ($CoverageOnly) {
    $result = Test-MirrorCoverage -WorkflowFiles $workflowFiles -CompositeFiles $compositeFiles -MirrorScripts @($mirror.Script) -HarnessSelf $harnessSelf -ScaffoldPatterns $scaffoldPatterns -RootForRel $RepoRoot
    $c = $result.Counts
    Write-Host "run-local-ci coverage manifest:" -ForegroundColor Cyan
    Write-Host ("  workflow files: {0} | composite actions: {1} | steps: {2} | scaffolding uses: {3} | script invocations: {4}" -f $c.workflow_files, $c.composite_actions, $c.steps, $c.scaffolding_uses, $c.script_invocations)
    if ($result.Failures.Count -gt 0) {
        Write-Host "run-local-ci -CoverageOnly: FAIL ($($result.Failures.Count) issue(s)):" -ForegroundColor Red
        $result.Failures | ForEach-Object { Write-Host "  ::error::$_" }
        exit 1
    }
    Write-Host "run-local-ci -CoverageOnly: PASS - every workflow check is a mirrored script or anchored scaffolding." -ForegroundColor Green
    exit 0
}

Write-Host "run-local-ci: running $($mirror.Count) checks locally (loop-tightener; CI is the authoritative gate)..." -ForegroundColor Cyan
& git -C $RepoRoot fetch origin $BaseBranch 2>$null | Out-Null   # best-effort; non-fatal if offline

$results = New-Object System.Collections.Generic.List[object]
Push-Location $RepoRoot
try {
    foreach ($m in $mirror) {
        $scriptPath = Join-Path $RepoRoot $m.Script
        if (-not (Test-Path -LiteralPath $scriptPath)) {
            $results.Add([pscustomobject]@{ Name = $m.Name; Status = 'MISSING'; Exit = -1 }); continue
        }
        Write-Host "`n=== $($m.Name) ($($m.Script)) ===" -ForegroundColor Cyan
        & $pwshExe (@('-NoProfile', '-File', $scriptPath) + @($m.LocalArgs))
        $code = $LASTEXITCODE
        $status = if ($code -eq 0) { 'PASS' } elseif ($code -eq 2 -and $m.EnvSkippable) { 'SKIP(env)' } else { 'FAIL' }
        $results.Add([pscustomobject]@{ Name = $m.Name; Status = $status; Exit = $code })
    }
} finally { Pop-Location }

Write-Host "`n================ run-local-ci summary ================" -ForegroundColor Cyan
$results | ForEach-Object {
    $color = if ($_.Status -eq 'PASS') { 'Green' } elseif ($_.Status -like 'SKIP*') { 'Yellow' } else { 'Red' }
    Write-Host ("  {0,-10} {1}" -f $_.Status, $_.Name) -ForegroundColor $color
}
$hardFails = @($results | Where-Object { $_.Status -eq 'FAIL' -or $_.Status -eq 'MISSING' })
if ($hardFails.Count -gt 0) {
    Write-Host "`nrun-local-ci: $($hardFails.Count) check(s) FAILED - fix before pushing." -ForegroundColor Red
    exit 1
}
Write-Host "`nrun-local-ci: all checks passed (env-skips are covered by CI)." -ForegroundColor Green
exit 0
