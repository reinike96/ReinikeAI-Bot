$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptRoot "config\Load-BotConfig.ps1")
. (Join-Path $scriptRoot "runtime\ActionPolicy.ps1")
. (Join-Path $scriptRoot "runtime\ActionValidator.ps1")
. (Join-Path $scriptRoot "runtime\CapabilitiesRegistry.ps1")
. (Join-Path $scriptRoot "runtime\ActionGuards.ps1")
. (Join-Path $scriptRoot "runtime\ActionExecutor.ps1")
. (Join-Path $scriptRoot "runtime\ConversationEngine.ps1")
. (Join-Path $scriptRoot "runtime\Doctor.ps1")
. (Join-Path $scriptRoot "runtime\JobManager.ps1")
. (Join-Path $scriptRoot "runtime\MediaHandlers.ps1")
. (Join-Path $scriptRoot "runtime\MemoryStore.ps1")
. (Join-Path $scriptRoot "runtime\OpenCodeClient.ps1")
. (Join-Path $scriptRoot "runtime\QueueManager.ps1")
. (Join-Path $scriptRoot "runtime\TagParser.ps1")
. (Join-Path $scriptRoot "runtime\TelegramApi.ps1")
. (Join-Path $scriptRoot "runtime\TelegramUpdateRouter.ps1")
. (Join-Path $scriptRoot "runtime\RuntimeState.ps1")
$botConfig = Import-BotSettings -ProjectRoot $scriptRoot

$token = $botConfig.Telegram.BotToken
$openRouterKey = $botConfig.LLM.OpenRouterApiKey
$apiUrl = "https://api.telegram.org/bot$token"
$offset = 0
$workDir = $botConfig.Paths.WorkDir
$archivesDir = $botConfig.Paths.ArchivesDir
if (-not (Test-Path $archivesDir)) { New-Item -ItemType Directory -Path $archivesDir | Out-Null }

function Sync-OpenCodeUserConfig {
    param(
        [string]$ConfiguredPath,
        [string]$ProjectTemplatePath
    )

    $canonicalPath = Join-Path $env:USERPROFILE ".config\opencode\config.json"
    $legacyPath = Join-Path $env:USERPROFILE ".config\opencode\opencode.json"
    $sourcePath = $null

    foreach ($candidate in @($ConfiguredPath, $canonicalPath, $legacyPath, $ProjectTemplatePath)) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path $candidate)) {
            $sourcePath = $candidate
            break
        }
    }

    if ($null -eq $sourcePath) {
        return
    }

    $targetPaths = @($canonicalPath)
    if (-not [string]::IsNullOrWhiteSpace($ConfiguredPath)) {
        $targetPaths += $ConfiguredPath
    }

    foreach ($targetPath in ($targetPaths | Select-Object -Unique)) {
        $targetDir = Split-Path -Parent $targetPath
        if (-not [string]::IsNullOrWhiteSpace($targetDir)) {
            New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
        }
        if ($sourcePath -ne $targetPath) {
            Copy-Item $sourcePath $targetPath -Force
        }
    }
}

Sync-OpenCodeUserConfig -ConfiguredPath $botConfig.OpenCode.ConfigPath -ProjectTemplatePath (Join-Path $scriptRoot "config\opencode.example.json")

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 > $null

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Net.Http

Set-Location -Path $workDir

# --- Parallel Temporary Folder Cleanup ---
Write-Host "Cleaning temporary folder..." -ForegroundColor DarkCyan
Start-ThreadJob -ScriptBlock {
    $tempFolder = $using:env:TEMP
    try {
        Get-ChildItem -Path $tempFolder -ErrorAction SilentlyContinue | 
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-1) } | 
        Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
    }
    catch {}
} -Name "CleanupTemp" | Out-Null

# --- Guard: Avoid multiple running instances ---
$currentPid = $PID
try {
    # Find PowerShell processes running the bot or receiver, excluding the current process.
    $others = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" | Where-Object { 
        ($_.CommandLine -match "TelegramBot.ps1" -or $_.CommandLine -match "Start-Receiver.ps1") -and $_.ProcessId -ne $currentPid 
    }
    foreach ($p in $others) {
        Write-Host "[GUARD] Conflicting instance detected (PID: $($p.ProcessId) - $($p.CommandLine)). Closing it..." -ForegroundColor DarkYellow
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }
    if ($others) { Start-Sleep -Seconds 2 }
}
catch {
    Write-DailyLog -message "Could not verify other running instances: $_" -type "WARN"
}

# --- Base Functions ---
function Write-DailyLog {
    param([string]$message, [string]$type = "INFO")
    $logFile = "$workDir\subagent_events.log"
    $currentDate = Get-Date -Format "yyyy-MM-dd"
    $timestamp = Get-Date -Format "HH:mm:ss"
    
    # Daily reset: clear the file if it was last modified on a previous day.
    if (Test-Path $logFile) {
        $lastWrite = (Get-Item $logFile).LastWriteTime.ToString("yyyy-MM-dd")
        if ($lastWrite -ne $currentDate) {
            Clear-Content $logFile -ErrorAction SilentlyContinue
        }
    }
    
    $logEntry = "[$currentDate $timestamp] [$type] $message"
    $logEntry | Out-File -FilePath $logFile -Append -Encoding UTF8
    Write-Host $logEntry -ForegroundColor Gray
}


# --- Helper: Fix job output encoding (Latin-1 misread as UTF-8) ---
function Repair-JobEncoding {
    param([string]$text)
    if ([string]::IsNullOrWhiteSpace($text)) { return $text }
    try {
        $bytesWin = [System.Text.Encoding]::GetEncoding(28591).GetBytes($text)
        return [System.Text.Encoding]::UTF8.GetString($bytesWin)
    }
    catch { return $text }
}

# --- Programmatic Job Tracking via jobs.json ---
function Write-JobsFile {
    $jobsFile = "$workDir\jobs.json"
    try {
        $snapshot = Get-ActiveJobs | ForEach-Object {
            @{
                jobId     = $_.Job.Id
                type      = $_.Type
                task      = $_.Task
                chatId    = $_.ChatId
                startTime = $_.StartTime.ToString("o")
                state     = $_.Job.State.ToString()
            }
        }
        $snapshot | ConvertTo-Json -Depth 5 | Set-Content $jobsFile -Encoding UTF8
    }
    catch { }
}


# --- Async job wrapper for external scripts (OpenCode-Task.ps1, Subagent.ps1) ---
function Start-ScriptJob {
    param(
        [string]$scriptCmd,
        [string]$chatId,
        [string]$taskLabel,
        [string]$originalTask = ""
    )
    $jobScript = {
        param($cmd, $workDir)
        Add-Type -AssemblyName System.Net.Http
        Set-Location -Path $workDir
        try {
            $res = Invoke-Expression $cmd 2>&1 | Out-String
            if ([string]::IsNullOrWhiteSpace($res)) { return "Script finished without output." }
            return $res
        }
        catch {
            return "[ERROR_SCRIPT] $_"
        }
    }
    $job = Start-Job -ScriptBlock $jobScript -ArgumentList $scriptCmd, $workDir
    return @{
        Job          = $job
        ChatId       = $chatId
        Task         = if ($originalTask) { $originalTask } else { $taskLabel }
        Label        = $taskLabel
        Type         = "Script"
        StartTime    = Get-Date
        LastTyping   = $null
        LastReport   = Get-Date
        LastStatusId = $null
        OutputBuffer = @()
    }
}

# --- OpenCode Server Startup ---
Write-Host "Starting OpenCode server..." -ForegroundColor Cyan

# Start the server in the background without blocking startup.
Start-ThreadJob -Name "OpenCodeServer" -ScriptBlock {
    param($apiKey, $host, $port, $password, $command)
    
    Get-Process -Name "opencode" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1

    $commandText = if ([string]::IsNullOrWhiteSpace($command)) { "opencode" } else { $command }
    $resolvedCommand = $null
    foreach ($candidate in @("$commandText.cmd", "$commandText.exe", $commandText)) {
        try {
            $cmdInfo = Get-Command $candidate -ErrorAction Stop | Select-Object -First 1
            if ($cmdInfo -and -not [string]::IsNullOrWhiteSpace($cmdInfo.Source)) {
                $sourcePath = $cmdInfo.Source
                if ($sourcePath -like "*.ps1") {
                    $cmdSibling = [System.IO.Path]::ChangeExtension($sourcePath, ".cmd")
                    $exeSibling = [System.IO.Path]::ChangeExtension($sourcePath, ".exe")
                    if (Test-Path $cmdSibling) {
                        $sourcePath = $cmdSibling
                    }
                    elseif (Test-Path $exeSibling) {
                        $sourcePath = $exeSibling
                    }
                }

                $resolvedCommand = $sourcePath
                break
            }
        }
        catch {}
    }
    if ([string]::IsNullOrWhiteSpace($resolvedCommand)) {
        $resolvedCommand = $commandText
    }

    $launchFile = "cmd.exe"
    $launchArgs = "/c `"$resolvedCommand`" serve --port $port --hostname $host"
    $nodeSourcePath = $null
    try {
        $nodeInfo = Get-Command "node.exe" -ErrorAction Stop | Select-Object -First 1
        if ($nodeInfo -and -not [string]::IsNullOrWhiteSpace($nodeInfo.Source)) {
            $nodeSourcePath = $nodeInfo.Source
        }
    }
    catch {}

    if ($resolvedCommand -like "*.cmd" -and -not [string]::IsNullOrWhiteSpace($nodeSourcePath)) {
        $opencodeScriptPath = Join-Path (Split-Path -Parent $resolvedCommand) "node_modules\opencode-ai\bin\opencode"
        if (Test-Path $opencodeScriptPath) {
            $launchFile = $nodeSourcePath
            $launchArgs = "`"$opencodeScriptPath`" serve --port $port --hostname $host"
        }
    }

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $launchFile
    $startInfo.Arguments = $launchArgs
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.EnvironmentVariables["OPENCODE_API_KEY"] = $apiKey
    $startInfo.EnvironmentVariables["OPENCODE_SERVER_PASSWORD"] = $password
    $pathEntries = @()
    $existingPath = $startInfo.EnvironmentVariables["PATH"]
    if (-not [string]::IsNullOrWhiteSpace($existingPath)) {
        $pathEntries += ($existingPath -split ';')
    }
    $resolvedDir = Split-Path -Parent $resolvedCommand
    if (-not [string]::IsNullOrWhiteSpace($resolvedDir)) {
        $pathEntries += $resolvedDir
    }
    if (-not [string]::IsNullOrWhiteSpace($nodeSourcePath)) {
        $pathEntries += (Split-Path -Parent $nodeSourcePath)
    }
    $startInfo.EnvironmentVariables["PATH"] = (($pathEntries | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique) -join ';')

    $proc = [System.Diagnostics.Process]::Start($startInfo)
    Start-Sleep -Milliseconds 250
    if ($proc -and $proc.HasExited) {
        $stderr = $proc.StandardError.ReadToEnd()
        $stdout = $proc.StandardOutput.ReadToEnd()
        Write-Host "OpenCode server exited during startup. stdout: $stdout stderr: $stderr" -ForegroundColor DarkYellow
    }
    
    for ($i = 0; $i -lt 15; $i++) {
        Start-Sleep -Seconds 2
        try {
            $cred = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("opencode:$password"))
            $health = Invoke-RestMethod -Uri "http://${host}:$port/global/health" -Headers @{ Authorization = "Basic $cred" } -TimeoutSec 2 -ErrorAction Stop
            if ($health.healthy) {
                Write-Host "OpenCode server is ready (v$($health.version))" -ForegroundColor Green
                return
            }
        }
        catch {}
    }
    Write-Host "OpenCode server did not respond in time" -ForegroundColor DarkGray
} -ArgumentList $botConfig.OpenCode.ApiKey, $botConfig.OpenCode.Host, $botConfig.OpenCode.Port, $botConfig.OpenCode.ServerPassword, $botConfig.OpenCode.Command | Out-Null

# Continue immediately while other startup work runs in parallel.

# --- Parallel File Loading ---
Write-Host "Starting ReinikeAI Bot v5" -ForegroundColor Green

$loadFilesJob = Start-ThreadJob -Name "LoadFiles" -ScriptBlock {
    param($wd)
    $sys = Get-Content "$wd\SYSTEM.md" -Raw -ErrorAction SilentlyContinue
    $mem = Get-Content "$wd\MEMORY.md" -Raw -ErrorAction SilentlyContinue
    return @{ sys = $sys; mem = $mem }
} -ArgumentList $workDir

$flushJob = Start-ThreadJob -Name "FlushTelegram" -ScriptBlock {
    param($api)
    try {
        $upd = Invoke-RestMethod -Uri "$api/getUpdates?offset=-1&timeout=0" -Method Get -TimeoutSec 10 -ErrorAction SilentlyContinue
        if ($upd.result.Count -gt 0) { return $upd.result[0].update_id + 1 }
    }
    catch {}
    return $null
} -ArgumentList $apiUrl

$cleanupMemJob = Start-ThreadJob -Name "CleanupMemory" -ScriptBlock {
    param($wd, $defaultChatId)
    $file = Get-ChildItem -Path "$wd\mem_*.json" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($file -and $file.Name -match 'mem_(\d+)\.json') {
        Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
        return $Matches[1]
    }
    return $defaultChatId
} -ArgumentList $workDir, $botConfig.Telegram.StartupChatId

Initialize-RuntimeState -BotConfig $botConfig

# Wait for critical startup tasks to finish.
$fileResult = $loadFilesJob | Wait-Job | Receive-Job
$sysPrompt = $fileResult.sys
$memoryCtx = $fileResult.mem

$flushResult = $flushJob | Wait-Job | Receive-Job
if ($null -ne $flushResult) {
    $offset = $flushResult
    Write-Host "Telegram queue flushed. Offset: $offset" -ForegroundColor DarkGray
}

$startupChatId = $cleanupMemJob | Wait-Job | Receive-Job
Write-Host "[SYSTEM] Memory cleanup complete. Chat: $startupChatId" -ForegroundColor Yellow

$fullSys = "$sysPrompt`n`nMEMORY CONTEXT:`n$memoryCtx`n`nRESPONSE LANGUAGE:`nAlways answer the user in $($botConfig.LLM.ResponseLanguage) unless the user explicitly asks for another language.`n`nFORMAT INSTRUCTIONS:`nPreferred format: reply with a single JSON object when you need actions: {`"reply`":`"text for the user`",`"actions`":[{`"type`":`"CMD`",`"command`":`"powershell command`"}]}. Supported action types: CMD, OPENCODE, PW_CONTENT, PW_SCREENSHOT, SCREENSHOT, STATUS, BUTTONS. BUTTONS format: {`"type`":`"BUTTONS`",`"text`":`"Question`",`"buttons`":[{`"text`":`"Approve`",`"callback_data`":`"yes`"}]}. If no action is needed, plain text is allowed. Legacy tag format like [CMD: ...] and [OPENCODE: chat | ...] is still accepted as fallback."

# Remove startup helper jobs.
Get-Job | Where-Object { $_.Name -match "LoadFiles|FlushTelegram|CleanupMemory" } | Remove-Job -Force -ErrorAction SilentlyContinue

# Register Telegram menu commands.
Set-TelegramCommands

if (-not [string]::IsNullOrWhiteSpace($startupChatId)) {
    Start-ThreadJob -Name "StartupMessage" -ScriptBlock {
        param($chatId, $api, $token)
        function Send-TelegramText {
            param($chatId, $text, $buttons = $null)
            if ([string]::IsNullOrWhiteSpace($text)) { return }
            $uri = "$api/sendMessage"
            $payload = @{ chat_id = $chatId; text = $text.Trim(); parse_mode = "Markdown" }
            $jsonPayload = $payload | ConvertTo-Json -Compress
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonPayload)
            try { Invoke-RestMethod -Uri $uri -Method Post -ContentType "application/json; charset=utf-8" -Body $bytes -ErrorAction SilentlyContinue | Out-Null } catch {}
        }
        $emojiCheck = [char]::ConvertFromUtf32(0x2705)
        $ts = Get-Date -Format "HH:mm:ss"
        Send-TelegramText -chatId $chatId -text "$emojiCheck *Bot Online* - $ts`n\`SYSTEM.md\` and \`MEMORY.md\` loaded.`nReady for instructions."
    } -ArgumentList $startupChatId, $apiUrl, $token | Out-Null

    Write-Host "[SYSTEM] Startup message sent to $startupChatId" -ForegroundColor Green
}

while ($true) {
    try {
        Invoke-JobMaintenanceCycle -WorkDir $workDir

        # Telegram polling
        $timeout = if ((Get-PendingChats).Count -gt 0) { 0 } else { 3 }
        $updates = Invoke-RestMethod -Uri "$apiUrl/getUpdates?offset=$offset&timeout=$timeout" -Method Get -TimeoutSec 45
        $offset = Invoke-TelegramUpdateRouter -UpdatesResponse $updates -CurrentOffset $offset -BotConfig $botConfig -ApiUrl $apiUrl -Token $token -OpenRouterKey $openRouterKey -WorkDir $workDir
        
        Invoke-PendingChatProcessing -FullSystemPrompt $fullSys -ApiUrl $apiUrl -WorkDir $workDir
    }
    catch {
        $err = $_.Exception.ToString()
        if ($err -match "409" -or $err -match "Conflict") {
            Write-DailyLog -message "HTTP 409 conflict: another instance is using the bot. Retrying in 5 seconds..." -type "ERROR"
            Write-Host "[!] Conflict detected. If this persists, check for manual processes." -ForegroundColor Red
            Start-Sleep -Seconds 5
        }
        else {
            Write-DailyLog -message "Error in main loop: $_" -type "ERROR"
            Start-Sleep -Seconds 3
        }
    }
}
