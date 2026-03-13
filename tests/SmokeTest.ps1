param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

$files = @((Join-Path $ProjectRoot "TelegramBot.ps1"))
$files += Get-ChildItem (Join-Path $ProjectRoot "runtime") -Filter "*.ps1" | ForEach-Object { $_.FullName }

$parseFailures = @()
foreach ($file in $files) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $file), [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors -and $errors.Count -gt 0) {
        $parseFailures += [PSCustomObject]@{
            File = $file
            Errors = @($errors | ForEach-Object { $_.Message })
        }
    }
}

if ($parseFailures.Count -gt 0) {
    $parseFailures | ForEach-Object {
        Write-Host "Parse error in $($_.File)" -ForegroundColor Red
        $_.Errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    }
    throw "Smoke test failed: PowerShell parse errors found."
}

$mainFile = Join-Path $ProjectRoot "TelegramBot.ps1"
$mainLineCount = (Get-Content $mainFile).Count
if ($mainLineCount -gt 350) {
    throw "Smoke test failed: TelegramBot.ps1 is longer than the 350-line architecture target ($mainLineCount)."
}

$residualGlobalMatches = Select-String -Path $mainFile, (Join-Path $ProjectRoot "runtime\*.ps1") -Pattern '\$global:(currentMainModel|secondaryMainModel|currentReasoningEffort|ActiveJobs|PendingChats|PendingConfirmations|LastExecutedTags)'
if ($residualGlobalMatches.Count -gt 0) {
    $residualGlobalMatches | ForEach-Object {
        Write-Host "$($_.Path):$($_.LineNumber): $($_.Line.Trim())" -ForegroundColor Red
    }
    throw "Smoke test failed: residual runtime globals were found."
}

Write-Host "Smoke test passed." -ForegroundColor Green
