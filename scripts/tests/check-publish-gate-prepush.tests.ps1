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
    Write-Host "`n=== identity gate ==="
    $f = New-PgRepo -Foreign
    $r = Run $f @((RefLine (Head $f)))
    Assert-True ($r.ExitCode -eq 0) 'non-instructions repo -> exit 0 (never blocks a consumer)'

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
    Import-Module ./scripts/lib/audit-note-helpers.psm1 -Force
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
}
finally { Remove-TestTempDirectories }

Complete-TestRun
