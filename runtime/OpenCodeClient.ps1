function Get-TaskCheckpointSubject {
    param(
        [string]$TaskText
    )

    if ([string]::IsNullOrWhiteSpace($TaskText)) {
        return ""
    }

    if ($TaskText -match "(?s)Task:\s*(.+)$") {
        return $Matches[1].Trim()
    }

    return $TaskText.Trim()
}

function Normalize-TaskCheckpointText {
    param(
        [string]$TaskText
    )

    $subject = Get-TaskCheckpointSubject -TaskText $TaskText
    if ([string]::IsNullOrWhiteSpace($subject)) {
        return ""
    }

    return (($subject.ToLowerInvariant() -replace '\s+', ' ').Trim())
}

function Get-TaskCheckpointKeywords {
    param(
        [string]$TaskText
    )

    $normalized = Normalize-TaskCheckpointText -TaskText $TaskText
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return @()
    }

    $stopWords = @(
        'para','esto','esta','este','that','with','from','then','them','into','como','cuando','donde','sobre',
        'usar','using','used','need','necesito','tarea','task','google','pagina','pages','page','resultados',
        'results','captura','capturas','screenshot','screenshots','browser','playwright','agent','build','archives',
        'primera','segunda','tercera','first','second','third','buscar','busca','search','links','enlace','enlaces',
        'retoma','reanuda','resume','continue','continua','retry','again','user','usuario','guardar','save'
    )

    $matches = [regex]::Matches($normalized, '\b[\p{L}\p{Nd}_-]{4,}\b')
    $keywords = foreach ($match in $matches) {
        $word = $match.Value
        if ($stopWords -notcontains $word) {
            $word
        }
    }

    return @($keywords | Select-Object -Unique)
}

function Get-TaskCheckpointFingerprint {
    param(
        [string]$TaskText
    )

    $normalized = Normalize-TaskCheckpointText -TaskText $TaskText
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return ""
    }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
        $hashBytes = $sha.ComputeHash($bytes)
        return -join ($hashBytes | ForEach-Object { $_.ToString("x2") })
    }
    finally {
        $sha.Dispose()
    }
}

function Get-TaskCheckpointRoot {
    param(
        [object]$BotConfig,
        [string]$ChatId
    )

    $archivesDir = if ($BotConfig -and $BotConfig.Paths -and $BotConfig.Paths.ArchivesDir) { $BotConfig.Paths.ArchivesDir } else { Join-Path $PWD "archives" }
    $root = Join-Path $archivesDir "checkpoints"
    if (-not [string]::IsNullOrWhiteSpace($ChatId)) {
        $root = Join-Path $root $ChatId
    }
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    return $root
}

function Initialize-OpenCodeSessionDiagnostics {
    param(
        [object]$BotConfig,
        [string]$ChatId,
        [string]$TaskText
    )

    $archivesDir = if ($BotConfig -and $BotConfig.Paths -and $BotConfig.Paths.ArchivesDir) { $BotConfig.Paths.ArchivesDir } else { Join-Path $PWD "archives" }
    New-Item -ItemType Directory -Force -Path $archivesDir | Out-Null

    $diagnosticPath = Join-Path $archivesDir "opencode-session-diagnostics.md"
    $startedAt = (Get-Date).ToString("o")
    $safeChatId = if ([string]::IsNullOrWhiteSpace($ChatId)) { "(none)" } else { $ChatId }
    $safeTask = if ([string]::IsNullOrWhiteSpace($TaskText)) { "(empty task)" } else { $TaskText.Trim() }

    $initialContent = @"
# OpenCode Session Diagnostics

- startedAt: $startedAt
- chatId: $safeChatId
- task: $safeTask

## Notes

- This file is overwritten at the start of each OpenCode session.
- OpenCode should append errors, retries, blockers, and fallback decisions here while it works.
- The orchestrator may append session metadata and raw event snapshots for debugging.
"@.Trim() + "`n"

    Set-Content -Path $diagnosticPath -Value $initialContent -Encoding UTF8
    return $diagnosticPath
}

function Read-TaskCheckpoint {
    param(
        [string]$CheckpointPath
    )

    if ([string]::IsNullOrWhiteSpace($CheckpointPath) -or -not (Test-Path $CheckpointPath)) {
        return $null
    }

    try {
        return (Get-Content $CheckpointPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Write-TaskCheckpoint {
    param(
        [string]$CheckpointPath,
        [hashtable]$Data
    )

    if ([string]::IsNullOrWhiteSpace($CheckpointPath) -or $null -eq $Data) {
        return
    }

    $targetDir = Split-Path -Parent $CheckpointPath
    if (-not [string]::IsNullOrWhiteSpace($targetDir)) {
        New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    }

    $Data.updatedAt = (Get-Date).ToString("o")
    $Data | ConvertTo-Json -Depth 8 | Set-Content -Path $CheckpointPath -Encoding UTF8
}

function New-TaskCheckpointData {
    param(
        [string]$ChatId,
        [string]$TaskText,
        [string]$Fingerprint
    )

    $subject = Get-TaskCheckpointSubject -TaskText $TaskText
    $normalized = Normalize-TaskCheckpointText -TaskText $TaskText
    $now = (Get-Date).ToString("o")

    return @{
        version = 1
        chatId = $ChatId
        fingerprint = $Fingerprint
        subject = $subject
        normalizedTask = $normalized
        createdAt = $now
        updatedAt = $now
        status = "pending"
        completedSteps = @()
        pendingSteps = @()
        discoveredUrls = @()
        discoveredFiles = @()
        extractedFacts = @()
        notes = @()
        lastAction = ""
        lastResultPreview = ""
        lastError = ""
    }
}

function Get-CheckpointStateForPrompt {
    param(
        [object]$CheckpointData
    )

    if ($null -eq $CheckpointData) {
        return "No prior checkpoint is available."
    }

    $lines = @()
    $lines += "Status: $($CheckpointData.status)"
    if ($CheckpointData.lastAction) { $lines += "Last action: $($CheckpointData.lastAction)" }
    if ($CheckpointData.completedSteps -and $CheckpointData.completedSteps.Count -gt 0) {
        $lines += "Completed steps: " + (($CheckpointData.completedSteps | Select-Object -First 6) -join "; ")
    }
    if ($CheckpointData.pendingSteps -and $CheckpointData.pendingSteps.Count -gt 0) {
        $lines += "Pending steps: " + (($CheckpointData.pendingSteps | Select-Object -First 6) -join "; ")
    }
    if ($CheckpointData.discoveredUrls -and $CheckpointData.discoveredUrls.Count -gt 0) {
        $lines += "Known URLs: " + (($CheckpointData.discoveredUrls | Select-Object -First 6) -join "; ")
    }
    if ($CheckpointData.discoveredFiles -and $CheckpointData.discoveredFiles.Count -gt 0) {
        $lines += "Known files: " + (($CheckpointData.discoveredFiles | Select-Object -First 6) -join "; ")
    }
    if ($CheckpointData.extractedFacts -and $CheckpointData.extractedFacts.Count -gt 0) {
        $lines += "Extracted facts: " + (($CheckpointData.extractedFacts | Select-Object -First 6) -join "; ")
    }
    if ($CheckpointData.lastResultPreview) { $lines += "Last result preview: $($CheckpointData.lastResultPreview)" }
    if ($CheckpointData.lastError) { $lines += "Last error: $($CheckpointData.lastError)" }

    return (($lines -join "`n").Trim())
}

function Resolve-TaskCheckpoint {
    param(
        [object]$BotConfig,
        [string]$ChatId,
        [string]$TaskText
    )

    $root = Get-TaskCheckpointRoot -BotConfig $BotConfig -ChatId $ChatId
    $fingerprint = Get-TaskCheckpointFingerprint -TaskText $TaskText
    $defaultPath = Join-Path $root "$fingerprint.json"
    $taskKeywords = @(Get-TaskCheckpointKeywords -TaskText $TaskText)
    $resumePattern = '(?i)\b(retoma|reanuda|resume|continue|continua|seguir|retry|again)\b'

    $existing = Read-TaskCheckpoint -CheckpointPath $defaultPath
    if ($null -ne $existing) {
        return [PSCustomObject]@{
            Path = $defaultPath
            Data = $existing
            Reused = $true
            Reason = "exact-match"
        }
    }

    $candidateFiles = @(Get-ChildItem -Path $root -Filter "*.json" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    foreach ($candidate in $candidateFiles) {
        $candidateData = Read-TaskCheckpoint -CheckpointPath $candidate.FullName
        if ($null -eq $candidateData) {
            continue
        }

        if ($candidateData.status -eq "completed" -and $TaskText -notmatch $resumePattern) {
            continue
        }

        $candidateKeywords = @($candidateData.extractedFacts + $candidateData.completedSteps + $candidateData.pendingSteps + (Get-TaskCheckpointKeywords -TaskText $candidateData.subject) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $overlap = @($taskKeywords | Where-Object { $candidateKeywords -contains $_ } | Select-Object -Unique)
        $shouldReuse = ($TaskText -match $resumePattern -and $candidateData.status -ne "completed") -or ($overlap.Count -ge 2)
        if ($shouldReuse) {
            return [PSCustomObject]@{
                Path = $candidate.FullName
                Data = $candidateData
                Reused = $true
                Reason = "related-task"
            }
        }
    }

    return [PSCustomObject]@{
        Path = $defaultPath
        Data = (New-TaskCheckpointData -ChatId $ChatId -TaskText $TaskText -Fingerprint $fingerprint)
        Reused = $false
        Reason = "new"
    }
}

function Update-TaskCheckpointState {
    param(
        [string]$CheckpointPath,
        [string]$TaskText = "",
        [string]$Status = "",
        [string]$ResultText = "",
        [string]$LastAction = "",
        [string]$LastError = ""
    )

    if ([string]::IsNullOrWhiteSpace($CheckpointPath)) {
        return
    }

    $checkpoint = Read-TaskCheckpoint -CheckpointPath $CheckpointPath
    if ($null -eq $checkpoint) {
        $checkpoint = New-TaskCheckpointData -ChatId "" -TaskText $TaskText -Fingerprint ([System.IO.Path]::GetFileNameWithoutExtension($CheckpointPath))
    }

    $mutable = @{}
    foreach ($prop in $checkpoint.PSObject.Properties) {
        $mutable[$prop.Name] = $prop.Value
    }

    if (-not [string]::IsNullOrWhiteSpace($TaskText)) {
        $mutable.subject = Get-TaskCheckpointSubject -TaskText $TaskText
        $mutable.normalizedTask = Normalize-TaskCheckpointText -TaskText $TaskText
    }
    if (-not [string]::IsNullOrWhiteSpace($Status)) { $mutable.status = $Status }
    if (-not [string]::IsNullOrWhiteSpace($LastAction)) { $mutable.lastAction = $LastAction }
    if (-not [string]::IsNullOrWhiteSpace($LastError)) { $mutable.lastError = $LastError }

    if (-not [string]::IsNullOrWhiteSpace($ResultText)) {
        $preview = $ResultText.Substring(0, [Math]::Min(400, $ResultText.Length)).Replace("`r", " ").Replace("`n", " ").Trim()
        $mutable.lastResultPreview = $preview

        $urlMatches = [regex]::Matches($ResultText, 'https?://[^\s`"''<>]+') | ForEach-Object { $_.Value.TrimEnd('.', ',', ';', ')') }
        $fileMatches = [regex]::Matches($ResultText, '([a-zA-Z]:\\[^:<>|"?\r\n]+\.(png|jpg|jpeg|pdf|docx|txt|zip|xlsx|csv))') | ForEach-Object { $_.Groups[1].Value }
        $factMatches = [regex]::Matches($ResultText, '(?im)^(?:- |\* |\d+\.\s+)(.+)$') | ForEach-Object { $_.Groups[1].Value.Trim() }

        $mutable.discoveredUrls = @($mutable.discoveredUrls + $urlMatches | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
        $mutable.discoveredFiles = @($mutable.discoveredFiles + $fileMatches | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
        $mutable.extractedFacts = @($mutable.extractedFacts + $factMatches | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 20 -Unique)
    }

    Write-TaskCheckpoint -CheckpointPath $CheckpointPath -Data $mutable
}

function Get-OpenCodeServerProcessIds {
    param(
        [object]$BotConfig
    )

    $pidMap = @{}
    if ($null -eq $BotConfig -or $null -eq $BotConfig.OpenCode) {
        return @()
    }

    $serverPort = [int]$BotConfig.OpenCode.Port
    $serverPattern = "(?i)(\bopencode(\.exe)?\b.*\bserve\b|node_modules\\opencode-ai\\bin\\opencode.*\bserve\b|serve --port $serverPort\b)"

    try {
        $listeningPids = Get-NetTCPConnection -LocalPort $serverPort -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty OwningProcess -Unique
        foreach ($processId in @($listeningPids)) {
            if ($null -ne $processId) {
                $pidMap["$processId"] = [int]$processId
            }
        }
    }
    catch {}

    try {
        $matchedProcesses = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
            ($_.Name -match '^(opencode|node|cmd)(\.exe)?$') -and
            (-not [string]::IsNullOrWhiteSpace($_.CommandLine)) -and
            ($_.CommandLine -match $serverPattern)
        }

        foreach ($proc in @($matchedProcesses)) {
            if ($null -ne $proc.ProcessId) {
                $pidMap["$($proc.ProcessId)"] = [int]$proc.ProcessId
            }
            if ($null -ne $proc.ParentProcessId -and $proc.ParentProcessId -gt 0) {
                $pidMap["$($proc.ParentProcessId)"] = [int]$proc.ParentProcessId
            }
        }
    }
    catch {}

    return @($pidMap.Values | Sort-Object -Descending)
}

function Stop-OpenCodeServer {
    param(
        [object]$BotConfig,
        [string]$Reason = "manual stop",
        [switch]$StopActiveJobs
    )

    $stoppedJobIds = @()
    $killedProcessIds = @()

    if ($StopActiveJobs -and (Get-Command Get-ActiveJobs -ErrorAction SilentlyContinue) -and (Get-Command Remove-ActiveJobById -ErrorAction SilentlyContinue)) {
        foreach ($jobRecord in @(Get-ActiveJobs | Where-Object { $_.Type -eq "OpenCode" })) {
            if ($jobRecord.CheckpointPath) {
                try {
                    Update-TaskCheckpointState -CheckpointPath $jobRecord.CheckpointPath -TaskText $jobRecord.Task -Status "interrupted" -LastAction "OpenCode task stopped by orchestrator" -LastError $Reason
                }
                catch {}
            }
            try {
                Stop-Job -Job $jobRecord.Job -ErrorAction SilentlyContinue | Out-Null
                Remove-Job -Job $jobRecord.Job -Force -ErrorAction SilentlyContinue
                $stoppedJobIds += $jobRecord.Job.Id
            }
            catch {}

            try {
                Remove-ActiveJobById -JobId $jobRecord.Job.Id
            }
            catch {}
        }

        if (Get-Command Write-JobsFile -ErrorAction SilentlyContinue) {
            try { Write-JobsFile } catch {}
        }
    }

    foreach ($threadJob in @(Get-Job -Name "OpenCodeServer" -ErrorAction SilentlyContinue)) {
        try {
            Stop-Job -Job $threadJob -ErrorAction SilentlyContinue | Out-Null
            Remove-Job -Job $threadJob -Force -ErrorAction SilentlyContinue
        }
        catch {}
    }

    foreach ($processId in @(Get-OpenCodeServerProcessIds -BotConfig $BotConfig)) {
        try {
            $proc = Get-Process -Id $processId -ErrorAction SilentlyContinue
            if ($null -ne $proc) {
                Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
                $killedProcessIds += $processId
            }
        }
        catch {}
    }

    Start-Sleep -Milliseconds 300
    $remainingProcesses = @(Get-OpenCodeServerProcessIds -BotConfig $BotConfig)

    if (Get-Command Write-DailyLog -ErrorAction SilentlyContinue) {
        $logMsg = "Stop-OpenCodeServer reason='$Reason' stopped_jobs=$($stoppedJobIds.Count) killed_processes=$($killedProcessIds.Count) remaining_processes=$($remainingProcesses.Count)"
        try { Write-DailyLog -message $logMsg -type "SYSTEM" } catch {}
    }

    return [PSCustomObject]@{
        Reason = $Reason
        JobsStopped = @($stoppedJobIds).Count
        ProcessesStopped = @($killedProcessIds | Select-Object -Unique).Count
        RemainingProcesses = @($remainingProcesses).Count
    }
}

function Test-OpenCodeServerHealth {
    param(
        [string]$ServerHost,
        [int]$ServerPort,
        [string]$Password,
        [int]$TimeoutSec = 2
    )

    try {
        $authBytes = [System.Text.Encoding]::ASCII.GetBytes("opencode:$Password")
        $authBase64 = [System.Convert]::ToBase64String($authBytes)
        $headers = @{ Authorization = "Basic $authBase64" }
        $health = Invoke-RestMethod -Uri "http://${ServerHost}:$ServerPort/global/health" -Headers $headers -TimeoutSec $TimeoutSec -ErrorAction Stop
        return ($null -ne $health -and $health.healthy)
    }
    catch {
        return $false
    }
}

function Start-OpenCodeServerIfNeeded {
    param(
        [object]$BotConfig
    )

    if ($null -eq $BotConfig -or $null -eq $BotConfig.OpenCode) {
        return $false
    }

    if (Test-OpenCodeServerHealth -ServerHost $BotConfig.OpenCode.Host -ServerPort $BotConfig.OpenCode.Port -Password $BotConfig.OpenCode.ServerPassword) {
        return $true
    }

    $commandText = if ([string]::IsNullOrWhiteSpace($BotConfig.OpenCode.Command)) { "opencode" } else { $BotConfig.OpenCode.Command }
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
    $launchArgs = "/c `"$resolvedCommand`" serve --port $($BotConfig.OpenCode.Port) --hostname $($BotConfig.OpenCode.Host)"
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
            $launchArgs = "`"$opencodeScriptPath`" serve --port $($BotConfig.OpenCode.Port) --hostname $($BotConfig.OpenCode.Host)"
        }
    }

    try {
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = $launchFile
        $startInfo.Arguments = $launchArgs
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.EnvironmentVariables["OPENCODE_API_KEY"] = $BotConfig.OpenCode.ApiKey
        $startInfo.EnvironmentVariables["OPENCODE_SERVER_PASSWORD"] = $BotConfig.OpenCode.ServerPassword

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
            return $false
        }
    }
    catch {
        return $false
    }

    for ($i = 0; $i -lt 10; $i++) {
        Start-Sleep -Seconds 1
        if (Test-OpenCodeServerHealth -ServerHost $BotConfig.OpenCode.Host -ServerPort $BotConfig.OpenCode.Port -Password $BotConfig.OpenCode.ServerPassword) {
            return $true
        }
    }

    return $false
}

function Invoke-OpenRouter {
    param([string]$model, [array]$messages, [string]$reasoningEffort = "minimal")
    $uri = "https://openrouter.ai/api/v1/chat/completions"
    $headers = @{
        "Authorization" = "Bearer $openRouterKey"
        "Content-Type"  = "application/json; charset=utf-8"
        "HTTP-Referer"  = "https://reinikeai.com"
        "X-Title"       = "ReinikeBot"
    }

    $processedMessages = @()
    foreach ($msg in $messages) {
        $msgRole = $msg.role
        $msgContent = $msg.content

        if ($processedMessages.Count -gt 0 -and $processedMessages[-1].role -eq $msgRole) {
            $prev = $processedMessages[-1]
            $prevText = if ($prev.content -is [array]) { ($prev.content | Where-Object { $_.type -eq "text" } | ForEach-Object { $_.text }) -join " " } else { "$($prev.content)" }
            $prevNonText = if ($prev.content -is [array]) { @($prev.content | Where-Object { $_.type -ne "text" }) } else { @() }
            $currText = if ($msgContent -is [array]) { ($msgContent | Where-Object { $_.type -eq "text" } | ForEach-Object { $_.text }) -join " " } else { "$msgContent" }
            $currNonText = if ($msgContent -is [array]) { @($msgContent | Where-Object { $_.type -ne "text" }) } else { @() }

            $mergedParts = @()
            if ($prevNonText.Count -gt 0) { $mergedParts += $prevNonText }
            if ($currNonText.Count -gt 0) { $mergedParts += $currNonText }
            $combinedText = "$prevText`n$currText".Trim()
            if (-not [string]::IsNullOrWhiteSpace($combinedText)) {
                $mergedParts += @{ type = "text"; text = $combinedText }
            }

            if ($mergedParts.Count -eq 1 -and $mergedParts[0].type -eq "text") {
                $processedMessages[-1] = @{ role = $msgRole; content = $mergedParts[0].text }
            }
            else {
                $processedMessages[-1] = @{ role = $msgRole; content = $mergedParts }
            }
        }
        else {
            $processedMessages += @{ role = $msgRole; content = $msgContent }
        }
    }

    $bodyObj = @{
        "model"    = $model
        "messages" = $processedMessages
    }
    if (-not [string]::IsNullOrWhiteSpace($reasoningEffort) -and $reasoningEffort -ne "none") {
        $bodyObj.Add("reasoning", @{ "effort" = $reasoningEffort })
    }

    $bodyJson = $bodyObj | ConvertTo-Json -Depth 10 -Compress
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyJson)
    $maxAttempts = 3
    $attempt = 0

    while ($attempt -lt $maxAttempts) {
        $attempt++
        try {
            $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $bodyBytes -TimeoutSec 60
            if ($null -eq $response.choices -or $response.choices.Count -eq 0) {
                $errStr = if ($response.error) { $response.error.message } else { "OpenRouter returned neither choices nor an explicit error." }
                Write-DailyLog -message "Fallo en OpenRouter (intento $attempt): $errStr" -type "ERROR"
                if ($attempt -lt $maxAttempts) { Start-Sleep -Seconds 2; continue }
                return "[ERROR_API] OpenRouter failed after multiple attempts: $errStr"
            }

            $rawContent = $response.choices[0].message.content
            if ([string]::IsNullOrWhiteSpace($rawContent)) {
                Write-DailyLog -message "OpenRouter returned empty content (attempt $attempt). $model" -type "WARN"
                if ($attempt -lt $maxAttempts) { Start-Sleep -Seconds 2; continue }
                return ""
            }
            return $rawContent
        }
        catch {
            $errDetails = if ($_.Exception) { $_.Exception.Message } else { $_.ToString() }
            if ($_.Exception -and $_.Exception.Response) {
                try {
                    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                    $errBody = $reader.ReadToEnd()
                    if ($errBody) { $errDetails += " | Response: $errBody" }
                }
                catch {}
            }

            Write-DailyLog -message "Error in Invoke-OpenRouter ($model) attempt ${attempt}: $errDetails" -type "ERROR"
            if ($attempt -lt $maxAttempts) { Start-Sleep -Seconds 2; continue }
            return "[ERROR_API] $errDetails"
        }
    }
}

function Start-OpenCodeJob {
    param(
        [string]$TaskDescription,
        [string]$ChatId,
        [string[]]$EnableMCPs = @(),
        [string]$Model = "",
        [string]$Agent = $null,
        [int]$TimeoutSec = 1200
    )
    if ([string]::IsNullOrWhiteSpace($Model)) {
        $Model = $botConfig.OpenCode.DefaultModel
    }
    [void](Start-OpenCodeServerIfNeeded -BotConfig $botConfig)
    $checkpointInfo = Resolve-TaskCheckpoint -BotConfig $botConfig -ChatId $ChatId -TaskText $TaskDescription
    $sessionDiagnosticsPath = Initialize-OpenCodeSessionDiagnostics -BotConfig $botConfig -ChatId $ChatId -TaskText $TaskDescription
    Update-TaskCheckpointState -CheckpointPath $checkpointInfo.Path -TaskText $TaskDescription -Status "running" -LastAction "Task delegated to OpenCode"
    $checkpointPrompt = Get-CheckpointStateForPrompt -CheckpointData $checkpointInfo.Data
    $jobScript = {
        param($taskDescription, $workDir, $archivesDir, $jobId, $enableMCPs, $modelStr, $agentStr, $timeoutSeconds, $openCodeHost, $openCodePort, $openCodePassword, $checkpointPath, $checkpointPrompt, $sessionDiagnosticsPath)
        Add-Type -AssemblyName System.Net.Http
        function Write-DailyLog {
            param([string]$message, [string]$type = "INFO")
            $logFile = "$workDir\subagent_events.log"
            $currentDate = Get-Date -Format "yyyy-MM-dd"
            $timestamp = Get-Date -Format "HH:mm:ss"
            if (Test-Path $logFile) {
                $lastWrite = (Get-Item $logFile).LastWriteTime.ToString("yyyy-MM-dd")
                if ($lastWrite -ne $currentDate) { Clear-Content $logFile -ErrorAction SilentlyContinue }
            }
            $sanitized = $message
            $redactionPatterns = @(
                '(?i)\b\d{8,10}:[A-Za-z0-9_-]{20,}\b',
                '(?i)\b(sk-or-v1|sk-[A-Za-z0-9_-]+)[A-Za-z0-9_-]*\b',
                '(?i)(Authorization["'':=\s]+Bearer\s+)[^\s]+',
                '(?i)(serverPassword["'':=\s]+)[^\s,;]+',
                '(?i)(openRouterApiKey["'':=\s]+)[^\s,;]+',
                '(?i)(apiKey["'':=\s]+)[^\s,;]+'
            )
            foreach ($pattern in $redactionPatterns) {
                $sanitized = [regex]::Replace($sanitized, $pattern, '$1[REDACTED]')
            }
            "[$currentDate $timestamp] [$type] $sanitized" | Out-File -FilePath $logFile -Append -Encoding UTF8
        }

        function Append-SessionDiagnostics {
            param([string]$Title, [string]$Body)

            if ([string]::IsNullOrWhiteSpace($sessionDiagnosticsPath)) {
                return
            }

            $header = "## $Title`n"
            $content = if ([string]::IsNullOrWhiteSpace($Body)) { "(empty)" } else { $Body.Trim() }
            Add-Content -Path $sessionDiagnosticsPath -Value ($header + $content + "`n") -Encoding UTF8
        }

        function Write-Heartbeat {
            param($jobId, $status)
            $heartbeatFile = "$workDir\heartbeat_$jobId.json"
            @{ jobId = $jobId; timestamp = (Get-Date).ToString("o"); status = $status } | ConvertTo-Json -Compress | Set-Content $heartbeatFile -Encoding UTF8
        }

        Write-DailyLog -message "OpenCode starting task: $taskDescription" -type "OPENCODE"
        Write-Heartbeat -jobId $jobId -status "starting"

        $openCodeUrl = "http://${openCodeHost}:${openCodePort}"
        $maxTimeout = $timeoutSeconds
        $authBytes = [System.Text.Encoding]::ASCII.GetBytes("opencode:$openCodePassword")
        $authBase64 = [System.Convert]::ToBase64String($authBytes)
        $headers = @{
            Authorization  = "Basic $authBase64"
            "Content-Type" = "application/json; charset=utf-8"
        }

        try {
            Write-Heartbeat -jobId $jobId -status "creating_session"
            Write-DailyLog -message "OpenCode job configuration: agent='$agentStr' model='$modelStr' timeout='${timeoutSeconds}s'" -type "OPENCODE"
            $sessionBody = @{ title = "Telegram" }
            if (-not $agentStr -and -not [string]::IsNullOrWhiteSpace($modelStr)) {
                $sessionBody["model"] = $modelStr
            }
            $sessionBytes = [System.Text.Encoding]::UTF8.GetBytes(($sessionBody | ConvertTo-Json -Compress))

            try {
                $sessionResp = Invoke-RestMethod -Uri "$openCodeUrl/session" -Method Post -Headers $headers -Body $sessionBytes -TimeoutSec 30
                $sessionId = $sessionResp.id
            }
            catch {
                $errContent = ""
                if ($_.Exception -and $_.Exception.Response) {
                    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                    $errContent = $reader.ReadToEnd()
                }
                $errMsg = $_.Exception.Message + " " + $errContent

                if ($errMsg -match "insufficient credits|balance|402|Payment Required") {
                    Write-DailyLog -message "OpenCode insufficient credits: $errMsg" -type "ERROR"
                    return "[ERROR_OPENCODE_CREDITS] OpenCode has insufficient credits. Please check your balance."
                }

                Write-DailyLog -message "Error creating OpenCode session: $errMsg" -type "ERROR"
                return "[ERROR_OPENCODE] Could not create the session: $($_.Exception.Message)"
            }

            if ([string]::IsNullOrWhiteSpace($sessionId)) {
                return "[ERROR_OPENCODE] Could not create the session (empty ID)."
            }
            Write-DailyLog -message "Session created: $sessionId" -type "OPENCODE"
            $sessionMetadata = @(
                "- sessionId: $sessionId",
                "- agent: $(if ([string]::IsNullOrWhiteSpace($agentStr)) { "(default)" } else { $agentStr })",
                "- model: $(if ([string]::IsNullOrWhiteSpace($modelStr)) { "(default)" } else { $modelStr })",
                "- timeoutSeconds: $timeoutSeconds"
            ) -join "`n"
            Append-SessionDiagnostics -Title "Session Metadata" -Body $sessionMetadata
            Write-Heartbeat -jobId $jobId -status "session_ready"

            $taskText = @"
Working directory: $workDir
Output directory for created files: $archivesDir
Task: $taskDescription

IMPORTANT: Any file you create must be saved in the output directory ($archivesDir). Do not create generated files in the project root ($workDir).

CHECKPOINT FILE:
$checkpointPath

CHECKPOINT RULES:
1. Read the checkpoint file first if it exists and continue from the saved state.
2. Do not repeat steps already marked as completed unless a real recovery step requires it.
3. After every durable milestone, update the checkpoint JSON with: status, completedSteps, pendingSteps, discoveredUrls, discoveredFiles, extractedFacts, lastAction, and lastError if any.
4. If you already reached a page, extracted links, opened a document, or produced partial output, write that state to the checkpoint before moving on.
5. If the task is retried later, use the checkpoint to resume directly instead of starting from scratch.

CURRENT CHECKPOINT STATE:
$checkpointPrompt
"@.Trim()

            $msgHash = @{
                parts = @(@{ type = "text"; text = $taskText })
            }
            if ($agentStr) { $msgHash.Add("agent", $agentStr) }
            $msgBody = $msgHash | ConvertTo-Json -Depth 5 -Compress
            $msgBytes = [System.Text.Encoding]::UTF8.GetBytes($msgBody)

            Write-Heartbeat -jobId $jobId -status "sending_message"
            Write-DailyLog -message "Sending task to OpenCode session $sessionId" -type "OPENCODE"

            try {
                $responseObj = Invoke-RestMethod -Uri "$openCodeUrl/session/$sessionId/message" -Method Post -Headers $headers -Body $msgBytes -TimeoutSec $maxTimeout
            }
            catch {
                $errContent = ""
                if ($_.Exception -and $_.Exception.Response) {
                    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                    $errContent = $reader.ReadToEnd()
                }
                $errMsg = $_.Exception.Message + " " + $errContent

                if ($errMsg -match "insufficient credits|balance|402|Payment Required") {
                    Write-DailyLog -message "OpenCode insufficient credits during execution: $errMsg" -type "ERROR"
                    return "[ERROR_OPENCODE_CREDITS] OpenCode ran out of credits. The task could not continue."
                }

                Write-DailyLog -message "Error in Invoke-RestMethod (message): $errMsg" -type "ERROR"
                return "[ERROR_OPENCODE] Failed to send the message: $($_.Exception.Message)"
            }

            $resultText = ""
            if ($null -ne $responseObj.parts) {
                $textParts = $responseObj.parts | Where-Object { $_.type -eq "text" -and $null -ne $_.text }
                $resultText = ($textParts | ForEach-Object { $_.text }) -join "`n"
            }

            try {
                $events = Invoke-RestMethod -Uri "$openCodeUrl/session/$sessionId/event" -Headers $headers -TimeoutSec 10 -ErrorAction Stop
                if ($null -ne $events) {
                    $eventsJson = $events | ConvertTo-Json -Depth 8
                    $eventsBody = @(
                        '```json',
                        $eventsJson,
                        '```'
                    ) -join "`n"
                    Append-SessionDiagnostics -Title "Raw Session Events" -Body $eventsBody
                }
            }
            catch {
                Append-SessionDiagnostics -Title "Event Capture Warning" -Body "Could not fetch /session/$sessionId/event after execution: $($_.Exception.Message)"
            }

            if ($resultText -match '\[CANNOT_COMPLETE:\s*(.+?)\]') {
                $reason = $matches[1]
                Write-DailyLog -message "OpenCode cannot complete task: $reason" -type "WARN"
                Append-SessionDiagnostics -Title "Completion Error" -Body $reason
                return "[ERROR_OPENCODE] The model reported it cannot complete this task: $reason"
            }

            if (-not [string]::IsNullOrWhiteSpace($resultText)) {
                $preview = $resultText.Substring(0, [Math]::Min(180, $resultText.Length)).Replace("`r", " ").Replace("`n", " ")
                Write-DailyLog -message "OpenCode response OK: len=$($resultText.Length) preview='$preview'" -type "OPENCODE"
                Append-SessionDiagnostics -Title "Final Response Preview" -Body $preview
                Write-Heartbeat -jobId $jobId -status "completed"
                return $resultText
            }
            else {
                $rawDebug = $responseObj | ConvertTo-Json -Depth 10 -Compress
                Write-DailyLog -message "OpenCode returned an empty response. Raw: $rawDebug" -type "WARN"
                Append-SessionDiagnostics -Title "Empty Response" -Body $rawDebug
                return "[ERROR_OPENCODE] Empty response"
            }
        }
        catch {
            Write-DailyLog -message "Error in OpenCode: $_" -type "ERROR"
            Append-SessionDiagnostics -Title "Unhandled Orchestrator Error" -Body "$($_.Exception.Message)"
            return "[ERROR_OPENCODE] $($_.Exception.Message)"
        }
        finally {
            $heartbeatFile = "$workDir\heartbeat_$jobId.json"
            if (Test-Path $heartbeatFile) { Remove-Item $heartbeatFile -Force -ErrorAction SilentlyContinue }
        }
    }

    $jobId = [Guid]::NewGuid().ToString()
    $job = Start-Job -ScriptBlock $jobScript -ArgumentList $TaskDescription, $workDir, $archivesDir, $jobId, $EnableMCPs, $Model, $Agent, $TimeoutSec, $botConfig.OpenCode.Host, $botConfig.OpenCode.Port, $botConfig.OpenCode.ServerPassword, $checkpointInfo.Path, $checkpointPrompt, $sessionDiagnosticsPath
    $labelSuffix = if ($EnableMCPs.Count -gt 0) { " (MCP: $($EnableMCPs -join ','))" } else { "" }
    if ($Agent) { $labelSuffix += " [Agent: $Agent]" }
    return @{
        Job          = $job
        ChatId       = $ChatId
        Task         = $TaskDescription
        Label        = "OpenCode HTTP$labelSuffix"
        Type         = "OpenCode"
        StartTime    = Get-Date
        LastTyping   = $null
        LastReport   = Get-Date
        LastStatusId = $null
        OutputBuffer = @()
        TimeoutSec   = $TimeoutSec
        CheckpointPath = $checkpointInfo.Path
        CheckpointReason = $checkpointInfo.Reason
        SessionDiagnosticsPath = $sessionDiagnosticsPath
    }
}
