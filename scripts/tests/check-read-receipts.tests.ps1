#Requires -Version 5.1
# Unit tests for the code-topic read-receipt gate (check-read-receipts.ps1 + read-receipt-helpers.psm1).
# Fixtures are synthesized in TEMP git repos (never committed under scripts/tests, which would self-trigger
# the gate on a committed *.cs/*.razor fixture).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Pass = 0
$script:Fail = 0

. (Join-Path $PSScriptRoot 'test-common.ps1')
Import-Module (Join-Path $PSScriptRoot '../lib/read-receipt-helpers.psm1') -Force -DisableNameChecking
$checker = (Resolve-Path (Join-Path $PSScriptRoot '../check-read-receipts.ps1')).Path

function Invoke-Checker {
    param([string] $Repo)
    & pwsh -NoProfile -File $checker -RepoRoot $Repo -StagedMode -WorktreeReceipt *> $null
    return $LASTEXITCODE
}
function New-Instr {
    param([string] $Dir, [string] $Name, [string] $ApplyTo, [string] $Token)
    $body = "---`napplyTo: `"$ApplyTo`"`n---`n`n# $Name`n`n<!-- read-receipt-token: $Token -->`n"
    Set-Content -LiteralPath (Join-Path $Dir "$Name.instructions.md") -Value $body -NoNewline
}

Write-Host "=== brace + comma expansion (the enforce-1 critical case) ==="
$brace = Expand-ApplyToPatterns -ApplyTo '"**/*.{cs,py,go}"'
Assert-True ((($brace | Sort-Object) -join ',') -eq '**/*.cs,**/*.go,**/*.py') 'brace **/*.{cs,py,go} expands to 3 patterns'
$comma = Expand-ApplyToPatterns -ApplyTo '**/*.cs,**/*.razor'
Assert-True ($comma.Count -eq 2) 'top-level comma splits to 2'
$cart = Expand-ApplyToPatterns -ApplyTo '{a,b}/*.{cs,py}'
Assert-True ($cart.Count -eq 4) 'multiple brace groups -> Cartesian 4'
$noSplitInBrace = Split-ApplyToTopLevel '**/*.{cs,py},**/*.razor'
Assert-True ($noSplitInBrace.Count -eq 2) 'commas inside {} are not top-level separators'
$threwEmpty = $false; try { Expand-ApplyToPatterns -ApplyTo '**/*.{cs,}' | Out-Null } catch { $threwEmpty = $true }
Assert-True $threwEmpty 'empty alternation fails closed (throws)'
$threwUnbal = $false; try { Split-ApplyToTopLevel '**/*.{cs,py' | Out-Null } catch { $threwUnbal = $true }
Assert-True $threwUnbal 'unbalanced brace fails closed (throws)'

Write-Host "=== token + receipt parsing ==="
Assert-True ((Get-TokenFromContent -Content "# T`n<!-- read-receipt-token: a1b2c3d4 -->") -eq 'a1b2c3d4') 'token extracted from header'
Assert-True ($null -eq (Get-TokenFromContent -Content "# T`nno token here")) 'absent token -> null'
$rr = Read-ReadsReceipt -Lines @('parent_sha: abc1234', 'reads=foo/bar.md@deadbeef', 'noise')
Assert-True ($rr.ParentSha -eq 'abc1234' -and $rr.Reads['foo/bar.md'] -eq 'deadbeef') 'receipt parsed (parent + reads)'

Write-Host "=== gated set resolution (excludes the **/* universal file) ==="
$repo = New-TestGitRepository -Prefix 'rr'
$instr = Join-Path $repo '.github/instructions'; New-Item -ItemType Directory -Path $instr -Force | Out-Null
New-Instr -Dir $instr -Name 'fake-cs'  -ApplyTo '**/*.cs'      -Token '11111111'
New-Instr -Dir $instr -Name 'fake-py'  -ApplyTo '**/*.{py,go}' -Token '22222222'
New-Instr -Dir $instr -Name 'universal' -ApplyTo '**/*'        -Token '33333333'
git -C $repo add -A 2>$null; git -C $repo commit -q -m 'fixtures' 2>$null
$gated = @(Get-WorktreeGatedTopicFiles -RepoRoot $repo)
Assert-True ($gated.Count -eq 2) 'gated set = 2 (the **/* universal file is excluded)'

Write-Host "=== glob matching (root-level + brace-glob + docs-only skip) ==="
Set-Content (Join-Path $repo 'Program.cs') 'class P{}'
New-Item -ItemType Directory -Path (Join-Path $repo 'src') -Force | Out-Null
Set-Content (Join-Path $repo 'src/x.py') 'pass'
Set-Content (Join-Path $repo 'README.md') 'docs'
git -C $repo add -A 2>$null
$gitInvoke = { param($a) & git -C $repo @a }
$matched = @(Get-MatchedGatedFiles -GatedSet $gated -DiffArgs @('diff','--cached','--name-only') -GitInvoke $gitInvoke)
Assert-True ($matched.Count -eq 2) 'root-level Program.cs + brace-glob src/x.py both match'

Write-Host "=== checker end-to-end ==="
Assert-True ((Invoke-Checker $repo) -eq 1) 'staged code, no receipt -> exit 1'
$head = (git -C $repo rev-parse HEAD).Trim()
$aud = Join-Path $repo '.github/pr-quality-gate/audits'; New-Item -ItemType Directory -Path $aud -Force | Out-Null
$receiptPath = Join-Path $aud 'read-receipts-last.md'
Set-Content $receiptPath "parent_sha: $head`nreads=.github/instructions/fake-cs.instructions.md@11111111`nreads=.github/instructions/fake-py.instructions.md@22222222`n" -NoNewline
Assert-True ((Invoke-Checker $repo) -eq 0) 'valid receipt -> exit 0'
(Get-Content $receiptPath) -replace '11111111', '99999999' | Set-Content $receiptPath
Assert-True ((Invoke-Checker $repo) -eq 1) 'stale token -> exit 1'
Set-Content $receiptPath "parent_sha: $($head.Substring(0,12))`nreads=.github/instructions/fake-cs.instructions.md@11111111`nreads=.github/instructions/fake-py.instructions.md@22222222`n" -NoNewline
Assert-True ((Invoke-Checker $repo) -eq 1) 'abbreviated 12-char parent_sha -> exit 1 at commit (full 40-char required; closes the staged<->note wedge)'
Set-Content $receiptPath "parent_sha: $($head.ToUpper())`nreads=.github/instructions/fake-cs.instructions.md@11111111`nreads=.github/instructions/fake-py.instructions.md@22222222`n" -NoNewline
Assert-True ((Invoke-Checker $repo) -eq 0) 'uppercase 40-char parent_sha -> exit 0 (mixed-case hex accepted; case-insensitive match)'

Write-Host "=== docs-only clean-skip + tokenless fail-closed ==="
$repo2 = New-TestGitRepository -Prefix 'rr2'
$instr2 = Join-Path $repo2 '.github/instructions'; New-Item -ItemType Directory -Path $instr2 -Force | Out-Null
New-Instr -Dir $instr2 -Name 'fake-cs' -ApplyTo '**/*.cs' -Token '11111111'
git -C $repo2 add -A 2>$null; git -C $repo2 commit -q -m 'fix' 2>$null
Set-Content (Join-Path $repo2 'README.md') 'docs'; git -C $repo2 add -A 2>$null
Assert-True ((Invoke-Checker $repo2) -eq 0) 'docs-only commit -> clean-skip exit 0'
Set-Content (Join-Path $instr2 'fake-cs.instructions.md') "---`napplyTo: `"**/*.cs`"`n---`n`n# Fake CS`n`n(no token)`n" -NoNewline
Set-Content (Join-Path $repo2 'Foo.cs') 'class F{}'; git -C $repo2 add -A 2>$null
Assert-True ((Invoke-Checker $repo2) -eq 1) 'tokenless gated file + staged .cs -> fail-closed exit 1'

Write-Host "=== delete-only commit of a gated file clean-skips (ACMRT excludes D) ==="
$repo3 = New-TestGitRepository -Prefix 'rr3'
$instr3 = Join-Path $repo3 '.github/instructions'; New-Item -ItemType Directory -Path $instr3 -Force | Out-Null
New-Instr -Dir $instr3 -Name 'fake-cs' -ApplyTo '**/*.cs' -Token '11111111'
Set-Content (Join-Path $repo3 'Foo.cs') 'class F{}'
git -C $repo3 add -A 2>$null; git -C $repo3 commit -q -m 'init' 2>$null
git -C $repo3 rm -q Foo.cs 2>$null
Assert-True ((Invoke-Checker $repo3) -eq 0) 'delete-only gated .cs -> clean-skip exit 0 (--diff-filter=ACMRT excludes D)'

Write-Host "=== staged token is authoritative; a tokenless worktree edit does not false-fail (round-3 bot finding) ==="
$repo4 = New-TestGitRepository -Prefix 'rr4'
$instr4 = Join-Path $repo4 '.github/instructions'; New-Item -ItemType Directory -Path $instr4 -Force | Out-Null
New-Instr -Dir $instr4 -Name 'fake-cs' -ApplyTo '**/*.cs' -Token '11111111'
git -C $repo4 add -A 2>$null; git -C $repo4 commit -q -m 'init' 2>$null
Set-Content (Join-Path $repo4 'Foo.cs') 'class F{}'; git -C $repo4 add -A 2>$null
$head4 = (git -C $repo4 rev-parse HEAD).Trim()
$aud4 = Join-Path $repo4 '.github/pr-quality-gate/audits'; New-Item -ItemType Directory -Path $aud4 -Force | Out-Null
Set-Content (Join-Path $aud4 'read-receipts-last.md') "parent_sha: $head4`nreads=.github/instructions/fake-cs.instructions.md@11111111`n" -NoNewline
Set-Content (Join-Path $instr4 'fake-cs.instructions.md') "---`napplyTo: `"**/*.cs`"`n---`n`n# Fake CS`n`n(token removed in worktree, still present staged)`n" -NoNewline
Assert-True ((Invoke-Checker $repo4) -eq 0) 'tokenless worktree edit but valid staged token + receipt -> exit 0 (staged authoritative)'

Write-Host "=== staged EMPTY gated file fails closed even when the worktree token is valid (no fail-open) ==="
$repo5 = New-TestGitRepository -Prefix 'rr5'
$instr5 = Join-Path $repo5 '.github/instructions'; New-Item -ItemType Directory -Path $instr5 -Force | Out-Null
New-Instr -Dir $instr5 -Name 'fake-cs' -ApplyTo '**/*.cs' -Token '11111111'
git -C $repo5 add -A 2>$null; git -C $repo5 commit -q -m 'init' 2>$null
Set-Content -LiteralPath (Join-Path $instr5 'fake-cs.instructions.md') -Value '' -NoNewline
Set-Content (Join-Path $repo5 'Foo.cs') 'class F{}'
git -C $repo5 add -A 2>$null
New-Instr -Dir $instr5 -Name 'fake-cs' -ApplyTo '**/*.cs' -Token '11111111'
$head5 = (git -C $repo5 rev-parse HEAD).Trim()
$aud5 = Join-Path $repo5 '.github/pr-quality-gate/audits'; New-Item -ItemType Directory -Path $aud5 -Force | Out-Null
Set-Content (Join-Path $aud5 'read-receipts-last.md') "parent_sha: $head5`nreads=.github/instructions/fake-cs.instructions.md@11111111`n" -NoNewline
Assert-True ((Invoke-Checker $repo5) -eq 1) 'EMPTY staged gated file, valid worktree token -> exit 1 (git-show-success gate, not content-truthiness; no fail-open)'

Write-Host "=== applyTo patterns are resolved from the STAGED index, not the worktree (round-6 bot finding) ==="
$repo6 = New-TestGitRepository -Prefix 'rr6'
$instr6 = Join-Path $repo6 '.github/instructions'; New-Item -ItemType Directory -Path $instr6 -Force | Out-Null
New-Instr -Dir $instr6 -Name 'fake-cs' -ApplyTo '**/*.cs' -Token '11111111'
git -C $repo6 add -A 2>$null; git -C $repo6 commit -q -m 'init applyTo **/*.cs' 2>$null
Set-Content (Join-Path $repo6 'Foo.cs') 'class F{}'; git -C $repo6 add -A 2>$null
New-Instr -Dir $instr6 -Name 'fake-cs' -ApplyTo '**/*.razor' -Token '11111111'
Assert-True ((Invoke-Checker $repo6) -eq 1) 'worktree applyTo narrowed to **/*.razor (unstaged) but staged **/*.cs matches the staged Foo.cs -> exit 1 (no fail-open; staged applyTo authoritative)'

Write-Host "=== staged applyTo **/* (universal) excludes the file from gating (index-authoritative exclusion) ==="
$repo7 = New-TestGitRepository -Prefix 'rr7'
$instr7 = Join-Path $repo7 '.github/instructions'; New-Item -ItemType Directory -Path $instr7 -Force | Out-Null
New-Instr -Dir $instr7 -Name 'fake-cs' -ApplyTo '**/*.cs' -Token '11111111'
git -C $repo7 add -A 2>$null; git -C $repo7 commit -q -m 'init' 2>$null
New-Instr -Dir $instr7 -Name 'fake-cs' -ApplyTo '**/*' -Token '11111111'
Set-Content (Join-Path $repo7 'Foo.cs') 'class F{}'; git -C $repo7 add -A 2>$null
New-Instr -Dir $instr7 -Name 'fake-cs' -ApplyTo '**/*.cs' -Token '11111111'
Assert-True ((Invoke-Checker $repo7) -eq 0) 'staged applyTo is universal **/* -> fake-cs not a code gate in the index -> staged Foo.cs requires no receipt -> exit 0'

Write-Host "=== gated membership is index-authoritative - a staged narrowing of a worktree-**/* file IS gated (no fail-open) ==="
$repo8 = New-TestGitRepository -Prefix 'rr8'
$instr8 = Join-Path $repo8 '.github/instructions'; New-Item -ItemType Directory -Path $instr8 -Force | Out-Null
New-Instr -Dir $instr8 -Name 'fake-cs' -ApplyTo '**/*' -Token '11111111'
git -C $repo8 add -A 2>$null; git -C $repo8 commit -q -m 'init universal' 2>$null
New-Instr -Dir $instr8 -Name 'fake-cs' -ApplyTo '**/*.cs' -Token '11111111'
Set-Content (Join-Path $repo8 'Foo.cs') 'class F{}'; git -C $repo8 add -A 2>$null
New-Instr -Dir $instr8 -Name 'fake-cs' -ApplyTo '**/*' -Token '11111111'
Assert-True ((Invoke-Checker $repo8) -eq 1) 'staged applyTo narrows **/* -> **/*.cs (worktree restored to **/*, unstaged) -> the staged narrowing is gated from the index -> staged Foo.cs needs a receipt -> exit 1 (membership not worktree-bound)'

Write-Host "=== gated membership is index-authoritative - an UNSTAGED worktree delete cannot silently un-gate (no fail-open) ==="
$repo9 = New-TestGitRepository -Prefix 'rr9'
$instr9 = Join-Path $repo9 '.github/instructions'; New-Item -ItemType Directory -Path $instr9 -Force | Out-Null
New-Instr -Dir $instr9 -Name 'fake-cs' -ApplyTo '**/*.cs' -Token '11111111'
git -C $repo9 add -A 2>$null; git -C $repo9 commit -q -m 'init **/*.cs' 2>$null
Remove-Item -LiteralPath (Join-Path $instr9 'fake-cs.instructions.md')
Set-Content (Join-Path $repo9 'Foo.cs') 'class F{}'; git -C $repo9 add 'Foo.cs' 2>$null
Assert-True ((Invoke-Checker $repo9) -eq 1) 'instruction file deleted in the worktree but the delete is unstaged -> still in the index -> staged Foo.cs is gated -> exit 1 (worktree-delete cannot silently un-gate)'

Write-Host "=== meta: the REAL repo gated set is exactly 16, all tokened (drift/tokenless guard) ==="
$realRepo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$realGated = @(Get-WorktreeGatedTopicFiles -RepoRoot $realRepo)
Assert-True ($realGated.Count -eq 16) "real gated set = 16 (got $($realGated.Count))"
Assert-True (@($realGated | Where-Object { -not $_.Token }).Count -eq 0) 'every real gated topic file carries a valid token'

Remove-TestTempDirectories
Complete-TestRun
