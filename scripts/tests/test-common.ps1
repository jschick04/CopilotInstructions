#Requires -Version 5.1

if ($null -eq $script:Temps) {
    $script:Temps = New-Object System.Collections.ArrayList
}

function Assert-True {
    param([bool] $Condition, [string] $Name)
    if ($Condition) { Write-Host "  [PASS] $Name"; $script:Pass++ }
    else { Write-Host "  [FAIL] $Name" -ForegroundColor Red; $script:Fail++ }
}

function New-TestTempDirectory {
    param([string] $Prefix)
    $directory = Join-Path ([IO.Path]::GetTempPath()) ("$Prefix-" + [Guid]::NewGuid().ToString('N').Substring(0, 12))
    New-Item -ItemType Directory -Path $directory | Out-Null
    [void]$script:Temps.Add($directory)
    return $directory
}

function Initialize-TestGitRepository {
    param([string] $Directory)
    git -C $Directory init -q -b main 2>$null
    git -C $Directory config user.email 't@t.t'
    git -C $Directory config user.name 'tester'
    git -C $Directory config commit.gpgsign false
}

function New-TestGitRepository {
    param([string] $Prefix)
    $directory = New-TestTempDirectory -Prefix $Prefix
    Initialize-TestGitRepository -Directory $directory
    return $directory
}

function New-TestCommit {
    param([string] $Directory, [string] $File, [string] $Content, [string] $Message)
    $fullPath = Join-Path $Directory $File
    New-Item -ItemType Directory -Path (Split-Path -Parent $fullPath) -Force | Out-Null
    Set-Content -LiteralPath $fullPath -Value $Content
    git -C $Directory add -A 2>$null
    git -C $Directory commit -q -m $Message
    return (git -C $Directory rev-parse HEAD).Trim()
}

function Remove-TestTempDirectories {
    foreach ($directory in $script:Temps) {
        if (Test-Path $directory) {
            Remove-Item -LiteralPath $directory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Complete-TestRun {
    foreach ($summaryLine in @("`n=== Summary ===", "Passes:   $script:Pass", "Failures: $script:Fail")) {
        Write-Host $summaryLine
    }
    if ($script:Fail -gt 0) { exit 1 }
    exit 0
}
