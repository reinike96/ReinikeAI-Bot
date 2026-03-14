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

function Send-DetectedFiles {
    param($chatId, $text)
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

    foreach ($rawPath in $candidatePaths) {
        $path = $rawPath.Trim('`', '"', "'", " ", ".")
        if (-not [System.IO.Path]::IsPathRooted($path)) {
            $normalizedRelative = $path -replace '^[.][\\/]', ''
            $path = Join-Path $workDir $normalizedRelative
        }

        if (Test-Path $path) {
            try {
                $path = [System.IO.Path]::GetFullPath($path)
            }
            catch {}
            if ($sentFiles -contains $path) { continue }

            $isAllowed = $false
            foreach ($root in $allowedRoots) {
                $normalizedRoot = $root
                try {
                    $normalizedRoot = [System.IO.Path]::GetFullPath($root)
                }
                catch {}

                if (-not [string]::IsNullOrWhiteSpace($normalizedRoot) -and $path.StartsWith($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $isAllowed = $true
                    break
                }
            }
            if (-not $isAllowed) {
                Write-DailyLog -message "Ignored file outside allowed paths: $path" -type "JOB"
                continue
            }
            if ($path -match '\.txt$' -and $path -notmatch 'report|result|final|summary') {
                Write-DailyLog -message "Ignored .txt file (likely internal log): $path" -type "JOB"
                continue
            }

            Write-DailyLog -message "Detected file for delivery: $path" -type "JOB"
            if ($path -match '\.(png|jpg|jpeg)$') {
                Send-TelegramPhoto -chatId $chatId -filePath $path
            }
            else {
                Send-TelegramDocument -chatId $chatId -filePath $path -caption "Generated file: $([System.IO.Path]::GetFileName($path))"
            }
            $sentFiles += $path
        }
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

            $startTime = Get-Date
            $process.Start() | Out-Null
            $exited = $process.WaitForExit(300000)
            $elapsed = ((Get-Date) - $startTime).TotalSeconds

            if ($exited) {
                $stdout = $process.StandardOutput.ReadToEnd()
                $stderr = $process.StandardError.ReadToEnd()
                $res = $stdout + $stderr
                $process.Dispose()

                Write-DailyLog -message "Command finished in $($elapsed.ToString('F2'))s. Output length: $($res.Length)" -type "CMD"
                if ($statusMsgId) { Edit-TelegramText -chatId $chatId -messageId $statusMsgId -text "✅ Command finished in $($elapsed.ToString('F2'))s." }
                if ([string]::IsNullOrWhiteSpace($res)) { return "OK" }
                return $res
            }
            else {
                $process.Kill()
                $process.Dispose()
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
    }
}
