param(
    [string]$Text = "",
    [string]$FilePath = "",
    [string]$Voice = "alloy",
    [string]$ChatId = "",
    [string]$OutputPath = ""
)

# Accept either -Text or -FilePath
if ([string]::IsNullOrWhiteSpace($Text) -and [string]::IsNullOrWhiteSpace($FilePath)) {
    Write-Host "Error: You must provide either -Text or -FilePath" -ForegroundColor Red
    Write-Host "Usage: -Text 'Your text here' OR -FilePath 'path\to\file.txt'" -ForegroundColor Yellow
    exit 1
}

# Read text from file if provided
if (-not [string]::IsNullOrWhiteSpace($FilePath)) {
    if (-not (Test-Path $FilePath)) {
        Write-Host "Error: File not found: $FilePath" -ForegroundColor Red
        exit 1
    }
    $Text = Get-Content $FilePath -Raw -ErrorAction Stop
    Write-Host "Read $($Text.Length) characters from: $FilePath" -ForegroundColor Cyan
}

$projectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
. (Join-Path $projectRoot "config\Load-BotConfig.ps1")
$botConfig = Import-BotSettings -ProjectRoot $projectRoot

$openRouterKey = $botConfig.LLM.OpenRouterApiKey
$archivesDir = if ($botConfig.Paths -and $botConfig.Paths.ArchivesDir) { $botConfig.Paths.ArchivesDir } else { Join-Path $projectRoot "archives" }
$token = $botConfig.Telegram.BotToken
$ChatId = if ([string]::IsNullOrWhiteSpace($ChatId)) { $botConfig.Telegram.DefaultChatId } else { $ChatId }
$apiUrl = "https://api.telegram.org/bot$token"

# Available voices: alloy, ash, ballad, coral, echo, fable, onyx, nova, sage, shimmer, verse, marin, cedar
$validVoices = @("alloy", "ash", "ballad", "coral", "echo", "fable", "onyx", "nova", "sage", "shimmer", "verse", "marin", "cedar")
if ($Voice -notin $validVoices) {
    Write-Host "Invalid voice '$Voice'. Using 'alloy' instead." -ForegroundColor Yellow
    $Voice = "alloy"
}

# Truncate text if too long
$maxChars = 4000
if ($Text.Length -gt $maxChars) {
    Write-Host "Text too long ($($Text.Length) chars). Truncating to $maxChars chars." -ForegroundColor Yellow
    $Text = $Text.Substring(0, $maxChars) + "..."
}

# Generate output filename if not provided
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $OutputPath = Join-Path $archivesDir "tts_$timestamp.pcm"
}
else {
    if (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
        $OutputPath = Join-Path $archivesDir $OutputPath
    }
}

# Ensure output directory exists
$outputDir = Split-Path -Parent $OutputPath
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
}

Write-Host "Generating audio with OpenRouter (model: openai/gpt-audio-mini, voice: $Voice)..." -ForegroundColor Cyan

# OpenRouter requires streaming for audio output
$chatUrl = "https://openrouter.ai/api/v1/chat/completions"

# Build the request body - audio output requires streaming
# IMPORTANT: format must be 'pcm16' when stream=true (not 'wav')
$bodyJson = @{
    model = "openai/gpt-audio-mini"
    modalities = @("text", "audio")
    audio = @{
        voice = $Voice
        format = "pcm16"
    }
    stream = $true
    messages = @(
        @{
            role = "user"
            content = "Read this text aloud in a natural, clear voice. Do not add any commentary, just read the text exactly: $Text"
        }
    )
} | ConvertTo-Json -Depth 10 -Compress

$audioGenerated = $false
$errorMessage = ""

try {
    # Make the request with streaming using HttpWebRequest for better SSE handling
    $request = [System.Net.WebRequest]::Create($chatUrl)
    $request.Method = "POST"
    $request.ContentType = "application/json"
    $request.Headers.Add("Authorization", "Bearer $openRouterKey")
    
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyJson)
    $request.ContentLength = $bodyBytes.Length
    
    $requestStream = $request.GetRequestStream()
    $requestStream.Write($bodyBytes, 0, $bodyBytes.Length)
    $requestStream.Close()
    
    $response = $request.GetResponse()
    $responseStream = $response.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($responseStream)
    
    $audioDataChunks = @()
    $transcriptChunks = @()
    
    while ($null -ne ($line = $reader.ReadLine())) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if (-not $line.StartsWith("data: ")) { continue }
        
        $data = $line.Substring(6).Trim()
        if ($data -eq "[DONE]") { break }
        
        try {
            $chunk = $data | ConvertFrom-Json
            $delta = $chunk.choices[0].delta
            if ($delta.audio) {
                if ($delta.audio.data) {
                    $audioDataChunks += $delta.audio.data
                }
                if ($delta.audio.transcript) {
                    $transcriptChunks += $delta.audio.transcript
                }
            }
        }
        catch {
            # Skip malformed JSON
            continue
        }
    }
    
    $reader.Close()
    $response.Close()
    
    if ($audioDataChunks.Count -gt 0) {
        # Combine all base64 chunks and decode
        $fullAudioB64 = $audioDataChunks -join ""
        $audioBytes = [System.Convert]::FromBase64String($fullAudioB64)
        [System.IO.File]::WriteAllBytes($OutputPath, $audioBytes)
        
        Write-Host "Audio saved to: $OutputPath" -ForegroundColor Green
        
        $fileInfo = Get-Item $OutputPath
        $sizeKB = [Math]::Round($fileInfo.Length / 1KB, 1)
        Write-Host "File size: $sizeKB KB" -ForegroundColor Gray
        
        if ($transcriptChunks.Count -gt 0) {
            $transcript = $transcriptChunks -join ""
            Write-Host "Transcript: $transcript" -ForegroundColor Gray
        }
        
        $audioGenerated = $true
    }
    else {
        $errorMessage = "No audio data received in response from OpenRouter"
        Write-Host $errorMessage -ForegroundColor Red
    }
}
catch {
    $errorMessage = "Error generating audio: $_"
    Write-Host $errorMessage -ForegroundColor Red
    if ($_.Exception.Response) {
        try {
            $errorStream = $_.Exception.Response.GetResponseStream()
            $errorReader = New-Object System.IO.StreamReader($errorStream)
            $errorContent = $errorReader.ReadToEnd()
            Write-Host "Response details: $errorContent" -ForegroundColor Red
            $errorMessage += " | Details: $errorContent"
        }
        catch {
            Write-Host "Could not read error response" -ForegroundColor Red
        }
    }
}

# Convert PCM to WAV and send to Telegram
if ($audioGenerated -and (Test-Path $OutputPath)) {
    Write-Host "Converting PCM to WAV..." -ForegroundColor Cyan
    
    # Create WAV file with proper header
    $wavPath = $OutputPath -replace '\.pcm$', '.wav'
    $pcmData = [System.IO.File]::ReadAllBytes($OutputPath)
    
    # PCM16 format: 24000 Hz, 16-bit, mono
    $sampleRate = 24000
    $bitsPerSample = 16
    $channels = 1
    $byteRate = $sampleRate * $channels * ($bitsPerSample / 8)
    $blockAlign = $channels * ($bitsPerSample / 8)
    $dataSize = $pcmData.Length
    
    # WAV header (44 bytes)
    $wavHeader = New-Object byte[] 44
    # "RIFF"
    $wavHeader[0] = 0x52; $wavHeader[1] = 0x49; $wavHeader[2] = 0x46; $wavHeader[3] = 0x46
    # File size - 8
    $fileSize = $dataSize + 36
    [BitConverter]::GetBytes([uint32]$fileSize).CopyTo($wavHeader, 4)
    # "WAVE"
    $wavHeader[8] = 0x57; $wavHeader[9] = 0x41; $wavHeader[10] = 0x56; $wavHeader[11] = 0x45
    # "fmt "
    $wavHeader[12] = 0x66; $wavHeader[13] = 0x6D; $wavHeader[14] = 0x74; $wavHeader[15] = 0x20
    # Subchunk1Size (16 for PCM)
    [BitConverter]::GetBytes([uint32]16).CopyTo($wavHeader, 16)
    # AudioFormat (1 = PCM)
    [BitConverter]::GetBytes([uint16]1).CopyTo($wavHeader, 20)
    # NumChannels
    [BitConverter]::GetBytes([uint16]$channels).CopyTo($wavHeader, 22)
    # SampleRate
    [BitConverter]::GetBytes([uint32]$sampleRate).CopyTo($wavHeader, 24)
    # ByteRate
    [BitConverter]::GetBytes([uint32]$byteRate).CopyTo($wavHeader, 28)
    # BlockAlign
    [BitConverter]::GetBytes([uint16]$blockAlign).CopyTo($wavHeader, 32)
    # BitsPerSample
    [BitConverter]::GetBytes([uint16]$bitsPerSample).CopyTo($wavHeader, 34)
    # "data"
    $wavHeader[36] = 0x64; $wavHeader[37] = 0x61; $wavHeader[38] = 0x74; $wavHeader[39] = 0x61
    # Subchunk2Size
    [BitConverter]::GetBytes([uint32]$dataSize).CopyTo($wavHeader, 40)
    
    # Write WAV file
    $wavData = New-Object byte[] ($wavHeader.Length + $pcmData.Length)
    $wavHeader.CopyTo($wavData, 0)
    $pcmData.CopyTo($wavData, $wavHeader.Length)
    [System.IO.File]::WriteAllBytes($wavPath, $wavData)
    
    Write-Host "WAV file created: $wavPath" -ForegroundColor Green
    
    # Send to Telegram using curl.exe (more reliable)
    Write-Host "Sending audio to Telegram chat $ChatId..." -ForegroundColor Cyan
    
    $sendAudioUrl = "$apiUrl/sendAudio"
    
    try {
        $result = curl.exe -s -X POST $sendAudioUrl -F "chat_id=$ChatId" -F "audio=@$wavPath" -F "caption=Audio response"
        $jsonResult = $result | ConvertFrom-Json
        if ($jsonResult.ok) {
            Write-Host "Audio sent successfully to Telegram" -ForegroundColor Green
            Write-Output "Audio sent successfully"
            # Clean up PCM file
            Remove-Item $OutputPath -ErrorAction SilentlyContinue
        } else {
            Write-Host "Telegram error: $($jsonResult.description)" -ForegroundColor Red
            Write-Output "Error sending audio: $($jsonResult.description)"
        }
    }
    catch {
        Write-Host "Error sending audio to Telegram: $_" -ForegroundColor Red
        Write-Output "Error sending audio: $_"
    }
}
elseif (-not $audioGenerated) {
    # Send error message to Telegram so user knows what happened
    $errorMsg = "No pude generar el audio. $errorMessage"
    try {
        $sendMsgUrl = "$apiUrl/sendMessage"
        $payload = @{ chat_id = $ChatId; text = $errorMsg } | ConvertTo-Json -Compress
        Invoke-RestMethod -Uri $sendMsgUrl -Method Post -ContentType "application/json" -Body ([System.Text.Encoding]::UTF8.GetBytes($payload)) | Out-Null
    }
    catch {
        Write-Host "Could not send error message to Telegram" -ForegroundColor Red
    }
    Write-Output $errorMsg
}

# Return the path for orchestrator to use
if ($audioGenerated) {
    Write-Output $OutputPath
}
