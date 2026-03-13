function Convert-TelegramDocumentToContext {
    param(
        [object]$Message
    )

    $document = $Message.document
    if ($null -eq $document) {
        return $null
    }

    $fileName = $document.file_name
    $fileId = $document.file_id
    $mimeType = $document.mime_type
    Write-Host "USER sent document: $fileName ($mimeType)" -ForegroundColor Yellow
    Write-DailyLog -message "Document received: $fileName ($mimeType)" -type "INFO"

    $localPath = Get-TelegramFile -fileId $fileId -originalFileName $fileName
    if ($null -eq $localPath) {
        Write-DailyLog -message "Could not download document: $fileName" -type "ERROR"
        return "The user sent a file ($fileName), but it could not be downloaded."
    }

    $extractedText = ""
    $caption = if (-not [string]::IsNullOrWhiteSpace($Message.caption)) { $Message.caption } else { "" }

    if ($mimeType -eq "text/plain" -or $fileName -match "\.txt$") {
        try {
            $extractedText = Get-Content $localPath -Raw -Encoding UTF8 -ErrorAction Stop
        }
        catch {
            $extractedText = Get-Content $localPath -Raw -ErrorAction SilentlyContinue
        }
    }
    elseif ($mimeType -eq "application/pdf" -or $fileName -match "\.pdf$") {
        try {
            $pdfTxt = & pdftotext $localPath - 2>$null
            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($pdfTxt)) {
                $extractedText = $pdfTxt | Out-String
            }
        }
        catch {}

        if ([string]::IsNullOrWhiteSpace($extractedText)) {
            try {
                $bytes = [System.IO.File]::ReadAllBytes($localPath)
                $pdfStr = [System.Text.Encoding]::Latin1.GetString($bytes)
                $textMatches = [regex]::Matches($pdfStr, '\(([^\)]{3,200})\)')
                $lines = $textMatches | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -match '[a-zA-Z]{3,}' }
                if ($lines.Count -gt 0) {
                    $extractedText = "[Basic PDF extraction]`n" + ($lines -join " ")
                }
            }
            catch {}
        }

        if ([string]::IsNullOrWhiteSpace($extractedText)) {
            $extractedText = "[PDF saved, but text extraction failed. Path: $localPath]"
        }
    }
    elseif ($mimeType -match "wordprocessingml|msword" -or $fileName -match "\.docx?$") {
        try {
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
            $zip = [System.IO.Compression.ZipFile]::OpenRead($localPath)
            $wordEntry = $zip.Entries | Where-Object { $_.FullName -eq "word/document.xml" } | Select-Object -First 1
            if ($null -ne $wordEntry) {
                $stream = $wordEntry.Open()
                $reader = New-Object System.IO.StreamReader($stream)
                $xmlContent = $reader.ReadToEnd()
                $reader.Dispose()
                $stream.Dispose()
                $extractedText = [regex]::Replace($xmlContent, '<[^>]+>', ' ')
                $extractedText = [regex]::Replace($extractedText, '\s{2,}', ' ').Trim()
            }
            $zip.Dispose()
        }
        catch {
            $extractedText = "[DOCX saved, but text extraction failed. Path: $localPath]"
        }
    }
    else {
        $extractedText = "[File received. Type: $mimeType. Path: $localPath]"
    }

    if ($extractedText.Length -gt 6000) {
        $extractedText = $extractedText.Substring(0, 6000) + "`n`n[...truncated. Full file at: $localPath]"
    }

    $docContext = "File received: $fileName | Local path: $localPath"
    if ($caption) { $docContext += " | Description: $caption" }
    $docContext += "`n`nContent:`n$extractedText"

    Write-Host "[DOC] Extracted $($extractedText.Length) chars from $fileName" -ForegroundColor Cyan
    Write-DailyLog -message "Document processed: $fileName -> $($extractedText.Length) chars" -type "INFO"
    return $docContext
}

function Invoke-TelegramCallbackRoute {
    param(
        [object]$CallbackQuery,
        [string]$ApiUrl,
        [int]$Offset
    )

    $chatId = $CallbackQuery.message.chat.id
    $callbackData = $CallbackQuery.data
    $callbackId = $CallbackQuery.id

    Write-Host "CALLBACK: User clicked button with data: $callbackData" -ForegroundColor Yellow
    Write-DailyLog -message "Callback received: $callbackData from ChatId: $chatId" -type "INFO"

    Answer-TelegramCallback -callbackQueryId $callbackId

    if ($callbackData -match '^confirm_cmd:(.+)$') {
        $confirmationId = $Matches[1]
        $pending = Remove-PendingConfirmation -ConfirmationId $confirmationId
        if ($null -ne $pending) {

            Send-TelegramText -chatId $chatId -text "Running approved command:`n``$($pending.Command)``"
            $cmdResult = Run-PCAction -actionStr $pending.Command -chatId $chatId
            Add-ChatMemory -chatId $chatId -role "user" -content "[SYSTEM - APPROVED CMD RESULT]:`n$cmdResult`n`nAnalyze the result above and reply to the user."
            Add-PendingChat -ChatId $chatId
        }
        else {
            Send-TelegramText -chatId $chatId -text "That confirmation request expired or was already used."
        }
        return
    }

    if ($callbackData -match '^cancel_cmd:(.+)$') {
        $confirmationId = $Matches[1]
        $pending = Remove-PendingConfirmation -ConfirmationId $confirmationId
        if ($null -ne $pending) {
            Add-ChatMemory -chatId $chatId -role "user" -content "[SYSTEM]: The user cancelled a pending sensitive command: $($pending.Command)"
        }
        Send-TelegramText -chatId $chatId -text "Sensitive command cancelled."
        return
    }

    if ($callbackData -eq "restart_confirm") {
        Send-TelegramText -chatId $chatId -text "Restarting the full system. Please wait a few seconds..."
        Write-DailyLog -message "/restart confirmed from button. Exiting so RunBot.bat can restart the process." -type "SYSTEM"
        Invoke-RestMethod -Uri "$ApiUrl/getUpdates?offset=$Offset&limit=1" -Method Get -ErrorAction SilentlyContinue | Out-Null
        exit 0
    }

    if ($callbackData -eq "restart_cancel") {
        Send-TelegramText -chatId $chatId -text "Restart cancelled."
        return
    }

    Add-ChatMemory -chatId $chatId -role "user" -content "[BUTTON PRESSED: $callbackData]"
    Add-PendingChat -ChatId $chatId
}

function Invoke-TelegramMessageRoute {
    param(
        [object]$Message,
        [object]$BotConfig,
        [string]$ApiUrl,
        [string]$Token,
        [string]$OpenRouterKey,
        [string]$WorkDir
    )

    $chatId = $Message.chat.id
    $text = $Message.text
    $photo = $Message.photo

    if ($null -ne $photo) {
        $fileId = $photo[-1].file_id
        $localPath = Get-TelegramFile -fileId $fileId
        if ($null -ne $localPath) {
            $userCaption = if (-not [string]::IsNullOrWhiteSpace($Message.caption)) { $Message.caption } else { "Analyze this image." }
            $base64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($localPath))
            $content = @(
                @{ type = "text"; text = $userCaption },
                @{ type = "image_url"; image_url = @{ url = "data:image/jpeg;base64,$base64" } }
            )
            Add-ChatMemory -chatId $chatId -role "user" -content $content
            Add-PendingChat -ChatId $chatId
            Write-Host "[MULTIMODAL] Image attached directly to the orchestrator." -ForegroundColor Cyan
        }
    }

    $voice = $Message.voice
    $audio = $Message.audio
    if ($null -ne $voice -or $null -ne $audio) {
        $fileItem = if ($null -ne $voice) { $voice } else { $audio }
        $localPath = Get-TelegramFile -fileId $fileItem.file_id
        if ($null -ne $localPath) {
            $userCaption = if (-not [string]::IsNullOrWhiteSpace($Message.caption)) { $Message.caption } else { "Listen to this audio." }
            $base64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($localPath))
            $ext = [System.IO.Path]::GetExtension($localPath).Trim('.').ToLower()
            if ($ext -eq "oga" -or $ext -eq "opus") { $ext = "ogg" }

            $content = @(
                @{ type = "text"; text = $userCaption },
                @{
                    type = "input_audio"
                    input_audio = @{ data = $base64; format = $ext }
                }
            )
            Add-ChatMemory -chatId $chatId -role "user" -content $content
            Add-PendingChat -ChatId $chatId
            Write-Host "[MULTIMODAL] Audio attached directly to the orchestrator." -ForegroundColor Cyan
        }
    }

    if ($null -ne $Message.document) {
        $text = Convert-TelegramDocumentToContext -Message $Message
    }

    if ($null -eq $text) {
        return
    }

    Write-Host "USER: $text" -ForegroundColor Yellow

    if ($text -eq "/new") {
        Clear-ChatMemory -chatId $chatId
        Send-TelegramText -chatId $chatId -text "Conversation memory cleared."
        return
    }

    if ($text -match "^/(thinking)\s+(low|medium|high|none)$") {
        Set-CurrentReasoningEffort -Value $matches[2].ToLower()
        Send-TelegramText -chatId $chatId -text "Reasoning effort changed to: $(Get-CurrentReasoningEffort)"
        return
    }

    if ($text -eq "/help" -or $text -eq "/start") {
        $helpMsg = "*Bot Commands:*`n`n"
        $helpMsg += "*/new* - Clear conversation memory.`n"
        $helpMsg += "*/doctor* - Run local diagnostics.`n"
        $helpMsg += "*/restart* - Restart the bot and its connections.`n"
        $helpMsg += "*/thinking [low|none]* - Change reasoning effort.`n`n"
        $helpMsg += "*Orchestrator Capabilities:*`n"
        $helpMsg += "- Run PowerShell commands with [CMD: ...].`n"
        $helpMsg += "- Take screenshots with [SCREENSHOT].`n"
        $helpMsg += "- Delegate complex browser work to OpenCode.`n`n"
        $helpMsg += "- Require approval before dangerous local commands.`n`n"
        $helpMsg += "*Installed Skills:*`n"
        $helpMsg += "- *OpenCode*: AI session and coding task management.`n"
        $helpMsg += "- *Outlook*: email handling.`n`n"
        $helpMsg += "_You can ask for complex tasks and the orchestrator will choose the right tool._"
        Send-TelegramText -chatId $chatId -text $helpMsg
        return
    }

    if ($text -eq "/status") {
        $statusMsg = Get-SystemStatusReport -WorkDir $WorkDir
        Send-TelegramText -chatId $chatId -text $statusMsg
        return
    }

    if ($text -eq "/doctor" -or $text -eq "/diag") {
        $doctorReport = Invoke-SystemDoctor -BotConfig $BotConfig -ApiUrl $ApiUrl -Token $Token -OpenRouterKey $OpenRouterKey -WorkDir $WorkDir
        Send-TelegramText -chatId $chatId -text $doctorReport
        return
    }

    if ($text -eq "/restart") {
        $restartButtons = @(
            [PSCustomObject]@{ text = "Restart"; callback_data = "restart_confirm" },
            [PSCustomObject]@{ text = "Cancel"; callback_data = "restart_cancel" }
        )
        Send-TelegramText -chatId $chatId -text "Confirm full bot restart?" -buttons $restartButtons
        return
    }

    Reset-LastExecutedTags
    Add-ChatMemory -chatId $chatId -role "user" -content $text
    Add-PendingChat -ChatId $chatId
}

function Invoke-TelegramUpdateRouter {
    param(
        [object]$UpdatesResponse,
        [int]$CurrentOffset,
        [object]$BotConfig,
        [string]$ApiUrl,
        [string]$Token,
        [string]$OpenRouterKey,
        [string]$WorkDir
    )

    $offset = $CurrentOffset
    foreach ($update in $UpdatesResponse.result) {
        $offset = $update.update_id + 1

        if ($null -ne $update.callback_query) {
            Invoke-TelegramCallbackRoute -CallbackQuery $update.callback_query -ApiUrl $ApiUrl -Offset $offset
            continue
        }

        if ($null -ne $update.message) {
            Invoke-TelegramMessageRoute -Message $update.message -BotConfig $BotConfig -ApiUrl $ApiUrl -Token $Token -OpenRouterKey $OpenRouterKey -WorkDir $WorkDir
        }
    }

    return $offset
}
