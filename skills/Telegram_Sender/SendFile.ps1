param(
    [Parameter(Mandatory=$true)]
    [string]$FilePath,
    [string]$Caption = "",
    [string]$ChatId = ""
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
. (Join-Path $projectRoot "config\Load-BotConfig.ps1")
$botConfig = Import-BotSettings -ProjectRoot $projectRoot

$token = $botConfig.Telegram.BotToken
$ChatId = if ([string]::IsNullOrWhiteSpace($ChatId)) { $botConfig.Telegram.DefaultChatId } else { $ChatId }
$apiUrl = "https://api.telegram.org/bot$token"

Add-Type -AssemblyName System.Net.Http

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

if (-not (Test-Path $FilePath)) {
    Write-Host "Error: File not found: $FilePath" -ForegroundColor Red
    exit 1
}

try {
    $FilePath = [System.IO.Path]::GetFullPath($FilePath)
}
catch {}

$fileInfo = Get-Item $FilePath
if ($fileInfo.Length -eq 0) {
    Write-Host "Error: File is empty" -ForegroundColor Red
    exit 1
}

if ($fileInfo.Length -gt 50MB) {
    Write-Host "Error: File exceeds the 50 MB limit" -ForegroundColor Red
    exit 1
}

$fileBytes = [System.IO.File]::ReadAllBytes($FilePath)
$fileName = $fileInfo.Name

$httpClient = New-Object System.Net.Http.HttpClient
$boundary = [System.Guid]::NewGuid().ToString()
$content = New-Object System.Net.Http.MultipartFormDataContent($boundary)
$content.Add((New-Object System.Net.Http.StringContent($ChatId)), "chat_id")

if (-not [string]::IsNullOrWhiteSpace($Caption)) {
    $content.Add((New-Object System.Net.Http.StringContent($Caption)), "caption")
}

$fileContent = New-Object System.Net.Http.ByteArrayContent -ArgumentList @(, $fileBytes)
$mimeType = switch -Regex ($fileName) {
    '\.pdf$' { "application/pdf" }
    '\.docx?$' { "application/msword" }
    '\.xlsx?$' { "application/vnd.ms-excel" }
    '\.png$' { "image/png" }
    '\.jpe?g$' { "image/jpeg" }
    '\.gif$' { "image/gif" }
    '\.zip$' { "application/zip" }
    '\.rar$' { "application/x-rar-compressed" }
    '\.mp4$' { "video/mp4" }
    '\.mp3$' { "audio/mpeg" }
    '\.txt$' { "text/plain" }
    default { "application/octet-stream" }
}
$fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse($mimeType)
$content.Add($fileContent, "document", $fileName)

$uri = "$apiUrl/sendDocument"

try {
    $postTask = $httpClient.PostAsync($uri, $content)
    $postTask.Wait()
    if ($postTask.Result.IsSuccessStatusCode) {
        Write-Host "File sent successfully: $fileName" -ForegroundColor Green
        if ($Caption) {
            Write-Host "Caption: $Caption" -ForegroundColor Cyan
        }
    }
    else {
        $responseBody = ""
        try {
            $responseBody = $postTask.Result.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        }
        catch {}
        Write-Host "Error sending file: $($postTask.Result.StatusCode) $responseBody" -ForegroundColor Red
        exit 1
    }
    $postTask.Result.Dispose()
}
catch {
    Write-Host "Error sending file: $_" -ForegroundColor Red
    exit 1
}
finally {
    $httpClient.Dispose()
}
