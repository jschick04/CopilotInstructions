#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Standalone pwsh self-test (Assert-* helpers, not Pester) for check-no-machine-paths.ps1.
# Run: pwsh -File scripts/tests/check-no-machine-paths.tests.ps1
#
# NOTE: this file is one of the gate's two SELF-EXCLUDED files, so the concrete machine-path fixtures below
# (C:\Users\alice\..., /Users/carol/..., /home/dave/...) do NOT trip the gate on its own introducing commit.
# Every concrete fixture in this change MUST stay inside this file or the gate script - never in the prose,
# the pre-commit block, the workflow, or run-local-ci.

$checkerPath = (Resolve-Path (Join-Path $PSScriptRoot '../check-no-machine-paths.ps1')).Path
. (Join-Path $PSScriptRoot 'test-common.ps1')
$pwshExe = Get-TestPwshExe

$script:Fail = 0
$script:Pass = 0

# Dot-source for direct Get-MachinePathFindings unit tests (the main block returns early when dot-sourced).
. $checkerPath

function Test-Line {
    param([string] $Line)
    return @(Get-MachinePathFindings -AddedLines @($Line)).Count -gt 0
}

# Run the gate as a subprocess against a fixture repo; returns the exit code.
function Invoke-Gate {
    param([string] $Repo, [switch] $Staged, [string] $Base, [switch] $NoMode)
    $callArgs = @('-NoProfile', '-File', $checkerPath, '-RepoRoot', $Repo)
    if ($Staged) { $callArgs += '-Staged' }
    if ($PSBoundParameters.ContainsKey('Base')) { $callArgs += @('-Base', $Base) }
    & $pwshExe @callArgs *> $null
    return $LASTEXITCODE
}

function Add-RepoFile {
    param([string] $Repo, [string] $File, [string] $Content)
    $full = Join-Path $Repo $File
    New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
    Set-Content -LiteralPath $full -Value $Content -NoNewline
    git -C $Repo add -- $File 2>$null
}

Write-Host 'Get-MachinePathFindings - CONCRETE machine paths must flag (>=1 finding):'
$mustFlag = @(
    'var p = "C:\Users\alice\secret.txt";',          # single-backslash
    'var p = "C:\\Users\\bob\\app";',                # escaped-backslash (C#/JSON/TS string literal)
    '{"path": "C:/Users/carol/app"}',               # forward-slash Windows
    'home = "/Users/dave/proj"',                     # macOS home
    'home = "/home/erin/proj"',                      # linux home
    'd = "D:\Users\frank\work\out.txt"',            # non-C drive
    'p = "C:\Users\younes\Downloads\x"',            # real name that starts with token "you"
    'p = "C:\Users\userland\x"',                     # starts with "user"
    'p = "C:\Users\sharedrive\x"',                   # starts with "shared"
    'p = "D:\Users\defaultsmith\x"',                 # starts with "default"
    'p = "c:\users\alice\x"'                          # lowercase Windows (still a real path)
)
foreach ($line in $mustFlag) {
    Assert-True (Test-Line $line) "FLAG: $line"
}

Write-Host 'Get-MachinePathFindings - placeholders / shared / runner / portable must NOT flag (0 findings):'
$mustNotFlag = @(
    'docs example: C:\Users\<you>\app',             # angle-bracket placeholder
    'docs example: C:\Users\<name>\app',            # angle-bracket placeholder
    'tpl: C:\Users\%USERNAME%\app',                 # env-var placeholder
    'tpl: C:\Users\$Env\app',                        # variable placeholder
    'generic: C:\Users\username\app',               # generic token "username"
    'generic: C:\Users\user\app',                    # generic token "user"
    'shared: C:\Users\Public\Documents',            # Windows shared
    'shared: C:\Users\Default\NTUSER.DAT',          # Windows template
    'mac shared: /Users/Shared/app',                # macOS shared
    'ci: C:\Users\runneradmin\work\repo',           # GitHub Windows runner
    'ci: /Users/runner/work/repo/x',                # GitHub macOS runner
    'portable: ~/Downloads/x',                       # tilde home (portable, not a leak)
    'system: C:\Windows\System32\drivers',          # system path (not under \Users)
    'system: C:\Program Files\app',                 # system path
    "route: router.get('/users/:id')",             # lowercase REST route (NB-1: case-sensitive anchor)
    'route: app.get("/users/list")'                # lowercase REST route
)
foreach ($line in $mustNotFlag) {
    Assert-False (Test-Line $line) "ALLOW: $line"
}

Write-Host 'Get-MachinePathFindings - reported match captures the full path snippet:'
$winFinding = @(Get-MachinePathFindings -AddedLines @('p = "C:\\Users\\bob\\app\\cfg.json";'))[0]
Assert-Equal 'C:\\Users\\bob\\app\\cfg.json' $winFinding.Match 'windows match captures full path'
Assert-Equal 'windows-home' $winFinding.Pattern 'windows pattern named'
$nixFinding = @(Get-MachinePathFindings -AddedLines @('home = "/home/erin/proj/x"'))[0]
Assert-Equal '/home/erin/proj/x' $nixFinding.Match 'unix match captures full path'

Assert-True ((@(Get-MachinePathFindings -AddedLines $null)).Count -eq 0) 'null added-lines -> 0 findings'
Assert-True ((@(Get-MachinePathFindings -AddedLines @())).Count -eq 0) 'empty added-lines -> 0 findings'
Assert-True ((@(Get-MachinePathFindings -AddedLines @('', 'no path here'))).Count -eq 0) 'blank + clean -> 0 findings'

Write-Host 'Staged mode:'
$repo = New-TestGitRepository -Prefix 'machpath-staged'
New-TestCommit -Directory $repo -File 'README.md' -Content "seed" -Message 'seed' | Out-Null
Assert-Equal 0 (Invoke-Gate -Repo $repo -Staged) 'staged: nothing staged -> exit 0 (empty = clean)'
Add-RepoFile -Repo $repo -File 'src/clean.cs' -Content 'var p = Path.Combine(home, "app");'
Assert-Equal 0 (Invoke-Gate -Repo $repo -Staged) 'staged: clean added line -> exit 0'
Add-RepoFile -Repo $repo -File 'src/leak.cs' -Content 'var p = "C:\Users\alice\Downloads\secret.txt";'
Assert-Equal 1 (Invoke-Gate -Repo $repo -Staged) 'staged: concrete machine path -> exit 1'

Write-Host 'Self-exclusion (both modes must skip the gate + its tests):'
$selfRepo = New-TestGitRepository -Prefix 'machpath-self'
New-TestCommit -Directory $selfRepo -File 'README.md' -Content 'seed' -Message 'seed' | Out-Null
Add-RepoFile -Repo $selfRepo -File 'scripts/check-no-machine-paths.ps1' -Content '# fixture: C:\Users\alice\app'
Add-RepoFile -Repo $selfRepo -File 'scripts/tests/check-no-machine-paths.tests.ps1' -Content '# fixture: /Users/carol/proj'
Assert-Equal 0 (Invoke-Gate -Repo $selfRepo -Staged) 'staged: concrete paths only in the 2 self-excluded files -> exit 0'
git -C $selfRepo checkout -q -b feature
git -C $selfRepo commit -q -m 'add gate fixtures' 2>$null
Assert-Equal 0 (Invoke-Gate -Repo $selfRepo -Base 'main') 'range: concrete paths only in the 2 self-excluded files -> exit 0'

# (regression for the header-vs-content ambiguity: a naive StartsWith('+++') drops such a line; the
#  hunk-aware walk treats it as content because it is inside a @@ hunk, not in the file preamble.)
Write-Host 'Diff-parser robustness (content lines starting with ++):'
$plusRepo = New-TestGitRepository -Prefix 'machpath-plus'
New-TestCommit -Directory $plusRepo -File 'README.md' -Content 'seed' -Message 'seed' | Out-Null
Add-RepoFile -Repo $plusRepo -File 'notes.txt' -Content '++ leaked path C:\Users\alice\secret'
Assert-Equal 1 (Invoke-Gate -Repo $plusRepo -Staged) 'staged: ++-prefixed content line with a machine path -> exit 1 (not dropped as a header)'

Write-Host 'Base / range mode:'
$rangeRepo = New-TestGitRepository -Prefix 'machpath-range'
New-TestCommit -Directory $rangeRepo -File 'README.md' -Content 'seed' -Message 'seed' | Out-Null
git -C $rangeRepo checkout -q -b feature
New-TestCommit -Directory $rangeRepo -File 'src/clean.cs' -Content 'var p = Path.Combine(home, "x");' -Message 'clean change' | Out-Null
Assert-Equal 0 (Invoke-Gate -Repo $rangeRepo -Base 'main') 'range: clean branch diff -> exit 0'
New-TestCommit -Directory $rangeRepo -File 'src/leak.cs' -Content 'home = "/home/dave/proj/secret"' -Message 'leak change' | Out-Null
Assert-Equal 1 (Invoke-Gate -Repo $rangeRepo -Base 'main') 'range: branch adds a machine path -> exit 1'

Write-Host 'Invocation + fail-closed:'
$modeRepo = New-TestGitRepository -Prefix 'machpath-mode'
New-TestCommit -Directory $modeRepo -File 'README.md' -Content 'seed' -Message 'seed' | Out-Null
Assert-Equal 2 (Invoke-Gate -Repo $modeRepo) 'no mode (-Staged/-Base absent) -> exit 2'
Assert-Equal 2 (Invoke-Gate -Repo $modeRepo -Staged -Base 'main') 'both -Staged and -Base -> exit 2'
Assert-Equal 2 (Invoke-Gate -Repo $modeRepo -Base 'no-such-ref-xyz') 'unresolvable -Base ref -> exit 2 (fail-closed)'

Remove-TestTempDirectories
Write-Host ''
Write-Host "check-no-machine-paths.tests: $script:Pass passed, $script:Fail failed."
if ($script:Fail -gt 0) { exit 1 }
exit 0
