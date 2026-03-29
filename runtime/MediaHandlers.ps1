function Take-Screenshot {
    param($filePath)
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen
    $bitmap = New-Object System.Drawing.Bitmap -ArgumentList $screen.Bounds.Width, $screen.Bounds.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($screen.Bounds.Left, $screen.Bounds.Top, 0, 0, $bitmap.Size)
    $bitmap.Save($filePath, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bitmap.Dispose()
}

function Get-TelegramFile {
    param($fileId, $originalFileName = $null)
    $uri = "$apiUrl/getFile?file_id=$fileId"
    try {
        $resp = Invoke-RestMethod -Uri $uri -Method Get
        if ($resp.ok) {
            $filePath = $resp.result.file_path
            $downloadUri = "https://api.telegram.org/file/bot$token/$filePath"
            $tempFolder = "$env:TEMP\ReinikeBot"
            if (-not (Test-Path $tempFolder)) { New-Item -Path $tempFolder -ItemType Directory | Out-Null }

            $fileName = if ($originalFileName) { $originalFileName } else { [System.IO.Path]::GetFileName($filePath) }
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $fileNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
            $fileExt = [System.IO.Path]::GetExtension($fileName)
            $uniqueFileName = "${fileNameWithoutExt}_${timestamp}${fileExt}"

            $localPath = Join-Path $tempFolder $uniqueFileName
            Invoke-WebRequest -Uri $downloadUri -OutFile $localPath
            Write-Host "[FILE] Downloaded: $localPath" -ForegroundColor Green
            return $localPath
        }
    }
    catch {
        Write-DailyLog -message "Error downloading Telegram file: $_" -type "ERROR"
    }
    return $null
}

function Test-DetectedFileDeliveryContext {
    param(
        [string]$Text,
        [string]$RawPath,
        [string]$ResolvedPath
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }

    $candidatePatterns = @(
        $ResolvedPath,
        $RawPath,
        [System.IO.Path]::GetFileName($ResolvedPath)
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    if ($candidatePatterns.Count -eq 0) {
        return $false
    }

    $deliveryHintPattern = '(?i)\b(saved|written|wrote|generated|created|exported|produced|downloaded|attached|attachment|upload(?:ed)?|output|report|result|summary|screenshot)\b'
    $lines = $Text.Replace("`r", "") -split "`n"
    foreach ($line in $lines) {
        foreach ($pattern in $candidatePatterns) {
            if ($line -notmatch [regex]::Escape($pattern)) {
                continue
            }

            $lineWithoutPath = [regex]::Replace($line, [regex]::Escape($pattern), ' ', 1)
            if ($lineWithoutPath -match $deliveryHintPattern) {
                return $true
            }
        }
    }

    return $false
}

function Get-ImageFilePrefix {
    param([string]$FileName)

    if ([string]::IsNullOrWhiteSpace($FileName)) { return "" }

    $name = [System.IO.Path]::GetFileNameWithoutExtension($FileName)

    # Extract prefix: everything before the last underscore followed by a number or word like "round", "step", "final"
    # Examples: "rpa_round1" -> "rpa", "rpa_final_result" -> "rpa", "screenshot_001" -> "screenshot"
    if ($name -match '^(.+?)[_-](round|step|final|result|\d+)([_-]|$)') {
        return $Matches[1].TrimEnd('_', '-')
    }

    # If no pattern matches, use the whole name as prefix
    return $name
}

function Send-DetectedFiles {
    param(
        $chatId,
        $text,
        [Nullable[datetime]]$JobStartTime = $null
    )

    if ([string]::IsNullOrWhiteSpace($text)) { return 0 }

    $sentFiles = @()
    $workDirArchives = Join-Path $workDir "archives"
    $configuredArchives = $null
    if ($script:botConfig -and $script:botConfig.Paths -and $script:botConfig.Paths.ArchivesDir) {
        $configuredArchives = $script:botConfig.Paths.ArchivesDir
    }
    $tempReinike = "$env:TEMP\ReinikeBot"
    $allowedRoots = @($configuredArchives, $workDirArchives, $tempReinike) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    $candidatePaths = New-Object System.Collections.Generic.List[string]
    $absolutePattern = '([a-zA-Z]:\\[^:<>|"?\r\n]+\.(png|jpg|jpeg|pdf|docx|txt|zip|xlsx|csv))'
    $relativePattern = '((?:\.\\|\.\/)?archives[\\/][^:<>|"?\r\n]+\.(png|jpg|jpeg|pdf|docx|txt|zip|xlsx|csv))'

    foreach ($m in [regex]::Matches($text, $absolutePattern)) {
        $candidatePaths.Add($m.Value) | Out-Null
    }
    foreach ($m in [regex]::Matches($text, $relativePattern)) {
        $candidatePaths.Add($m.Value) | Out-Null
    }

    # First pass: collect all valid candidates with their metadata
    $validCandidates = @()
    foreach ($rawPath in $candidatePaths) {
        $path = $rawPath.Trim('`', '"', "'", " ", ".")
        if (-not [System.IO.Path]::IsPathRooted($path)) {
            $normalizedRelative = $path -replace '^[.][\\/]', ''
            $path = Join-Path $workDir $normalizedRelative
        }

        if (-not (Test-Path $path)) { continue }

        try {
            $path = [System.IO.Path]::GetFullPath($path)
        }
        catch { Write-DailyLog -message "Resolve-OutputFiles: Failed to resolve path $path" -type "WARN"; continue }

        $isAllowed = $false
        foreach ($root in $allowedRoots) {
            $normalizedRoot = $root
            try {
                $normalizedRoot = [System.IO.Path]::GetFullPath($root)
            }
            catch { <# Intentionally silent - trying multiple roots #> }

            if (-not [string]::IsNullOrWhiteSpace($normalizedRoot) -and $path.StartsWith($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                $isAllowed = $true
                break
            }
        }
        if (-not $isAllowed) {
            Write-DailyLog -message "Ignored file outside allowed paths: $path" -type "JOB"
            continue
        }

        $hasExplicitDeliveryContext = Test-DetectedFileDeliveryContext -Text $text -RawPath $rawPath -ResolvedPath $path
        $isFreshFile = $false
        $fileLastWriteTime = $null
        if ($JobStartTime) {
            try {
                $fileInfo = Get-Item -LiteralPath $path -ErrorAction Stop
                $fileLastWriteTime = $fileInfo.LastWriteTime
                $freshCutoff = $JobStartTime.Value.AddSeconds(-5)
                if ($fileInfo.LastWriteTime -ge $freshCutoff) {
                    $isFreshFile = $true
                }
            }
            catch { <# File may have been deleted - not critical #> }
        }

        if (-not $hasExplicitDeliveryContext -and -not $isFreshFile) {
            Write-DailyLog -message "Ignored referenced file without generation context: $path" -type "JOB"
            continue
        }

        if ($path -match '\.txt$' -and $path -notmatch 'report|result|final|summary') {
            Write-DailyLog -message "Ignored .txt file (likely internal log): $path" -type "JOB"
            continue
        }

        $isImage = $path -match '\.(png|jpg|jpeg)$'
        $prefix = if ($isImage) { Get-ImageFilePrefix -FileName ([System.IO.Path]::GetFileName($path)) } else { "" }

        $validCandidates += [PSCustomObject]@{
            Path = $path
            IsImage = $isImage
            Prefix = $prefix
            LastWriteTime = $fileLastWriteTime
        }
    }

    # Group images by prefix and select only the most recent from each group
    $imageGroups = @{}
    $nonImageFiles = @()
    foreach ($candidate in $validCandidates) {
        if ($candidate.IsImage -and -not [string]::IsNullOrWhiteSpace($candidate.Prefix)) {
            if (-not $imageGroups.ContainsKey($candidate.Prefix)) {
                $imageGroups[$candidate.Prefix] = @()
            }
            $imageGroups[$candidate.Prefix] += $candidate
        }
        elseif ($candidate.IsImage) {
            # Image without a recognizable prefix pattern - send it directly
            $nonImageFiles += $candidate
        }
        else {
            $nonImageFiles += $candidate
        }
    }

    # For each image group, select only the most recent file
    $filesToSend = @()
    foreach ($prefix in $imageGroups.Keys) {
        $group = $imageGroups[$prefix]
        if ($group.Count -eq 1) {
            $filesToSend += $group[0]
        }
        else {
            # Sort by LastWriteTime descending and take the most recent
            $sorted = @($group | Where-Object { $null -ne $_.LastWriteTime } | Sort-Object -Property LastWriteTime -Descending)
            if ($sorted.Count -gt 0) {
                $mostRecent = $sorted[0]
                # Log which files were skipped
                foreach ($skipped in @($group | Where-Object { $_.Path -ne $mostRecent.Path })) {
                    Write-DailyLog -message "Skipped intermediate image (same prefix '$prefix'): $($skipped.Path)" -type "JOB"
                }
                $filesToSend += $mostRecent
            }
            else {
                # No LastWriteTime available, take the first one
                $filesToSend += $group[0]
            }
        }
    }
    $filesToSend += $nonImageFiles

    # Send the selected files
    foreach ($fileToSend in $filesToSend) {
        $path = $fileToSend.Path
        if ($sentFiles -contains $path) { continue }

        Write-DailyLog -message "Detected file for delivery: $path" -type "JOB"
        if ($fileToSend.IsImage) {
            Send-TelegramPhoto -chatId $chatId -filePath $path
        }
        else {
            Send-TelegramDocument -chatId $chatId -filePath $path -caption "Generated file: $([System.IO.Path]::GetFileName($path))"
        }
        $sentFiles += $path
    }

    return $sentFiles.Count
}

function Run-PCAction {
    param($actionStr, $chatId = $null)
    $actionStr = $actionStr.Trim()

    $statusMsgId = $null
    if ($chatId) {
        $emojiHourglass = [char]::ConvertFromUtf32(0x23F3)
        $msg = Send-TelegramText -chatId $chatId -text "$emojiHourglass PC CMD: Running command, please wait..."
        if ($msg -and $msg.result) { $statusMsgId = $msg.result.message_id }
    }

    Write-DailyLog -message "Ejecutando PC CMD: $actionStr" -type "CMD"
    Write-Host "[PC CMD] $actionStr" -ForegroundColor DarkYellow
    if ($actionStr -eq "[SCREENSHOT]") {
        $tempFolder = "$env:TEMP\ReinikeBot"
        if (-not (Test-Path $tempFolder)) { New-Item -Path $tempFolder -ItemType Directory | Out-Null }
        $out = Join-Path $tempFolder "ss.png"
        Take-Screenshot -filePath $out
        if ($statusMsgId) { Edit-TelegramText -chatId $chatId -messageId $statusMsgId -text "✅ Screenshot taken successfully." }
        return "Screenshot saved to $out"
    }
    else {
        try {
            $sb = [scriptblock]::Create($actionStr)
            $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($sb.ToString()))

            $processInfo = New-Object System.Diagnostics.ProcessStartInfo
            $processInfo.FileName = "powershell.exe"
            $processInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encodedCommand"
            $processInfo.RedirectStandardOutput = $true
            $processInfo.RedirectStandardError = $true
            $processInfo.UseShellExecute = $false
            $processInfo.CreateNoWindow = $true

            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $processInfo
            $stdoutBuilder = New-Object System.Text.StringBuilder
            $stderrBuilder = New-Object System.Text.StringBuilder
            $stdoutEvent = $null
            $stderrEvent = $null

            $appendOutput = {
                param($builder, $eventArgs)
                if ($null -ne $eventArgs.Data) {
                    [void]$builder.AppendLine($eventArgs.Data)
                }
            }

            $stdoutEvent = Register-ObjectEvent -InputObject $process -EventName OutputDataReceived -Action {
                & $Event.MessageData.Callback $Event.MessageData.Builder $Event.SourceEventArgs
            } -MessageData @{
                Builder = $stdoutBuilder
                Callback = $appendOutput
            }
            $stderrEvent = Register-ObjectEvent -InputObject $process -EventName ErrorDataReceived -Action {
                & $Event.MessageData.Callback $Event.MessageData.Builder $Event.SourceEventArgs
            } -MessageData @{
                Builder = $stderrBuilder
                Callback = $appendOutput
            }

            $startTime = Get-Date
            $process.Start() | Out-Null
            $trackedPid = [int]$process.Id
            Add-ActiveProcess @{
                Pid = $trackedPid
                Kind = "PC_CMD"
                Command = $actionStr
                ChatId = $chatId
                CreatedAt = Get-Date
            }
            $process.BeginOutputReadLine()
            $process.BeginErrorReadLine()
            $exited = $process.WaitForExit(300000)
            $elapsed = ((Get-Date) - $startTime).TotalSeconds

            if ($exited) {
                $process.WaitForExit()
                $res = $stdoutBuilder.ToString() + $stderrBuilder.ToString()
                Remove-ActiveProcessByPid -Pid $trackedPid

                Write-DailyLog -message "Command finished in $($elapsed.ToString('F2'))s. Output length: $($res.Length)" -type "CMD"
                if ($statusMsgId) { Edit-TelegramText -chatId $chatId -messageId $statusMsgId -text "✅ Command finished in $($elapsed.ToString('F2'))s." }
                if ([string]::IsNullOrWhiteSpace($res)) { return "OK" }
                return $res
            }
            else {
                try {
                    Start-Process -FilePath "cmd.exe" -ArgumentList "/c taskkill /PID $trackedPid /T /F" -WindowStyle Hidden -Wait | Out-Null
                }
                catch {
                    try { $process.Kill() } catch { <# Process may already be terminated #> }
                }
                Remove-ActiveProcessByPid -Pid $trackedPid
                Write-DailyLog -message "Command timed out after 300s. Command: $actionStr" -type "WARN"
                if ($statusMsgId) { Edit-TelegramText -chatId $chatId -messageId $statusMsgId -text "❌ Timeout: Command exceeded 300 seconds." }
                return "Timeout: the command exceeded 300 seconds"
            }
        }
        catch {
            Write-DailyLog -message "Error running command: $_" -type "ERROR"
            if ($statusMsgId) { Edit-TelegramText -chatId $chatId -messageId $statusMsgId -text "❌ Error: $_" }
            return "Execution error: $_"
        }
        finally {
            foreach ($eventRef in @($stdoutEvent, $stderrEvent)) {
                if ($null -eq $eventRef) {
                    continue
                }

                try { Unregister-Event -SourceIdentifier $eventRef.Name -ErrorAction SilentlyContinue } catch { <# Event may not exist #> }
                try { Remove-Job -Id $eventRef.Id -Force -ErrorAction SilentlyContinue } catch { <# Job may not exist #> }
            }

            if ($null -ne $process) {
                try {
                    if (-not $process.HasExited) {
                        try { $process.CancelOutputRead() } catch { <# Stream may already be closed #> }
                        try { $process.CancelErrorRead() } catch { <# Stream may already be closed #> }
                    }
                }
                catch { <# Process cleanup - not critical #> }

                try { $process.Dispose() } catch { <# Process already disposed #> }
            }
        }
    }
}

function Stop-TrackedPCCommands {
    param(
        [string]$Reason = "manual stop"
    )

    $stoppedPids = @()
    foreach ($procRecord in @(Get-ActiveProcesses | Where-Object { $_.Kind -eq "PC_CMD" })) {
        $targetPid = 0
        try { $targetPid = [int]$procRecord.Pid } catch { $targetPid = 0 }
        if ($targetPid -le 0) {
            continue
        }

        try {
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c taskkill /PID $targetPid /T /F" -WindowStyle Hidden -Wait | Out-Null
            $stoppedPids += $targetPid
        }
        catch {
            try {
                Stop-Process -Id $targetPid -Force -ErrorAction SilentlyContinue
                $stoppedPids += $targetPid
            }
            catch { <# Process may already be terminated #> }
        }
        finally {
            Remove-ActiveProcessByPid -Pid $targetPid
        }
    }

    try {
        Write-DailyLog -message "Stop-TrackedPCCommands reason='$Reason' stopped_pids=$(@($stoppedPids | Select-Object -Unique).Count)" -type "SYSTEM"
    }
    catch { Write-Host "Stop-TrackedPCCommands: Failed to log" }

    return [PSCustomObject]@{
        Reason = $Reason
        ProcessesStopped = @($stoppedPids | Select-Object -Unique).Count
    }
}

function Stop-ActiveLocalJobs {
    param(
        [string]$Reason = "manual stop"
    )

    $stoppedJobIds = @()
    foreach ($jobRecord in @(Get-ActiveJobs | Where-Object { $_.Type -ne "OpenCode" })) {
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
        try { Write-JobsFile } catch { Write-DailyLog -message "Stop-ActiveLocalJobs: Failed to write jobs file" -type "WARN" }
    }

    try {
        Write-DailyLog -message "Stop-ActiveLocalJobs reason='$Reason' stopped_jobs=$(@($stoppedJobIds | Select-Object -Unique).Count)" -type "SYSTEM"
    }
    catch { Write-Host "Stop-ActiveLocalJobs: Failed to log" }

    return [PSCustomObject]@{
        Reason = $Reason
        JobsStopped = @($stoppedJobIds | Select-Object -Unique).Count
    }
}

function Stop-UntrackedAutomationProcesses {
    param(
        [string]$Reason = "manual stop"
    )

    $patterns = @(
        '\bopencode\b',
        'OpenCode'
    )

    $stopped = @()
    foreach ($proc in @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)) {
        $cmd = "$($proc.CommandLine)"
        $name = "$($proc.Name)"
        if ([string]::IsNullOrWhiteSpace($cmd) -and [string]::IsNullOrWhiteSpace($name)) {
            continue
        }

        $matchesPattern = $false
        foreach ($pattern in $patterns) {
            if ($name -match $pattern -or $cmd -match $pattern) {
                $matchesPattern = $true
                break
            }
        }

        if (-not $matchesPattern) {
            continue
        }

        $targetPid = 0
        try { $targetPid = [int]$proc.ProcessId } catch { $targetPid = 0 }
        if ($targetPid -le 0) {
            continue
        }

        try {
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c taskkill /PID $targetPid /T /F" -WindowStyle Hidden -Wait | Out-Null
            $stopped += [PSCustomObject]@{ Pid = $targetPid; Name = $name }
        }
        catch { Write-DailyLog -message "Stop-UntrackedAutomationProcesses: Failed to kill process $targetPid ($name)" -type "WARN" }
    }

    try {
        Write-DailyLog -message "Stop-UntrackedAutomationProcesses reason='$Reason' stopped=$(@($stopped).Count)" -type "SYSTEM"
    }
    catch { Write-Host "Stop-UntrackedAutomationProcesses: Failed to log" }

    return [PSCustomObject]@{
        Reason = $Reason
        ProcessesStopped = @($stopped).Count
        Processes = @($stopped)
    }
}

function Stop-AllAutomationProcesses {
    param(
        [object]$BotConfig,
        [string]$Reason = "manual stop",
        [switch]$StopActiveJobs
    )

    $localJobsSummary = Stop-ActiveLocalJobs -Reason $Reason
    $trackedSummary = Stop-TrackedPCCommands -Reason $Reason
    $openCodeSummary = Stop-OpenCodeServer -BotConfig $BotConfig -Reason $Reason -StopActiveJobs:$StopActiveJobs
    $untrackedSummary = Stop-UntrackedAutomationProcesses -Reason $Reason

    return [PSCustomObject]@{
        Reason = $Reason
        LocalJobsStopped = $localJobsSummary.JobsStopped
        TrackedCommandsStopped = $trackedSummary.ProcessesStopped
        OpenCodeJobsStopped = $openCodeSummary.JobsStopped
        OpenCodeProcessesStopped = $openCodeSummary.ProcessesStopped
        RemainingOpenCodeProcesses = $openCodeSummary.RemainingProcesses
        UntrackedProcessesStopped = $untrackedSummary.ProcessesStopped
        UntrackedProcesses = $untrackedSummary.Processes
    }
}
