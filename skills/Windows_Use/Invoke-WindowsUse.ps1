param(
    [Parameter(Mandatory = $true)]
    [string]$Task,
    [string]$Provider = "",
    [string]$Model = "",
    [string]$ReasoningEffort = "",
    [ValidateSet("edge", "chrome", "firefox")]
    [string]$Browser = "",
    [int]$MaxSteps = 0,
    [switch]$UseVision,
    [switch]$Experimental,
    [switch]$RunnerDebug
)

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $projectRoot "config\Load-BotConfig.ps1")
$botConfig = Import-BotSettings -ProjectRoot $projectRoot

if (-not $botConfig.PSObject.Properties["WindowsUse"] -or -not $botConfig.WindowsUse.Enabled) {
    Write-Error "Windows-Use is disabled in config. Enable windowsUse.enabled in config/settings.json first."
    exit 1
}

function Resolve-PythonInvocation {
    param([string]$ConfiguredCommand)

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($ConfiguredCommand)) {
        $candidates += $ConfiguredCommand.Trim()
    }
    $candidates += @("py", "python", "python3")

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if ($candidate -eq "py") {
            $cmd = Get-Command "py" -ErrorAction SilentlyContinue
            if ($cmd) { return @("py", "-3") }
            continue
        }

        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($cmd) { return ,@($candidate) }
    }

    return ,@()
}

$providerToUse = if ([string]::IsNullOrWhiteSpace($Provider)) { $botConfig.WindowsUse.Provider } else { $Provider.Trim() }
$modelToUse = if ([string]::IsNullOrWhiteSpace($Model)) { $botConfig.WindowsUse.Model } else { $Model.Trim() }
$reasoningEffortToUse = if ([string]::IsNullOrWhiteSpace($ReasoningEffort)) { "$($botConfig.WindowsUse.ReasoningEffort)" } else { $ReasoningEffort.Trim() }
$browserToUse = if ([string]::IsNullOrWhiteSpace($Browser)) { $botConfig.WindowsUse.Browser } else { $Browser.Trim().ToLowerInvariant() }
$maxStepsToUse = if ($MaxSteps -gt 0) { $MaxSteps } else { [int]$botConfig.WindowsUse.MaxSteps }
$taskToRun = "One bounded run. Preserve exact requested text. Prefer exact paste/input over approximate typing. Task: $Task"

if ([string]::IsNullOrWhiteSpace($providerToUse)) {
    Write-Error "No Windows-Use provider configured."
    exit 1
}
if ([string]::IsNullOrWhiteSpace($modelToUse)) {
    Write-Error "No Windows-Use model configured."
    exit 1
}
if ($maxStepsToUse -le 0) {
    $maxStepsToUse = 30
}

$pythonInvocation = Resolve-PythonInvocation -ConfiguredCommand $botConfig.WindowsUse.PythonCommand
if ($pythonInvocation.Count -eq 0) {
    Write-Error "Python launcher not found. Set windowsUse.pythonCommand in config/settings.json or install Python."
    exit 1
}

$runnerPath = Join-Path $PSScriptRoot "windows_use_runner.py"
if (-not (Test-Path $runnerPath)) {
    Write-Error "Windows-Use runner script not found at $runnerPath"
    exit 1
}

$logDir = Join-Path $botConfig.Paths.ArchivesDir "windows-use"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$logPath = Join-Path $logDir "last-run.jsonl"
if (Test-Path $logPath) {
    Clear-Content -Path $logPath -ErrorAction SilentlyContinue
}

if ($providerToUse -eq "openrouter" -and [string]::IsNullOrWhiteSpace($env:OPENROUTER_API_KEY)) {
    $env:OPENROUTER_API_KEY = $botConfig.LLM.OpenRouterApiKey
}
$env:ANONYMIZED_TELEMETRY = "false"

$scriptArgs = @(
    $runnerPath,
    "--task", $taskToRun,
    "--provider", $providerToUse,
    "--model", $modelToUse,
    "--reasoning-effort", $reasoningEffortToUse,
    "--browser", $browserToUse,
    "--max-steps", "$maxStepsToUse",
    "--log-file", $logPath
)

if ($UseVision -or $botConfig.WindowsUse.UseVision) { $scriptArgs += "--use-vision" }
if ($Experimental -or $botConfig.WindowsUse.Experimental) { $scriptArgs += "--experimental" }
if ($RunnerDebug) { $scriptArgs += "--debug" }

$commandName = [string]$pythonInvocation[0]
$commandArgs = @()
if ($pythonInvocation.Count -gt 1) {
    $commandArgs += @($pythonInvocation[1..($pythonInvocation.Count - 1)])
}
$commandArgs += $scriptArgs

Write-Host "[Windows-Use] Provider: $providerToUse | Model: $modelToUse | Browser: $browserToUse | MaxSteps: $maxStepsToUse" -ForegroundColor Cyan
Write-Host "[Windows-Use] Python command: $commandName" -ForegroundColor DarkGray
Write-Host "[Windows-Use] Log file: $logPath" -ForegroundColor DarkGray

try {
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $commandName
    $allArgs = @($commandArgs)
    $startInfo.Arguments = [string]::Join(' ', ($allArgs | ForEach-Object {
        if ($_ -match '\s|"') {
            '"' + ($_.Replace('"', '\"')) + '"'
        }
        else {
            $_
        }
    }))
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $process.Start() | Out-Null
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $exitCode = [int]$process.ExitCode
    $process.Dispose()
    $outputText = (($stdout + "`n" + $stderr).Trim())
}
catch {
    $exitCode = 1
    $outputText = $_.Exception.Message
}

if ($exitCode -ne 0) {
    Write-Error "Windows-Use failed with exit code $exitCode.`n$outputText"
    exit $exitCode
}

Write-Output $outputText
