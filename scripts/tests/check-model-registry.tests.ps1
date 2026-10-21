#Requires -Version 5.1
# Standalone pwsh self-test for scripts/check-model-registry.ps1.
# NOT Pester. Run: pwsh -File scripts/tests/check-model-registry.tests.ps1

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-common.ps1')
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$checker = Join-Path $repoRoot 'scripts/check-model-registry.ps1'
$script:Pass = 0; $script:Fail = 0
Import-Module (Join-Path $repoRoot 'scripts/lib/panel-ledger-helpers.psm1') -Force
$HeavyModelAllowList = @(& git -C $repoRoot show ':.github/pr-quality-gate/data/heavy-allowlist.txt')

$registryRel = '.github/playbooks/multi-model-review/current-model-registry.md'

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
    '| `heavy-a` | `model-one` | xhigh | long_context | default slate | - |',
    '| `heavy-b` | `model-one` | high | long_context | default slate | deliberately below the ceiling |',
    '| `orphan-tier` | `model-two` | high | default | no default slate consumer | - |'
)

# The mapping table the sentinels must protect: two tiers collide on (model, effort, context_tier), so any
# fixture that ends up validating something ELSE will pass when it should fail.
$collidingMap = @(
    '| `heavy-a` | `model-one` | xhigh | long_context | default slate | - |',
    '| `heavy-b` | `model-one` | xhigh | long_context | default slate | - |',
    '| `orphan-tier` | `model-two` | high | default | no default slate consumer | - |'
)

function Invoke-Case {
    param(
        [string[]] $MapRows = $goodMap,
        [string[]] $TierRows = $goodTiers,
        [string] $MapHeader = '| Tier id | Current model | effort | context_tier | consumers | Notes |',
        [string] $MapDivider = '| --- | --- | --- | --- | --- | --- |',
        [string] $TierHeader = '| Tier id | Description |',
        [string] $TierDivider = '| --- | --- |',
        [string] $SelectorLine = 'slate: `heavy-a` + `heavy-b`',
        [string] $AgentsLine = '# no tier references here',
        [string] $TriageLine = '# no tier references here',
        [string[]] $DecoyLines = @(),
        [string[]] $PreTableLines = @(),
        [string[]] $TierSentinels = @('<!-- registry:tiers:begin -->', '<!-- registry:tiers:end -->'),
        [string[]] $MapSentinels = @('<!-- registry:mapping:begin -->', '<!-- registry:mapping:end -->'),
        [string[]] $ExtraLines = @()
    )
    $dir = New-TestGitRepository -Prefix 'modelreg'
    $MapRows = @($MapRows | ForEach-Object { $_.Replace('model-one', $HeavyModelAllowList[0]) })
    Add-RepoFile $dir $registryRel (
        @('# Registry', '') + $DecoyLines +
        @('## Capability tiers', '', $TierSentinels[0], $TierHeader, $TierDivider) + $TierRows + @($TierSentinels[1]) +
        @('', '## Current mapping', '') + $PreTableLines +
        @($MapSentinels[0], $MapHeader, $MapDivider) + $MapRows + @($MapSentinels[1]) + $ExtraLines
    )
    Add-RepoFile $dir '.github/playbooks/post-code-change.md' @($SelectorLine)
    # Every selector scope the checker greps must EXIST, or a per-tag assertion passes because the scope is
    # absent rather than because it lacks the tier - which proves nothing about the rule under test.
    Add-RepoFile $dir 'AGENTS.md' @($AgentsLine)
    Add-RepoFile $dir '.github/pr-quality-gate/panel-policy.md' @('# floors')
    Add-RepoFile $dir '.github/pr-quality-gate/invoke-panel.ps1' @('# launcher')
    Add-RepoFile $dir '.github/pr-quality-gate/data/heavy-allowlist.txt' @($HeavyModelAllowList)
    Commit $dir
    return (Run $dir)
}

try {
    Write-Host "`n=== a well-formed registry passes ==="
    $r = Invoke-Case
    Assert-True ($r.ExitCode -eq 0) 'valid registry -> exit 0'

    Write-Host "`n=== (model, effort) collision is caught - the re-collapse gate ==="
    $r = Invoke-Case -MapRows @(
        '| `heavy-a` | `model-one` | xhigh | long_context | default slate | - |',
        '| `heavy-b` | `model-one` | xhigh | long_context | default slate | ceiling-synced by mistake |',
        '| `orphan-tier` | `model-two` | high | default | no default slate consumer | - |'
    )
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'share model') 'two tiers on one model at the same effort -> exit 1 (tier re-collapse blocked)'

    Write-Host "`n=== a padded model code span renders identically, so it is the same slot ==="
    foreach ($padded in @('` model-one `', '`model-one `', '` model-one`')) {
        $r = Invoke-Case -MapRows @(
            '| `heavy-a` | `model-one` | xhigh | long_context | default slate | - |',
            "| ``heavy-b`` | $padded | xhigh | long_context | default slate | - |",
            '| `orphan-tier` | `model-two` | high | default | no default slate consumer | - |'
        )
        Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'share model') "padded model span $padded -> exit 1 (renders as the same model)"
    }

    $r = Invoke-Case -MapRows @(
        '| `heavy-a` | ` ` | xhigh | long_context | default slate | - |',
        '| `heavy-b` | `model-one` | high | long_context | default slate | - |',
        '| `orphan-tier` | `model-two` | high | default | no default slate consumer | - |'
    )
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'must be backticked and non-empty') 'an all-whitespace model span -> exit 1 (not a model named " ")'

    $r = Invoke-Case -MapRows @(
        '| `heavy-a` | model-one | xhigh | long_context | default slate | - |',
        '| `heavy-b` | `model-two` | high | long_context | default slate | - |',
        '| `orphan-tier` | `model-three` | high | default | no default slate consumer | - |'
    )
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'must be backticked and non-empty') 'an unbackticked model cell -> exit 1 (a violation, not a null-method crash)'

    Write-Host "`n=== mis-cased effort is rejected (case-sensitive enum, not -in) ==="
    $r = Invoke-Case -MapRows @(
        '| `heavy-a` | `model-one` | XHIGH | long_context | default slate | - |',
        '| `heavy-b` | `model-one` | high | long_context | default slate | - |',
        '| `orphan-tier` | `model-two` | high | default | no default slate consumer | - |'
    )
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'effort') 'effort XHIGH -> exit 1 (case-sensitive; -in would have accepted it)'

    Write-Host "`n=== mis-cased context_tier is rejected ==="
    $r = Invoke-Case -MapRows @(
        '| `heavy-a` | `model-one` | xhigh | LONG_CONTEXT | default slate | - |',
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
        '| `heavy-a` | `model-one` | xhigh | long_context | triage | claims AGENTS.md but is only in a playbook |',
        '| `heavy-b` | `model-one` | high | long_context | default slate | - |',
        '| `orphan-tier` | `model-two` | high | default | no default slate consumer | - |'
    )
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'triage') 'tag bound to AGENTS.md, which exists but omits the tier -> exit 1'

    Write-Host "`n=== the same tag PASSES once its own scope actually references the tier ==="
    $r = Invoke-Case -MapRows @(
        '| `heavy-a` | `model-one` | xhigh | long_context | triage | - |',
        '| `heavy-b` | `model-one` | high | long_context | default slate | - |',
        '| `orphan-tier` | `model-two` | high | default | no default slate consumer | - |'
    ) -SelectorLine 'slate: `heavy-b`' -AgentsLine 'triages: `heavy-a`'
    Assert-True ($r.ExitCode -eq 0) 'triage tag with a real AGENTS.md reference -> exit 0 (rule is satisfiable, not merely failing)'

    Write-Host "`n=== the triage tag binds to its own scope too ==="
    $r = Invoke-Case -MapRows @(
        '| `heavy-a` | `model-one` | xhigh | long_context | triage | claims the triage scope but is only in a playbook |',
        '| `heavy-b` | `model-one` | high | long_context | default slate | - |',
        '| `orphan-tier` | `model-two` | high | default | no default slate consumer | - |'
    )
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'triage') 'triage tag without an AGENTS.md reference -> exit 1'

    $r = Invoke-Case -MapRows @(
        '| `heavy-a` | `model-one` | xhigh | long_context | triage | - |',
        '| `heavy-b` | `model-one` | high | long_context | default slate | - |',
        '| `orphan-tier` | `model-two` | high | default | no default slate consumer | - |'
    ) -SelectorLine 'slate: `heavy-b`' -AgentsLine 'triage: `heavy-a`'
    Assert-True ($r.ExitCode -eq 0) 'triage tag with a real AGENTS.md reference -> exit 0'

    Write-Host "`n=== markdown outside the sentinels cannot change what is validated ==="
    $noise = @('## Current mapping', '<details>', '  ## indented', '---', 'Tier id | Model | x', '```text', '## fenced', '```', '<!-- | a | b | -->', '   <?php ?>')
    $r = Invoke-Case -DecoyLines ($noise + '') -PreTableLines ($noise + '') -ExtraLines ($noise + '')
    Assert-True ($r.ExitCode -eq 0) 'every container shape this PR chased, placed outside the sentinels -> exit 0'

    $r = Invoke-Case -DecoyLines ($noise + '') -MapRows $collidingMap
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'share model') 'the same noise cannot hide a colliding real table -> exit 1'

    Write-Host "`n=== each sentinel must appear exactly once ==="
    $r = Invoke-Case -MapSentinels @('<!-- registry:mapping:begin -->', 'NOT-THE-END')
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'exactly one') 'missing end sentinel -> exit 1'

    $r = Invoke-Case -TierSentinels @('NOT-THE-BEGIN', '<!-- registry:tiers:end -->')
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'exactly one') 'missing begin sentinel -> exit 1'

    $r = Invoke-Case -ExtraLines @('<!-- registry:mapping:begin -->', '| a | b |', '<!-- registry:mapping:end -->')
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'exactly one') 'a duplicate sentinel pair -> exit 1 (found 2 and 2)'

    $r = Invoke-Case -DecoyLines @('```text', '<!-- registry:mapping:begin -->', '```')
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'exactly one') 'a fenced copy of a sentinel still counts -> exit 1 (exact match, no container reasoning)'

    Write-Host "`n=== the end sentinel must follow its begin ==="
    $r = Invoke-Case -MapSentinels @('<!-- registry:mapping:end -->', '<!-- registry:mapping:begin -->')
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'must come after') 'inverted sentinels -> exit 1'

    Write-Host "`n=== every non-blank line between sentinels must be a table row ==="
    $r = Invoke-Case -MapRows ($goodMap + @('a note that is not a row'))
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'is not a table row') 'prose between the sentinels -> exit 1'

    $r = Invoke-Case -MapRows ($goodMap + @('| unterminated row'))
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'is not a table row') 'a row without a closing pipe -> exit 1'

    $r = Invoke-Case -MapRows (@('') + $goodMap)
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'is blank') 'a blank line between the sentinels -> exit 1 (a blank line ends the table in GFM)'

    Write-Host "`n=== the validated span must be the rendered table ==="
    $shadow = @('| Tier id | Current model | effort | context_tier | consumers | Notes |', '| --- | --- | --- | --- | --- | --- |', '| `heavy-a` | `model-SHADOW` | xhigh | long_context | default slate | - |')
    $r = Invoke-Case -ExtraLines (@('', '## Older slate', '') + $shadow)
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'exactly once') 'a second mapping table elsewhere in the file -> exit 1 (it renders but is not validated)'

    $r = Invoke-Case -DecoyLines (@('```text') + $shadow + @('```', ''))
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'exactly once') 'a fenced copy of the mapping table -> exit 1'

    $r = Invoke-Case -DecoyLines (@('<!--') + $shadow + @('-->', ''))
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'exactly once') 'a commented copy of the mapping table -> exit 1'

    $r = Invoke-Case -PreTableLines @('| Tier id | Current model | effort | context_tier | consumers | Notes |', '')
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'exactly once') 'a stray copy of the header line alone -> exit 1'

    Write-Host "`n=== the header must sit immediately after the begin sentinel ==="
    $r = Invoke-Case -MapHeader '| a | b | c | d | e | f |' -MapDivider '| --- | --- | --- | --- | --- | --- |' -MapRows (@('| Tier id | Current model | effort | context_tier | consumers | Notes |', '| --- | --- | --- | --- | --- | --- |') + $goodMap)
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'must be the table header') 'canonical header present but not directly after the begin sentinel -> exit 1'

    Write-Host "`n=== sentinels tolerate trailing whitespace but not indentation ==="
    $r = Invoke-Case -MapSentinels @('<!-- registry:mapping:begin -->   ', '<!-- registry:mapping:end -->')
    Assert-True ($r.ExitCode -eq 0) 'trailing whitespace on a sentinel -> exit 0'

    $r = Invoke-Case -MapSentinels @('  <!-- registry:mapping:begin -->', '<!-- registry:mapping:end -->')
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'exactly one') 'an indented sentinel does not count -> exit 1'

    Write-Host "`n=== a wrong cell count is caught (malformed row) ==="
    $r = Invoke-Case -MapRows @(
        '| `heavy-a` | `model-one` | xhigh | long_context | default slate |',
        '| `heavy-b` | `model-one` | high | long_context | default slate | - |',
        '| `orphan-tier` | `model-two` | high | default | no default slate consumer | - |'
    )
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match '6 cells') 'five-cell mapping row -> exit 1'

    Write-Host "`n=== the tiers side of every mirrored guard is bound too ==="
    $r = Invoke-Case -TierRows @()
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'missing or empty') 'empty tiers span between sentinels -> exit 1 (no vacuous pass)'

    $r = Invoke-Case -MapRows @()
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'missing or empty') 'empty mapping span between sentinels -> exit 1'

    $r = Invoke-Case -TierHeader '| Tier id | Purpose |'
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'must be the table header|must appear exactly once') 'renamed tiers header -> exit 1'

    $r = Invoke-Case -TierDivider '| --- |'
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'divider') 'tiers divider with the wrong cell count -> exit 1'

    Write-Host "`n=== per-cell grammar guards ==="
    $r = Invoke-Case -TierRows @('| `heavy-a` |', '| `heavy-b` | second |', '| `orphan-tier` | third |')
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'must have exactly 2 cells') 'tiers row with the wrong cell count -> exit 1'

    $r = Invoke-Case -TierRows @('| `Heavy-A` | bad grammar |', '| `heavy-b` | second |', '| `orphan-tier` | third |')
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'violates the id grammar') 'tier id violating the id grammar -> exit 1'

    $r = Invoke-Case -MapRows @(
        '| `Heavy-A` | `model-one` | xhigh | long_context | default slate | - |',
        '| `heavy-b` | `model-one` | high | long_context | default slate | - |',
        '| `orphan-tier` | `model-two` | high | default | no default slate consumer | - |'
    )
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'violates the id grammar') 'mapping tier id violating the id grammar -> exit 1'

    Write-Host "`n=== no second table may render anywhere in the file ==="
    foreach ($ghostHeader in @(
        '| Tier | Model | effort | context_tier | consumers | Notes |',
        '| Tier ID | Current Model | effort | context_tier | consumers | Notes |',
        'Tier id | Current model | effort | context_tier | consumers | Notes',
        '|Tier id|Current model|effort|context_tier|consumers|Notes|'
    )) {
        $r = Invoke-Case -ExtraLines @('', '## Older slate', '', $ghostHeader, '| --- | --- | --- | --- | --- | --- |', '| `heavy-a` | `model-GHOST` | xhigh | long_context | default slate | - |')
        Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'delimiter row outside the sentinel spans') "ghost table with header '$($ghostHeader.Substring(0, 24))...' -> exit 1"
    }

    $r = Invoke-Case -ExtraLines @('', '## Older slate', '', 'Tier id | Current model', '--- | ---', '`heavy-a` | `model-GHOST`')
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'delimiter row outside the sentinel spans') 'a pipe-less ghost table -> exit 1'

    $r = Invoke-Case -DecoyLines @('```text', '| a | b |', '| --- | --- |', '```', '')
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'delimiter row outside the sentinel spans') 'a fenced delimiter row still counts -> exit 1 (exact match, no container reasoning)'

    $r = Invoke-Case -DecoyLines @('Rows look like `| --- | --- |` in this file.', '')
    Assert-True ($r.ExitCode -eq 0) 'a delimiter row inside an inline code span -> exit 0 (the documented way to show the grammar)'

    $r = Invoke-Case -DecoyLines @('---', '***', '- a bullet', '   ---', '')
    Assert-True ($r.ExitCode -eq 0) 'thematic breaks and bullets are not delimiter rows -> exit 0'

    foreach ($quoted in @('> | --- | --- |', '>> | --- | --- |', '>|---|---|', '  > | :--- | ---: |')) {
        $r = Invoke-Case -ExtraLines @('', '> Tier | Model', $quoted, '> `heavy-a` | `model-GHOST`')
        Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'delimiter row outside the sentinel spans') "blockquoted delimiter '$quoted' -> exit 1"
    }

    $r = Invoke-Case -ExtraLines @('', '> a quoted paragraph', '> with no table in it')
    Assert-True ($r.ExitCode -eq 0) 'an ordinary blockquote -> exit 0'

    $r = Invoke-Case -ExtraLines @('', '| Tier | Model |', '| :--- | ---: |', '| `heavy-a` | `model-GHOST` |')
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'delimiter row outside the sentinel spans') 'an alignment-colon delimiter row -> exit 1'

    $r = Invoke-Case -ExtraLines @('', "| Tier | Model |", "|`t---`t|`t---`t|", '| `heavy-a` | `model-GHOST` |')
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'delimiter row outside the sentinel spans') 'a tab-padded delimiter row -> exit 1'

    $r = Invoke-Case -ExtraLines @('', '| | |', '')
    Assert-True ($r.ExitCode -eq 0) 'a line of only pipes and spaces is not a delimiter row -> exit 0'

    $vt = [char]11; $ff = [char]12
    $r = Invoke-Case -ExtraLines @('', '| Tier | Model |', "|$vt---$vt|$vt---$vt|", '| `heavy-a` | `model-GHOST` |')
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'delimiter row outside the sentinel spans') 'a vertical-tab-padded delimiter row -> exit 1'

    $r = Invoke-Case -ExtraLines @('', '| Tier | Model |', "|$ff---$ff|$ff---$ff|", '| `heavy-a` | `model-GHOST` |')
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'delimiter row outside the sentinel spans') 'a form-feed-padded delimiter row -> exit 1'

    Write-Host "`n=== a one-column GFM table needs no pipe at all ==="
    foreach ($oneCol in @(':---', '---:', ':---:')) {
        $r = Invoke-Case -ExtraLines @('', 'Current model', $oneCol, '`model-GHOST`')
        Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'delimiter row outside the sentinel spans') "pipe-less one-column delimiter '$oneCol' -> exit 1"
    }

    $r = Invoke-Case -ExtraLines @('', 'Not a table', '---', 'just a setext heading')
    Assert-True ($r.ExitCode -eq 0) 'a bare --- stays legal -> exit 0 (setext underline, renders no table)'

    foreach ($padded in @("$vt---$vt", "$ff---$ff", "$vt---")) {
        $r = Invoke-Case -ExtraLines @('', 'Current model', $padded, '`model-GHOST`')
        Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'delimiter row outside the sentinel spans') 'a VT/FF-padded dash-only delimiter -> exit 1 (breaks the setext reading, renders a table)'
    }

    $r = Invoke-Case -ExtraLines @('', 'Not a table', "`t---`t", 'tab padding keeps it a setext heading')
    Assert-True ($r.ExitCode -eq 0) 'a tab-padded bare --- stays legal -> exit 0 (renders no table)'

    Write-Host "`n=== delimiter-ish lines that cannot render a table are left alone ==="
    foreach ($notADelimiter in @('::---', '-:-', '--- || ---', '- -', '-', '| - - - |', '| --- --- |', '| : - |', '| --- | - - |', '|')) {
        $r = Invoke-Case -ExtraLines @('', 'Header', $notADelimiter, 'value')
        Assert-True ($r.ExitCode -eq 0) "'$notADelimiter' fails the cell grammar and renders no table -> exit 0"
    }

    Write-Host "`n=== outer pipes are not symmetric: only space/tab may precede a leading pipe ==="
    foreach ($leading in @("$vt| --- |", "$ff| --- |", "$vt|-", "$ff|-")) {
        $r = Invoke-Case -ExtraLines @('', '| a |', $leading, '| 1 |')
        Assert-True ($r.ExitCode -eq 0) 'a VT/FF before the leading pipe is cell content, so the row renders nothing -> exit 0'
    }

    foreach ($trailing in @("| --- |$vt", "| --- |$ff")) {
        $r = Invoke-Case -ExtraLines @('', '| a |', $trailing, '| 1 |')
        Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'delimiter row outside the sentinel spans') 'a VT/FF AFTER the trailing pipe still renders a table -> exit 1'
    }

    Write-Host "`n=== the consumers tag set is matched case-sensitively ==="
    $r = Invoke-Case -MapRows @(
        '| `heavy-a` | `model-one` | xhigh | long_context | Default Slate | - |',
        '| `heavy-b` | `model-one` | high | long_context | default slate | - |',
        '| `orphan-tier` | `model-two` | high | default | no default slate consumer | - |'
    )
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match "consumers tag 'Default Slate' is not one of") 'a case-variant consumers tag -> exit 1 (hashtable scope lookup would otherwise normalise it silently)'

    Write-Host "`n=== the git-grep oracle fails closed rather than reporting a false verdict ==="
    $d = New-TestGitRepository -Prefix 'modelreg-gitfail'
    Add-RepoFile $d $registryRel (@('# Registry', '', '<!-- registry:tiers:begin -->', '| Tier id | Description |', '| --- | --- |') + $goodTiers + @('<!-- registry:tiers:end -->', '', '<!-- registry:mapping:begin -->', '| Tier id | Current model | effort | context_tier | consumers | Notes |', '| --- | --- | --- | --- | --- | --- |') + $goodMap + @('<!-- registry:mapping:end -->'))
    Add-RepoFile $d '.github/playbooks/post-code-change.md' @('slate: `heavy-a` + `heavy-b`')
    Add-RepoFile $d 'AGENTS.md' @('# none'); Add-RepoFile $d '.github/pr-quality-gate/panel-policy.md' @('# floors')
    Add-RepoFile $d '.github/pr-quality-gate/invoke-panel.ps1' @('# launcher')
    $fixtureRegistry = Join-Path $d $registryRel
    Set-Content -LiteralPath $fixtureRegistry -Value ((Get-Content -LiteralPath $fixtureRegistry -Raw).Replace('model-one', $HeavyModelAllowList[0]))
    Add-RepoFile $d '.github/pr-quality-gate/data/heavy-allowlist.txt' @($HeavyModelAllowList)
    Commit $d
    # Corrupting the index is the only route that breaks git grep while still satisfying the repo-root anchors:
    # deleting .git trips the anchor check first, and a non-matching pathspec exits 1, not >1.
    [IO.File]::WriteAllBytes((Join-Path $d '.git/index'), [byte[]](1..64))
    $r = Run $d
    Assert-True ($r.ExitCode -eq 2 -and $r.Output -match 'Failing closed') 'a broken git-grep oracle -> exit 2 (not a false "tagged but unreferenced" verdict)'

    Write-Host "`n=== a raw HTML table renders without a delimiter row, so its markup is refused ==="
    foreach ($html in @('<table>', '<TABLE>', '  <table class="x">', '<table><tr><td>ghost</td></tr></table>', '<tr><td>ghost</td></tr>', '</table>', '<table/>', '<table', "<table`u{000C}>")) {
        $r = Invoke-Case -ExtraLines @('', $html)
        Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'raw HTML table markup') "raw HTML '$html' outside the spans -> exit 1"
    }

    $r = Invoke-Case -ExtraLines @('', '<details>', '<summary>notes</summary>', '</details>')
    Assert-True ($r.ExitCode -eq 0) 'non-table raw HTML outside the spans -> exit 0 (only table markup is refused)'

    $r = Invoke-Case -ExtraLines @('', 'A `<threshold>` placeholder and a <theme> tag are not table markup.')
    Assert-True ($r.ExitCode -eq 0) 'tag-like words with a table-element prefix -> exit 0 (the terminator class is load-bearing)'

    foreach ($notMarkup in @('Contact: <table@example.com>.', 'Mail <td@example.com> for access.', '<tablefoo>', '<table=x>', "<table`u{00A0}>")) {
        $r = Invoke-Case -ExtraLines @('', $notMarkup)
        Assert-True ($r.ExitCode -eq 0) "'$notMarkup' -> exit 0 (renders no table, so the HTML rule must not fire)"
    }

    Write-Host "`n=== HTML table markup is refused inside the spans too ==="
    $r = Invoke-Case -MapRows @(
        '| `heavy-a` | `model-one` | xhigh | long_context | default slate | <table><tr><td>`model-GHOST`</td></tr></table> |',
        '| `heavy-b` | `model-one` | high | long_context | default slate | - |',
        '| `orphan-tier` | `model-two` | high | default | no default slate consumer | - |'
    )
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'raw HTML table markup') 'HTML table in a validated Notes cell -> exit 1 (renders nested inside the validated table)'

    $r = Invoke-Case -TierRows @('| `heavy-a` | <table><tr><td>ghost</td></tr></table> |', '| `heavy-b` | second |', '| `orphan-tier` | third |')
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'raw HTML table markup') 'HTML table in a validated Description cell -> exit 1'

    $r = Invoke-Case -MapRows @(
        '| heavy-a | `model-one` | xhigh | long_context | default slate | - |',
        '| `heavy-b` | `model-one` | high | long_context | default slate | - |',
        '| `orphan-tier` | `model-two` | high | default | no default slate consumer | - |'
    )
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'must be backticked') 'mapping tier id without backticks -> exit 1'


    $r = Invoke-Case -TierRows @('| heavy-a | not backticked |', '| `heavy-b` | second |', '| `orphan-tier` | third |')
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'must be backticked') 'tier id without backticks -> exit 1'

    $r = Invoke-Case -TierRows @('| `heavy-a` (retired) | trailing text after the span |', '| `heavy-b` | second |', '| `orphan-tier` | third |')
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'must be backticked') 'tier-id cell with trailing text -> exit 1 (anchors are load-bearing)'

    $r = Invoke-Case -TierRows @('| `heavy-a` |  |', '| `heavy-b` | second |', '| `orphan-tier` | third |')
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'empty description') 'empty tier description -> exit 1'

    $r = Invoke-Case -MapRows @(
        '| `heavy-a` | model-one | xhigh | long_context | default slate | - |',
        '| `heavy-b` | `model-one` | high | long_context | default slate | - |',
        '| `orphan-tier` | `model-two` | high | default | no default slate consumer | - |'
    )
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'model must be backticked') 'model name without backticks -> exit 1'

    $r = Invoke-Case -MapRows @(
        '| `heavy-a` | `model-one` | xhigh | long_context |  | - |',
        '| `heavy-b` | `model-one` | high | long_context | default slate | - |',
        '| `orphan-tier` | `model-two` | high | default | no default slate consumer | - |'
    )
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'empty consumers cell') 'empty consumers cell -> exit 1'

    $r = Invoke-Case -MapRows @(
        '| `heavy-a` | `model-one` | xhigh | long_context | default slate | - |',
        '| `heavy-b` | `model-one` | high | long_context | default slate | - |',
        '| `orphan-tier` | `model-two` | high | default | no default slate consumer, default slate | - |'
    )
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'cannot combine') 'no-consumer tag combined with another tag -> exit 1'

    Write-Host "`n=== rows and the end sentinel are column-0 too ==="
    $r = Invoke-Case -MapRows (@('  | `heavy-a` | `model-one` | xhigh | long_context | default slate | - |') + $goodMap[1..2])
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'is not a table row') 'an indented row between the sentinels -> exit 1'

    $r = Invoke-Case -MapSentinels @('<!-- registry:mapping:begin -->', '  <!-- registry:mapping:end -->')
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'exactly one') 'an indented END sentinel does not count -> exit 1'

    $r = Invoke-Case -MapRows @(
        '| `heavy-a` | `model-one` | xhigh | long_context | default slate | a \\| b |',
        '| `heavy-b` | `model-one` | high | long_context | default slate | - |',
        '| `orphan-tier` | `model-two` | high | default | no default slate consumer | - |'
    )
    Assert-True ($r.ExitCode -eq 0) 'a Notes cell containing an escaped backslash before a pipe is not split (accepted limitation of the one-char lookbehind; affects Notes text only, never a tier id, model or tag)'


    $r = Invoke-Case -MapHeader '| Tier id | Current model | max_effort | context_tier | consumers | Notes |'
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'must appear exactly once') 'renamed effort column header -> exit 1 (canonical header now absent)'

    Write-Host "`n=== tier-id parity is enforced BOTH ways ==="
    $r = Invoke-Case -TierRows ($goodTiers + '| `described-only` | has no mapping row |')
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'described but has no current-mapping row') 'described tier with no mapping -> exit 1'

    $r = Invoke-Case -MapRows ($goodMap + '| `mapped-only` | `model-three` | low | default | default slate | - |') -SelectorLine 'slate: `heavy-a` + `heavy-b` + `mapped-only`'
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'mapped but has no capability-tiers description') 'mapped tier with no description -> exit 1'

    Write-Host "`n=== a duplicate tier id is caught ==="
    $r = Invoke-Case -MapRows ($goodMap + '| `heavy-a` | `model-four` | low | default | default slate | - |')
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'duplicate tier id') 'duplicate mapping tier id -> exit 1'

    $r = Invoke-Case -TierRows @('| `heavy-a` | anchor |', '| `heavy-a` | duplicate |', '| `heavy-b` | second |', '| `orphan-tier` | third |')
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'duplicate tier id') 'duplicate tiers-side tier id -> exit 1'

    Write-Host "`n=== an unknown consumers tag is caught ==="
    $r = Invoke-Case -MapRows @(
        '| `heavy-a` | `model-one` | xhigh | long_context | sometimes | - |',
        '| `heavy-b` | `model-one` | high | long_context | default slate | - |',
        '| `orphan-tier` | `model-two` | high | default | no default slate consumer | - |'
    )
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'consumers tag') 'invented consumers tag -> exit 1'

    Write-Host "`n=== a missing mapping table fails closed (no vacuous pass) ==="
    $d = New-TestGitRepository -Prefix 'modelreg-empty'
    Add-RepoFile $d $registryRel @('# Registry', '', '## Capability tiers', '', '<!-- registry:tiers:begin -->', '| Tier id | Description |', '| --- | --- |', '| `heavy-a` | anchor |', '<!-- registry:tiers:end -->')
    Commit $d
    $r = Run $d
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'current-mapping') 'registry with no mapping table -> exit 1 (not a silent pass)'

    Write-Host "`n=== a missing divider row is caught (would otherwise silently skip a data row) ==="
    $d = New-TestGitRepository -Prefix 'modelreg-nodiv'
    $noDivider = @('# Registry', '', '## Capability tiers', '', '<!-- registry:tiers:begin -->', '| Tier id | Description |', '| --- | --- |') + $goodTiers + @('<!-- registry:tiers:end -->') +
                 @('', '## Current mapping', '', '<!-- registry:mapping:begin -->', '| Tier id | Current model | effort | context_tier | consumers | Notes |') + $goodMap + @('<!-- registry:mapping:end -->')
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
        '| `heavy-a` | `model-one` | xhigh | long_context | default slate | note with an escaped pipe a\|b |',
        '| `heavy-b` | `model-one` | high | long_context | default slate | - |',
        '| `orphan-tier` | `model-two` | high | default | no default slate consumer | - |'
    )
    Assert-True ($r.ExitCode -eq 0) 'escaped pipe in Notes -> exit 0 (not read as an extra column)'

    Write-Host "`n=== a stray non-table line inside a table is malformed, not a terminator ==="
    $r = Invoke-Case -MapRows @($goodMap[0], 'stray prose that would truncate parsing', $goodMap[1], $goodMap[2])
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'is not a table row') 'stray line mid-table -> exit 1 (later rows cannot be silently dropped)'

    Write-Host "`n=== a staged same-vendor heavy rotation is validated for membership only ==="
    $rotDir = New-TestGitRepository -Prefix 'modelreg-rotation'
    $rotMap = @($goodMap | ForEach-Object { $_.Replace('model-one', $HeavyModelAllowList[0]) })
    Add-RepoFile $rotDir $registryRel (@('# Registry', '', '## Capability tiers', '', '<!-- registry:tiers:begin -->', '| Tier id | Description |', '| --- | --- |') + $goodTiers + @('<!-- registry:tiers:end -->', '', '## Current mapping', '', '<!-- registry:mapping:begin -->', '| Tier id | Current model | effort | context_tier | consumers | Notes |', '| --- | --- | --- | --- | --- | --- |') + $rotMap + @('<!-- registry:mapping:end -->'))
    Add-RepoFile $rotDir '.github/playbooks/post-code-change.md' @('slate: `heavy-a` + `heavy-b`')
    Add-RepoFile $rotDir 'AGENTS.md' @('# no tier references here')
    Add-RepoFile $rotDir '.github/pr-quality-gate/panel-policy.md' @('# floors')
    Add-RepoFile $rotDir '.github/pr-quality-gate/invoke-panel.ps1' @('# launcher')
    Add-RepoFile $rotDir 'scripts/lib/panel-ledger-helpers.psm1' @('function Test-RequiresFullPanel {}')
    Add-RepoFile $rotDir '.github/pr-quality-gate/data/heavy-allowlist.txt' @($HeavyModelAllowList)
    Commit $rotDir
    $rotatedModel = ($HeavyModelAllowList[0] -split '-')[0] + '-rotated-9'
    $registryFull = Join-Path $rotDir $registryRel
    Set-Content -LiteralPath $registryFull -Value ((Get-Content -LiteralPath $registryFull) | ForEach-Object { $_.Replace($HeavyModelAllowList[0], $rotatedModel) }) -Encoding utf8
    Add-RepoFile $rotDir '.github/pr-quality-gate/data/heavy-allowlist.txt' @(@($rotatedModel) + @($HeavyModelAllowList | Select-Object -Skip 1))
    git -C $rotDir add -A 2>$null
    $r = Run $rotDir
    Assert-True ($r.ExitCode -eq 0) "staged authorized rotation passes the registry checker (rotation enforced by ledger-bound gates) -> exit 0: $($r.Output)"
    Add-RepoFile $rotDir '.github/pr-quality-gate/data/heavy-allowlist.txt' @($HeavyModelAllowList)
    git -C $rotDir add -A 2>$null
    $r = Run $rotDir
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'absent from the heavy-model allowlist') 'staged heavy model missing from the indexed allowlist -> exit 1'

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
