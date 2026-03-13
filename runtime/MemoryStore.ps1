function Get-ChatMemory {
    param($chatId)
    $file = "$workDir\mem_$chatId.json"
    if (Test-Path $file) {
        try {
            $content = Get-Content $file -Raw -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace($content)) {
                $parsed = $content | ConvertFrom-Json -ErrorAction Stop
                if ($null -ne $parsed) {
                    return @($parsed)
                }
            }
        }
        catch { }
    }
    return @()
}

function Add-ChatMemory {
    param($chatId, $role, $content)
    $file = "$workDir\mem_$chatId.json"
    [array]$mem = Get-ChatMemory -chatId $chatId
    $mem += @{ "role" = $role; "content" = $content }
    if ($content -is [array]) {
        $types = ($content | ForEach-Object { $_.type }) -join ","
        Write-DailyLog -message "Multimodal memory: stored $($content.Count) parts ($types) for role '$role'" -type "INFO"
    }
    if ($mem.Count -gt 20) { $mem = $mem[-20..-1] }
    $mem | ConvertTo-Json -Depth 10 -Compress | Set-Content $file -Encoding UTF8
}

function Clear-ChatMemory {
    param($chatId)
    $file = "$workDir\mem_$chatId.json"
    if (Test-Path $file) { Remove-Item $file -Force -ErrorAction SilentlyContinue }
}

function Optimize-ChatMemory {
    param($chatId)
    $file = "$workDir\mem_$chatId.json"
    if (-not (Test-Path $file)) { return }

    try {
        $history = Get-ChatMemory -chatId $chatId
        if ($history.Count -eq 0) { return }

        $lastUserIndex = -1
        for ($k = $history.Count - 1; $k -ge 0; $k--) {
            if ($history[$k].role -eq "user") {
                $lastUserIndex = $k
                break
            }
        }

        $modified = $false
        for ($i = 0; $i -lt $history.Count; $i++) {
            $msg = $history[$i]
            if ($i -eq $lastUserIndex) { continue }

            if ($msg.content -is [array]) {
                for ($j = 0; $j -lt $msg.content.Count; $j++) {
                    $part = $msg.content[$j]

                    if ($part.type -eq "input_audio" -and $part.input_audio.data -and $part.input_audio.data.Length -gt 2000) {
                        $msg.content[$j] = @{ type = "text"; text = " (Audio trimmed)" }
                        $modified = $true
                    }
                    elseif ($part.type -eq "image_url" -and $part.image_url.url -match "^data:image/.+;base64," -and $part.image_url.url.Length -gt 2000) {
                        $msg.content[$j] = @{ type = "text"; text = " (Image trimmed)" }
                        $modified = $true
                    }
                }

                $allText = $true
                foreach ($part in $msg.content) { if ($part.type -ne "text") { $allText = $false; break } }
                if ($allText) {
                    $combined = ($msg.content | ForEach-Object { $_.text }) -join " "
                    $msg.content = $combined.Trim()
                    $modified = $true
                }
            }
        }

        if ($modified) {
            Write-DailyLog -message "Chat memory optimized for $chatId (heavy multimedia trimmed)." -type "INFO"
            $history | ConvertTo-Json -Depth 10 -Compress | Set-Content $file -Encoding UTF8
        }
    }
    catch {
        Write-DailyLog -message "Error optimizing memory: $_" -type "ERROR"
    }
}
