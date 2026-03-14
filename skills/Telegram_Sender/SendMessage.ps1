param(
    [Parameter(Mandatory=$true)]
    [string]$Message,
    [switch]$Caption = $false,
    [string]$ChatId = "",
    [object[]]$Buttons = $null
)

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
. (Join-Path $projectRoot "config\Load-BotConfig.ps1")
$botConfig = Import-BotSettings -ProjectRoot $projectRoot

$token = $botConfig.Telegram.BotToken
$ChatId = if ([string]::IsNullOrWhiteSpace($ChatId)) { $botConfig.Telegram.DefaultChatId } else { $ChatId }
$apiUrl = "https://api.telegram.org/bot$token"

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

function Send-TelegramText {
    param($chatId, $text, $buttons = $null)
    if ([string]::IsNullOrWhiteSpace($text)) { return }
    
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

    foreach ($p in $parts) {
        $payload = @{ chat_id = $chatId; text = $p.Trim(); parse_mode = "Markdown" }
        
        if ($buttons) {
            $inlineKeyboard = @()
            
            if ($buttons -is [string]) {
                $buttonNames = $buttons -split ','
                $currentRow = @()
                foreach ($name in $buttonNames) {
                    $cleanName = $name.Trim()
                    if (-not [string]::IsNullOrWhiteSpace($cleanName)) {
                        $currentRow += [PSCustomObject]@{ text = [string]$cleanName; callback_data = [string]$cleanName }
                    }
                }
                if ($currentRow.Count -gt 0) {
                    $inlineKeyboard += ,@($currentRow)
                }
            }
            else {
                foreach ($btn in $buttons) {
                    $row = @(
                        [PSCustomObject]@{ text = [string]$btn.Text; callback_data = [string]$btn.CallbackData }
                    )
                    $inlineKeyboard += ,@($row)
                }
            }
            
            if ($inlineKeyboard.Count -gt 0) {
                $replyMarkup = [PSCustomObject]@{
                    inline_keyboard = $inlineKeyboard
                }
                $payload["reply_markup"] = $replyMarkup
            }
        }
        
        $jsonPayload = $payload | ConvertTo-Json -Depth 10 -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonPayload)
        try {
            Invoke-RestMethod -Uri "$apiUrl/sendMessage" -Method Post -ContentType "application/json; charset=utf-8" -Body $bytes -ErrorAction Stop | Out-Null
            Write-Host "Message sent successfully" -ForegroundColor Green
        }
        catch {
            $payload.Remove("parse_mode")
            $jsonPayload = $payload | ConvertTo-Json -Depth 10 -Compress
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonPayload)
            try {
                Invoke-RestMethod -Uri "$apiUrl/sendMessage" -Method Post -ContentType "application/json; charset=utf-8" -Body $bytes -ErrorAction SilentlyContinue | Out-Null
                Write-Host "Message sent (without markdown)" -ForegroundColor Green
            }
            catch {
                Write-Host "Error sending message: $_" -ForegroundColor Red
                exit 1
            }
        }
        Start-Sleep -Milliseconds 200
    }
}

if ($Caption) {
    $env:TELEGRAM_CAPTION = $Message
}

Send-TelegramText -chatId $ChatId -text $Message -buttons $Buttons

