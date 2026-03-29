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
        'linkedin','post','posts','draft','borrador','contenido','content','instrucciones','instructions',
        'publicar','publish','manualmente','manually','composer','feed',
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

    $diagnosticsDir = Join-Path $archivesDir "session-diagnostics"
    New-Item -ItemType Directory -Force -Path $diagnosticsDir | Out-Null

    $startedAt = (Get-Date).ToString("o")
    $safeChatId = if ([string]::IsNullOrWhiteSpace($ChatId)) { "none" } else { ($ChatId -replace '[^a-zA-Z0-9_-]', '_') }
    $safeTask = if ([string]::IsNullOrWhiteSpace($TaskText)) { "(empty task)" } else { $TaskText.Trim() }
    $fingerprint = Get-TaskCheckpointFingerprint -TaskText $TaskText
    $shortFingerprint = if ([string]::IsNullOrWhiteSpace($fingerprint)) { [Guid]::NewGuid().ToString("N").Substring(0, 12) } else { $fingerprint.Substring(0, [Math]::Min(12, $fingerprint.Length)) }
    $timestampLabel = Get-Date -Format "yyyyMMdd_HHmmss"
    $diagnosticPath = Join-Path $diagnosticsDir ("opencode-{0}-{1}-{2}.md" -f $timestampLabel, $safeChatId, $shortFingerprint)

    $initialContent = @"
# OpenCode Session Diagnostics

## Session

- startedAt: $startedAt
- chatId: $safeChatId
- task: $safeTask

## Progress Log

(append short bullet lines here while the task is running)

## Notes

- This file is per session and should not be overwritten by another job.
- OpenCode should append short bullet lines to Progress Log for milestones, blockers, retries, and strategy changes.
- The orchestrator may append session metadata, warnings, usage, and raw event snapshots in separate sections.
"@.Trim() + "`n"

    Set-Content -Path $diagnosticPath -Value $initialContent -Encoding UTF8
    return $diagnosticPath
}

function Get-OpenCodeCliSessionIds {
    param(
        [string]$CommandName,
        [string]$WorkingDirectory,
        [string]$ApiKey = ""
    )

    try {
        Set-Location -Path $WorkingDirectory
        if (-not [string]::IsNullOrWhiteSpace($ApiKey)) {
            $env:OPENCODE_API_KEY = $ApiKey
        }

        $raw = (& $CommandName session list 2>&1 | Out-String)
        $matches = [regex]::Matches($raw, '(?m)^(ses_[A-Za-z0-9]+)\b')
        $ids = @()
        foreach ($match in $matches) {
            $ids += $match.Groups[1].Value
        }
        return @($ids | Select-Object -Unique)
    }
    catch {
        return @()
    }
}

function Export-OpenCodeSessionJson {
    param(
        [string]$CommandName,
        [string]$WorkingDirectory,
        [string]$SessionId,
        [string]$ApiKey = ""
    )

    if ([string]::IsNullOrWhiteSpace($SessionId)) {
        return $null
    }

    try {
        Set-Location -Path $WorkingDirectory
        if (-not [string]::IsNullOrWhiteSpace($ApiKey)) {
            $env:OPENCODE_API_KEY = $ApiKey
        }

        $raw = (& $CommandName export $SessionId 2>&1 | Out-String)
        $jsonStart = $raw.IndexOf('{')
        if ($jsonStart -lt 0) {
            return $null
        }

        $jsonText = $raw.Substring($jsonStart)
        return ($jsonText | ConvertFrom-Json -Depth 100)
    }
    catch {
        return $null
    }
}

function Get-OpenCodeUsagePayloadFromExport {
    param(
        [object]$ExportData
    )

    if ($null -eq $ExportData -or $null -eq $ExportData.messages) {
        return $null
    }

    $inputTokens = 0
    $outputTokens = 0
    $reasoningTokens = 0
    $cacheReadTokens = 0
    $cacheWriteTokens = 0
    $totalTokens = 0
    $cost = 0.0

    foreach ($message in @($ExportData.messages)) {
        if ($null -eq $message -or $null -eq $message.info) {
            continue
        }

        if ("$($message.info.role)" -ne "assistant") {
            continue
        }

        $tokens = $message.info.tokens
        if ($tokens) {
            $inputTokens += [int]($tokens.input)
            $outputTokens += [int]($tokens.output)
            $reasoningTokens += [int]($tokens.reasoning)
            if ($tokens.cache) {
                $cacheReadTokens += [int]($tokens.cache.read)
                $cacheWriteTokens += [int]($tokens.cache.write)
            }
            $totalTokens += [int]($tokens.total)
        }

        if ($message.info.PSObject.Properties["cost"]) {
            $cost += [double]($message.info.cost)
        }
    }

    return [PSCustomObject]@{
        SessionId = if ($ExportData.info) { "$($ExportData.info.id)" } else { "" }
        InputTokens = $inputTokens
        OutputTokens = $outputTokens
        ReasoningTokens = $reasoningTokens
        CacheReadTokens = $cacheReadTokens
        CacheWriteTokens = $cacheWriteTokens
        TotalTokens = $totalTokens
        Cost = [Math]::Round($cost, 6)
    }
}

function Convert-OpenCodeUsagePayloadToMarker {
    param(
        [object]$Usage
    )

    if ($null -eq $Usage) {
        return ""
    }

    $lines = @(
        "[OPENCODE_USAGE]",
        "sessionId: $($Usage.SessionId)",
        "inputTokens: $($Usage.InputTokens)",
        "outputTokens: $($Usage.OutputTokens)",
        "reasoningTokens: $($Usage.ReasoningTokens)",
        "cacheReadTokens: $($Usage.CacheReadTokens)",
        "cacheWriteTokens: $($Usage.CacheWriteTokens)",
        "totalTokens: $($Usage.TotalTokens)",
        "cost: $($Usage.Cost)",
        "[/OPENCODE_USAGE]"
    )

    return ($lines -join "`n")
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

function Convert-ToCheckpointStringArray {
    param(
        $Value
    )

    if ($null -eq $Value) {
        return @()
    }

    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) {
            return @()
        }
        return @($Value)
    }

    $items = @()
    foreach ($entry in @($Value)) {
        if ($null -eq $entry) {
            continue
        }

        $text = "$entry".Trim()
        if ([string]::IsNullOrWhiteSpace($text)) {
            continue
        }

        $items += $text
    }

    return @($items)
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
    $notes = @(Convert-ToCheckpointStringArray -Value $CheckpointData.notes)
    if ($notes.Count -gt 0) {
        $lines += "Notes: " + (($notes | Select-Object -Last 4) -join "; ")
    }
    if ($CheckpointData.lastResultPreview) { $lines += "Last result preview: $($CheckpointData.lastResultPreview)" }
    if ($CheckpointData.lastError) { $lines += "Last error: $($CheckpointData.lastError)" }
    if ($CheckpointData.updatedAt) { $lines += "Updated at: $($CheckpointData.updatedAt)" }

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

        $candidateKeywordSeed = @(
            (Convert-ToCheckpointStringArray -Value $candidateData.extractedFacts) +
            (Convert-ToCheckpointStringArray -Value $candidateData.completedSteps) +
            (Convert-ToCheckpointStringArray -Value $candidateData.pendingSteps) +
            (Get-TaskCheckpointKeywords -TaskText $candidateData.subject)
        )
        $candidateKeywords = @($candidateKeywordSeed | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $overlap = @($taskKeywords | Where-Object { $candidateKeywords -contains $_ } | Select-Object -Unique)
        $shouldReuse = ($TaskText -match $resumePattern -and $candidateData.status -ne "completed") -or ($overlap.Count -ge 4)
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

        $urlSeed = @(
            (Convert-ToCheckpointStringArray -Value $mutable.discoveredUrls) +
            (Convert-ToCheckpointStringArray -Value $urlMatches)
        )
        $fileSeed = @(
            (Convert-ToCheckpointStringArray -Value $mutable.discoveredFiles) +
            (Convert-ToCheckpointStringArray -Value $fileMatches)
        )
        $factSeed = @(
            (Convert-ToCheckpointStringArray -Value $mutable.extractedFacts) +
            (Convert-ToCheckpointStringArray -Value $factMatches)
        )

        $mutable.discoveredUrls = @($urlSeed | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
        $mutable.discoveredFiles = @($fileSeed | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
        $mutable.extractedFacts = @($factSeed | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 20 -Unique)
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
    catch { Write-DailyLog -message "Get-OpenCodeServerProcessIds: Failed to enumerate processes via netstat" -type "WARN" }

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
    catch { Write-DailyLog -message "Get-OpenCodeServerProcessIds: Failed to enumerate processes via WMI" -type "WARN" }

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
                catch { Write-DailyLog -message "Stop-OpenCodeServer: Failed to update checkpoint for job $($jobRecord.Job.Id)" -type "WARN" }
            }
            try {
                Stop-Job -Job $jobRecord.Job -ErrorAction SilentlyContinue | Out-Null
                Remove-Job -Job $jobRecord.Job -Force -ErrorAction SilentlyContinue
                $stoppedJobIds += $jobRecord.Job.Id
            }
            catch { Write-DailyLog -message "Stop-OpenCodeServer: Failed to stop job $($jobRecord.Job.Id)" -type "WARN" }

            try {
                Remove-ActiveJobById -JobId $jobRecord.Job.Id
            }
            catch { Write-DailyLog -message "Stop-OpenCodeServer: Failed to remove job $($jobRecord.Job.Id) from active list" -type "WARN" }
        }

        if (Get-Command Write-JobsFile -ErrorAction SilentlyContinue) {
            try { Write-JobsFile } catch { Write-DailyLog -message "Stop-OpenCodeServer: Failed to write jobs file" -type "WARN" }
        }
    }

    foreach ($threadJob in @(Get-Job -Name "OpenCodeServer" -ErrorAction SilentlyContinue)) {
        try {
            Stop-Job -Job $threadJob -ErrorAction SilentlyContinue | Out-Null
            Remove-Job -Job $threadJob -Force -ErrorAction SilentlyContinue
        }
        catch { Write-DailyLog -message "Stop-OpenCodeServer: Failed to stop thread job" -type "WARN" }
    }

    foreach ($processId in @(Get-OpenCodeServerProcessIds -BotConfig $BotConfig)) {
        try {
            $proc = Get-Process -Id $processId -ErrorAction SilentlyContinue
            if ($null -ne $proc) {
                Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
                $killedProcessIds += $processId
            }
        }
        catch { Write-DailyLog -message "Stop-OpenCodeServer: Failed to kill process $processId" -type "WARN" }
    }

    Start-Sleep -Milliseconds 300
    $remainingProcesses = @(Get-OpenCodeServerProcessIds -BotConfig $BotConfig)

    if (Get-Command Write-DailyLog -ErrorAction SilentlyContinue) {
        $logMsg = "Stop-OpenCodeServer reason='$Reason' stopped_jobs=$($stoppedJobIds.Count) killed_processes=$($killedProcessIds.Count) remaining_processes=$($remainingProcesses.Count)"
        try { Write-DailyLog -message $logMsg -type "SYSTEM" } catch { Write-Host "Failed to log: $logMsg" }
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
            $normalizedContent = Convert-OpenRouterContentToText -Content $rawContent
            if ([string]::IsNullOrWhiteSpace($normalizedContent)) {
                Write-DailyLog -message "OpenRouter returned empty content (attempt $attempt). $model" -type "WARN"
                if ($attempt -lt $maxAttempts) { Start-Sleep -Seconds 2; continue }
                return ""
            }
            return $normalizedContent
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

function Convert-OpenRouterContentToText {
    param(
        [Parameter(ValueFromPipeline = $true)]
        $Content
    )

    if ($null -eq $Content) {
        return ""
    }

    if ($Content -is [string]) {
        return $Content
    }

    if ($Content -is [array]) {
        $parts = @()
        foreach ($item in $Content) {
            if ($null -eq $item) {
                continue
            }

            if ($item -is [string]) {
                $parts += $item
                continue
            }

            if ($item.PSObject.Properties["text"] -and -not [string]::IsNullOrWhiteSpace("$($item.text)")) {
                $parts += "$($item.text)"
                continue
            }

            if ($item.PSObject.Properties["content"] -and -not [string]::IsNullOrWhiteSpace("$($item.content)")) {
                $parts += "$($item.content)"
                continue
            }

            try {
                $parts += ($item | ConvertTo-Json -Depth 10 -Compress)
            }
            catch {
                $parts += "$item"
            }
        }

        return ($parts -join "`n").Trim()
    }

    if ($Content.PSObject.Properties["text"] -and -not [string]::IsNullOrWhiteSpace("$($Content.text)")) {
        return "$($Content.text)"
    }

    if ($Content.PSObject.Properties["content"] -and -not [string]::IsNullOrWhiteSpace("$($Content.content)")) {
        return (Convert-OpenRouterContentToText -Content $Content.content)
    }

    try {
        return ($Content | ConvertTo-Json -Depth 10 -Compress)
    }
    catch {
        return "$Content"
    }
}

function New-OpenCodeRuntimeTaskPrompt {
    param(
        [string]$TaskDescription,
        [string]$WorkDir,
        [string]$OutputDir,
        [string]$CheckpointPath,
        [string]$CheckpointPrompt,
        [string]$SessionDiagnosticsPath,
        [bool]$AllowParallelPlan = $true
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Working directory: $WorkDir") | Out-Null
    $lines.Add("Output directory: $OutputDir") | Out-Null
    $lines.Add("FILE OUTPUT RULE: Save ALL generated files (scripts, images, reports, exports, downloads, etc.) to the Output directory ($OutputDir) unless the user explicitly requests a different path. Do NOT create files in the Working directory root or any other location.") | Out-Null
    $lines.Add("Checkpoint file: $CheckpointPath") | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($SessionDiagnosticsPath)) {
        $lines.Add("Session diagnostics file: $SessionDiagnosticsPath") | Out-Null
    }
    $lines.Add("Checkpoint rule: resume from it when present, do not repeat completed steps, and update it after durable milestones with status, completedSteps, pendingSteps, discoveredUrls, discoveredFiles, extractedFacts, notes, lastAction, and lastError.") | Out-Null
    $lines.Add("Visibility rule: keep the checkpoint and diagnostics files current enough that the orchestrator can explain your progress every few minutes.") | Out-Null
    $lines.Add("Progress rule: before major work and after each durable milestone, update the checkpoint file in place. Keep status, completedSteps, pendingSteps, notes, lastAction, and lastError current. If blocked, state exactly what blocked you.") | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($SessionDiagnosticsPath)) {
        $lines.Add("Diagnostics rule: append short bullet lines to the Progress Log in the diagnostics file whenever you hit a blocker, retry a failed path, change strategy, or complete a milestone. Be concrete, not generic.") | Out-Null
    }
    $lines.Add("Loop guard: if the same command, tool, or strategy fails twice, do not keep retrying that path. Either switch to a materially different approach once, or stop with [CANNOT_COMPLETE: concise reason].") | Out-Null
    $lines.Add("FAIL-FAST RULE: Before attempting any work, check your available tools. If the task REQUIRES a tool you do not have (Playwright, Excel MCP, file-converter, computer-control, Word MCP), do NOT improvise. Return [TOOLS_MISSING] with MissingTool, Task, and Reason fields immediately. This lets the orchestrator re-route you.") | Out-Null
    if ($AllowParallelPlan) {
        $lines.Add("Parallel rule: if the task clearly splits into 2-4 independent non-interactive branches that should run concurrently, do not simulate parallelism yourself. Return exactly [ORCHESTRATOR_PARALLEL_PLAN] JSON [/ORCHESTRATOR_PARALLEL_PLAN] with fields strategy, merge_task, and tasks[]. Each task needs title, route, and task. Use only routes build, browser, docs, sheets, computer, or social.") | Out-Null
    }
    else {
        $lines.Add("Parallel rule: do not return ORCHESTRATOR_PARALLEL_PLAN for this task. Complete it directly.") | Out-Null
    }
    $lines.Add("") | Out-Null
    $taskText = if ($null -eq $TaskDescription) { "" } else { "$TaskDescription" }
    $lines.Add("Task:") | Out-Null
    $lines.Add($taskText.Trim()) | Out-Null

    if (-not [string]::IsNullOrWhiteSpace($CheckpointPrompt)) {
        $lines.Add("") | Out-Null
        $lines.Add("Current checkpoint state:") | Out-Null
        $lines.Add($CheckpointPrompt.Trim()) | Out-Null
    }

    return (($lines | Where-Object { $null -ne $_ }) -join "`n").Trim()
}

function Start-OpenCodeJob {
    param(
        [string]$TaskDescription,
        [string]$ChatId,
        [string[]]$EnableMCPs = @(),
        [string]$Model = "",
        [string]$Agent = $null,
        [int]$TimeoutSec = 1200,
        [bool]$AllowParallelPlan = $true
    )
    $requestedModel = $Model
    if ([string]::IsNullOrWhiteSpace($Model)) {
        $Model = $botConfig.OpenCode.DefaultModel
    }
    $transport = "cli"
    if ($botConfig.OpenCode -and $botConfig.OpenCode.PSObject.Properties["Transport"] -and -not [string]::IsNullOrWhiteSpace("$($botConfig.OpenCode.Transport)")) {
        $transport = "$($botConfig.OpenCode.Transport)".Trim().ToLowerInvariant()
    }
    $checkpointInfo = Resolve-TaskCheckpoint -BotConfig $botConfig -ChatId $ChatId -TaskText $TaskDescription
    $sessionDiagnosticsPath = Initialize-OpenCodeSessionDiagnostics -BotConfig $botConfig -ChatId $ChatId -TaskText $TaskDescription
    Update-TaskCheckpointState -CheckpointPath $checkpointInfo.Path -TaskText $TaskDescription -Status "running" -LastAction "Task delegated to OpenCode"
    $checkpointPrompt = Get-CheckpointStateForPrompt -CheckpointData $checkpointInfo.Data
    $runtimeTaskPrompt = New-OpenCodeRuntimeTaskPrompt -TaskDescription $TaskDescription -WorkDir $workDir -OutputDir $archivesDir -CheckpointPath $checkpointInfo.Path -CheckpointPrompt $checkpointPrompt -SessionDiagnosticsPath $sessionDiagnosticsPath -AllowParallelPlan:$AllowParallelPlan

    if ($transport -ne "http") {
        $heartbeatId = [Guid]::NewGuid().ToString("N")
        $heartbeatPath = Join-Path $workDir "archives\heartbeat_$heartbeatId.json"
        $cliModel = if ([string]::IsNullOrWhiteSpace($requestedModel)) { "" } else { $requestedModel.Trim() }
        $jobScript = {
            param($taskDescription, $runtimeTaskPrompt, $workDir, $archivesDir, $heartbeatPath, $enableMCPs, $modelStr, $agentStr, $timeoutSeconds, $openCodeCommand, $openCodeApiKey, $checkpointPath, $checkpointPrompt, $sessionDiagnosticsPath)
            Add-Type -AssemblyName System.Net.Http
            function Write-DailyLog {
                param([string]$message, [string]$type = "INFO")
                $logFile = "$workDir\archives\subagent_events.log"
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
                param([string]$status)

                @{ timestamp = (Get-Date).ToString("o"); status = $status } | ConvertTo-Json -Compress | Set-Content $heartbeatPath -Encoding UTF8
            }

            function Get-OpenCodeCliSessionIds {
                param([string]$CommandName, [string]$WorkingDirectory, [string]$ApiKey = "")
                try {
                    Set-Location -Path $WorkingDirectory
                    if (-not [string]::IsNullOrWhiteSpace($ApiKey)) { $env:OPENCODE_API_KEY = $ApiKey }
                    $raw = (& $CommandName session list 2>&1 | Out-String)
                    $matches = [regex]::Matches($raw, '(?m)^(ses_[A-Za-z0-9]+)\b')
                    $ids = @()
                    foreach ($match in $matches) { $ids += $match.Groups[1].Value }
                    return @($ids | Select-Object -Unique)
                } catch { return @() }
            }

            function Export-OpenCodeSessionJson {
                param([string]$CommandName, [string]$WorkingDirectory, [string]$SessionId, [string]$ApiKey = "")
                if ([string]::IsNullOrWhiteSpace($SessionId)) { return $null }
                try {
                    Set-Location -Path $WorkingDirectory
                    if (-not [string]::IsNullOrWhiteSpace($ApiKey)) { $env:OPENCODE_API_KEY = $ApiKey }
                    $raw = (& $CommandName export $SessionId 2>&1 | Out-String)
                    $jsonStart = $raw.IndexOf('{')
                    if ($jsonStart -lt 0) { return $null }
                    $jsonText = $raw.Substring($jsonStart)
                    return ($jsonText | ConvertFrom-Json -Depth 100)
                } catch { return $null }
            }

            # NOTE: This function is duplicated from line 200 because PowerShell jobs run in a separate process
            # and cannot access functions from the parent script. This is intentional.
            function Get-OpenCodeUsagePayloadFromExport {
                param([object]$ExportData)
                if ($null -eq $ExportData -or $null -eq $ExportData.messages) { return $null }
                $inputTokens = 0; $outputTokens = 0; $reasoningTokens = 0; $cacheReadTokens = 0; $cacheWriteTokens = 0; $totalTokens = 0; $cost = 0.0
                foreach ($message in @($ExportData.messages)) {
                    if ($null -eq $message -or $null -eq $message.info) { continue }
                    if ("$($message.info.role)" -ne "assistant") { continue }
                    $tokens = $message.info.tokens
                    if ($tokens) {
                        $inputTokens += [int]($tokens.input)
                        $outputTokens += [int]($tokens.output)
                        $reasoningTokens += [int]($tokens.reasoning)
                        if ($tokens.cache) {
                            $cacheReadTokens += [int]($tokens.cache.read)
                            $cacheWriteTokens += [int]($tokens.cache.write)
                        }
                        $totalTokens += [int]($tokens.total)
                    }
                    if ($message.info.PSObject.Properties["cost"]) { $cost += [double]($message.info.cost) }
                }
                return [PSCustomObject]@{
                    SessionId = if ($ExportData.info) { "$($ExportData.info.id)" } else { "" }
                    InputTokens = $inputTokens
                    OutputTokens = $outputTokens
                    ReasoningTokens = $reasoningTokens
                    CacheReadTokens = $cacheReadTokens
                    CacheWriteTokens = $cacheWriteTokens
                    TotalTokens = $totalTokens
                    Cost = [Math]::Round($cost, 6)
                }
            }

            function Convert-OpenCodeUsagePayloadToMarker {
                param([object]$Usage)
                if ($null -eq $Usage) { return "" }
                @(
                    "[OPENCODE_USAGE]",
                    "sessionId: $($Usage.SessionId)",
                    "inputTokens: $($Usage.InputTokens)",
                    "outputTokens: $($Usage.OutputTokens)",
                    "reasoningTokens: $($Usage.ReasoningTokens)",
                    "cacheReadTokens: $($Usage.CacheReadTokens)",
                    "cacheWriteTokens: $($Usage.CacheWriteTokens)",
                    "totalTokens: $($Usage.TotalTokens)",
                    "cost: $($Usage.Cost)",
                    "[/OPENCODE_USAGE]"
                ) -join "`n"
            }

            $taskText = $runtimeTaskPrompt

            try {
                Set-Location -Path $workDir
                if (-not [string]::IsNullOrWhiteSpace($openCodeApiKey)) {
                    $env:OPENCODE_API_KEY = $openCodeApiKey
                }

                $modelLabel = if ([string]::IsNullOrWhiteSpace($modelStr)) { "(opencode default)" } else { $modelStr }
                $agentLabel = if ([string]::IsNullOrWhiteSpace($agentStr)) { "(none)" } else { $agentStr }
                Write-DailyLog -message "OpenCode CLI starting task: $taskDescription" -type "OPENCODE"
                Write-DailyLog -message "OpenCode CLI configuration: agent_hint='$agentLabel' model='$modelLabel' timeout='${timeoutSeconds}s'" -type "OPENCODE"
                $cliMetadata = @(
                    "- transport: cli",
                    "- agentHint: $agentLabel",
                    "- model: $modelLabel",
                    "- timeoutSeconds: $timeoutSeconds"
                ) -join "`n"
                Append-SessionDiagnostics -Title "CLI Metadata" -Body $cliMetadata
                Write-Heartbeat -status "starting_cli"
                $sessionIdsBefore = @(Get-OpenCodeCliSessionIds -CommandName $openCodeCommand -WorkingDirectory $workDir -ApiKey $openCodeApiKey)

                $opencodeArgs = @("run", $taskText)
                if (-not [string]::IsNullOrWhiteSpace($modelStr)) {
                    $opencodeArgs += @("--model", $modelStr)
                }
                if (-not [string]::IsNullOrWhiteSpace($agentStr)) {
                    $opencodeArgs += @("--agent", $agentStr)
                }

                $innerJob = Start-Job -ScriptBlock {
                    param($commandName, $argsList, $jobWorkDir, $jobApiKey)
                    Set-Location -Path $jobWorkDir
                    if (-not [string]::IsNullOrWhiteSpace($jobApiKey)) {
                        $env:OPENCODE_API_KEY = $jobApiKey
                    }
                    & $commandName @argsList 2>&1 | Out-String
                } -ArgumentList $openCodeCommand, $opencodeArgs, $workDir, $openCodeApiKey

                $deadline = (Get-Date).AddSeconds($timeoutSeconds)
                while ($true) {
                    $finished = Wait-Job -Job $innerJob -Timeout 5
                    if ($finished) {
                        break
                    }

                    if ((Get-Date) -ge $deadline) {
                        Stop-Job -Job $innerJob -ErrorAction SilentlyContinue | Out-Null
                        Remove-Job -Job $innerJob -Force -ErrorAction SilentlyContinue
                        Write-DailyLog -message "OpenCode CLI timed out after ${timeoutSeconds}s" -type "WARN"
                        Append-SessionDiagnostics -Title "Timeout" -Body "The CLI execution exceeded ${timeoutSeconds}s."
                        return "[ERROR_TIMEOUT] OpenCode did not finish within $timeoutSeconds seconds."
                    }

                    Write-Heartbeat -status "running_cli"
                }

                $result = Receive-Job -Job $innerJob -ErrorAction SilentlyContinue
                $childErrors = $innerJob.ChildJobs | ForEach-Object { $_.Error } | Where-Object { $null -ne $_ }
                Remove-Job -Job $innerJob -Force -ErrorAction SilentlyContinue

                $resultText = ($result | Out-String).Trim()
                if ($childErrors) {
                    $errText = ($childErrors | ForEach-Object { "$_" }) -join "; "
                    if ([string]::IsNullOrWhiteSpace($resultText)) {
                        $resultText = "[ERROR_OPENCODE] $errText"
                    }
                }

                if ($resultText -match 'insufficient credits|no credits|balance empty|Payment Required|credit limit|rate limit exceeded|out of credits') {
                    Write-DailyLog -message "OpenCode CLI insufficient credits: $resultText" -type "ERROR"
                    return "[ERROR_OPENCODE_CREDITS] OpenCode has insufficient credits. Please check your balance."
                }

                if ($resultText -match '\[CANNOT_COMPLETE:\s*(.+?)\]') {
                    $reason = $Matches[1]
                    Write-DailyLog -message "OpenCode CLI cannot complete task: $reason" -type "WARN"
                    Append-SessionDiagnostics -Title "Completion Error" -Body $reason
                    return "[ERROR_OPENCODE] The model reported it cannot complete this task: $reason"
                }

                if ([string]::IsNullOrWhiteSpace($resultText)) {
                    Write-DailyLog -message "OpenCode CLI returned an empty response." -type "WARN"
                    Append-SessionDiagnostics -Title "Empty Response" -Body "(empty)"
                    return "[ERROR_OPENCODE] Empty response"
                }

                $preview = $resultText.Substring(0, [Math]::Min(180, $resultText.Length)).Replace("`r", " ").Replace("`n", " ")
                Write-DailyLog -message "OpenCode CLI response OK: len=$($resultText.Length) preview='$preview'" -type "OPENCODE"
                Append-SessionDiagnostics -Title "Final Response Preview" -Body $preview
                $sessionIdsAfter = @(Get-OpenCodeCliSessionIds -CommandName $openCodeCommand -WorkingDirectory $workDir -ApiKey $openCodeApiKey)
                $newSessionId = @($sessionIdsAfter | Where-Object { $sessionIdsBefore -notcontains $_ } | Select-Object -First 1)
                if (-not $newSessionId -and $sessionIdsAfter.Count -gt 0) {
                    $newSessionId = $sessionIdsAfter[0]
                }
                $usageMarker = ""
                if ($newSessionId) {
                    $exportData = Export-OpenCodeSessionJson -CommandName $openCodeCommand -WorkingDirectory $workDir -SessionId $newSessionId -ApiKey $openCodeApiKey
                    $usage = Get-OpenCodeUsagePayloadFromExport -ExportData $exportData
                    if ($usage) {
                        $usageMarker = Convert-OpenCodeUsagePayloadToMarker -Usage $usage
                        $usageSummary = "session=$($usage.SessionId) total=$($usage.TotalTokens) input=$($usage.InputTokens) output=$($usage.OutputTokens) reasoning=$($usage.ReasoningTokens) cacheRead=$($usage.CacheReadTokens) cost=$($usage.Cost)"
                        Write-DailyLog -message "OpenCode CLI usage: $usageSummary" -type "OPENCODE"
                        Append-SessionDiagnostics -Title "Usage Summary" -Body $usageSummary
                    }
                }
                Write-Heartbeat -status "completed"
                if ([string]::IsNullOrWhiteSpace($usageMarker)) {
                    return $resultText
                }
                return ($resultText.TrimEnd() + "`n`n" + $usageMarker)
            }
            catch {
                Write-DailyLog -message "Error in OpenCode CLI: $_" -type "ERROR"
                Append-SessionDiagnostics -Title "Unhandled Orchestrator Error" -Body "$($_.Exception.Message)"
                return "[ERROR_OPENCODE] $($_.Exception.Message)"
            }
            finally {
                if (Test-Path $heartbeatPath) { Remove-Item $heartbeatPath -Force -ErrorAction SilentlyContinue }
            }
        }

        $job = Start-Job -ScriptBlock $jobScript -ArgumentList $TaskDescription, $runtimeTaskPrompt, $workDir, $archivesDir, $heartbeatPath, $EnableMCPs, $cliModel, $Agent, $TimeoutSec, $botConfig.OpenCode.Command, $botConfig.OpenCode.ApiKey, $checkpointInfo.Path, $checkpointPrompt, $sessionDiagnosticsPath
        $labelSuffix = if ($EnableMCPs.Count -gt 0) { " (MCP: $($EnableMCPs -join ','))" } else { "" }
        if ($Agent) { $labelSuffix += " [Agent hint: $Agent]" }
        return @{
            Job          = $job
            ChatId       = $ChatId
            Task         = $TaskDescription
            Label        = "OpenCode CLI$labelSuffix"
            Type         = "OpenCode"
            Transport    = "cli"
            StartTime    = Get-Date
            LastTyping   = $null
            LastReport   = Get-Date
            LastStatusId = $null
            OutputBuffer = @()
            TimeoutSec   = $TimeoutSec
            CheckpointPath = $checkpointInfo.Path
            CheckpointReason = $checkpointInfo.Reason
            SessionDiagnosticsPath = $sessionDiagnosticsPath
            HeartbeatPath = $heartbeatPath
            RequestedAgent = $Agent
            RequestedModel = $requestedModel
            AllowParallelPlan = $AllowParallelPlan
        }
    }

    [void](Start-OpenCodeServerIfNeeded -BotConfig $botConfig)
    $jobScript = {
        param($taskDescription, $runtimeTaskPrompt, $workDir, $archivesDir, $jobId, $enableMCPs, $modelStr, $agentStr, $timeoutSeconds, $openCodeHost, $openCodePort, $openCodePassword, $checkpointPath, $checkpointPrompt, $sessionDiagnosticsPath)
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
            $heartbeatFile = "$workDir\archives\heartbeat_$jobId.json"
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

            $sessionCreateTimeout = [Math]::Max(90, [Math]::Min([int]$maxTimeout, 300))
            $sessionCreateAttempts = 0
            $sessionCreateMaxAttempts = 2
            $sessionId = $null

            while ($sessionCreateAttempts -lt $sessionCreateMaxAttempts -and [string]::IsNullOrWhiteSpace($sessionId)) {
                $sessionCreateAttempts++
                try {
                    $sessionResp = Invoke-RestMethod -Uri "$openCodeUrl/session" -Method Post -Headers $headers -Body $sessionBytes -TimeoutSec $sessionCreateTimeout
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

                    Write-DailyLog -message "Error creating OpenCode session (attempt ${sessionCreateAttempts}/${sessionCreateMaxAttempts}): $errMsg" -type "ERROR"
                    if ($sessionCreateAttempts -lt $sessionCreateMaxAttempts) {
                        Start-Sleep -Seconds 5
                    }
                    else {
                        return "[ERROR_OPENCODE] Could not create the session: $($_.Exception.Message)"
                    }
                }
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

            $taskText = $runtimeTaskPrompt

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
                $usageMarker = ""
                $usage = $null
                if ($responseObj.PSObject.Properties["messages"]) {
                    $usage = Get-OpenCodeUsagePayloadFromExport -ExportData $responseObj
                }
                elseif ($null -ne $events -and $events.PSObject.Properties["messages"]) {
                    $usage = Get-OpenCodeUsagePayloadFromExport -ExportData $events
                }
                if ($usage) {
                    if ([string]::IsNullOrWhiteSpace("$($usage.SessionId)")) {
                        $usage.SessionId = $sessionId
                    }
                    $usageMarker = Convert-OpenCodeUsagePayloadToMarker -Usage $usage
                    $usageSummary = "session=$($usage.SessionId) total=$($usage.TotalTokens) input=$($usage.InputTokens) output=$($usage.OutputTokens) reasoning=$($usage.ReasoningTokens) cacheRead=$($usage.CacheReadTokens) cost=$($usage.Cost)"
                    Write-DailyLog -message "OpenCode HTTP usage: $usageSummary" -type "OPENCODE"
                    Append-SessionDiagnostics -Title "Usage Summary" -Body $usageSummary
                }
                Write-Heartbeat -jobId $jobId -status "completed"
                if ([string]::IsNullOrWhiteSpace($usageMarker)) {
                    return $resultText
                }
                return ($resultText.TrimEnd() + "`n`n" + $usageMarker)
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
            $heartbeatFile = "$workDir\archives\heartbeat_$jobId.json"
            if (Test-Path $heartbeatFile) { Remove-Item $heartbeatFile -Force -ErrorAction SilentlyContinue }
        }
    }

    $jobId = [Guid]::NewGuid().ToString()
    $job = Start-Job -ScriptBlock $jobScript -ArgumentList $TaskDescription, $runtimeTaskPrompt, $workDir, $archivesDir, $jobId, $EnableMCPs, $Model, $Agent, $TimeoutSec, $botConfig.OpenCode.Host, $botConfig.OpenCode.Port, $botConfig.OpenCode.ServerPassword, $checkpointInfo.Path, $checkpointPrompt, $sessionDiagnosticsPath
    $labelSuffix = if ($EnableMCPs.Count -gt 0) { " (MCP: $($EnableMCPs -join ','))" } else { "" }
    if ($Agent) { $labelSuffix += " [Agent: $Agent]" }
    return @{
        Job          = $job
        ChatId       = $ChatId
        Task         = $TaskDescription
        Label        = "OpenCode HTTP$labelSuffix"
        Type         = "OpenCode"
        Transport    = "http"
        StartTime    = Get-Date
        LastTyping   = $null
        LastReport   = Get-Date
        LastStatusId = $null
        OutputBuffer = @()
        TimeoutSec   = $TimeoutSec
        CheckpointPath = $checkpointInfo.Path
        CheckpointReason = $checkpointInfo.Reason
        SessionDiagnosticsPath = $sessionDiagnosticsPath
        RequestedAgent = $Agent
        RequestedModel = $requestedModel
        AllowParallelPlan = $AllowParallelPlan
    }
}
