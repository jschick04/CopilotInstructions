#Requires -Version 5.1
# Pure validators for the post-code-change panel LEDGER gate. Isolated from comment-audit
# (no shared code); asserts only load-bearing §2B keys, opaque to other rows to avoid drift.

Set-StrictMode -Version Latest

$script:GitEmptyTreeSha = '4b825dc642cb6eb9a060e54bf8d69288fbee4904'

function Get-GitEmptyTreeSha { $script:GitEmptyTreeSha }

$script:GuardedPathPatterns = @(
    '.githooks/**','scripts/lib/**','scripts/check-*.ps1','scripts/run-local-ci.ps1','scripts/run-quality-gate-ci.ps1',
    'scripts/verify-pattern-catalog.ps1','scripts/generate-pattern-catalog.ps1','scripts/Get-ReviewedArtifactId.ps1','scripts/flush-audits.ps1','scripts/sync-critical-rules.*',
    'scripts/tests/**','scripts/yaml-emit-helpers.sh','.github/workflows/**','.github/actions/**','.github/pr-quality-gate/gate-runner.*',
    '.github/pr-quality-gate/structure-manifest.txt','.github/pr-quality-gate/HIGH-TIER-SLUGS.md',
    '.github/pr-quality-gate/panel-policy.md','.github/pr-quality-gate/data/heavy-allowlist.txt',
    '.github/pr-quality-gate/data/no-repo-slugs-allowlist.txt','.github/pr-quality-gate/data/checker-registry.tsv',
    '.github/pr-quality-gate/data/smart-punctuation-allowlist.txt','.github/pr-quality-gate/data/encoding-loss-waivers.txt',
    '.github/pr-quality-gate/dry-waivers.txt','.github/pr-quality-gate/read-receipts.tsv',
    'setup.ps1','setup.sh'
)
$script:NonGuardedPathPatterns = @(
    '.github/playbooks/**','.github/instructions/**','.github/pr-quality-gate/pattern-catalog.md',
    '.github/pr-quality-gate/pattern-catalog.sources/**','.github/pr-quality-gate/coding-preferences.md',
    '.github/pr-quality-gate/audits/**','.github/pr-quality-gate/data/findings.csv',
    '.github/pr-quality-gate/data/panel-misses.csv','.github/pr-quality-gate/data/README.md',
    '.github/pr-quality-gate/invoke-panel.ps1','scripts/Add-PanelMissesRow.ps1',
    'scripts/migrate-panel-misses-csv.ps1','scripts/show-audit.ps1','.github/copilot-instructions.md'
)

function Test-GuardedPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    $normalized = $Path -replace '\\','/'
    foreach ($pattern in $script:GuardedPathPatterns) { if ($normalized -like $pattern) { return $true } }
    return $false
}


$script:LegacyPanelSlateFloor = @{ MinReviewers=4; MinClaude=1; MinGpt=1; MinGptOrGrok=2; MinGemini=1; MinRubberDuck=1; MinCodeReview=2; MinHeavy=1; HeavyEqualsCount=$false; DistinctModels=$false }

$script:PanelSlateFloor = @{
    MinReviewers  = 4
    MinClaude     = 1
    MinGpt        = 1
    MinGptOrGrok  = 2
    MinGemini     = 1
    MinRubberDuck = 1
    MinCodeReview = 2
    MinHeavy      = 4
    HeavyEqualsCount = $true
    DistinctModels = $true
    MinReviewersTriage = 2
}
function Get-PanelSlateFloor { $script:PanelSlateFloor.Clone() }

$script:CodeExtensions = @(
    'cs','csx','ps1','psm1','psd1','sh','bash','zsh','ts','tsx','mts','cts','js','jsx','mjs','cjs',
    'cpp','h','hpp','c','cc','cxx','py','go','rs','java','kt','swift','rb','razor','cshtml','aspx',
    'css','scss','sass','less','html','htm','sql','bicep','tf',
    'csproj','props','targets','vcxproj','proj','sln'
)

$script:GovTierNone = 0
$script:GovTierPanelRequired = 1
$script:GovTierSafetyCritical = 2
$script:SafetyCriticalSegments = @(
    'auth', 'authentication', 'authorization', 'crypto', 'cryptography', 'security',
    'interop', 'pinvoke', 'native', 'payment', 'payments', 'billing', 'financial'
)

function Test-PathSafetyCriticalSegment {
    param([Parameter(Mandatory)] [string] $NormalizedPath)
    $p = $NormalizedPath
    if ($p -ceq 'AGENTS.md') { return $true }
    if ($p -like '.githooks/*') { return $true }
    if ($p -like '.github/workflows/*') { return $true }
    if ($p -like '*/panel-policy.md' -or $p -ceq '.github/pr-quality-gate/panel-policy.md') { return $true }
    $leaf = $p.Substring($p.LastIndexOf('/') + 1)
    if ($p -like 'scripts/check-*' -and $leaf -like 'check-*') { return $true }
    if ($p -like 'scripts/lib/*-helpers.psm1') { return $true }

    $segs = $p.ToLowerInvariant() -split '/'
    foreach ($seg in $segs) {
        $bare = if ($seg -match '^(.+?)\.[^.]+$') { $matches[1] } else { $seg }
        if ($script:SafetyCriticalSegments -contains $seg -or $script:SafetyCriticalSegments -contains $bare) {
            return $true
        }
    }
    return $false
}

function Get-GitBlobText {
    param([Parameter(Mandatory)] [string] $RepoRoot, [Parameter(Mandatory)] [string] $ObjectPath)
    $text = & git --no-optional-locks -C $RepoRoot show $ObjectPath 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return (@($text) -join "`n")
}

function Test-RequiresFullPanel {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $RepoRoot, [string] $CommitSha)
    $sentinel = '.github/pr-quality-gate/panel-policy.md'
    $helperPath = 'scripts/lib/panel-ledger-helpers.psm1'
    if (-not $CommitSha) {
        & git --no-optional-locks -C $RepoRoot cat-file -e "HEAD:$sentinel" 2>$null
        $headSentinel = $LASTEXITCODE -eq 0
        & git --no-optional-locks -C $RepoRoot cat-file -e ":$sentinel" 2>$null
        $indexSentinel = $LASTEXITCODE -eq 0
        if ($headSentinel -and -not $indexSentinel) { throw 'activation sentinel moved/removed; update checker constant' }
        if ($headSentinel -or $indexSentinel) { return $true }
    }
    $objects = if ($CommitSha) { @($CommitSha, "$CommitSha^") } else { @('HEAD', '') }
    foreach ($object in $objects) {
        & git --no-optional-locks -C $RepoRoot cat-file -e "${object}:$sentinel" 2>$null
        if ($LASTEXITCODE -eq 0) { return $true }
        $helper = Get-GitBlobText -RepoRoot $RepoRoot -ObjectPath "${object}:$helperPath"
        if ($helper -and $helper.Contains('function Test-RequiresFullPanel')) { return $true }
    }
    if ($CommitSha) { return Test-IsPostAdoption -RepoRoot $RepoRoot -CommitSha $CommitSha }
    return Test-IsPostAdoption -RepoRoot $RepoRoot -StagedMode
}

function Test-RewriteRequiresFullPanel {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $RepoRoot, [Parameter(Mandatory)] [string] $TipSha, [Parameter(Mandatory)] [string] $RemoteSha, [string[]] $OverwrittenShas = @())
    if (Test-RequiresFullPanel -RepoRoot $RepoRoot -CommitSha $TipSha) { return $true }
    if (Test-RequiresFullPanel -RepoRoot $RepoRoot -CommitSha $RemoteSha) { return $true }
    $commits = @($OverwrittenShas | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Select-Object -Unique)
    if ($commits.Count -eq 0) { return $false }
    $sentinel = '.github/pr-quality-gate/panel-policy.md'
    $helperPath = 'scripts/lib/panel-ledger-helpers.psm1'
    $probes = @(foreach ($commit in $commits) { foreach ($revision in @($commit, "$commit^")) { "${revision}:$sentinel"; "${revision}:$helperPath" } })
    $results = @($probes | & git --no-optional-locks -C $RepoRoot cat-file '--batch-check=%(objectname) %(objecttype)' 2>$null)
    if ($LASTEXITCODE -ne 0 -or $results.Count -ne $probes.Count) { throw 'cannot probe overwritten commits for activation' }
    $helperBlobs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    for ($index = 0; $index -lt $probes.Count; $index++) {
        $result = ([string]$results[$index]).Trim()
        if ($result -ceq "$($probes[$index]) missing") { continue }
        if ($result -notmatch '^(?<oid>[0-9a-fA-F]{40}|[0-9a-fA-F]{64}) (?<type>blob|tree|commit|tag)$') { throw "cannot probe overwritten commits for activation: $result" }
        if ($probes[$index].EndsWith(":$sentinel")) { return $true }
        if ($Matches['type'] -eq 'blob') { [void]$helperBlobs.Add($Matches['oid']) }
    }
    foreach ($blob in $helperBlobs) {
        $helper = Get-GitBlobText -RepoRoot $RepoRoot -ObjectPath $blob
        if ($helper -and $helper.Contains('function Test-RequiresFullPanel')) { return $true }
    }
    return $false
}

function Test-IsArtifactBindingAdopted {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $RepoRoot, [Parameter(Mandatory)] [string] $CommitSha)
    $artifactPath = 'scripts/Get-ReviewedArtifactId.ps1'
    $marker = "ParameterSetName = 'Commit'"
    $artifactScript = Get-GitBlobText -RepoRoot $RepoRoot -ObjectPath "${CommitSha}:$artifactPath"
    if ($artifactScript -and $artifactScript.Contains($marker)) { return $true }
    $adoption = @(& git --no-optional-locks -C $RepoRoot log -1 --full-history --diff-merges=separate --format=%H "-S$marker" $CommitSha -- $artifactPath 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'cannot determine artifact-binding adoption ancestry' }
    if (@($adoption | Where-Object { $_ }).Count -gt 0) { return $true }
    $shallow = @(& git --no-optional-locks -C $RepoRoot rev-parse --is-shallow-repository 2>$null)
    if ($LASTEXITCODE -ne 0 -or $shallow.Count -ne 1 -or ([string]$shallow[0]).Trim() -cnotin @('true', 'false')) { throw 'cannot determine whether artifact-binding adoption history is shallow' }
    if (([string]$shallow[0]).Trim() -ceq 'true') { throw 'artifact-binding adoption cannot be determined in a shallow clone; fetch full history (git fetch --unshallow)' }
    return $false
}

function Test-IsPostAdoption {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $RepoRoot, [string] $CommitSha, [switch] $StagedMode)
    $helperPath = 'scripts/lib/panel-ledger-helpers.psm1'
    $objects = if ($StagedMode) { @('', 'HEAD') } elseif ($CommitSha) { @($CommitSha) } else { throw 'Test-IsPostAdoption requires -CommitSha or -StagedMode' }
    foreach ($object in $objects) {
        $helper = Get-GitBlobText -RepoRoot $RepoRoot -ObjectPath "${object}:$helperPath"
        if ($helper -and $helper.Contains('function Test-RequiresFullPanel')) { return $true }
    }
    $revision = if ($StagedMode) { 'HEAD' } else { $CommitSha }
    & git --no-optional-locks -C $RepoRoot rev-parse --verify "$revision^{commit}" 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0 -and $StagedMode) { return $false }
    if ($LASTEXITCODE -ne 0) { throw 'cannot resolve adoption revision' }
    $adoption = @(& git --no-optional-locks -C $RepoRoot log -1 --full-history --diff-merges=separate --format=%H -S'function Test-RequiresFullPanel' $revision -- $helperPath 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'cannot determine post-adoption ancestry' }
    return @($adoption | Where-Object { $_ }).Count -gt 0
}

function Get-HeavyModelPolicy {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $RepoRoot, [string] $CommitSha, [string] $ParentSha = '', [switch] $StagedMode, [string[]] $LedgerLines = @(), [switch] $MembershipOnly)
    $path = '.github/pr-quality-gate/data/heavy-allowlist.txt'
    $object = if ($StagedMode) { ":$path" } elseif ($CommitSha) { "${CommitSha}:$path" } else { throw 'heavy policy requires staged or commit context' }
    $text = Get-GitBlobText -RepoRoot $RepoRoot -ObjectPath $object
    $models = @($text -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $errors = [System.Collections.Generic.List[string]]::new()
    if (-not $text -or $models.Count -eq 0) { $errors.Add('heavy-allowlist.txt missing or empty in governing git object') }
    if (@($models | Sort-Object -Unique -CaseSensitive).Count -ne $models.Count -or @($models | Where-Object { $_ -cnotmatch '^(claude|gpt|gemini|grok)-[a-z0-9.-]+$' }).Count -gt 0) { $errors.Add('heavy-allowlist.txt has duplicate or malformed model ids') }
    if ($MembershipOnly) { return [pscustomobject]@{ Models = $models; Errors = $errors.ToArray() } }
    if (-not $ParentSha) {
        $parentRef = if ($StagedMode) { 'HEAD' } else { "$CommitSha^" }
        $parentLines = @(& git --no-optional-locks -C $RepoRoot rev-parse --verify $parentRef 2>$null)
        if ($LASTEXITCODE -eq 0 -and $parentLines.Count -eq 1) { $ParentSha = $parentLines[0] }
    }
    $parentText = if ($ParentSha -and $ParentSha -ne $script:GitEmptyTreeSha) { Get-GitBlobText -RepoRoot $RepoRoot -ObjectPath "${ParentSha}:$path" } else { $null }
    $parentAdopted = $ParentSha -and $ParentSha -ne $script:GitEmptyTreeSha -and (Test-IsPostAdoption -RepoRoot $RepoRoot -CommitSha $ParentSha)
    if (-not $parentText -or -not $parentAdopted) {
        $initial = @('claude-opus-5.5','gpt-6.1-sol','gemini-4-argon','grok-4.7','gpt-5.3-codex')
        if (($models -join "`n") -cne ($initial -join "`n")) { $errors.Add('introducing heavy allowlist must equal the pinned five model ids') }
        if ($parentAdopted -and -not $parentText) { $errors.Add('post-adoption heavy allowlist cannot be deleted and re-added') }
    } else {
        $priorModels = @($parentText -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $removed = @($priorModels | Where-Object { $models -cnotcontains $_ })
        $added = @($models | Where-Object { $priorModels -cnotcontains $_ })
        $rotation = Get-RegistryRotationMap -LedgerLines $LedgerLines
        $pairs = if ($rotation.RowCount -eq 1 -and $rotation.Errors.Count -eq 0) { @($rotation.Entries) } else { @() }
        foreach ($model in $added) {
            $mapped = $false
            foreach ($pair in $pairs) {
                if ($pair) {
                    $tierId = $pair.TierId; $from = $pair.From; $to = $pair.To
                    if ($to -ceq $model -and $removed -ccontains $from -and ($from -split '-')[0] -ceq ($to -split '-')[0]) {
                        $retireRows = @($LedgerLines | Where-Object { $_ -cmatch ('^slate-substitution:\s+slot:[^\s<>]+\s+tier:' + [regex]::Escape($tierId) + '\s+from:' + [regex]::Escape($from) + '\s+to:' + [regex]::Escape($to) + '\s+reason:(model-retired|model-superseded)\s*$') })
                        if ($retireRows.Count -eq 1) { $mapped = $true }
                    }
                }
            }
            if (-not $mapped) { $errors.Add("added heavy model '$model' requires an acknowledged same-vendor retirement mapping") }
        }
    }
    return [pscustomobject]@{ Models = $models; Errors = $errors.ToArray() }
}

function Get-RegistryRotationMap {
    param([AllowEmptyCollection()] [string[]] $LedgerLines = @())
    $rows = @($LedgerLines | Where-Object { [string]$_ -cmatch '^registry-rotation:\s*"registry-rotation-acknowledged"\s+ref:[^\s<>]+\s+map:(.+)$' })
    $entries = [System.Collections.Generic.List[object]]::new()
    $errors = [System.Collections.Generic.List[string]]::new()
    if ($rows.Count -gt 1) { $errors.Add('duplicate registry-rotation rows') }
    if ($rows.Count -ge 1 -and [string]$rows[0] -cmatch '\smap:(.+)$') {
        foreach ($entryText in ($matches[1].Trim() -split ',')) {
            $entry = $entryText.Trim()
            if ($entry -cmatch '^([\w-]+)=([^\s<>]+)>([^\s<>]+)$') { $entries.Add([pscustomobject]@{ TierId = $matches[1]; From = $matches[2]; To = $matches[3] }) }
            else { $errors.Add("malformed registry-rotation map entry '$entryText'") }
        }
    }
    return [pscustomobject]@{ RowCount = $rows.Count; Entries = $entries.ToArray(); Errors = $errors.ToArray() }
}

function Get-RegistryModelMap {
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $RegistryText)
    $lines = @($RegistryText -split "`n")
    $beginAt = @(); $endAt = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].TrimEnd("`r") -ceq '<!-- registry:mapping:begin -->') { $beginAt += $i }
        if ($lines[$i].TrimEnd("`r") -ceq '<!-- registry:mapping:end -->') { $endAt += $i }
    }
    if ($beginAt.Count -ne 1 -or $endAt.Count -ne 1 -or $endAt[0] -le $beginAt[0]) { return $null }
    $models = @{}
    $tiers = @{}
    for ($i = $beginAt[0] + 1; $i -lt $endAt[0]; $i++) {
        $line = ([string]$lines[$i]).TrimEnd("`r")
        if ($line -notmatch '^\|') { continue }
        $cells = @($line.Trim().Trim('|') -split '(?<!\\)\|' | ForEach-Object { $_.Trim() })
        if ($cells.Count -ne 6) { continue }
        $tierMatch = [regex]::Match($cells[0], '^`([^`]+)`$')
        $modelMatch = [regex]::Match($cells[1], '^`([^`]+)`$')
        if (-not $tierMatch.Success -or -not $modelMatch.Success) { continue }
        $tierId = $tierMatch.Groups[1].Value
        $modelId = $modelMatch.Groups[1].Value
        $tierClassMatch = [regex]::Match($tierId, '^(heavy|light)-(claude|gpt|gemini|grok)\b')
        if ($tierClassMatch.Success) {
            $entry = [PSCustomObject]@{ TierId = $tierId; Tier = $tierClassMatch.Groups[1].Value; Family = $tierClassMatch.Groups[2].Value; Model = $modelId }
            $models[$modelId] = $entry
            $tiers[$tierId] = $entry
        }
    }
    return [PSCustomObject]@{ Models = $models; Tiers = $tiers }
}

function Test-PanelRegistryBinding {
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $LedgerLines,
        [Parameter(Mandatory)] [object[]] $Reviewers,
        [Parameter(Mandatory)] [string] $RegistryText,
        [Parameter(Mandatory)] [string] $StagedRegistryText,
        [string[]] $HeavyModels = @()
    )
    $errors = [System.Collections.Generic.List[string]]::new()
    $parentMap = Get-RegistryModelMap -RegistryText $RegistryText
    $stagedMap = Get-RegistryModelMap -RegistryText $StagedRegistryText
    if ($null -eq $parentMap -or $null -eq $stagedMap) { return @('registry binding failed: required sentinel mapping table is missing or malformed') }
    $substitutions = @{}
    foreach ($line in $LedgerLines) {
        if ([string]$line -cmatch '^slate-substitution:\s*slot:([^\s<>]+)\s+tier:([^\s<>]+)\s+from:([^\s<>]+)\s+to:([^\s<>]+)\s+reason:(model-retired|model-superseded|tier-added|family-unavailable)\s*$') {
            if ($substitutions.ContainsKey($matches[1])) { $errors.Add("duplicate slate-substitution for slot '$($matches[1])'") }
            $substitutions[$matches[1]] = [PSCustomObject]@{ Slot=$matches[1]; TierId=$matches[2]; From=$matches[3]; To=$matches[4]; Reason=$matches[5] }
        }
    }
    $rotationParse = Get-RegistryRotationMap -LedgerLines $LedgerLines
    $rotation = $rotationParse.RowCount -gt 0
    $rotationMap = @{}
    foreach ($rotationError in $rotationParse.Errors) { $errors.Add($rotationError) }
    foreach ($entry in $rotationParse.Entries) { $rotationMap[$entry.TierId] = "$($entry.From)>$($entry.To)" }
    if ($substitutions.Count -gt 0 -and -not $rotation) { $errors.Add('every slate-substitution requires a registry-rotation-acknowledged row') }
    if ($rotationMap.Count -ne $substitutions.Count) { $errors.Add('registry-rotation map must match the slate-substitution rows exactly') }
    foreach ($sub in $substitutions.Values) {
        if (-not $rotationMap.ContainsKey($sub.TierId) -or $rotationMap[$sub.TierId] -cne "$($sub.From)>$($sub.To)") { $errors.Add("registry-rotation map does not match tier '$($sub.TierId)'") }
    }
    foreach ($reviewer in $Reviewers) {
        if ($reviewer.Tier -eq 'heavy' -and $HeavyModels -cnotcontains $reviewer.Model) { $errors.Add("slot '$($reviewer.Slot)' heavy model '$($reviewer.Model)' is absent from HeavyModelAllowList") }
        $row = if ($parentMap.Models.ContainsKey($reviewer.Model)) { $parentMap.Models[$reviewer.Model] } else { $null }
        $fallback = $substitutions.ContainsKey($reviewer.Slot) -and $substitutions[$reviewer.Slot].Reason -ceq 'family-unavailable'
        if ($fallback) {
            $sub = $substitutions[$reviewer.Slot]
            if ($sub.TierId -cne 'heavy-grok-premium' -or -not $parentMap.Tiers.ContainsKey('heavy-grok-premium') -or -not $parentMap.Tiers.ContainsKey('heavy-gpt-codex') -or $sub.From -cne $parentMap.Tiers['heavy-grok-premium'].Model -or $sub.To -cne $parentMap.Tiers['heavy-gpt-codex'].Model -or $reviewer.Model -cne $sub.To -or $reviewer.Family -cne 'gpt' -or $reviewer.Tier -cne 'heavy') { $errors.Add("slot '$($reviewer.Slot)' invalid Grok-to-codex family-unavailable substitution") }
            continue
        }
        if ($row) {
            if ($row.Family -cne $reviewer.Family -or $row.Tier -cne $reviewer.Tier) { $errors.Add("slot '$($reviewer.Slot)' family/tier does not match parent registry row for '$($reviewer.Model)'") }
            if ($substitutions.ContainsKey($reviewer.Slot)) { $errors.Add("slot '$($reviewer.Slot)' has an unnecessary substitution row") }
            continue
        }
        if (-not $substitutions.ContainsKey($reviewer.Slot)) { $errors.Add("slot '$($reviewer.Slot)' model '$($reviewer.Model)' is absent from the parent registry and has no substitution row"); continue }
        $sub = $substitutions[$reviewer.Slot]
        if ($sub.From -cne 'none' -and ($sub.From -split '-')[0] -cne ($sub.To -split '-')[0]) { $errors.Add("slot '$($reviewer.Slot)' rotation changes model vendor") }
        $target = if ($stagedMap.Models.ContainsKey($sub.To)) { $stagedMap.Models[$sub.To] } else { $null }
        if (-not $target -or $target.TierId -cne $sub.TierId -or $target.Model -cne $reviewer.Model) { $errors.Add("slot '$($reviewer.Slot)' substitution target does not resolve in the staged registry") }
        if ($target -and ($target.Family -cne $reviewer.Family -or $target.Tier -cne $reviewer.Tier)) { $errors.Add("slot '$($reviewer.Slot)' family/tier does not match staged substitution row") }
        if ($reviewer.Tier -eq 'heavy' -and $HeavyModels -cnotcontains $reviewer.Model) { $errors.Add("slot '$($reviewer.Slot)' heavy model '$($reviewer.Model)' is absent from HeavyModelAllowList") }
        $priorTier = if ($parentMap.Tiers.ContainsKey($sub.TierId)) { $parentMap.Tiers[$sub.TierId] } else { $null }
        if ($priorTier) {
            if ($sub.From -cne $priorTier.Model -or $priorTier.Tier -cne $reviewer.Tier) { $errors.Add("slot '$($reviewer.Slot)' substitution does not match the parent tier mapping") }
        } elseif ($sub.Reason -cne 'tier-added' -or $sub.From -cne 'none' -or $sub.TierId -notmatch '^heavy-') {
            $errors.Add("slot '$($reviewer.Slot)' new tier requires from:none and reason:tier-added")
        }
    }
    foreach ($slot in $substitutions.Keys) { if (@($Reviewers | Where-Object Slot -eq $slot).Count -eq 0) { $errors.Add("slate-substitution names unknown slot '$slot'") } }
    return $errors.ToArray()
}

function Get-PathGovernanceTier {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    $p = ($Path -replace '\\', '/').Trim()
    if (-not $p) { return $script:GovTierNone }
    if ($p -like '.github/pr-quality-gate/audits/*') { return $script:GovTierNone }

    $panelRequired = $false
    if ($p -ceq 'AGENTS.md') { $panelRequired = $true }
    elseif ($p -ceq 'setup.ps1' -or $p -ceq 'setup.sh') { $panelRequired = $true }
    elseif ($p -ceq '.gitattributes' -or $p -ceq '.gitignore' -or $p -ceq '.github/copilot-instructions.md') { $panelRequired = $true }
    elseif ($p -like '.github/instructions/*' -or
        $p -like '.github/playbooks/*' -or
        $p -like '.github/workflows/*' -or
        $p -like '.github/pr-quality-gate/*' -or
        $p -like '.githooks/*' -or
        $p -like 'scripts/*') { $panelRequired = $true }
    else {
        $ext = [System.IO.Path]::GetExtension($p).TrimStart('.').ToLowerInvariant()
        if ($ext -and ($script:CodeExtensions -contains $ext)) { $panelRequired = $true }
    }

    if (-not $panelRequired) { return $script:GovTierNone }
    if (Test-PathSafetyCriticalSegment -NormalizedPath $p) { return $script:GovTierSafetyCritical }
    return $script:GovTierPanelRequired
}

function Test-PathPanelRequired {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    return ((Get-PathGovernanceTier -Path $Path) -ge $script:GovTierPanelRequired)
}

function Get-ChangedGovernanceTier {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [AllowNull()] [string[]] $ChangedPaths,
        [AllowEmptyCollection()] [AllowNull()] [string[]] $NameStatusLines = @()
    )
    $maxTier = $script:GovTierNone
    foreach ($path in @($ChangedPaths)) {
        if (-not $path) { continue }
        $tier = Get-PathGovernanceTier -Path $path
        if ($tier -gt $maxTier) { $maxTier = $tier }
        if ($maxTier -ge $script:GovTierSafetyCritical) { return $maxTier }
    }
    foreach ($line in @($NameStatusLines)) {
        if (-not $line) { continue }
        if ([string]$line -cmatch '^R\d+\t([^\t]+)\t([^\t]+)$') {
            $oldPath = ($matches[1] -replace '\\', '/').Trim()
            $newPath = ($matches[2] -replace '\\', '/').Trim()
            $oldDir = if ($oldPath -match '^(.*)/[^/]+$') { $matches[1] } else { '' }
            $newDir = if ($newPath -match '^(.*)/[^/]+$') { $matches[1] } else { '' }
            $isMove = $oldDir -ne $newDir
            $touchesTest = ($oldPath -match '(^|/)tests?(/|$)' -or $newPath -match '(^|/)tests?(/|$)')
            if ($isMove -and ($touchesTest -or (Get-PathGovernanceTier -Path $newPath) -ge $script:GovTierPanelRequired -or (Get-PathGovernanceTier -Path $oldPath) -ge $script:GovTierPanelRequired)) {
                return $script:GovTierSafetyCritical
            }
        }
    }
    return $maxTier
}

function Get-PanelRequired {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $ChangedPaths)
    foreach ($path in $ChangedPaths) {
        if (-not $path) { continue }
        if (Test-PathPanelRequired -Path $path) { return $true }
    }
    return $false
}

function Test-Transcript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $LedgerLines,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $HeaderName,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $ReadyVerdict,
        [hashtable] $Floor,
        [string] $ErrorPrefix,
        [string] $ExpectedArtifact = '',
        [switch] $RequireArtifact,
        [string] $RegistryText = '',
        [string] $StagedRegistryText = '',
        [bool] $PostAdoption = $false,
        [bool] $RequiresFull = $false,
        [string[]] $HeavyModels = @()
    )
    if (@('CODE_REVIEW_READY', 'DESIGN_READY') -notcontains $ReadyVerdict) {
        throw "Test-Transcript: -ReadyVerdict must be CODE_REVIEW_READY or DESIGN_READY (got '$ReadyVerdict')"
    }
    if (-not $Floor) { $Floor = if ($PostAdoption) { $script:PanelSlateFloor } else { $script:LegacyPanelSlateFloor } }
    if (-not $ErrorPrefix) { $ErrorPrefix = $HeaderName }
    $profileLine = $LedgerLines | Where-Object { [string]$_ -cmatch '^profile:\s*(full|triage|lint-only)\s*$' } | Select-Object -First 1
    $triageAck = $LedgerLines | Where-Object { [string]$_ -cmatch '^triage-ack:\s*"triage-acknowledged"\s+ref:[^\s<>]+\s*$' } | Select-Object -First 1
    if ($profileLine -and $profileLine -cmatch '^profile:\s*triage\s*$' -and $triageAck -and -not $RequiresFull) {
        $Floor = @{ MinReviewers = 2; MaxReviewers = 2; MinClaude = 0; MinGpt = 0; MinGptOrGrok = 0; MinGemini = 0; MinRubberDuck = 0; MinCodeReview = 2; MinHeavy = 0; HeavyEqualsCount = $false; DistinctModels = $true; Triage = $true }
    }

    $errors = New-Object System.Collections.Generic.List[string]
    $lines = @($LedgerLines)

    $headerRx = '^\s*' + [regex]::Escape($HeaderName) + ':\s*$'
    $headerIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if (([string]$lines[$i]) -cmatch $headerRx) { $headerIdx = $i; break }
    }
    if ($headerIdx -lt 0) {
        $errors.Add("$ErrorPrefix but no '$HeaderName`:' block is present (the multi-model slate must be recorded)")
        return $errors.ToArray()
    }

    $verdictRx = [regex]::Escape($ReadyVerdict)
    $grammar = '^\s*-\s*slot:([^\s<>]+)\s+model:([^\s<>]+)\s+family:(claude|gpt|gemini|grok)\s+role:(rubber-duck|code-review)\s+tier:(heavy|light)\s+verdict:(' + $verdictRx + '|NEEDS_REWORK)\s+rounds:([1-9]\d*)(?:\s+artifact:([a-fA-F0-9]{64}))?\s*$'
    $candidates = New-Object System.Collections.Generic.List[string]
    $findings = New-Object System.Collections.Generic.List[string]
    for ($i = $headerIdx + 1; $i -lt $lines.Count; $i++) {
        $ln = [string]$lines[$i]
        if ($ln -cmatch '^\s*[A-Za-z][\w-]*:') { break }
        if ($ln -cmatch '^\s*-\s*slot:') { $candidates.Add($ln) }
        elseif ($ln -cmatch '^\s*-\s*findings:\s*(.*)$') { $findings.Add($matches[1]) }
    }
    $findingsArr = $findings.ToArray()
    if ($findingsArr.Count -ne 1) {
        $errors.Add("$HeaderName block has $($findingsArr.Count) '- findings:' line(s); exactly 1 required (the panel-findings disclosure note)")
    } else {
        $findingsValue = ([string]$findingsArr[0]).Trim()
        if (-not ($findingsValue -match '\S')) {
            $errors.Add("$HeaderName '- findings:' line is empty; record a one-line panel-findings summary")
        } elseif ($findingsValue -cmatch '^<[^>]*>$') {
            $errors.Add("$HeaderName '- findings:' line is an unsubstituted placeholder ('$findingsValue'); fill in the actual panel findings")
        }
    }
    $candidates = $candidates.ToArray()
    $reviewers = New-Object System.Collections.Generic.List[object]
    foreach ($line in $candidates) {
        if ($line -cmatch $grammar) {
            $reviewers.Add([PSCustomObject]@{
                Slot = $matches[1]; Model = $matches[2]; Family = $matches[3]
                Role = $matches[4]; Tier = $matches[5]; Verdict = $matches[6]; Rounds = [long] $matches[7]; Artifact = $matches[8]
            })
        } else {
            $errors.Add("malformed $HeaderName reviewer line: '$(([string]$line).Trim())'")
        }
    }

    $reviewerArr = $reviewers.ToArray()
    if ($reviewerArr.Count -eq 0) {
        $errors.Add("$HeaderName block present but has no valid reviewer lines")
        return $errors.ToArray()
    }

    foreach ($g in @($reviewerArr | Group-Object -Property Slot | Where-Object { $_.Count -gt 1 })) {
        $errors.Add("duplicate reviewer slot '$($g.Name)' in $HeaderName (each reviewer must have a unique slot)")
    }
    $artifactValues = @($reviewerArr | ForEach-Object { $_.Artifact } | Where-Object { $_ } | Sort-Object -Unique)
    if ($RequireArtifact -and @($reviewerArr | Where-Object { -not $_.Artifact }).Count -gt 0) { $errors.Add("$HeaderName requires an artifact token on every reviewer slot") }
    if ($artifactValues.Count -gt 1) { $errors.Add("$HeaderName reviewer artifact tokens must be identical") }
    if ($ExpectedArtifact -and ($artifactValues.Count -ne 1 -or $artifactValues[0] -cne $ExpectedArtifact)) { $errors.Add("$HeaderName artifact token does not match the reviewed artifact") }
    foreach ($r in $reviewerArr) {
        if ($r.Rounds -gt [int]::MaxValue) { $errors.Add("reviewer slot '$($r.Slot)' rounds exceed Int32") }
        if ($r.Verdict -cne $ReadyVerdict) {
            $errors.Add("reviewer slot '$($r.Slot)' verdict is '$($r.Verdict)', not $ReadyVerdict (panel not converged to unanimous)")
        }
        if ($r.Rounds -lt 1) {
            $errors.Add("reviewer slot '$($r.Slot)' rounds must be >= 1 (got $($r.Rounds))")
        }
    }

    if ($PostAdoption) {
        foreach ($reviewer in $reviewerArr) {
            if ($reviewer.Model -cnotmatch ('^' + [regex]::Escape($reviewer.Family) + '-')) { $errors.Add("slot '$($reviewer.Slot)' model '$($reviewer.Model)' prefix does not match family '$($reviewer.Family)'") }
            if ($reviewer.Tier -eq 'heavy' -and $HeavyModels -cnotcontains $reviewer.Model) { $errors.Add("slot '$($reviewer.Slot)' heavy model '$($reviewer.Model)' is absent from HeavyModelAllowList") }
        }
    }
    if ($RegistryText) { foreach ($registryError in (Test-PanelRegistryBinding -LedgerLines $LedgerLines -Reviewers $reviewerArr -RegistryText $RegistryText -StagedRegistryText $StagedRegistryText -HeavyModels $HeavyModels)) { $errors.Add($registryError) } }

    $distinct = @($reviewerArr | Group-Object -Property Slot | ForEach-Object { $_.Group | Select-Object -First 1 })
    $nClaude = @($distinct | Where-Object { $_.Family -eq 'claude' }).Count
    $nGpt    = @($distinct | Where-Object { $_.Family -eq 'gpt' }).Count
    $nGemini = @($distinct | Where-Object { $_.Family -eq 'gemini' }).Count
    $nGrok = @($distinct | Where-Object { $_.Family -eq 'grok' }).Count
    $nDuck   = @($distinct | Where-Object { $_.Role -eq 'rubber-duck' }).Count
    $nReview = @($distinct | Where-Object { $_.Role -eq 'code-review' }).Count
    $nHeavy  = @($distinct | Where-Object { $_.Tier -eq 'heavy' }).Count

    if ($distinct.Count -lt $Floor.MinReviewers) { $errors.Add("$HeaderName has $($distinct.Count) distinct reviewer(s); the full slate floor requires >= $($Floor.MinReviewers)") }
    if ($Floor.ContainsKey('MaxReviewers') -and $distinct.Count -ne $Floor.MaxReviewers) { $errors.Add("$HeaderName triage slate requires exactly $($Floor.MaxReviewers) reviewers") }
    if ($Floor.ContainsKey('Triage') -and $Floor.Triage) {
        if (@($distinct.Family | Sort-Object -Unique).Count -ne 2) { $errors.Add("$HeaderName triage reviewers must use distinct families") }
        if (@($distinct | Where-Object { $_.Tier -ne 'light' -or $_.Role -ne 'code-review' }).Count -gt 0) { $errors.Add("$HeaderName triage reviewers must all be light-tier code-reviewers") }
    }
    if ($nClaude -lt $Floor.MinClaude)           { $errors.Add("$HeaderName has $nClaude Claude-family reviewer(s); full floor requires >= $($Floor.MinClaude)") }
    if ($nGpt -lt $Floor.MinGpt)                 { $errors.Add("$HeaderName has $nGpt GPT-family reviewer(s); full floor requires >= $($Floor.MinGpt)") }
    if (($nGpt + $nGrok) -lt $Floor.MinGptOrGrok) { $errors.Add("$HeaderName has $($nGpt + $nGrok) GPT/Grok reviewer(s); full floor requires >= $($Floor.MinGptOrGrok)") }
    if ($nGemini -lt $Floor.MinGemini)           { $errors.Add("$HeaderName has $nGemini Gemini-family reviewer(s); full floor requires >= $($Floor.MinGemini)") }
    if ($nDuck -lt $Floor.MinRubberDuck)         { $errors.Add("$HeaderName has $nDuck rubber-duck reviewer(s); full floor requires >= $($Floor.MinRubberDuck)") }
    if ($nReview -lt $Floor.MinCodeReview)       { $errors.Add("$HeaderName has $nReview code-review reviewer(s); full floor requires >= $($Floor.MinCodeReview)") }
    if ($nHeavy -lt $Floor.MinHeavy)             { $errors.Add("$HeaderName has $nHeavy heavy-tier reviewer(s); full floor requires >= $($Floor.MinHeavy)") }
    if ($Floor.HeavyEqualsCount -and $nHeavy -ne $distinct.Count) { $errors.Add("$HeaderName requires every reviewer to be heavy-tier") }
    if ($Floor.DistinctModels -and @($distinct.Model | Sort-Object -Unique).Count -ne $distinct.Count) { $errors.Add("$HeaderName requires distinct model names") }

    return $errors.ToArray()
}

function Test-PanelTranscript {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $LedgerLines, [string] $ExpectedArtifact = '', [switch] $RequireArtifact, [string] $RegistryText = '', [string] $StagedRegistryText = '', [bool] $PostAdoption = $false, [bool] $RequiresFull = $false, [string[]] $HeavyModels = @())
    return Test-Transcript -LedgerLines $LedgerLines -HeaderName 'panel-transcript' -ReadyVerdict 'CODE_REVIEW_READY' -ErrorPrefix "post-code-change-panel is 'ran, unanimous'" -ExpectedArtifact $ExpectedArtifact -RequireArtifact:$RequireArtifact -RegistryText $RegistryText -StagedRegistryText $StagedRegistryText -PostAdoption:$PostAdoption -RequiresFull:$RequiresFull -HeavyModels $HeavyModels
}

function Test-PrePanelTranscript {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $LedgerLines, [bool] $PostAdoption = $false, [bool] $RequiresFull = $false, [string[]] $HeavyModels = @())
    return Test-Transcript -LedgerLines $LedgerLines -HeaderName 'pre-panel-transcript' -ReadyVerdict 'DESIGN_READY' -ErrorPrefix "pre-code-change-panel is 'ran, unanimous'" -PostAdoption:$PostAdoption -RequiresFull:$RequiresFull -HeavyModels $HeavyModels
}

function Test-LedgerDisclosureRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $LedgerLines,
        [Parameter(Mandatory)] [string] $RowKey,
        [Parameter(Mandatory)] [string[]] $AllowedRegexes,
        [Parameter(Mandatory)] [bool] $Required
    )
    $errs = New-Object System.Collections.Generic.List[string]
    $keyRx = '^\s*' + [regex]::Escape($RowKey) + ':\s*\S'
    $line = $LedgerLines | Where-Object { $_ -cmatch $keyRx } | Select-Object -First 1
    if (-not $line) {
        if ($Required) { $errs.Add("missing required '$RowKey`:' row") }
        return $errs.ToArray()
    }
    $val = ($line -replace ('^\s*' + [regex]::Escape($RowKey) + ':\s*'), '').Trim()
    if (Test-PreCommitGateValue -Value $val) {
        $errs.Add("unsubstituted template placeholder for $RowKey")
        return $errs.ToArray()
    }
    $ok = $false
    foreach ($rx in $AllowedRegexes) { if ($val -cmatch $rx) { $ok = $true; break } }
    if (-not $ok) { $errs.Add("$RowKey value is not one of the allowed forms (got: '$val')") }
    return $errs.ToArray()
}

function Get-LedgerSubBlockMap {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $LedgerLines, [Parameter(Mandatory)] [string] $ParentKey)
    $lines = @($LedgerLines)
    $parentIdx = -1; $parentIndent = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if (([string]$lines[$i]) -cmatch ('^(\s*)' + [regex]::Escape($ParentKey) + ':\s*$')) {
            $parentIdx = $i; $parentIndent = $matches[1].Length; break
        }
    }
    if ($parentIdx -lt 0) { return $null }
    $map = [ordered]@{}
    for ($i = $parentIdx + 1; $i -lt $lines.Count; $i++) {
        $ln = [string]$lines[$i]
        if ($ln -match '^\s*$' -or $ln -match '^\s*#') { continue }
        $indent = ($ln -replace '^(\s*).*$', '$1').Length
        if ($indent -le $parentIndent) { break }
        if ($ln -cmatch '^\s*([\w-]+):\s*(.*?)\s*$') { $map[[string]$matches[1]] = [string]$matches[2] }
    }
    return $map
}

function Test-LedgerG6 {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $LedgerLines)
    $errs = New-Object System.Collections.Generic.List[string]
    $triggers = @('implementation-planning', 'library-restructure', 'design-exploration', 'performance-comparison', 'scope-planning', 'system-framing', 'project-vocabulary')
    $requiredClass = @('implementation-planning', 'library-restructure')
    $invokePlaybooks = @('implementation-planning', 'library-restructure', 'design-exploration', 'performance-comparison')

    $td = Get-LedgerSubBlockMap -LedgerLines $LedgerLines -ParentKey 'pre-impl-trigger-detections'
    $pd = Get-LedgerSubBlockMap -LedgerLines $LedgerLines -ParentKey 'pre-impl-playbook-decisions'
    $pv = Get-LedgerSubBlockMap -LedgerLines $LedgerLines -ParentKey 'playbook-invocations'
    if ($null -eq $td) { $errs.Add("missing required 'pre-impl-trigger-detections:' block") }
    if ($null -eq $pd) { $errs.Add("missing required 'pre-impl-playbook-decisions:' block") }
    if ($null -eq $pv) { $errs.Add("missing required 'playbook-invocations:' block") }
    if ($errs.Count -gt 0) { return $errs.ToArray() }

    foreach ($t in $triggers) {
        $tv = if ($td.Contains($t)) { [string]$td[$t] } else { $null }
        if ($null -eq $tv) { $errs.Add("pre-impl-trigger-detections missing '$t'"); continue }
        if ($tv -notmatch '^(yes|no)$') { $errs.Add("pre-impl-trigger-detections '$t' must be yes|no (got '$tv')"); continue }

        $dv = if ($pd.Contains($t)) { [string]$pd[$t] } else { $null }
        if ($null -eq $dv) { $errs.Add("pre-impl-playbook-decisions missing '$t'"); continue }
        if ($dv -cmatch '<[^>]*>') { $errs.Add("unsubstituted template placeholder in pre-impl-playbook-decisions '$t'"); continue }
        if ($requiredClass -contains $t) {
            if ($tv -eq 'yes') {
                if (-not (($dv -cmatch '^invoked$') -or ($dv -cmatch '^required-but-skipped:\s*"[^"\s][^"]*"\s*$'))) {
                    $errs.Add("pre-impl-playbook-decisions '$t' (REQUIRED class, trigger=yes) must be invoked / required-but-skipped:`"...`" (got '$dv')")
                }
            } elseif ($dv -cne 'not-required-trigger-not-detected') {
                $errs.Add("pre-impl-playbook-decisions '$t' (REQUIRED class, trigger=no) must be not-required-trigger-not-detected (got '$dv')")
            }
        } elseif ($tv -eq 'yes') {
            if (-not (($dv -cmatch '^invoked$') -or ($dv -cmatch '^offered-and-declined:\s*"[^"\s][^"]*"\s*$') -or ($dv -cmatch '^required-but-skipped:\s*"[^"\s][^"]*"\s*$'))) {
                $errs.Add("pre-impl-playbook-decisions '$t' (OFFERED, trigger=yes) must be invoked / offered-and-declined:`"...`" / required-but-skipped:`"...`" (got '$dv')")
            }
        } else {
            if ($dv -cne 'not-applicable') { $errs.Add("pre-impl-playbook-decisions '$t' (OFFERED, trigger=no) must be not-applicable (got '$dv')") }
        }
    }
    foreach ($t in $invokePlaybooks) {
        $iv = if ($pv.Contains($t)) { [string]$pv[$t] } else { $null }
        if ($null -eq $iv) { $errs.Add("playbook-invocations missing '$t'"); continue }
        if ($iv -cmatch '<[^>]*>') { $errs.Add("unsubstituted template placeholder in playbook-invocations '$t'"); continue }
        if (-not (($iv -cmatch '^ran\b') -or ($iv -cmatch '^N/A:\s*\S'))) { $errs.Add("playbook-invocations '$t' must be 'ran (...)' or 'N/A: <reason>' (got '$iv')") }
    }
    return $errs.ToArray()
}

function Test-LedgerImplementationCheckpoint {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $LedgerLines)
    $errs = New-Object System.Collections.Generic.List[string]
    $map = Get-LedgerSubBlockMap -LedgerLines $LedgerLines -ParentKey 'implementation-checkpoint'
    if ($null -eq $map) {
        $errs.Add("missing required 'implementation-checkpoint:' block (the pre-code-change DESIGN panel ran, so the implementation node must be co-present)")
        return $errs.ToArray()
    }

    $status = if ($map.Contains('status')) { [string]$map['status'] } else { $null }
    if ($null -eq $status) { $errs.Add("implementation-checkpoint missing 'status'") }
    elseif ($status -cmatch '<[^>]*>') { $errs.Add("unsubstituted template placeholder in implementation-checkpoint 'status'") }
    elseif ($status -cne 'complete') { $errs.Add("implementation-checkpoint 'status' must be 'complete' (got '$status')") }

    $designReady = if ($map.Contains('design_ready')) { [string]$map['design_ready'] } else { $null }
    if ($null -eq $designReady) { $errs.Add("implementation-checkpoint missing 'design_ready'") }
    elseif ($designReady -cmatch '<[^>]*>') { $errs.Add("unsubstituted template placeholder in implementation-checkpoint 'design_ready'") }
    elseif ($designReady -cne 'yes') { $errs.Add("implementation-checkpoint 'design_ready' must be 'yes' (got '$designReady')") }

    $diffMatches = if ($map.Contains('diff_matches_design')) { [string]$map['diff_matches_design'] } else { $null }
    if ($null -eq $diffMatches) {
        $errs.Add("implementation-checkpoint missing 'diff_matches_design'")
    } elseif ($diffMatches -cmatch '^<.*>$') {
        $errs.Add("unsubstituted template placeholder in implementation-checkpoint 'diff_matches_design'")
    } elseif ($diffMatches -cmatch '^diverged:\s*"(.*)"\s*$') {
        $note = $matches[1]
        if ([string]::IsNullOrWhiteSpace($note) -or ($note -cmatch '^\s*<[^>]*>\s*$')) {
            $errs.Add("implementation-checkpoint 'diff_matches_design' diverged note must be a non-empty real note, not a '<...>' placeholder (got '$diffMatches')")
        }
    } elseif ($diffMatches -cne 'yes') {
        $errs.Add("implementation-checkpoint 'diff_matches_design' must be 'yes' or a diverged disclosure ('diverged:`"<one-line note>`"') (got '$diffMatches')")
    }

    return $errs.ToArray()
}

function Test-PanelLedger {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $LedgerLines,
        [Parameter(Mandatory)] [string] $ExpectedParentSha,
        [Parameter(Mandatory)] [ValidateRange(0, 2)] [int] $GovernanceTier,
        [bool] $RequiresFull = $false,
        [bool] $PostAdoption = $false,
        [switch] $BoundStaged,
        [switch] $RequireArtifact,
        [int] $WorktreeDivergentCount = 0,
        [string] $ExpectedIndexTree = '',
        [string] $ExpectedArtifact = '',
        [string] $RegistryText = '',
        [string] $StagedRegistryText = '',
        [string[]] $HeavyModels = @(),
        [int] $GuardedPathCount = 0
    )
    $result = [PSCustomObject]@{ Valid = $true; Errors = @(); ParentSha = $null }
    if (($BoundStaged -or $PostAdoption) -and $GuardedPathCount -gt 0) {
        $guardRows = @($LedgerLines | Where-Object { $_ -cmatch '^checker-edit:' })
        if ($guardRows.Count -ne 1 -or $guardRows[0] -cnotmatch ('^checker-edit:\s*"checker-edit-acknowledged"\s+ref:[^\s<>]+\s+paths:' + $GuardedPathCount + '\s*$')) { $result.Valid = $false; $result.Errors += "checker-edit acknowledgement requires matching paths:$GuardedPathCount" }
    }
    $panelRequired = ($GovernanceTier -ge 1) -or $RequiresFull
    $safetyCritical = ($GovernanceTier -ge 2) -or ($RequiresFull -and $PostAdoption)
    $profileValueLine = $LedgerLines | Where-Object { [string]$_ -cmatch '^profile:\s*\S' } | Select-Object -First 1
    if ($profileValueLine -and $profileValueLine -cnotmatch '^profile:\s*(full|triage)\s*$') { $result.Valid = $false; $result.Errors += 'profile must be full or triage in a panel ledger' }
    if ($RequiresFull -and $profileValueLine -cmatch '^profile:\s*triage\s*$') { $result.Valid = $false; $result.Errors += 'triage is forbidden when full panel is required' }

    $LedgerLines = @($LedgerLines)
    if ($LedgerLines.Count -gt 0 -and $LedgerLines[0]) { $LedgerLines[0] = ([string]$LedgerLines[0]).TrimStart([char]0xFEFF) }

    $parentShaLine = $LedgerLines | Where-Object { $_ -cmatch '^parent_sha:\s*(.+?)\s*$' } | Select-Object -First 1
    if (-not $parentShaLine) {
        $result.Valid = $false; $result.Errors += "missing required 'parent_sha:' header"; return $result
    }
    $commitSubjectLine = $LedgerLines | Where-Object { $_ -cmatch '^commit_subject:\s*(.+?)\s*$' } | Select-Object -First 1
    if (-not $commitSubjectLine) {
        $result.Valid = $false; $result.Errors += "missing required 'commit_subject:' header"; return $result
    }
    if ($commitSubjectLine -cmatch '^commit_subject:\s*<') {
        $result.Valid = $false; $result.Errors += "unsubstituted template placeholder for commit_subject"; return $result
    }
    if ($parentShaLine -cmatch '^parent_sha:\s*<') {
        $result.Valid = $false; $result.Errors += "unsubstituted template placeholder for parent_sha"; return $result
    }
    if ($parentShaLine -cmatch '^parent_sha:\s*([a-fA-F0-9]{40}|[a-fA-F0-9]{64})\s*$') {
        $result.ParentSha = $matches[1]
        if ($ExpectedParentSha -eq $script:GitEmptyTreeSha) {
            $result.Valid = $false
            $result.Errors += "ledger declares hex parent_sha '$($result.ParentSha)' but expected root-commit empty-tree sentinel"
        } elseif (-not $ExpectedParentSha.Equals($result.ParentSha, [System.StringComparison]::OrdinalIgnoreCase)) {
            $result.Valid = $false
            $result.Errors += "ledger parent_sha '$($result.ParentSha)' does not match expected '$ExpectedParentSha' (stale ledger)"
        }
    } elseif ($parentShaLine -cmatch '^parent_sha:\s*(NONE|EMPTY_TREE)\s*$') {
        if ($ExpectedParentSha -ne $script:GitEmptyTreeSha) {
            $result.Valid = $false
            $result.Errors += "ledger declares root-commit placeholder '$($matches[1])' but commit has a real parent '$ExpectedParentSha'"
        } else {
            $result.ParentSha = $matches[1]
        }
    } else {
        $result.Valid = $false
        $result.Errors += "ledger parent_sha value is invalid (must be a full 40- or 64-char hex SHA, NONE, or EMPTY_TREE): $parentShaLine"
        return $result
    }

    # post-code-change-panel: the load-bearing row (na invalid when the diff is panel-required).
    $panelLine = $LedgerLines | Where-Object { $_ -cmatch '^\s*post-code-change-panel:\s*\S' } | Select-Object -First 1
    if (-not $panelLine) {
        $result.Valid = $false; $result.Errors += "missing required 'post-code-change-panel:' row"
    } else {
        $panelVal = ($panelLine -replace '^\s*post-code-change-panel:\s*', '').Trim()
        if ($panelVal -cmatch '<[^>]*>') {
            $result.Valid = $false; $result.Errors += "unsubstituted template placeholder for post-code-change-panel"
        } else {
            $ran    = $panelVal -cmatch '^ran,\s*unanimous\s*$'
            $waived = $panelVal -cmatch '^user-waived:\s*"panel-waive-acknowledged"\s+ref:[^\s<>]+\s*$'
            $na     = $panelVal -cmatch '^N/A:\s*\S'
            if ($safetyCritical) {
                if (-not $ran) {
                    $result.Valid = $false
                    $result.Errors += "post-code-change-panel must be 'ran, unanimous' (a user-waive or N/A is NOT permitted for a path-detectable safety-critical change); got: '$panelVal'"
                }
            } elseif ($panelRequired) {
                if (-not ($ran -or $waived)) {
                    $result.Valid = $false
                    $result.Errors += "post-code-change-panel must be 'ran, unanimous' or a tightened 'user-waived' (panel-waive-acknowledged token + ref:<call-ref>) because the diff touches code/governance paths; got: '$panelVal'"
                }
            } else {
                if (-not ($ran -or $waived -or $na)) {
                    $result.Valid = $false
                    $result.Errors += "post-code-change-panel must be 'ran, unanimous', 'N/A: <reason>', or a tightened 'user-waived' (panel-waive-acknowledged token + ref:<call-ref>); got: '$panelVal'"
                }
            }
            if ($ran) {
                foreach ($transcriptError in (Test-PanelTranscript -LedgerLines $LedgerLines -ExpectedArtifact $ExpectedArtifact -RequireArtifact:($BoundStaged -or $RequireArtifact) -RegistryText $RegistryText -StagedRegistryText $StagedRegistryText -PostAdoption:$PostAdoption -RequiresFull:$RequiresFull -HeavyModels $HeavyModels)) {
                    $result.Valid = $false; $result.Errors += $transcriptError
                }
            }
        }
    }

    $panelRan = ($panelLine -and (($panelLine -replace '^\s*post-code-change-panel:\s*', '').Trim() -cmatch '^ran,\s*unanimous\s*$'))
    $prePanelLine = $LedgerLines | Where-Object { $_ -cmatch '^\s*pre-code-change-panel:\s*\S' } | Select-Object -First 1
    if (-not $prePanelLine) {
        if ($panelRequired) { $result.Valid = $false; $result.Errors += "missing required 'pre-code-change-panel:' row (the diff touches code/governance paths)" }
    } else {
        $preVal = ($prePanelLine -replace '^\s*pre-code-change-panel:\s*', '').Trim()
        if ($preVal -cmatch '<[^>]*>') {
            $result.Valid = $false; $result.Errors += "unsubstituted template placeholder for pre-code-change-panel"
        } else {
            $preRan    = $preVal -cmatch '^ran,\s*unanimous\s*$'
            $preWaived = $preVal -cmatch '^user-waived:\s*"panel-waive-acknowledged"\s+ref:[^\s<>]+\s*$'
            $preNa     = $preVal -cmatch '^N/A:\s*\S'
            if ($safetyCritical) {
                if (-not $preRan) {
                    $result.Valid = $false
                    $result.Errors += "pre-code-change-panel must be 'ran, unanimous' (a user-waive or N/A is NOT permitted for a path-detectable safety-critical change); got: '$preVal'"
                }
            } elseif ($panelRequired) {
                if (-not ($preRan -or $preWaived)) {
                    $result.Valid = $false
                    $result.Errors += "pre-code-change-panel must be 'ran, unanimous' or a tightened 'user-waived' (panel-waive-acknowledged token + ref:<call-ref>) because the diff touches code/governance paths; got: '$preVal'"
                }
            } else {
                if (-not ($preRan -or $preWaived -or $preNa)) {
                    $result.Valid = $false
                    $result.Errors += "pre-code-change-panel must be 'ran, unanimous', 'N/A: <reason>', or a tightened 'user-waived'; got: '$preVal'"
                }
            }
            if ($preRan) {
                foreach ($e in (Test-PrePanelTranscript -LedgerLines $LedgerLines -PostAdoption:$PostAdoption -RequiresFull:$RequiresFull -HeavyModels $HeavyModels)) {
                    $result.Valid = $false; $result.Errors += $e
                }
                foreach ($e in (Test-LedgerImplementationCheckpoint -LedgerLines $LedgerLines)) {
                    $result.Valid = $false; $result.Errors += $e
                }
            }
        }
    }

    foreach ($e in (Test-LedgerDisclosureRow -LedgerLines $LedgerLines -RowKey 'diagnosis-repro-ref' -Required $panelRequired -AllowedRegexes @('^reproduction-locked:\s*\S', '^benchmark:\s*\S', '^N/A:\s*\S'))) {
        $result.Valid = $false; $result.Errors += $e
    }
    foreach ($e in (Test-LedgerDisclosureRow -LedgerLines $LedgerLines -RowKey 'approach-selection-G3' -Required $panelRequired -AllowedRegexes @('^fix-cause\s*$', '^document-symptom:\s*"[^"\s][^"]*"\s*$', '^N/A:\s*\S'))) {
        $result.Valid = $false; $result.Errors += $e
    }
    $g5Allowed = if ($safetyCritical) { @('^panel-ran\s*$') } else { @('^not-applicable\s*$', '^panel-ran\s*$', '^safety-critical-confirmed-skip:\s*ref:[^\s<>]+\s*$') }
    foreach ($e in (Test-LedgerDisclosureRow -LedgerLines $LedgerLines -RowKey 'safety-critical-eval-G5' -Required $panelRequired -AllowedRegexes $g5Allowed)) {
        $result.Valid = $false; $result.Errors += $e
    }

    if ($panelRequired) {
        foreach ($e in (Test-LedgerG6 -LedgerLines $LedgerLines)) { $result.Valid = $false; $result.Errors += $e }
    }

    $buildLine = $LedgerLines | Where-Object { $_ -cmatch '^\s*build:\s*\S' } | Select-Object -First 1
    if (-not $buildLine) {
        $result.Valid = $false; $result.Errors += "missing required 'build:' row"
    } elseif ($buildLine -cmatch '^\s*build:\s*<') {
        $result.Valid = $false; $result.Errors += "unsubstituted template placeholder for build"
    } else {
        $buildVal = ($buildLine -replace '^\s*build:\s*', '').Trim()
        if ($buildVal -imatch '^failed') {
            $result.Valid = $false; $result.Errors += "build row reports failure"
        } elseif (-not ($buildVal -imatch '^passed\b' -or $buildVal -imatch '^N/A:\s*\S')) {
            $result.Valid = $false; $result.Errors += "build row must be 'passed[, <details>]', 'failed: <reason>', or 'N/A: <reason>' (got: '$buildVal')"
        }
    }

    $testsLine = $LedgerLines | Where-Object { $_ -cmatch '^\s*tests:\s*\S' } | Select-Object -First 1
    if (-not $testsLine) {
        $result.Valid = $false; $result.Errors += "missing required 'tests:' row"
    } elseif ($testsLine -cmatch '^\s*tests:\s*<') {
        $result.Valid = $false; $result.Errors += "unsubstituted template placeholder for tests"
    } else {
        $testsVal = ($testsLine -replace '^\s*tests:\s*', '').Trim()
        if ($testsVal -imatch '^failed') {
            $result.Valid = $false; $result.Errors += "tests row reports failure"
        } elseif (-not ($testsVal -imatch '^passed\b' -or $testsVal -imatch '^N/A:\s*\S')) {
            $result.Valid = $false; $result.Errors += "tests row must be 'passed[, <details>]', 'failed: <reason>', or 'N/A: <reason>' (got: '$testsVal')"
        }
    }

    if ($BoundStaged) {
        $evidenceLine = @($LedgerLines | Where-Object { [string]$_ -cmatch '^evidence-tree:' })
        if ($evidenceLine.Count -ne 1 -or $evidenceLine[0] -cnotmatch '^evidence-tree:\s*(worktree-clean|index-export\s+tree:([0-9a-fA-F]{40}|[0-9a-fA-F]{64}))\s*$') {
            $result.Valid = $false; $result.Errors += 'bound staged ledger requires evidence-tree: worktree-clean or index-export tree:<full-tree-sha>'
        } elseif ($matches[1] -eq 'worktree-clean' -and $WorktreeDivergentCount -ne 0) {
            $result.Valid = $false; $result.Errors += "evidence-tree worktree-clean is invalid when worktree_divergent=$WorktreeDivergentCount"
        } elseif ($matches[2] -and $ExpectedIndexTree -and $matches[2] -cne $ExpectedIndexTree) {
            $result.Valid = $false; $result.Errors += 'evidence-tree index-export does not match git write-tree for the current index'
        }
        $slugRows = @($LedgerLines | Where-Object { [string]$_ -match '^\s*slug-review:' })
        $topLevelSlugRows = @($LedgerLines | Where-Object { [string]$_ -cmatch '^slug-review:' })
        $slugReviewPattern = '^slug-review:\s*ran\s+findings:([0-9]+)\s+fixed:([0-9]+)\s+routed:([0-9]+)\s*$'
        $slugReviewMatch = if ($topLevelSlugRows.Count -eq 1) { [regex]::Match([string]$topLevelSlugRows[0], $slugReviewPattern) } else { $null }
        if ($slugRows.Count -ne 1 -or $topLevelSlugRows.Count -ne 1 -or -not $slugReviewMatch.Success) {
            $result.Valid = $false; $result.Errors += 'bound staged ledger requires exactly one top-level slug-review row: ran findings:<n> fixed:<k> routed:<j>'
        } else {
            [decimal]$slugFindings = 0
            [decimal]$slugFixed = 0
            [decimal]$slugRouted = 0
            $countsValid = [decimal]::TryParse($slugReviewMatch.Groups[1].Value, [System.Globalization.NumberStyles]::None, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$slugFindings) -and
                [decimal]::TryParse($slugReviewMatch.Groups[2].Value, [System.Globalization.NumberStyles]::None, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$slugFixed) -and
                [decimal]::TryParse($slugReviewMatch.Groups[3].Value, [System.Globalization.NumberStyles]::None, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$slugRouted)
            if (-not $countsValid) {
                $result.Valid = $false; $result.Errors += 'slug-review counts must be non-negative decimal integers'
            } elseif ($slugFindings -ne ($slugFixed + $slugRouted)) {
                $result.Valid = $false; $result.Errors += 'slug-review findings must equal fixed + routed'
            } else {
                $slugRowIndex = [array]::IndexOf([object[]]$LedgerLines, [object]$topLevelSlugRows[0])
                $panelTranscriptFindingsIndex = -1
                $insidePanelTranscript = $false
                for ($lineIndex = 0; $lineIndex -lt $LedgerLines.Count; $lineIndex++) {
                    $line = [string]$LedgerLines[$lineIndex]
                    if ($line -cmatch '^\s*panel-transcript:\s*$') { $insidePanelTranscript = $true; continue }
                    if ($insidePanelTranscript -and $line -cmatch '^\s*-\s*findings:\s*\S') {
                        $panelTranscriptFindingsIndex = $lineIndex
                        break
                    }
                }
                if ($panelRan -and ($panelTranscriptFindingsIndex -lt 0 -or $slugRowIndex -le $panelTranscriptFindingsIndex)) {
                    $result.Valid = $false; $result.Errors += 'slug-review row must be top-level and follow the post-code-change panel transcript'
                }
            }
        }
    }

    if (@($result.Errors).Count -gt 0) { $result.Valid = $false }
    return $result
}

function Get-BlockBulletChildren {
    # Bounded sub-block scan: return the '- ' bullet child lines under a top-level 'HeaderKey:' line,
    # stopping at the next top-level 'key:' line (so a later section's bullets can never satisfy an
    # earlier empty header). Returns $null when the header is absent, else the (possibly empty) array.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $Lines,
        [Parameter(Mandatory)] [string] $HeaderKey
    )
    $ls = @($Lines)
    $headerRx = '^\s*' + [regex]::Escape($HeaderKey) + ':\s*(#.*)?$'
    $headerIdx = -1
    for ($i = 0; $i -lt $ls.Count; $i++) {
        if (([string]$ls[$i]) -cmatch $headerRx) { $headerIdx = $i; break }
    }
    if ($headerIdx -lt 0) { return $null }
    $children = New-Object System.Collections.Generic.List[string]
    for ($i = $headerIdx + 1; $i -lt $ls.Count; $i++) {
        $ln = [string]$ls[$i]
        if ($ln -match '^\s*$' -or $ln -cmatch '^\s*#') { continue }
        if ($ln -cmatch '^\s*-\s') { $children.Add($ln); continue }
        if ($ln -cmatch '^\s*[A-Za-z][\w-]*:') { break }
    }
    return , $children.ToArray()
}

function Test-PreCommitGateValue {
    # Placeholder check on an already-extracted value: an unsubstituted '<...>' survives stripping quoted
    # substrings (an unquoted placeholder), OR a quoted substring is itself a bare '<...>' placeholder
    # (e.g. keep_reason:"<rationale>"). Stripping quoted content keeps legit angle-bracket syntax
    # (List<T>, "handles <T>") from false-matching, matching Test-LedgerDisclosureRow's quote-aware guard.
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Value)
    return ((($Value -replace '"[^"]*"', '""') -cmatch '<[^>]*>') -or ($Value -cmatch '"\s*<[^>]*>\s*"'))
}

function Test-PreCommitGateBlock {
    # Validator for the PRE-COMMIT GATE PASSED receipt/note body (the 4th audit receipt). Asserts only
    # the load-bearing user-approval keys + parent_sha freshness (opaque to other rows, mirroring
    # Test-PanelLedger). Slug enumeration is required only for a code/governance (tier>=1) commit; the
    # user-approval fields (diff_approved / subject_approved / staged_diff_verified / commit_ownership /
    # rule_coverage_passed) are required on EVERY commit.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $BlockLines,
        [Parameter(Mandatory)] [string] $ExpectedParentSha,
        [Parameter(Mandatory)] [ValidateRange(0, 2)] [int] $GovernanceTier,
        [bool] $RequiresFull = $false,
        [bool] $PostAdoption = $false
    )
    $result = [PSCustomObject]@{ Valid = $true; Errors = @(); ParentSha = $null }
    $lines = @($BlockLines)
    if ($lines.Count -gt 0 -and $lines[0]) { $lines[0] = ([string]$lines[0]).TrimStart([char]0xFEFF) }
    $tierRequiresSlugs = $GovernanceTier -ge 1

    $parentShaLine = $lines | Where-Object { $_ -cmatch '^parent_sha:\s*(.+?)\s*$' } | Select-Object -First 1
    if (-not $parentShaLine) {
        $result.Valid = $false; $result.Errors += "missing required 'parent_sha:' header"; return $result
    }
    if ($parentShaLine -cmatch '^parent_sha:\s*<') {
        $result.Valid = $false; $result.Errors += "unsubstituted template placeholder for parent_sha"; return $result
    }
    if ($parentShaLine -cmatch '^parent_sha:\s*([a-fA-F0-9]{40}|[a-fA-F0-9]{64})\s*$') {
        $result.ParentSha = $matches[1]
        if ($ExpectedParentSha -eq $script:GitEmptyTreeSha) {
            $result.Valid = $false
            $result.Errors += "block declares hex parent_sha '$($result.ParentSha)' but expected root-commit empty-tree sentinel"
        } elseif (-not $ExpectedParentSha.Equals($result.ParentSha, [System.StringComparison]::OrdinalIgnoreCase)) {
            $result.Valid = $false
            $result.Errors += "block parent_sha '$($result.ParentSha)' does not match expected '$ExpectedParentSha' (stale block)"
        }
    } elseif ($parentShaLine -cmatch '^parent_sha:\s*(NONE|EMPTY_TREE)\s*$') {
        if ($ExpectedParentSha -ne $script:GitEmptyTreeSha) {
            $result.Valid = $false
            $result.Errors += "block declares root-commit placeholder '$($matches[1])' but commit has a real parent '$ExpectedParentSha'"
        } else {
            $result.ParentSha = $matches[1]
        }
    } else {
        $result.Valid = $false
        $result.Errors += "block parent_sha value is invalid (must be a full 40- or 64-char hex SHA, NONE, or EMPTY_TREE): $parentShaLine"
        return $result
    }

    $commitSubjectLine = $lines | Where-Object { $_ -cmatch '^commit_subject:' } | Select-Object -First 1
    if (-not $commitSubjectLine) {
        $result.Valid = $false; $result.Errors += "missing required 'commit_subject:' header"
    } elseif ($commitSubjectLine -cmatch '^commit_subject:\s*<') {
        $result.Valid = $false; $result.Errors += "unsubstituted template placeholder for commit_subject"
    } elseif ($commitSubjectLine -cnotmatch '^commit_subject:\s*\S') {
        $result.Valid = $false; $result.Errors += "'commit_subject:' header is empty/whitespace-only"
    }

    if (-not ($lines | Where-Object { $_ -cmatch '^\s*PRE-COMMIT GATE PASSED\s*$' } | Select-Object -First 1)) {
        $result.Valid = $false; $result.Errors += "missing required 'PRE-COMMIT GATE PASSED' header line"
    }

    $gateLine = $lines | Where-Object { $_ -cmatch '^\s*gate\|' } | Select-Object -First 1
    if (-not $gateLine) {
        $result.Valid = $false; $result.Errors += "missing required 'gate|' line"
    } else {
        foreach ($key in @('diff_shown', 'diff_approved', 'staged_diff_verified')) {
            if ($gateLine -cmatch ('\|' + $key + '=([^|]*)')) {
                $v = ([string]$matches[1]).Trim()
                if ($v -cnotmatch '^yes\b') {
                    $result.Valid = $false; $result.Errors += "gate '$key' must be an affirmative 'yes...' (got: '$v')"
                }
            } else {
                $result.Valid = $false; $result.Errors += "gate line missing required key '$key'"
            }
        }
        if ($gateLine -cmatch '\|commit_ownership=([^|]*)') {
            $v = ([string]$matches[1]).Trim()
            if ($v -cnotmatch '^(agent|user)$') {
                $result.Valid = $false; $result.Errors += "gate 'commit_ownership' must be 'agent' or 'user' (got: '$v')"
            }
        } else {
            $result.Valid = $false; $result.Errors += "gate line missing required key 'commit_ownership'"
        }
        if ($gateLine -cmatch '\|profile=([^|]*)') {
            $profileValue = ([string]$matches[1]).Trim()
            if ($PostAdoption -and $profileValue -cnotmatch '^(full|triage|lint-only)$') {
                $result.Valid = $false; $result.Errors += "gate 'profile' must be full, triage or lint-only (got: '$profileValue')"
            } elseif ($RequiresFull -and $profileValue -cne 'full') {
                $result.Valid = $false; $result.Errors += "gate 'profile' must be full when the instruction-repo full panel is required (got: '$profileValue')"
            }
        } else {
            $result.Valid = $false; $result.Errors += "gate line missing required key 'profile'"
        }
        if ($gateLine -cmatch '\|rule_coverage_passed=([^|]*)') {
            $v = ([string]$matches[1]).Trim()
            if ($v -cnotmatch '^(true|false)$') {
                $result.Valid = $false; $result.Errors += "gate 'rule_coverage_passed' must be 'true' or 'false' (got: '$v')"
            } elseif ($tierRequiresSlugs -and $v -cne 'true') {
                $result.Valid = $false; $result.Errors += "gate 'rule_coverage_passed' must be 'true' for a code/governance (tier>=1) commit (got: '$v')"
            }
        } else {
            $result.Valid = $false; $result.Errors += "gate line missing required key 'rule_coverage_passed'"
        }
    }

    $subjectLine = $lines | Where-Object { $_ -cmatch '^\s*subject\|' } | Select-Object -First 1
    if (-not $subjectLine) {
        $result.Valid = $false; $result.Errors += "missing required 'subject|' line"
    } else {
        if ($subjectLine -cmatch '\|proposed_subject="(.*)"\|subject_approved=') {
            $ps = [string]$matches[1]
            if ([string]::IsNullOrWhiteSpace($ps) -or ($ps -cmatch '^\s*<')) {
                $result.Valid = $false; $result.Errors += "subject 'proposed_subject' must be a non-empty real subject, not empty/placeholder (got: '$ps')"
            }
        } else {
            $result.Valid = $false; $result.Errors += "subject line missing required quoted 'proposed_subject=`"...`"'"
        }
        if ($subjectLine -cmatch '\|subject_approved=([^|]*)') {
            $v = ([string]$matches[1]).Trim()
            if ($v -cnotmatch '^yes\b') {
                $result.Valid = $false; $result.Errors += "subject 'subject_approved' must be an affirmative 'yes...' (got: '$v')"
            }
        } else {
            $result.Valid = $false; $result.Errors += "subject line missing required key 'subject_approved'"
        }
        if ($subjectLine -cmatch '\|format_check=([^|]*)') {
            $fc = [string]$matches[1]
            # Genuine git reverts carry a git-generated body (single_line:no, body:yes); mirror
            # check-commit-message.ps1's `^Revert "` exemption by relaxing only those two polarities.
            $isRevert = $commitSubjectLine -and ($commitSubjectLine -cmatch '^commit_subject:\s*Revert "')
            $expectedBools = [ordered]@{
                'single_line'                = 'yes'
                'co_authored_by_trailer'     = 'no'
                'body'                       = 'no'
                'conventional_commit_prefix' = 'no'
            }
            $relaxedKeys = if ($isRevert) { @('single_line', 'body') } else { @() }
            $seen = @{}
            $fcErrors = @()
            foreach ($tok in ($fc -split ',')) {
                if ($tok -cnotmatch '^([a-z_]+):(.+)$') { $fcErrors += "malformed subfield '$tok'"; continue }
                $key = $matches[1]; $val = $matches[2]
                if ($seen.ContainsKey($key)) { $fcErrors += "duplicate subfield '$key'"; continue }
                $seen[$key] = $val
                if ($key -eq 'subject_length_chars') {
                    $lenVal = 0
                    if (-not [int]::TryParse($val, [ref]$lenVal) -or $lenVal -lt 0) {
                        $fcErrors += "subject_length_chars must be a non-negative integer (got '$val')"
                    } elseif (-not $isRevert -and $lenVal -gt 72) {
                        $fcErrors += "subject_length_chars must be <= 72 (got '$val')"
                    }
                } elseif ($expectedBools.Contains($key)) {
                    if ($relaxedKeys -contains $key) {
                        if ($val -cne 'yes' -and $val -cne 'no') { $fcErrors += "$key must be 'yes' or 'no' (got '$val')" }
                    } elseif ($val -cne $expectedBools[$key]) {
                        $fcErrors += "$key must be '$($expectedBools[$key])' (got '$val')"
                    }
                } else {
                    $fcErrors += "unknown subfield '$key'"
                }
            }
            foreach ($requiredKey in @($expectedBools.Keys) + 'subject_length_chars') {
                if (-not $seen.ContainsKey($requiredKey)) { $fcErrors += "missing subfield '$requiredKey'" }
            }
            if ($fcErrors.Count -gt 0) {
                $result.Valid = $false; $result.Errors += "subject 'format_check' invalid: $($fcErrors -join '; ') (got: '$fc')"
            }
        } else {
            $result.Valid = $false; $result.Errors += "subject line missing required key 'format_check'"
        }
    }

    $craChildren = Get-BlockBulletChildren -Lines $lines -HeaderKey 'core_rules_acknowledged'
    if ($null -eq $craChildren) {
        $result.Valid = $false; $result.Errors += "missing required 'core_rules_acknowledged:' block"
    } elseif ($tierRequiresSlugs) {
        $slugBullets = @($craChildren | Where-Object { $_ -cmatch '^\s*-\s*slug:\S' })
        if ($slugBullets.Count -lt 1) {
            $result.Valid = $false; $result.Errors += "core_rules_acknowledged has no '- slug:<slug>' entries (required for a code/governance tier>=1 commit)"
        }
        foreach ($bullet in $craChildren) {
            if (Test-PreCommitGateValue -Value $bullet) {
                $result.Valid = $false; $result.Errors += "core_rules_acknowledged has an unsubstituted placeholder: $($bullet.Trim())"; break
            }
        }
    }

    $sfChildren = Get-BlockBulletChildren -Lines $lines -HeaderKey 'staged_files'
    if ($null -eq $sfChildren) {
        $result.Valid = $false; $result.Errors += "missing required 'staged_files:' block"
    } else {
        $pathBullets = @($sfChildren | Where-Object { $_ -cmatch '^\s*-\s*\S' })
        if ($pathBullets.Count -lt 1) {
            $result.Valid = $false; $result.Errors += "staged_files has no enumerated paths"
        } else {
            foreach ($bullet in $pathBullets) {
                if (Test-PreCommitGateValue -Value $bullet) {
                    $result.Valid = $false; $result.Errors += "staged_files has an unsubstituted placeholder: $($bullet.Trim())"; break
                }
            }
        }
    }

    if (@($result.Errors).Count -gt 0) { $result.Valid = $false }
    return $result
}

Export-ModuleMember -Function Get-HeavyModelPolicy, Get-RegistryRotationMap, Test-PanelRegistryBinding, Test-GuardedPath, Test-RequiresFullPanel, Test-RewriteRequiresFullPanel, Test-IsPostAdoption, Test-PathPanelRequired, Get-PanelRequired, Get-PathGovernanceTier, Get-ChangedGovernanceTier, Test-PanelLedger, Test-PanelTranscript, Test-PrePanelTranscript, Test-Transcript, Test-IsArtifactBindingAdopted, Test-LedgerG6, Test-LedgerImplementationCheckpoint, Get-LedgerSubBlockMap, Get-PanelSlateFloor, Get-GitEmptyTreeSha, Test-PreCommitGateBlock -Variable GitEmptyTreeSha, GuardedPathPatterns, NonGuardedPathPatterns
