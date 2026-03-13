function Invoke-SystemDoctor {
    param(
        [object]$BotConfig,
        [string]$ApiUrl,
        [string]$Token,
        [string]$OpenRouterKey,
        [string]$WorkDir
    )

    $lines = @()
    $lines += "*System Doctor*"
    $lines += ""

    $checks = @()

    $checks += [PSCustomObject]@{
        Name = "Telegram token"
        Ok   = -not [string]::IsNullOrWhiteSpace($Token) -and $Token -notmatch 'PASTE_'
        Info = if (-not [string]::IsNullOrWhiteSpace($Token) -and $Token -notmatch 'PASTE_') { "Configured" } else { "Missing" }
    }
    $checks += [PSCustomObject]@{
        Name = "Default chat ID"
        Ok   = -not [string]::IsNullOrWhiteSpace($BotConfig.Telegram.DefaultChatId) -and $BotConfig.Telegram.DefaultChatId -notmatch 'PASTE_'
        Info = "$($BotConfig.Telegram.DefaultChatId)"
    }
    $checks += [PSCustomObject]@{
        Name = "OpenRouter API key"
        Ok   = -not [string]::IsNullOrWhiteSpace($OpenRouterKey) -and $OpenRouterKey -notmatch 'PASTE_'
        Info = if (-not [string]::IsNullOrWhiteSpace($OpenRouterKey) -and $OpenRouterKey -notmatch 'PASTE_') { "Configured" } else { "Missing" }
    }
    $checks += [PSCustomObject]@{
        Name = "Work directory"
        Ok   = Test-Path $WorkDir
        Info = $WorkDir
    }
    $checks += [PSCustomObject]@{
        Name = "Archives directory"
        Ok   = Test-Path $BotConfig.Paths.ArchivesDir
        Info = $BotConfig.Paths.ArchivesDir
    }

    $openCodeCommandOk = $false
    try {
        $null = Get-Command $BotConfig.OpenCode.Command -ErrorAction Stop
        $openCodeCommandOk = $true
    }
    catch {}
    $checks += [PSCustomObject]@{
        Name = "OpenCode command"
        Ok   = $openCodeCommandOk
        Info = $BotConfig.OpenCode.Command
    }

    $checks += [PSCustomObject]@{
        Name = "Chrome executable"
        Ok   = Test-Path $BotConfig.Browser.ChromeExecutable
        Info = $BotConfig.Browser.ChromeExecutable
    }
    $checks += [PSCustomObject]@{
        Name = "Chrome profile dir"
        Ok   = Test-Path $BotConfig.Browser.ChromeProfileDir
        Info = $BotConfig.Browser.ChromeProfileDir
    }
    $checks += [PSCustomObject]@{
        Name = "Playwright profile dir"
        Ok   = Test-Path $BotConfig.Browser.PlaywrightProfileDir
        Info = $BotConfig.Browser.PlaywrightProfileDir
    }

    foreach ($check in $checks) {
        $icon = if ($check.Ok) { "OK" } else { "FAIL" }
        $lines += "- $icon $($check.Name): $($check.Info)"
    }

    try {
        if (-not [string]::IsNullOrWhiteSpace($Token) -and $Token -notmatch 'PASTE_') {
            $telegramHealth = Invoke-RestMethod -Uri "$ApiUrl/getMe" -Method Get -TimeoutSec 10 -ErrorAction Stop
            $lines += "- OK Telegram API: @$($telegramHealth.result.username)"
        }
        else {
            $lines += "- FAIL Telegram API: token missing"
        }
    }
    catch {
        $lines += "- FAIL Telegram API: $($_.Exception.Message)"
    }

    try {
        if (-not [string]::IsNullOrWhiteSpace($BotConfig.OpenCode.ServerPassword)) {
            $cred = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("opencode:$($BotConfig.OpenCode.ServerPassword)"))
            $healthUrl = "http://$($BotConfig.OpenCode.Host):$($BotConfig.OpenCode.Port)/global/health"
            $health = Invoke-RestMethod -Uri $healthUrl -Headers @{ Authorization = "Basic $cred" } -TimeoutSec 5 -ErrorAction Stop
            $lines += "- OK OpenCode server: healthy=$($health.healthy) version=$($health.version)"
        }
        else {
            $lines += "- FAIL OpenCode server: password missing"
        }
    }
    catch {
        $lines += "- FAIL OpenCode server: $($_.Exception.Message)"
    }

    $lines += ""
    $lines += "*Hints*"
    $lines += "- Run `Install.ps1` if folders are missing."
    $lines += "- Fill `config/settings.json` if any credential check failed."
    $lines += "- Start OpenCode before browser-heavy tasks if the health check is failing."

    return ($lines -join "`n")
}
