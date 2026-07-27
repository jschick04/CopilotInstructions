#Requires -Version 5.1
# Standalone pwsh self-test for scripts/check-model-registry.ps1.
# NOT Pester. Run: pwsh -File scripts/tests/check-model-registry.tests.ps1

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-common.ps1')
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$checker = Join-Path $repoRoot 'scripts/check-model-registry.ps1'
$script:Pass = 0; $script:Fail = 0

$registryRel = '.github/playbooks/multi-model-review/current-model-registry.md'

function New-RegistryRepo {
    param(
        [string[]] $TierRows,
        [string[]] $MapRows,
        [string] $TierHeader = '| Tier id | Description |',
        [string] $MapHeader = '| Tier id | Current model | effort | context_tier | consumers | Notes |',
        [string] $MapDivider = '| --- | --- | --- | --- | --- | --- |'
    )
    $dir = New-TestGitRepository -Prefix 'modelreg'
    $body = @('# Registry', '', '## Capability tiers', '', $TierHeader, '| --- | --- |') + $TierRows +
            @('', '## Current mapping', '', $MapHeader, $MapDivider) + $MapRows
    $full = Join-Path $dir $registryRel
    New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
    Set-Content -LiteralPath $full -Value $body -Encoding utf8
    return $dir
}
function Add-RepoFile {
    param([string] $Dir, [string] $Rel, [string[]] $Lines)
    $full = Join-Path $Dir $Rel
    New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
    Set-Content -LiteralPath $full -Value $Lines -Encoding utf8
}
function Run {
    param([string] $Dir)
    $out = & pwsh -NoProfile -File $checker -RepoRoot $Dir 2>&1
    return [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Output = ($out | Out-String) }
}
function Commit { param([string] $Dir) git -C $Dir add -A 2>$null; git -C $Dir commit -q -m init }

# A minimal valid registry: two tiers on the same model at different efforts (the shape the real file uses),
# one tagged from a playbook, one with no selector reference at all.
$goodTiers = @(
    '| `heavy-a` | anchor tier |',
    '| `heavy-b` | second heavy tier |',
    '| `orphan-tier` | optional, unused |'
)
$goodMap = @(
    '| `heavy-a` | `model-one` | max | long_context | default slate | - |',
    '| `heavy-b` | `model-one` | high | long_context | default slate | deliberately below the ceiling |',
    '| `orphan-tier` | `model-two` | high | default | no default slate consumer | - |'
)

function Invoke-Case {
    param(
        [string[]] $MapRows = $goodMap,
        [string[]] $TierRows = $goodTiers,
        [string] $MapHeader = '| Tier id | Current model | effort | context_tier | consumers | Notes |',
        [string] $MapDivider = '| --- | --- | --- | --- | --- | --- |',
        [string] $SelectorLine = 'slate: `heavy-a` + `heavy-b`'
    )
    $dir = New-RegistryRepo -TierRows $TierRows -MapRows $MapRows -MapHeader $MapHeader -MapDivider $MapDivider
    Add-RepoFile $dir '.github/playbooks/post-code-change.md' @($SelectorLine)
    Commit $dir
    return (Run $dir)
}

try {
    Write-Host "`n=== a well-formed registry passes ==="
    $r = Invoke-Case
    Assert-True ($r.ExitCode -eq 0) 'valid registry -> exit 0'

    Write-Host "`n=== (model, effort) collision is caught - the re-collapse gate ==="
    $r = Invoke-Case -MapRows @(
        '| `heavy-a` | `model-one` | max | long_context | default slate | - |',
        '| `heavy-b` | `model-one` | max | long_context | default slate | ceiling-synced by mistake |',
        '| `orphan-tier` | `model-two` | high | default | no default slate consumer | - |'
    )
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'share model') 'two tiers on one model at the same effort -> exit 1 (tier re-collapse blocked)'

    Write-Host "`n=== mis-cased effort is rejected (case-sensitive enum, not -in) ==="
    $r = Invoke-Case -MapRows @(
        '| `heavy-a` | `model-one` | MAX | long_context | default slate | - |',
        '| `heavy-b` | `model-one` | high | long_context | default slate | - |',
        '| `orphan-tier` | `model-two` | high | default | no default slate consumer | - |'
    )
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'effort') 'effort MAX -> exit 1 (case-sensitive; -in would have accepted it)'

    Write-Host "`n=== mis-cased context_tier is rejected ==="
    $r = Invoke-Case -MapRows @(
        '| `heavy-a` | `model-one` | max | LONG_CONTEXT | default slate | - |',
        '| `heavy-b` | `model-one` | high | long_context | default slate | - |',
        '| `orphan-tier` | `model-two` | high | default | no default slate consumer | - |'
    )
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'context_tier') 'context_tier LONG_CONTEXT -> exit 1 (case-sensitive)'

    Write-Host "`n=== a zero-consumer tier is NOT tripped by its own registry rows ==="
    $r = Invoke-Case
    Assert-True ($r.ExitCode -eq 0 -and $r.Output -notmatch 'orphan-tier') 'orphan-tier passes despite appearing twice in the registry itself (self-exclusion works)'

    Write-Host "`n=== a tier tagged 'no default slate consumer' that IS referenced by a selector fails ==="
    $r = Invoke-Case -SelectorLine 'slate: `heavy-a` + `heavy-b` + `orphan-tier`'
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'orphan-tier') 'referenced tier tagged no-consumer -> exit 1'

    Write-Host "`n=== a tag with no reference in ITS OWN scope fails (per-tag, not global presence) ==="
    $r = Invoke-Case -MapRows @(
        '| `heavy-a` | `model-one` | max | long_context | sub-agent default | claims AGENTS.md but is only in a playbook |',
        '| `heavy-b` | `model-one` | high | long_context | default slate | - |',
        '| `orphan-tier` | `model-two` | high | default | no default slate consumer | - |'
    )
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'sub-agent default') 'tag bound to AGENTS.md with only a playbook reference -> exit 1'

    Write-Host "`n=== a wrong cell count is caught (malformed row) ==="
    $r = Invoke-Case -MapRows @(
        '| `heavy-a` | `model-one` | max | long_context | default slate |',
        '| `heavy-b` | `model-one` | high | long_context | default slate | - |',
        '| `orphan-tier` | `model-two` | high | default | no default slate consumer | - |'
    )
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match '6 cells') 'five-cell mapping row -> exit 1'

    Write-Host "`n=== a changed header is caught (schema drift) ==="
    $r = Invoke-Case -MapHeader '| Tier id | Current model | max_effort | context_tier | consumers | Notes |'
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'header') 'renamed effort column header -> exit 1'

    Write-Host "`n=== tier-id parity is enforced BOTH ways ==="
    $r = Invoke-Case -TierRows ($goodTiers + '| `described-only` | has no mapping row |')
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'described but has no current-mapping row') 'described tier with no mapping -> exit 1'

    $r = Invoke-Case -MapRows ($goodMap + '| `mapped-only` | `model-three` | low | default | default slate | - |') -SelectorLine 'slate: `heavy-a` + `heavy-b` + `mapped-only`'
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'mapped but has no capability-tiers description') 'mapped tier with no description -> exit 1'

    Write-Host "`n=== a duplicate tier id is caught ==="
    $r = Invoke-Case -MapRows ($goodMap + '| `heavy-a` | `model-four` | low | default | default slate | - |')
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'duplicate tier id') 'duplicate mapping tier id -> exit 1'

    Write-Host "`n=== an unknown consumers tag is caught ==="
    $r = Invoke-Case -MapRows @(
        '| `heavy-a` | `model-one` | max | long_context | sometimes | - |',
        '| `heavy-b` | `model-one` | high | long_context | default slate | - |',
        '| `orphan-tier` | `model-two` | high | default | no default slate consumer | - |'
    )
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'consumers tag') 'invented consumers tag -> exit 1'

    Write-Host "`n=== a missing mapping table fails closed (no vacuous pass) ==="
    $d = New-TestGitRepository -Prefix 'modelreg-empty'
    Add-RepoFile $d $registryRel @('# Registry', '', '## Capability tiers', '', '| Tier id | Description |', '| --- | --- |', '| `heavy-a` | anchor |')
    Commit $d
    $r = Run $d
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'Current mapping') 'registry with no mapping table -> exit 1 (not a silent pass)'

    Write-Host "`n=== a missing divider row is caught (would otherwise silently skip a data row) ==="
    $d = New-TestGitRepository -Prefix 'modelreg-nodiv'
    $noDivider = @('# Registry', '', '## Capability tiers', '', '| Tier id | Description |', '| --- | --- |') + $goodTiers +
                 @('', '## Current mapping', '', '| Tier id | Current model | effort | context_tier | consumers | Notes |') + $goodMap
    Add-RepoFile $d $registryRel $noDivider
    Add-RepoFile $d '.github/playbooks/post-code-change.md' @('slate: `heavy-a` + `heavy-b`')
    Commit $d
    $r = Run $d
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'divider') 'mapping table with no divider row -> exit 1 (first data row cannot be silently skipped)'

    Write-Host "`n=== a divider with the wrong cell count is caught ==="
    $r = Invoke-Case -MapDivider '| --- | --- |'
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'divider') 'two-cell divider under a six-column header -> exit 1'

    Write-Host "`n=== an escaped pipe in a Notes cell is valid markdown and must not be misparsed ==="
    $r = Invoke-Case -MapRows @(
        '| `heavy-a` | `model-one` | max | long_context | default slate | note with an escaped pipe a\|b |',
        '| `heavy-b` | `model-one` | high | long_context | default slate | - |',
        '| `orphan-tier` | `model-two` | high | default | no default slate consumer | - |'
    )
    Assert-True ($r.ExitCode -eq 0) 'escaped pipe in Notes -> exit 0 (not read as an extra column)'

    Write-Host "`n=== a stray non-table line inside a table is malformed, not a terminator ==="
    $d = New-TestGitRepository -Prefix 'modelreg-stray'
    $stray = @('# Registry', '', '## Capability tiers', '', '| Tier id | Description |', '| --- | --- |') + $goodTiers +
             @('', '## Current mapping', '', '| Tier id | Current model | effort | context_tier | consumers | Notes |', '| --- | --- | --- | --- | --- | --- |',
               $goodMap[0], 'stray prose that would truncate parsing', $goodMap[1], $goodMap[2])
    Add-RepoFile $d $registryRel $stray
    Add-RepoFile $d '.github/playbooks/post-code-change.md' @('slate: `heavy-a` + `heavy-b`')
    Commit $d
    $r = Run $d
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'non-table line') 'stray line mid-table -> exit 1 (later rows cannot be silently dropped)'

    Write-Host "`n=== a missing registry file is an invocation failure, not a pass ==="
    $d = New-TestGitRepository -Prefix 'modelreg-none'
    # The repo-root anchor must EXIST, or Resolve-RepoRoot aborts first and this never reaches the
    # registry-not-found guard it claims to test.
    Add-RepoFile $d '.github/playbooks/post-code-change.md' @('# a playbook, but no registry')
    Commit $d
    $r = Run $d
    Assert-True ($r.ExitCode -eq 2 -and $r.Output -match 'registry not found') 'absent registry (with a valid repo root) -> exit 2 naming the missing registry'
}
finally { Remove-TestTempDirectories }

Complete-TestRun
