#Requires -Version 5.1
# Unit tests for the code-topic read-receipt gate (check-read-receipts.ps1 + read-receipt-helpers.psm1).
# Fixtures are synthesized in TEMP git repos (never committed under scripts/tests, which would self-trigger
# the gate on a committed *.cs/*.razor fixture).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Pass = 0
$script:Fail = 0

. (Join-Path $PSScriptRoot 'test-common.ps1')
Import-Module (Join-Path $PSScriptRoot '..\lib\read-receipt-helpers.psm1') -Force -DisableNameChecking
$checker = (Resolve-Path (Join-Path $PSScriptRoot '..\check-read-receipts.ps1')).Path

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
$gated = @(Get-GatedTopicFiles -RepoRoot $repo)
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

Write-Host "=== meta: the REAL repo gated set is exactly 13, all tokened (drift/tokenless guard) ==="
$realRepo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$realGated = @(Get-GatedTopicFiles -RepoRoot $realRepo)
Assert-True ($realGated.Count -eq 13) "real gated set = 13 (got $($realGated.Count))"
Assert-True (@($realGated | Where-Object { -not $_.Token }).Count -eq 0) 'every real gated topic file carries a valid token'

Remove-TestTempDirectories
Complete-TestRun
