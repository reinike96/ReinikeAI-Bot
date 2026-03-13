function Protect-TelegramMarkdown {
    param([string]$text)
    if ([string]::IsNullOrWhiteSpace($text)) { return "" }
    return $text -replace '_', '\_' -replace '\*', '\*' -replace '\[', '\[' -replace '`', '\`'
}

function Send-TelegramPhoto {
    param($chatId, $filePath)
    $uri = "$apiUrl/sendPhoto"
    if (-not (Test-Path $filePath) -or (Get-Item $filePath).Length -eq 0) { return }
    $fileBytes = [System.IO.File]::ReadAllBytes($filePath)
    $fileName = [System.IO.Path]::GetFileName($filePath)

    $httpClient = New-Object System.Net.Http.HttpClient
    $boundary = [System.Guid]::NewGuid().ToString()
    $content = New-Object System.Net.Http.MultipartFormDataContent($boundary)
    $content.Add((New-Object System.Net.Http.StringContent($chatId)), "chat_id")

    $fileContent = New-Object System.Net.Http.ByteArrayContent -ArgumentList @(, $fileBytes)
    $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("image/png")
    $content.Add($fileContent, "photo", $fileName)

    try {
        $postTask = $httpClient.PostAsync($uri, $content)
        $postTask.Wait()
        $postTask.Result.Dispose()
    }
    catch {}
    $httpClient.Dispose()
}

function Send-TelegramDocument {
    param($chatId, $filePath, $caption = "")
    $uri = "$apiUrl/sendDocument"
    if (-not (Test-Path $filePath) -or (Get-Item $filePath).Length -eq 0) { return }
    $fileBytes = [System.IO.File]::ReadAllBytes($filePath)
    $fileName = [System.IO.Path]::GetFileName($filePath)

    $httpClient = New-Object System.Net.Http.HttpClient
    $boundary = [System.Guid]::NewGuid().ToString()
    $content = New-Object System.Net.Http.MultipartFormDataContent($boundary)
    $content.Add((New-Object System.Net.Http.StringContent($chatId)), "chat_id")
    if ($caption) { $content.Add((New-Object System.Net.Http.StringContent($caption)), "caption") }

    $fileContent = New-Object System.Net.Http.ByteArrayContent -ArgumentList @(, $fileBytes)
    $mimeType = switch -Regex ($fileName) {
        '\.pdf$' { "application/pdf" }
        '\.docx?$' { "application/msword" }
        '\.xlsx?$' { "application/vnd.ms-excel" }
        '\.png$' { "image/png" }
        '\.jpe?g$' { "image/jpeg" }
        default { "application/octet-stream" }
    }
    $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse($mimeType)
    $content.Add($fileContent, "document", $fileName)

    try {
        $postTask = $httpClient.PostAsync($uri, $content)
        $postTask.Wait()
        $postTask.Result.Dispose()
    }
    catch {}
    $httpClient.Dispose()
}

function Send-TelegramText {
    param($chatId, $text, $buttons = $null)
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }

    $maxLen = 4000
    $parts = @()
    if ($text.Length -gt $maxLen) {
        $remaining = $text
        while ($remaining.Length -gt $maxLen) {
            $splitPos = $remaining.LastIndexOf("`n", $maxLen)
            if ($splitPos -lt 1000) { $splitPos = $maxLen }
            $parts += $remaining.Substring(0, $splitPos)
            $remaining = $remaining.Substring($splitPos).Trim()
        }
        $parts += $remaining
    }
    else {
        $parts = @($text)
    }

    $lastResponse = $null
    $totalParts = $parts.Count
    for ($i = 0; $i -lt $totalParts; $i++) {
        $p = $parts[$i]
        $payload = @{ chat_id = $chatId; text = $p.Trim(); parse_mode = "Markdown" }

        if ($buttons -and ($i -eq $totalParts - 1)) {
            $inlineKeyboard = @()
            foreach ($btn in $buttons) {
                $btnText = if ($btn.Text) { $btn.Text } else { $btn.text }
                $btnData = if ($btn.CallbackData) { $btn.CallbackData } else { $btn.callback_data }
                $inlineKeyboard += , @(@{ text = $btnText; callback_data = $btnData })
            }
            $payload["reply_markup"] = @{ inline_keyboard = $inlineKeyboard }
        }

        $jsonPayload = $payload | ConvertTo-Json -Depth 10 -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonPayload)
        try {
            $lastResponse = Invoke-RestMethod -Uri "$apiUrl/sendMessage" -Method Post -ContentType "application/json; charset=utf-8" -Body $bytes -ErrorAction Stop
        }
        catch {
            Write-DailyLog -message "Fallo Markdown en mensaje. Reintentando con escape..." -type "WARN"
            $payload["text"] = Protect-TelegramMarkdown -text $p.Trim()
            $jsonPayload = $payload | ConvertTo-Json -Depth 10 -Compress
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonPayload)
            $lastResponse = Invoke-RestMethod -Uri "$apiUrl/sendMessage" -Method Post -ContentType "application/json; charset=utf-8" -Body $bytes -ErrorAction SilentlyContinue
        }
        Start-Sleep -Milliseconds 200
    }
    return $lastResponse
}

function Edit-TelegramText {
    param($chatId, $messageId, $text)
    if ([string]::IsNullOrWhiteSpace($text) -or -not $messageId) { return $null }

    $payload = @{
        chat_id    = $chatId
        message_id = $messageId
        text       = $text.Trim()
        parse_mode = "Markdown"
    }

    $jsonPayload = $payload | ConvertTo-Json -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonPayload)
    try {
        return Invoke-RestMethod -Uri "$apiUrl/editMessageText" -Method Post -ContentType "application/json; charset=utf-8" -Body $bytes -ErrorAction Stop
    }
    catch {
        if ($_.Exception.Message -match "message is not modified") {
            return @{ ok = $true }
        }

        $payload.Remove("parse_mode")
        $jsonPayload = $payload | ConvertTo-Json -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonPayload)
        try {
            return Invoke-RestMethod -Uri "$apiUrl/editMessageText" -Method Post -ContentType "application/json; charset=utf-8" -Body $bytes -ErrorAction SilentlyContinue
        }
        catch { return $null }
    }
}

function Update-TelegramStatus {
    param($job, $text)
    if ($job.LastStatusId) {
        $edit = Edit-TelegramText -chatId $job.ChatId -messageId $job.LastStatusId -text $text
        if ($edit -and $edit.ok) { return $job.LastStatusId }
    }

    $newMsg = Send-TelegramText -chatId $job.ChatId -text $text
    if ($newMsg -and $newMsg.ok) {
        $job.LastStatusId = $newMsg.result.message_id
        return $job.LastStatusId
    }
    return $null
}

function Answer-TelegramCallback {
    param($callbackQueryId, $text = $null)
    $payload = @{ callback_query_id = $callbackQueryId }
    if ($text) { $payload.text = $text }
    $jsonPayload = $payload | ConvertTo-Json -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonPayload)
    try {
        Invoke-RestMethod -Uri "$apiUrl/answerCallbackQuery" -Method Post -ContentType "application/json; charset=utf-8" -Body $bytes -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
        Write-DailyLog -message "Error respondiendo callback: $_" -type "WARN"
    }
}

function Set-TelegramCommands {
    $commands = @(
        @{ command = "start"; description = "Start the bot and view help" },
        @{ command = "new"; description = "Clear conversation memory" },
        @{ command = "status"; description = "Show active tasks" },
        @{ command = "doctor"; description = "Run a local diagnostics check" },
        @{ command = "screenshot"; description = "Take an instant screenshot" },
        @{ command = "restart"; description = "Restart the bot" },
        @{ command = "thinking"; description = "Change reasoning level (example: /thinking high)" }
    )

    $payload = @{ commands = $commands }
    $jsonPayload = $payload | ConvertTo-Json -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonPayload)

    try {
        $resp = Invoke-RestMethod -Uri "$apiUrl/setMyCommands" -Method Post -ContentType "application/json; charset=utf-8" -Body $bytes -ErrorAction Stop
        if ($resp.ok) {
            Write-DailyLog -message "Telegram commands registered successfully." -type "SYSTEM"
        }
    }
    catch {
        Write-DailyLog -message "Error registering Telegram commands: $_" -type "ERROR"
    }
}

function Send-TelegramButtons {
    param([string]$chatId, [string]$text, [string]$buttonsJson)
    try {
        $cleanJson = $buttonsJson.Trim()
        if (-not $cleanJson.EndsWith("]")) { $cleanJson += "]" }
        if (-not $cleanJson.StartsWith("[")) { $cleanJson = "[" + $cleanJson }

        $btnArr = $cleanJson | ConvertFrom-Json
        Send-TelegramText -chatId $chatId -text $text -buttons $btnArr
    }
    catch {
        Write-DailyLog -message "Error in Send-TelegramButtons: $_`nRaw: $buttonsJson" -type "ERROR"
        Send-TelegramText -chatId $chatId -text $text
    }
}

function Send-TelegramTyping {
    param($chatId)
    $payload = @{ chat_id = $chatId; action = "typing" }
    $jsonPayload = $payload | ConvertTo-Json -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonPayload)
    try { Invoke-RestMethod -Uri "$apiUrl/sendChatAction" -Method Post -ContentType "application/json; charset=utf-8" -Body $bytes -ErrorAction SilentlyContinue | Out-Null } catch {}
}
