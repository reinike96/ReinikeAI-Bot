param(
    [Parameter(Mandatory = $true)]
    [string]$Task,
    [string]$Model = "",
    [int]$TimeoutMinutes = 20,
    [string[]]$EnableMCPs = @()
)

$workDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location -Path $workDir
. (Join-Path $workDir "config\Load-BotConfig.ps1")
$botConfig = Import-BotSettings -ProjectRoot $workDir

$ocCmd = $botConfig.OpenCode.Command
if ([string]::IsNullOrWhiteSpace($Model)) {
    $Model = $botConfig.OpenCode.DefaultModel
}

Write-Host "[OpenCode-Task] Starting (timeout: ${TimeoutMinutes} min, model: $Model)..." -ForegroundColor Cyan

try {
    # The job is simple now because the config already lives on disk.
    $job = Start-Job -ScriptBlock {
        param($ocCmd, $Task, $Model, $workDir)
        Set-Location $workDir
        & $ocCmd run $Task --model $Model --session TelegramSession
    } -ArgumentList $ocCmd, $Task, $Model, $workDir

    $finished = Wait-Job $job -Timeout ($TimeoutMinutes * 60)

    if (-not $finished) {
        Stop-Job $job
        Remove-Job $job -Force
        Write-Output "[ERROR_TIMEOUT] OpenCode did not finish within $TimeoutMinutes minutes."
        exit 1
    }

    $result = Receive-Job $job -ErrorAction SilentlyContinue
    Remove-Job $job -Force

    $resultString = ($result | Out-String).Trim()
    
    # --- Detección mejorada de errores de créditos ---
    $creditErrorPattern = "insufficient credits|no credits|balance empty|Payment Required|credit limit|rate limit exceeded|out of credits"
    if ($resultString -match $creditErrorPattern) {
        Write-Output "[ERROR_OPENCODE_CREDITS] Insufficient OpenCode credits detected in the CLI."
        exit 1
    }

    if ([string]::IsNullOrWhiteSpace($resultString)) {
        Write-Output "[OpenCode finished without output]"
    } else {
        Write-Output $resultString
    }
}
catch {
    Write-Output "[ERROR_OPENCODE] $($_.Exception.Message)"
    exit 1
}
