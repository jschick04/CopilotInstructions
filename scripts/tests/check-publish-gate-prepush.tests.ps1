#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-common.ps1')
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$checker = Join-Path $repoRoot 'scripts/check-publish-gate-prepush.ps1'

$script:Pass = 0; $script:Fail = 0
$zero = '0' * 40
$tokPush = 'a1b2c3d4'
$tokCreate = 'e5f6a7b8'
$readsPush = "reads=.github/playbooks/pre-pr-push.md@$tokPush"
$readsCreate = "reads=.github/playbooks/pre-pr-creation-review.md@$tokCreate"

function New-PgRepo {
    param([switch] $Foreign, [switch] $OmitCreationReview)
    $dir = New-TestGitRepository -Prefix 'pg'
    git -C $dir remote add origin ($(if ($Foreign) { 'https://github.com/someone/other.git' } else { 'https://github.com/jschick04/CopilotInstructions.git' }))
    Set-Content -LiteralPath (Join-Path $dir 'AGENTS.md') -Value 'x' -NoNewline
    New-Item -ItemType Directory -Path (Join-Path $dir 'scripts') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $dir 'scripts/check-post-code-change.ps1') -Value 'x' -NoNewline
    New-Item -ItemType Directory -Path (Join-Path $dir '.github/pr-quality-gate/audits') -Force | Out-Null
    if (-not $Foreign) { Set-Content -LiteralPath (Join-Path $dir '.github/pr-quality-gate/panel-policy.md') -Value 'fixture policy' }
    New-Item -ItemType Directory -Path (Join-Path $dir '.github/playbooks') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $dir '.github/playbooks/pre-pr-push.md') -Value "# push`n<!-- read-receipt-token: $tokPush -->`n"
    if (-not $OmitCreationReview) {
        Set-Content -LiteralPath (Join-Path $dir '.github/playbooks/pre-pr-creation-review.md') -Value "# create`n<!-- read-receipt-token: $tokCreate -->`n"
    }
    git -C $dir add -A 2>$null
    git -C $dir commit -q -m init
    return $dir
}
function Head { param($Dir) (git -C $Dir rev-parse HEAD).Trim() }
function WriteReceipt { param($Dir, [string[]] $Lines) Set-Content -LiteralPath (Join-Path $Dir '.github/pr-quality-gate/audits/publish-gate-receipt') -Value $Lines }
function RefLine { param($Sha, $Dst = 'refs/heads/main', $RemoteSha = $zero) "refs/heads/main $Sha $Dst $RemoteSha" }
function Run {
    param($Dir, [string[]] $Refs, [string] $RemoteUrl = '')
    $a = @('-NoProfile', '-File', $checker, '-RepoRoot', $Dir, '-RefUpdateLines') + $Refs
    if ($RemoteUrl) { $a += @('-RemoteUrl', $RemoteUrl) }
    $out = & pwsh @a 2>&1
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($out | Out-String) }
}

try {
    Write-Host "`n=== git-object activation ==="
    $f = New-PgRepo -Foreign
    $r = Run $f @((RefLine (Head $f)))
    Assert-True ($r.ExitCode -eq 0) 'non-instructions repo -> exit 0 (never blocks a consumer)'

    $baseBranch = (git -C $f rev-parse --abbrev-ref HEAD).Trim()
    git -C $f checkout -q -b adopted 2>$null
    Set-Content -LiteralPath (Join-Path $f '.github/pr-quality-gate/panel-policy.md') -Value 'fixture policy'
    git -C $f add -A 2>$null; git -C $f commit -q -m adopt
    $adoptedTip = Head $f
    git -C $f checkout -q $baseBranch 2>$null
    $r = Run $f @((RefLine $adoptedTip))
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'no publish-gate receipt') 'pre-adoption checkout pushing an adopted branch requires a receipt'
    $r = Run $f @("refs/heads/main $adoptedTip refs/tags/v1 $zero")
    Assert-True ($r.ExitCode -eq 0) 'adopted tip pushed to an exempt namespace stays exempt'

    Write-Host "`n=== sha256 object ids ==="
    $zero64 = '0' * 64
    $r = Run $f @("refs/heads/main $zero64 refs/heads/gone $('c' * 64)")
    Assert-True ($r.ExitCode -eq 0) '64-hex all-zero local sha is a deletion, not a malformed line'
    $r = Run $f @("refs/heads/main $('c' * 52) refs/heads/main $zero64")
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'malformed object id') '52-hex object id still rejected'
    $repo256 = New-TestTempDirectory -Prefix 'pg256'
    & git -C $repo256 init -q --object-format=sha256 2>$null
    if ($LASTEXITCODE -eq 0) {
        New-Item -ItemType Directory -Path (Join-Path $repo256 '.github/pr-quality-gate/audits') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $repo256 '.github/playbooks') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $repo256 '.github/pr-quality-gate/panel-policy.md') -Value 'fixture policy'
        Set-Content -LiteralPath (Join-Path $repo256 '.github/playbooks/pre-pr-push.md') -Value "# push`n<!-- read-receipt-token: $tokPush -->`n"
        Set-Content -LiteralPath (Join-Path $repo256 '.github/playbooks/pre-pr-creation-review.md') -Value "# create`n<!-- read-receipt-token: $tokCreate -->`n"
        git -C $repo256 add -A 2>$null; git -C $repo256 -c user.name=t -c user.email=t@example.com commit -q -m init 2>$null
        $tip256 = Head $repo256
        Assert-Equal 64 $tip256.Length 'sha256 fixture produces a 64-hex tip'
        $r = Run $repo256 @("refs/heads/main $tip256 refs/heads/main $zero64")
        Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'no publish-gate receipt') '64-hex governed push activates and requires a receipt'
        WriteReceipt $repo256 @("publish_gate_ready: turn-1 remote:origin dst:refs/heads/main sha:$tip256", $readsPush, $readsCreate)
        $r = Run $repo256 @("refs/heads/main $tip256 refs/heads/main $zero64")
        Assert-True ($r.ExitCode -eq 0) "64-hex receipt sha marker authorizes the matching 64-hex tip: $($r.Output)"
        WriteReceipt $repo256 @("publish_gate_ready: turn-1 remote:origin dst:refs/heads/main sha:$($tip256.Substring(0, 40))", $readsPush, $readsCreate)
        $r = Run $repo256 @("refs/heads/main $tip256 refs/heads/main $zero64")
        Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'no fresh publish-gate receipt') '40-hex prefix of a 64-hex tip does not authorize'
    }

    Write-Host "`n=== not-applicable pushes ==="
    $d = New-PgRepo
    $r = Run $d @("refs/heads/main $zero refs/heads/main $(Head $d)")
    Assert-True ($r.ExitCode -eq 0) 'branch delete -> exit 0 (nothing published)'
    $r = Run $d @("refs/tags/v1 $(Head $d) refs/tags/v1 $zero")
    Assert-True ($r.ExitCode -eq 0) 'tag push -> exit 0 (exempt namespace)'
    $r = Run $d @("refs/notes/x $(Head $d) refs/notes/copilot-audit-panel $zero")
    Assert-True ($r.ExitCode -eq 0) 'notes push -> exit 0 (exempt by remote ref)'

    Write-Host "`n=== publish_gate_ready happy path ==="
    $d = New-PgRepo; $h = Head $d
    WriteReceipt $d @("publish_gate_ready: turn-1 remote:origin dst:refs/heads/main sha:$h", $readsPush, $readsCreate)
    $r = Run $d @((RefLine $h))
    Assert-True ($r.ExitCode -eq 0) 'publish_gate_ready + matching remote/dst/sha + fresh both reads -> 0'

    WriteReceipt $d @("publish_gate_ready: turn-1 remote:github.com/jschick04/copilotinstructions dst:refs/heads/main sha:$h", $readsPush, $readsCreate)
    $r = Run $d @((RefLine $h)) 'https://github.com/jschick04/CopilotInstructions.git'
    Assert-True ($r.ExitCode -eq 0) 'RemoteUrl normalized identity matches -> 0'
    $r = Run $d @((RefLine $h)) 'https://github.com/jschick04/Other.git'
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'no fresh publish-gate receipt') 'retargeted remote URL -> 1'

    Write-Host "`n=== sandbox_push_declared ==="
    $d = New-PgRepo; $h = Head $d
    WriteReceipt $d @("sandbox_push_declared: turn-2 remote:origin dst:refs/heads/main sha:$h", $readsPush)
    $r = Run $d @((RefLine $h))
    Assert-True ($r.ExitCode -eq 0) 'sandbox_push_declared + pre-pr-push read only -> 0'

    Write-Host "`n=== refs/for governed path ==="
    $d = New-PgRepo; $h = Head $d
    WriteReceipt $d @("publish_gate_ready: turn-1 remote:origin dst:refs/for/main sha:$h", $readsPush, $readsCreate)
    $r = Run $d @("HEAD $h refs/for/main $zero")
    Assert-True ($r.ExitCode -eq 0) 'refs/for/* is governed and authorized -> 0'

    Write-Host "`n=== remote URL with spaces (local path) ==="
    Import-Module (Join-Path $repoRoot 'scripts/lib/audit-note-helpers.psm1') -Force
    $spaceUrl = 'C:\my repo\backup'
    $spaceId = Get-NormalizedRemoteIdentity -Url $spaceUrl
    $d = New-PgRepo; $h = Head $d
    WriteReceipt $d @("publish_gate_ready: turn-1 remote:$spaceId dst:refs/heads/main sha:$h", $readsPush, $readsCreate)
    $r = Run $d @((RefLine $h)) $spaceUrl
    Assert-True ($r.ExitCode -eq 0 -and $spaceId -match '\s') 'spaced-path remote identity round-trips and matches -> 0 (not falsely blocked)'

    Write-Host "`n=== violations ==="
    $d = New-PgRepo; $h = Head $d
    $r = Run $d @((RefLine $h))
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'no publish-gate receipt exists') 'missing receipt -> 1'

    WriteReceipt $d @("publish_gate_ready: turn-1 remote:origin dst:refs/heads/main sha:$('a'*40)", $readsPush, $readsCreate)
    $r = Run $d @((RefLine $h))
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'no fresh publish-gate receipt') 'wrong sha -> 1'

    git -C $d commit -q --allow-empty -m empty
    $h2 = Head $d
    WriteReceipt $d @("publish_gate_ready: turn-1 remote:origin dst:refs/heads/main sha:$h", $readsPush, $readsCreate)
    $r = Run $d @((RefLine $h2))
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'no fresh publish-gate receipt') 'same tree, different sha (stale) -> 1'

    WriteReceipt $d @("publish_gate_ready: turn-1 remote:origin dst:refs/heads/other sha:$h2", $readsPush, $readsCreate)
    $r = Run $d @((RefLine $h2))
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'no fresh publish-gate receipt') 'wrong dst ref -> 1'

    WriteReceipt $d @("publish_gate_ready: turn-1 remote:origin dst:refs/heads/main sha:$($h2.Substring(0,12))", $readsPush, $readsCreate)
    $r = Run $d @((RefLine $h2))
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'no fresh publish-gate receipt') '12-hex sha prefix in marker -> 1 (no match; 40-hex required)'

    WriteReceipt $d @("publish_gate_ready: turn-1 remote:origin dst:refs/heads/Main sha:$h2", $readsPush, $readsCreate)
    $r = Run $d @("refs/heads/Main $h2 refs/heads/Main $zero")
    Assert-True ($r.ExitCode -eq 0) 'case-exact dst matches -> 0'
    $r = Run $d @((RefLine $h2))
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'no fresh publish-gate receipt') 'case-mismatch dst (Main vs main) -> 1'

    WriteReceipt $d @(
        "publish_gate_ready: turn-1 remote:origin dst:refs/heads/main sha:$h2",
        "sandbox_push_declared: turn-2 remote:origin dst:refs/heads/main sha:$h2",
        $readsPush, $readsCreate)
    $r = Run $d @((RefLine $h2))
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'ambiguous') 'duplicate matching rows -> 1'

    WriteReceipt $d @("publish_gate_ready: turn-1 remote:origin dst:refs/heads/main sha:$h2", $readsPush)
    $r = Run $d @((RefLine $h2))
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'missing the read citation') 'ready citing only one playbook -> 1'

    WriteReceipt $d @("publish_gate_ready: turn-1 remote:origin dst:refs/heads/main sha:$h2", $readsPush, "reads=.github/playbooks/pre-pr-creation-review.md@deadbeef")
    $r = Run $d @((RefLine $h2))
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'stale read token') 'stale reads token -> 1'

    WriteReceipt $d @("publish_gate_ready: turn-1 remote:origin dst:refs/heads/main sha:$h2", $readsPush, $readsCreate, $readsCreate)
    $r = Run $d @((RefLine $h2))
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'duplicate reads citation') 'duplicate reads line -> 1'

    WriteReceipt $d @("publish_gate_ready: turn-1 remote:origin dst:refs/heads/main sha:$h2", $readsPush, $readsCreate, 'reads=.github/playbooks/pre-pr-creation-review.md@BADTOKEN')
    $r = Run $d @((RefLine $h2))
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'malformed reads citation') 'malformed reads line -> 1'

    WriteReceipt $d @("publish_gate_ready: turn-1 remote:origin dst:refs/heads/main sha:$h2", $readsPush, $readsCreate, 'reads=   @deadbeef')
    $r = Run $d @((RefLine $h2))
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'malformed reads citation') 'whitespace-only reads file -> 1 (not silently accepted)'

    Write-Host "`n=== missing playbook blob at tip ==="
    $d = New-PgRepo -OmitCreationReview; $h = Head $d
    WriteReceipt $d @("publish_gate_ready: turn-1 remote:origin dst:refs/heads/main sha:$h", $readsPush, $readsCreate)
    $r = Run $d @((RefLine $h))
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'cannot read') 'playbook absent at pushed tip -> 1'

    Write-Host "`n=== malformed input + multi-ref ==="
    $d = New-PgRepo; $h = Head $d
    $r = Run $d @("refs/heads/main $h refs/heads/main")
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'malformed pre-push ref-update line') 'malformed 4-field ref line -> 1'
    $r = Run $d @("refs/heads/main nothex refs/heads/main $zero")
    Assert-True ($r.ExitCode -eq 1 -and $r.Output -match 'malformed object id') 'non-hex object id -> 1'
    $multi = @((RefLine $h 'refs/heads/main'), (RefLine $h 'refs/heads/second'))
    $mout = $multi | & pwsh -NoProfile -File $checker -RepoRoot $d 2>&1
    Assert-True ($LASTEXITCODE -eq 1 -and ($mout | Out-String) -match 'branches separately') 'multi-ref governed push -> 1 (reject)'

    $creationPlaybook = Get-Content -LiteralPath (Join-Path $repoRoot '.github/playbooks/pre-pr-creation-review.md') -Raw
    $triggerCode = [regex]::Match($creationPlaybook, '(?s)```powershell\s*(\$priorHeadSha =.*?)```').Groups[1].Value
    Assert-True ($triggerCode -match '\$priorBase = <prior-run panelBaseSha' -and $triggerCode -match '\$priorCommitCount = <prior-run panelCommitCount') 'rerun procedure initializes prior base and commit count'
    $triggerCode = $triggerCode -replace '<prior-run panelHeadSha, or "none">', '"none"' -replace '<prior-run panelBaseSha, or "none">', '"none"' -replace '<prior-run panelCommitCount, or 0>', '0'
    $triggerCode = $triggerCode -replace '<recorded base_url>', '$baseRepo' -replace '<recorded base_branch>', '"main"'
    $triggerBlock = [scriptblock]::Create($triggerCode + "`n[pscustomobject]@{ Base = `$currentBase; Count = `$currentCommitCount; Triggers = (`$triggers -join ',') }")
    $gitExe = (Get-Command git -CommandType Application | Select-Object -First 1).Source
    $baseRepo = New-TestGitRepository -Prefix 'approved-base'
    $baseSeed = New-TestCommit -Directory $baseRepo -File 'base.txt' -Content 'base' -Message 'base'
    $localRepo = New-TestTempDirectory -Prefix 'base-local'
    & $gitExe clone -q --no-local $baseRepo $localRepo
    if ($LASTEXITCODE -ne 0) { throw 'cannot clone base resolution fixture' }
    $newTip = New-TestCommit -Directory $baseRepo -File 'base.txt' -Content 'new tip' -Message 'new tip'
    function Invoke-BaseResolution {
        param([string] $RemoteCase = 'actual')
        function git {
            $global:LASTEXITCODE = 0
            if ($args[0] -eq 'ls-remote') {
                switch ($RemoteCase) {
                    'empty' { return }
                    'duplicate' { "$newTip`trefs/heads/main"; "$newTip`trefs/heads/main"; return }
                    'malformed' { 'not-a-sha refs/heads/main'; return }
                    'short' { "$($newTip.Substring(0,7))`trefs/heads/main"; return }
                    'wrongref' { "$newTip`trefs/heads/other"; return }
                    'shift' { "$baseSeed`trefs/heads/main"; return }
                    'failed' { $global:LASTEXITCODE = 1; return }
                }
            }
            & $gitExe @args
            $global:LASTEXITCODE = $LASTEXITCODE
        }
        & $triggerBlock
    }
    Push-Location $localRepo
    try {
        foreach ($remoteCase in @('empty','duplicate','malformed','short','wrongref','failed')) {
            Assert-ThrowsLike -Action { Invoke-BaseResolution -RemoteCase $remoteCase } -Pattern 'remote record|SHA/ref record' -Name "rerun base resolution rejects $remoteCase remote output"
        }
        $resolved = Invoke-BaseResolution
        Assert-Equal $baseSeed $resolved.Base 'remote record resolves to SHA-only merge-base after fetching missing object'
        Assert-Equal 0 $resolved.Count 'first-run count uses restored prior-state initialization'
        Assert-Equal 'first-run' $resolved.Triggers 'first-run trigger survives valid remote resolution'
        $resolvedAgain = Invoke-BaseResolution
        Assert-Equal $baseSeed $resolvedAgain.Base 'already available remote commit resolves without fetching'
    } finally { Pop-Location }

    Write-Host "`n=== pre-push hook: invoked checkers fail closed when absent or diverged from HEAD ==="
    $hookRepo = New-TestGitRepository -Prefix 'pph'
    $hookRemote = New-TestTempDirectory -Prefix 'pphr'
    git init -q --bare $hookRemote
    git -C $hookRepo remote add origin $hookRemote
    git -C $hookRepo config core.autocrlf false
    New-Item -ItemType Directory -Path (Join-Path $hookRepo '.githooks'), (Join-Path $hookRepo 'scripts/lib'), (Join-Path $hookRepo 'scripts/tests'), (Join-Path $hookRepo '.github/pr-quality-gate/sub') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $hookRepo '.githooks/pre-push'), ((Get-Content -Raw -LiteralPath (Join-Path $repoRoot '.githooks/pre-push')) -replace "`r`n", "`n"))
    foreach ($stub in 'check-audit-notes-prepush.ps1', 'check-signoff.ps1', 'check-publish-gate-prepush.ps1', 'run-local-ci.ps1', 'Get-ReviewedArtifactId.ps1', 'flush-audits.ps1') {
        Set-Content -LiteralPath (Join-Path $hookRepo "scripts/$stub") -Value 'exit 0'
    }
    Set-Content -LiteralPath (Join-Path $hookRepo 'scripts/lib/stub.psm1') -Value 'function Get-Stub { 1 }'
    Set-Content -LiteralPath (Join-Path $hookRepo 'scripts/tests/stub.tests.ps1') -Value 'exit 0'
    [IO.File]::WriteAllText((Join-Path $hookRepo 'scripts/lf-only.ps1'), "exit 0`n")
    Set-Content -LiteralPath (Join-Path $hookRepo '.github/pr-quality-gate/gate.ps1') -Value 'exit 0'
    Set-Content -LiteralPath (Join-Path $hookRepo '.github/pr-quality-gate/sub/runner.sh') -Value 'exit 0'
    Set-Content -LiteralPath (Join-Path $hookRepo '.github/pr-quality-gate/notes.md') -Value 'notes'
    if ($env:OS -ne 'Windows_NT') { & chmod +x (Join-Path $hookRepo '.githooks/pre-push') }
    git -C $hookRepo add -A
    git -C $hookRepo update-index --chmod=+x .githooks/pre-push
    $null = New-TestCommit -Directory $hookRepo -File 'a.txt' -Content 'a' -Message 'hook fixture'
    Assert-True ((git -C $hookRepo ls-tree HEAD .githooks/pre-push) -match '^100755 ') 'fixture commits the pre-push hook as executable (100755)'
    function Invoke-HookPush {
        $output = @(& git -C $hookRepo -c core.hooksPath=.githooks push -q origin HEAD:refs/heads/probe 2>&1)
        $code = $LASTEXITCODE
        & git -C $hookRepo push -q --no-verify origin --delete probe 2>$null | Out-Null
        return [PSCustomObject]@{ ExitCode = $code; Output = ($output | Out-String) }
    }
    function Reset-HookRepo {
        & git -C $hookRepo reset -q --hard HEAD
        & git -C $hookRepo clean -q -fd
    }
    $clean = Invoke-HookPush
    Assert-True ($clean.ExitCode -eq 0 -and $clean.Output -notmatch 'ERROR') "clean hook checkers -> push passes ($($clean.Output.Trim()))"
    foreach ($checker in 'check-signoff.ps1', 'check-audit-notes-prepush.ps1', 'check-publish-gate-prepush.ps1', 'run-local-ci.ps1') {
        Remove-Item -LiteralPath (Join-Path $hookRepo "scripts/$checker")
        $missing = Invoke-HookPush
        Assert-True ($missing.ExitCode -ne 0 -and $missing.Output -match [regex]::Escape("scripts/$checker")) "missing worktree $checker -> push fails"
        Reset-HookRepo
        Set-Content -LiteralPath (Join-Path $hookRepo "scripts/$checker") -Value 'exit 0 # edited'
        $edited = Invoke-HookPush
        Assert-True ($edited.ExitCode -ne 0 -and $edited.Output -match [regex]::Escape("scripts/$checker")) "unstaged edit to $checker -> push fails"
        & git -C $hookRepo add -- "scripts/$checker"
        $staged = Invoke-HookPush
        Assert-True ($staged.ExitCode -ne 0) "staged-but-uncommitted edit to $checker -> push fails"
        Reset-HookRepo
    }
    Set-Content -LiteralPath (Join-Path $hookRepo 'scripts/lib/stub.psm1') -Value 'function Get-Stub { 2 }'
    $libEdit = Invoke-HookPush
    Assert-True ($libEdit.ExitCode -ne 0 -and $libEdit.Output -match 'scripts/lib') 'unstaged scripts/lib module edit -> push fails'
    Reset-HookRepo
    Set-Content -LiteralPath (Join-Path $hookRepo 'scripts/lib/extra.psm1') -Value 'function Get-Extra { 1 }'
    $libUntracked = Invoke-HookPush
    Assert-True ($libUntracked.ExitCode -ne 0 -and $libUntracked.Output -match 'scripts/lib') 'untracked scripts/lib module -> push fails'
    Reset-HookRepo
    Set-Content -LiteralPath (Join-Path $hookRepo 'scripts/Get-ReviewedArtifactId.ps1') -Value 'exit 0 # edited'
    $artifactEdit = Invoke-HookPush
    Assert-True ($artifactEdit.ExitCode -ne 0 -and $artifactEdit.Output -match 'Get-ReviewedArtifactId') 'unstaged Get-ReviewedArtifactId.ps1 edit -> push fails'
    Reset-HookRepo
    Add-Content -LiteralPath (Join-Path $hookRepo '.githooks/pre-push') -Value '# edited'
    $hookEdit = Invoke-HookPush
    Assert-True ($hookEdit.ExitCode -ne 0 -and $hookEdit.Output -match '\.githooks') 'unstaged .githooks edit -> push fails'
    Reset-HookRepo
    Set-Content -LiteralPath (Join-Path $hookRepo 'b.txt') -Value 'b'
    $unrelated = Invoke-HookPush
    Assert-True ($unrelated.ExitCode -eq 0) 'unrelated untracked file -> push still passes'
    Reset-HookRepo
    foreach ($flag in '--skip-worktree', '--assume-unchanged') {
        & git -C $hookRepo update-index $flag -- scripts/check-signoff.ps1
        Set-Content -LiteralPath (Join-Path $hookRepo 'scripts/check-signoff.ps1') -Value 'exit 0 # hidden edit'
        Assert-True ([string]::IsNullOrWhiteSpace((git -C $hookRepo status --porcelain -- scripts/check-signoff.ps1 | Out-String))) "fixture: $flag hides the edit from git status"
        $hidden = Invoke-HookPush
        Assert-True ($hidden.ExitCode -ne 0 -and $hidden.Output -match 'scripts/check-signoff\.ps1') "$flag + edited checker -> push fails"
        & git -C $hookRepo update-index ($flag -replace '^--', '--no-') -- scripts/check-signoff.ps1
        Reset-HookRepo
        & git -C $hookRepo update-index $flag -- scripts/check-signoff.ps1
        $hiddenClean = Invoke-HookPush
        Assert-True ($hiddenClean.ExitCode -eq 0) "$flag on an unedited checker -> push passes"
        & git -C $hookRepo update-index ($flag -replace '^--', '--no-') -- scripts/check-signoff.ps1
    }
    foreach ($guarded in 'scripts/tests/stub.tests.ps1', '.github/pr-quality-gate/gate.ps1', '.github/pr-quality-gate/sub/runner.sh') {
        Add-Content -LiteralPath (Join-Path $hookRepo $guarded) -Value '# edited'
        $guardedEdit = Invoke-HookPush
        Assert-True ($guardedEdit.ExitCode -ne 0 -and $guardedEdit.Output -match [regex]::Escape($guarded)) "unstaged edit to $guarded -> push fails and names the path"
        Reset-HookRepo
    }
    Set-Content -LiteralPath (Join-Path $hookRepo '.github/pr-quality-gate/new.ps1') -Value 'exit 0'
    Set-Content -LiteralPath (Join-Path $hookRepo 'scripts/new-checker.ps1') -Value 'exit 0'
    $twoUntracked = Invoke-HookPush
    Assert-True ($twoUntracked.ExitCode -ne 0 -and $twoUntracked.Output -match '\.github/pr-quality-gate/new\.ps1' -and $twoUntracked.Output -match 'scripts/new-checker\.ps1') 'every untracked enforcement path is named'
    Reset-HookRepo
    Add-Content -LiteralPath (Join-Path $hookRepo '.github/pr-quality-gate/notes.md') -Value 'edited'
    $notesEdit = Invoke-HookPush
    Assert-True ($notesEdit.ExitCode -eq 0) 'non-script pr-quality-gate edit -> push still passes'
    Reset-HookRepo
    git -C $hookRepo config core.autocrlf true
    [IO.File]::WriteAllText((Join-Path $hookRepo 'scripts/lf-only.ps1'), "exit 0`r`n")
    $crlfClean = Invoke-HookPush
    Assert-True ($crlfClean.ExitCode -eq 0) "autocrlf CRLF worktree copy of an LF-committed checker -> push passes ($($crlfClean.Output.Trim()))"
    [IO.File]::WriteAllText((Join-Path $hookRepo 'scripts/lf-only.ps1'), "exit 1`r`n")
    $crlfEdit = Invoke-HookPush
    Assert-True ($crlfEdit.ExitCode -ne 0 -and $crlfEdit.Output -match 'scripts/lf-only\.ps1') 'autocrlf content edit -> push fails'
    git -C $hookRepo config core.autocrlf false
    Reset-HookRepo
}
finally { Remove-TestTempDirectories }

Complete-TestRun
