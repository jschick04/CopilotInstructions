#Requires -Version 5.1
# Standalone pwsh self-test for scripts/check-structural-conformance.ps1.
# NOT Pester. Run: pwsh -File scripts/tests/check-structural-conformance.tests.ps1

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-common.ps1')
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$checker = Join-Path $repoRoot 'scripts/check-structural-conformance.ps1'

$script:Pass = 0; $script:Fail = 0

function New-ManifestDir {
    param([string[]] $Rules)
    $dir = New-TestTempDirectory -Prefix 'sc'
    $manifest = @('# test manifest') + $Rules
    Set-Content -LiteralPath (Join-Path $dir 'manifest.txt') -Value $manifest
    return $dir
}
function Run {
    param([string] $Dir, [hashtable] $Opts)
    $a = @('-NoProfile', '-File', $checker, '-RepoRoot', $Dir, '-ManifestPath', 'manifest.txt', '-Quiet') + ($Opts.GetEnumerator() | ForEach-Object { "-$($_.Key)"; if ($_.Value -isnot [switch] -and $_.Value -ne $true) { $_.Value } })
    $out = & pwsh @a 2>&1
    return [PSCustomObject]@{ ExitCode = $LASTEXITCODE; Output = ($out | Out-String) }
}

$RULES = @('scripts/*.ps1', 'src/Features/*/*.cs', '.github/playbooks/*/*.md', 'docs/*.md')

try {
    Write-Host "`n=== matching via -Paths ==="
    $d = New-ManifestDir -Rules $RULES
    $r = Run $d @{ Paths = 'scripts/new-check.ps1' }
    Assert-True ($r.ExitCode -eq 0) 'conforming path (scripts/new-check.ps1) -> exit 0'
    $r = Run $d @{ Paths = 'src/Features/Orders/PlaceOrder.cs' }
    Assert-True ($r.ExitCode -eq 0) 'conforming nested slice (src/Features/Orders/PlaceOrder.cs) -> exit 0'

    Write-Host "`n=== the user's divergence failure ==="
    # manifest allows src/Features/*; session B invents src/Modules/Billing -> must HARD-BLOCK
    $r = Run $d @{ Paths = 'src/Modules/Billing/Payment.cs' }
    Assert-True ($r.ExitCode -eq 1) "divergent layout (src/Modules/Billing/Payment.cs) -> exit 1 (HARD-BLOCK)"
    Assert-True ($r.Output -match 'do NOT conform|UNMATCHED') 'reports the non-conformance'
    $r = Run $d @{ Paths = 'scripts/lib/helper.psm1' }
    Assert-True ($r.ExitCode -eq 1) 'misplaced file (scripts/lib/*.psm1 not allowed by this manifest) -> exit 1'

    Write-Host "`n=== manifest validation (anchored-prefix MUST) ==="
    $bad = New-ManifestDir -Rules @('**/*.cs')
    $r = Run $bad @{ Paths = 'src/Features/Orders/X.cs' }
    Assert-True ($r.ExitCode -eq 2 -and $r.Output -match 'not anchored|leading-wildcard') 'leading-wildcard rule (**/*.cs) -> exit 2 config error'
    $bad2 = New-ManifestDir -Rules @('*/Commands/*.cs')
    $r = Run $bad2 @{ Paths = 'src/Commands/X.cs' }
    Assert-True ($r.ExitCode -eq 2) 'leading-wildcard rule (*/Commands/*.cs) -> exit 2'

    Write-Host "`n=== no manifest -> no-op ==="
    $empty = New-TestTempDirectory -Prefix 'sc-none'
    $r = Run $empty @{ Paths = 'anything/goes.cs' }
    Assert-True ($r.ExitCode -eq 0) 'no manifest present -> exit 0 (no-op)'

    Write-Host "`n=== staged (index) ACR detection in a real repo ==="
    $g = New-TestGitRepository -Prefix 'sc-git'
    New-Item -ItemType Directory -Path (Join-Path $g 'src/Features/Orders') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $g 'scripts') -Force | Out-Null
    Set-Content (Join-Path $g 'manifest.txt') (@('# m') + $RULES)
    Set-Content (Join-Path $g 'src/Features/Orders/Existing.cs') 'x'
    git -C $g add -A 2>$null; git -C $g commit -q -m base
    Set-Content (Join-Path $g 'scripts/tool.ps1') 'x'; git -C $g add scripts/tool.ps1 2>$null
    $r = Run $g @{}
    Assert-True ($r.ExitCode -eq 0) 'staged conforming new file -> exit 0'
    New-Item -ItemType Directory -Path (Join-Path $g 'src/Modules/Billing') -Force | Out-Null
    Set-Content (Join-Path $g 'src/Modules/Billing/Pay.cs') 'x'; git -C $g add src/Modules/Billing/Pay.cs 2>$null
    $r = Run $g @{}
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'Modules/Billing') 'staged divergent new file -> exit 1'
    # reset; MODIFY an existing conforming file (M, not ACR) -> not checked
    git -C $g reset -q; git -C $g checkout -q -- .
    Add-Content (Join-Path $g 'src/Features/Orders/Existing.cs') 'more'; git -C $g add src/Features/Orders/Existing.cs 2>$null
    $r = Run $g @{}
    Assert-True ($r.ExitCode -eq 0) 'staged MODIFY of an existing file (not ACR) -> exit 0 (only new/moved paths are gated)'

    Write-Host "`n=== rename re-homing to a divergent location ==="
    git -C $g reset -q; git -C $g checkout -q -- .
    New-Item -ItemType Directory -Path (Join-Path $g 'src/Wrong') -Force | Out-Null
    git -C $g mv src/Features/Orders/Existing.cs src/Wrong/Existing.cs 2>$null
    $r = Run $g @{}
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'src/Wrong') 'rename re-homing code to a divergent dir -> exit 1 (new path checked)'

    Write-Host "`n=== base-pinned manifest (a PR cannot broaden its OWN gate) ==="
    $mPath = '.github/pr-quality-gate/structure-manifest.txt'   # the checker's DEFAULT -ManifestPath
    $bp = New-TestGitRepository -Prefix 'sc-bp'
    New-Item -ItemType Directory -Path (Join-Path $bp '.github/pr-quality-gate') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $bp 'src/Features/Orders') -Force | Out-Null
    # BASE: manifest allows only src/Features/*/*.cs
    Set-Content (Join-Path $bp $mPath) @('# base manifest', 'src/Features/*/*.cs', '.github/pr-quality-gate/*.txt')
    Set-Content (Join-Path $bp 'src/Features/Orders/Existing.cs') 'x'
    git -C $bp add -A 2>$null; git -C $bp commit -q -m base
    $baseSha = ((git -C $bp rev-parse HEAD) | Out-String).Trim()
    # HEAD: broaden the WORKTREE manifest to ALSO allow src/Modules/*, and add a divergent file
    Set-Content (Join-Path $bp $mPath) @('# broadened', 'src/Features/*/*.cs', 'src/Modules/*/*.cs', '.github/pr-quality-gate/*.txt')
    New-Item -ItemType Directory -Path (Join-Path $bp 'src/Modules/Billing') -Force | Out-Null
    Set-Content (Join-Path $bp 'src/Modules/Billing/Pay.cs') 'x'
    git -C $bp add -A 2>$null; git -C $bp commit -q -m head
    # -BaseRef + NO -ManifestPath -> read the manifest from BASE (M1, no Modules) -> BLOCK
    $o = (& pwsh @('-NoProfile', '-File', $checker, '-RepoRoot', $bp, '-BaseRef', $baseSha, '-Quiet') 2>&1 | Out-String); $c = $LASTEXITCODE
    Assert-True ($c -eq 1 -and $o -match 'Modules/Billing') 'base-pinned manifest BLOCKS a path the PR-head manifest would admit (cannot broaden own gate)'
    # control: with the broadened WORKTREE manifest explicitly pinned, the same path is admitted
    & pwsh @('-NoProfile', '-File', $checker, '-RepoRoot', $bp, '-BaseRef', $baseSha, '-ManifestPath', $mPath, '-Quiet') 2>&1 | Out-Null; $c2 = $LASTEXITCODE
    Assert-True ($c2 -eq 0) 'explicit worktree (broadened) manifest admits the path (control: base-pin is what blocks)'
    # git failure -> fail closed (exit 2), not a silent exit 0
    $ogf = (& pwsh @('-NoProfile', '-File', $checker, '-RepoRoot', $bp, '-BaseRef', 'no-such-ref-xyz', '-ManifestPath', $mPath, '-Quiet') 2>&1 | Out-String); $cgf = $LASTEXITCODE
    Assert-True ($cgf -eq 2 -and $ogf -match 'Failing closed') 'git diff failure (bad -BaseRef) -> exit 2 (fail closed, not exit 0)'
    # unresolvable -BaseRef WITHOUT an explicit -ManifestPath -> the base-pinned manifest read must
    # NOT silently fall back to the worktree (which would let a PR define its own gate); fail closed.
    $obr = (& pwsh @('-NoProfile', '-File', $checker, '-RepoRoot', $bp, '-BaseRef', 'no-such-ref-xyz', '-Quiet') 2>&1 | Out-String); $cbr = $LASTEXITCODE
    Assert-True ($cbr -eq 2 -and $obr -match 'does not resolve|Failing closed') 'unresolvable -BaseRef (no -ManifestPath) -> exit 2 (fail closed, no worktree fallback)'

    Write-Host "`n=== bootstrap: base lacks the manifest -> fall back to the worktree manifest ==="
    $bs = New-TestGitRepository -Prefix 'sc-bs'
    New-Item -ItemType Directory -Path (Join-Path $bs 'scripts') -Force | Out-Null
    Set-Content (Join-Path $bs 'scripts/seed.ps1') 'x'
    git -C $bs add -A 2>$null; git -C $bs commit -q -m 'base (no manifest)'
    $bsBase = ((git -C $bs rev-parse HEAD) | Out-String).Trim()
    # HEAD introduces the manifest (scripts only) + a DIVERGENT file -> fallback must apply the worktree manifest
    New-Item -ItemType Directory -Path (Join-Path $bs '.github/pr-quality-gate') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $bs 'src/Modules') -Force | Out-Null
    Set-Content (Join-Path $bs $mPath) @('# m', 'scripts/*.ps1', '.github/pr-quality-gate/*.txt')
    Set-Content (Join-Path $bs 'scripts/tool.ps1') 'x'
    Set-Content (Join-Path $bs 'src/Modules/X.cs') 'x'
    git -C $bs add -A 2>$null; git -C $bs commit -q -m 'add manifest + divergent file'
    $o3 = (& pwsh @('-NoProfile', '-File', $checker, '-RepoRoot', $bs, '-BaseRef', $bsBase, '-Quiet') 2>&1 | Out-String); $c3 = $LASTEXITCODE
    Assert-True ($c3 -eq 1 -and $o3 -match 'Modules/X') 'bootstrap (base has no manifest) -> falls back to the worktree manifest + applies it (divergent file BLOCKED)'

    Write-Host "`n=== base has an EMPTY (0-byte) manifest -> fail closed, NOT worktree fallback ==="
    $be = New-TestGitRepository -Prefix 'sc-be'
    New-Item -ItemType Directory -Path (Join-Path $be '.github/pr-quality-gate') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $be 'scripts') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $be $mPath), '')   # 0-byte base manifest: git show exits 0, empty stdout
    Set-Content (Join-Path $be 'scripts/seed.ps1') 'x'
    git -C $be add -A 2>$null; git -C $be commit -q -m 'base (empty manifest)'
    $beBase = ((git -C $be rev-parse HEAD) | Out-String).Trim()
    # HEAD broadens the worktree manifest + adds a path; base-pin must NOT fall back to the broadened worktree
    Set-Content (Join-Path $be $mPath) @('scripts/*.ps1', 'src/Modules/*/*.cs')
    New-Item -ItemType Directory -Path (Join-Path $be 'src/Modules/Billing') -Force | Out-Null
    Set-Content (Join-Path $be 'src/Modules/Billing/Pay.cs') 'x'
    git -C $be add -A 2>$null; git -C $be commit -q -m head
    & pwsh @('-NoProfile', '-File', $checker, '-RepoRoot', $be, '-BaseRef', $beBase, '-Quiet') 2>&1 | Out-Null; $ce = $LASTEXITCODE
    Assert-True ($ce -eq 2) 'empty (0-byte) base manifest -> exit 2 config error (fail closed; NOT worktree fallback)'
}
finally { Remove-TestTempDirectories }

Complete-TestRun
