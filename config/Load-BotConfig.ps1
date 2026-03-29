function Get-BotProjectRoot {
    param([string]$ProjectRoot)

    if (-not [string]::IsNullOrWhiteSpace($ProjectRoot)) {
        return $ProjectRoot
    }

    return (Split-Path -Parent $PSScriptRoot)
}

function Get-ConfigNodeValue {
    param(
        [object]$Node,
        [string]$Path
    )

    if ($null -eq $Node -or [string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    $current = $Node
    foreach ($segment in ($Path -split '\.')) {
        if ($null -eq $current) {
            return $null
        }

        $next = $current.PSObject.Properties[$segment]
        if ($null -eq $next) {
            return $null
        }

        $current = $next.Value
    }

    return $current
}

function Get-ResolvedConfigValue {
    param(
        [object]$JsonConfig,
        [string]$EnvName,
        [string]$JsonPath,
        [object]$DefaultValue
    )

    $envValue = [Environment]::GetEnvironmentVariable($EnvName)
    if (-not [string]::IsNullOrWhiteSpace($envValue)) {
        return $envValue
    }

    $jsonValue = Get-ConfigNodeValue -Node $JsonConfig -Path $JsonPath
    if ($null -ne $jsonValue -and "$jsonValue" -ne "") {
        return $jsonValue
    }

    return $DefaultValue
}

function Get-ResolvedConfigArray {
    param(
        [object]$JsonConfig,
        [string]$EnvName,
        [string]$JsonPath,
        [object[]]$DefaultValue = @()
    )

    $envValue = [Environment]::GetEnvironmentVariable($EnvName)
    if (-not [string]::IsNullOrWhiteSpace($envValue)) {
        return @($envValue -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    $jsonValue = Get-ConfigNodeValue -Node $JsonConfig -Path $JsonPath
    if ($jsonValue -is [System.Collections.IEnumerable] -and $jsonValue -isnot [string]) {
        return @($jsonValue | ForEach-Object { "$_".Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    return @($DefaultValue)
}

function Import-BotSettings {
    param([string]$ProjectRoot)

    $root = Get-BotProjectRoot -ProjectRoot $ProjectRoot
    $settingsPath = Join-Path $root "config\settings.json"
    $jsonConfig = $null

    if (Test-Path $settingsPath) {
        $raw = Get-Content $settingsPath -Raw -ErrorAction SilentlyContinue
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $jsonConfig = $raw | ConvertFrom-Json
        }
    }

    $downloadsDir = Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "DOWNLOADS_DIR" -JsonPath "paths.downloadsDir" -DefaultValue (Join-Path $env:USERPROFILE "Downloads")
    $chromeExecutable = Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "CHROME_EXECUTABLE" -JsonPath "browser.chromeExecutable" -DefaultValue "C:\Program Files\Google\Chrome\Application\chrome.exe"
    $chromeProfileDir = Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "CHROME_PROFILE_DIR" -JsonPath "browser.chromeProfileDir" -DefaultValue (Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data\Default")
    $playwrightProfileDir = Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "PLAYWRIGHT_PROFILE_DIR" -JsonPath "browser.playwrightProfileDir" -DefaultValue (Join-Path $root "profiles\playwright")
    $defaultChatId = Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "TELEGRAM_DEFAULT_CHAT_ID" -JsonPath "telegram.defaultChatId" -DefaultValue ""
    $startupChatId = Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "TELEGRAM_STARTUP_CHAT_ID" -JsonPath "telegram.startupChatId" -DefaultValue $defaultChatId
    $authorizedChatIds = Get-ResolvedConfigArray -JsonConfig $jsonConfig -EnvName "TELEGRAM_AUTHORIZED_CHAT_IDS" -JsonPath "telegram.authorizedChatIds" -DefaultValue @($defaultChatId)
    $authorizedUserIds = Get-ResolvedConfigArray -JsonConfig $jsonConfig -EnvName "TELEGRAM_AUTHORIZED_USER_IDS" -JsonPath "telegram.authorizedUserIds" -DefaultValue @()
    $browserPackEnabled = [System.Convert]::ToBoolean((Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "BOT_PACK_BROWSER" -JsonPath "opencode.packs.browser" -DefaultValue $true))
    $docsPackEnabled = [System.Convert]::ToBoolean((Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "BOT_PACK_DOCS" -JsonPath "opencode.packs.docs" -DefaultValue $false))
    $sheetsPackEnabled = [System.Convert]::ToBoolean((Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "BOT_PACK_SHEETS" -JsonPath "opencode.packs.sheets" -DefaultValue $false))
    $computerPackEnabled = [System.Convert]::ToBoolean((Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "BOT_PACK_COMPUTER" -JsonPath "opencode.packs.computer" -DefaultValue $false))
    $socialPackEnabled = [System.Convert]::ToBoolean((Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "BOT_PACK_SOCIAL" -JsonPath "opencode.packs.social" -DefaultValue $false))

    return [PSCustomObject]@{
        Telegram = [PSCustomObject]@{
            BotToken          = Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "TELEGRAM_BOT_TOKEN" -JsonPath "telegram.botToken" -DefaultValue ""
            DefaultChatId     = $defaultChatId
            StartupChatId     = $startupChatId
            AuthorizedChatIds = $authorizedChatIds
            AuthorizedUserIds = $authorizedUserIds
        }
        LLM = [PSCustomObject]@{
            OpenRouterApiKey = Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "OPENROUTER_API_KEY" -JsonPath "llm.openRouterApiKey" -DefaultValue ""
            PrimaryModel     = Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "BOT_PRIMARY_MODEL" -JsonPath "llm.primaryModel" -DefaultValue "xiaomi/mimo-v2-omni"
            SecondaryModel   = Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "BOT_SECONDARY_MODEL" -JsonPath "llm.secondaryModel" -DefaultValue "qwen/qwen3.5-27b"
            MultimodalModel  = Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "BOT_MULTIMODAL_MODEL" -JsonPath "llm.multimodalModel" -DefaultValue "xiaomi/mimo-v2-omni"
            ReasoningEffort  = Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "BOT_REASONING_EFFORT" -JsonPath "llm.reasoningEffort" -DefaultValue "medium"
            ResponseLanguage = Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "BOT_RESPONSE_LANGUAGE" -JsonPath "llm.responseLanguage" -DefaultValue "English"
        }
        OpenCode = [PSCustomObject]@{
            ApiKey         = Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "OPENCODE_API_KEY" -JsonPath "opencode.apiKey" -DefaultValue ""
            ServerPassword = Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "OPENCODE_SERVER_PASSWORD" -JsonPath "opencode.serverPassword" -DefaultValue ""
            Host           = Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "OPENCODE_HOST" -JsonPath "opencode.host" -DefaultValue "127.0.0.1"
            Port           = [int](Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "OPENCODE_PORT" -JsonPath "opencode.port" -DefaultValue 4096)
            Command        = Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "OPENCODE_COMMAND" -JsonPath "opencode.command" -DefaultValue "opencode"
            ConfigPath     = Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "OPENCODE_CONFIG_PATH" -JsonPath "opencode.configPath" -DefaultValue (Join-Path $env:USERPROFILE ".config\opencode\opencode.json")
            Transport      = Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "OPENCODE_TRANSPORT" -JsonPath "opencode.transport" -DefaultValue "cli"
            DefaultModel   = Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "OPENCODE_DEFAULT_MODEL" -JsonPath "opencode.defaultModel" -DefaultValue "opencode/mimo-v2-pro-free"
            Packs          = [PSCustomObject]@{
                Browser = $browserPackEnabled
                Docs = $docsPackEnabled
                Sheets = $sheetsPackEnabled
                Computer = $computerPackEnabled
                Social = $socialPackEnabled
            }
        }
        Browser = [PSCustomObject]@{
            ChromeExecutable   = $chromeExecutable
            ChromeProfileDir   = $chromeProfileDir
            PlaywrightProfileDir = $playwrightProfileDir
            Locale             = Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "BROWSER_LOCALE" -JsonPath "browser.locale" -DefaultValue "en-US"
            Timezone           = Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "BROWSER_TIMEZONE" -JsonPath "browser.timezone" -DefaultValue "UTC"
            DebugPort          = [int](Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "BROWSER_DEBUG_PORT" -JsonPath "browser.debugPort" -DefaultValue 9333)
            KeepOpen           = [System.Convert]::ToBoolean((Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "BROWSER_KEEP_OPEN" -JsonPath "browser.keepOpen" -DefaultValue $true))
            HeadlessByDefault  = [System.Convert]::ToBoolean((Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "BROWSER_HEADLESS_BY_DEFAULT" -JsonPath "browser.headlessByDefault" -DefaultValue $true))
        }
        Paths = [PSCustomObject]@{
            WorkDir          = $root
            ArchivesDir      = Join-Path $root "archives"
            DownloadsDir     = $downloadsDir
            PersonalDataFile = Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "PERSONAL_DATA_FILE" -JsonPath "paths.personalDataFile" -DefaultValue (Join-Path $root "PERSONAL DATA.local.md")
        }
    }
}

function Set-PersistentReasoningEffort {
    param(
        [string]$ProjectRoot,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "Reasoning effort value cannot be empty."
    }

    $normalizedValue = $Value.Trim().ToLowerInvariant()
    if ($normalizedValue -notin @("low", "medium", "high", "none")) {
        throw "Unsupported reasoning effort: $Value"
    }

    $root = Get-BotProjectRoot -ProjectRoot $ProjectRoot
    $settingsPath = Join-Path $root "config\settings.json"
    $settingsExamplePath = Join-Path $root "config\settings.example.json"

    $jsonConfig = $null
    if (Test-Path $settingsPath) {
        $raw = Get-Content $settingsPath -Raw -ErrorAction Stop
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $jsonConfig = $raw | ConvertFrom-Json -ErrorAction Stop
        }
    }
    elseif (Test-Path $settingsExamplePath) {
        $raw = Get-Content $settingsExamplePath -Raw -ErrorAction Stop
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $jsonConfig = $raw | ConvertFrom-Json -ErrorAction Stop
        }
    }

    if ($null -eq $jsonConfig) {
        $jsonConfig = [pscustomobject]@{}
    }

    if (-not $jsonConfig.PSObject.Properties["llm"] -or $null -eq $jsonConfig.llm) {
        $jsonConfig | Add-Member -NotePropertyName "llm" -NotePropertyValue ([pscustomobject]@{})
    }

    if ($jsonConfig.llm.PSObject.Properties["reasoningEffort"]) {
        $jsonConfig.llm.reasoningEffort = $normalizedValue
    }
    else {
        $jsonConfig.llm | Add-Member -NotePropertyName "reasoningEffort" -NotePropertyValue $normalizedValue
    }

    $jsonConfig | ConvertTo-Json -Depth 20 | Set-Content -Path $settingsPath -Encoding UTF8
    return $normalizedValue
}

function Normalize-OpenCodeModelValue {
    param(
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "OpenCode model value cannot be empty."
    }

    $normalizedValue = $Value.Trim()
    if ($normalizedValue -match '\s') {
        throw "OpenCode model cannot contain spaces. Use values like 'mimo-v2-pro-free' or 'opencode/kimi-k2.5'."
    }

    if ($normalizedValue -notmatch '^[A-Za-z0-9._/-]+$') {
        throw "Unsupported OpenCode model format: $Value"
    }

    if ($normalizedValue -notmatch '/') {
        $normalizedValue = "opencode/$normalizedValue"
    }

    return $normalizedValue.ToLowerInvariant()
}

function Set-PersistentOpenCodeDefaultModel {
    param(
        [string]$ProjectRoot,
        [string]$Value
    )

    $normalizedValue = Normalize-OpenCodeModelValue -Value $Value

    $root = Get-BotProjectRoot -ProjectRoot $ProjectRoot
    $settingsPath = Join-Path $root "config\settings.json"
    $settingsExamplePath = Join-Path $root "config\settings.example.json"

    $jsonConfig = $null
    if (Test-Path $settingsPath) {
        $raw = Get-Content $settingsPath -Raw -ErrorAction Stop
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $jsonConfig = $raw | ConvertFrom-Json -ErrorAction Stop
        }
    }
    elseif (Test-Path $settingsExamplePath) {
        $raw = Get-Content $settingsExamplePath -Raw -ErrorAction Stop
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $jsonConfig = $raw | ConvertFrom-Json -ErrorAction Stop
        }
    }

    if ($null -eq $jsonConfig) {
        $jsonConfig = [pscustomobject]@{}
    }

    if (-not $jsonConfig.PSObject.Properties["opencode"] -or $null -eq $jsonConfig.opencode) {
        $jsonConfig | Add-Member -NotePropertyName "opencode" -NotePropertyValue ([pscustomobject]@{})
    }

    if ($jsonConfig.opencode.PSObject.Properties["defaultModel"]) {
        $jsonConfig.opencode.defaultModel = $normalizedValue
    }
    else {
        $jsonConfig.opencode | Add-Member -NotePropertyName "defaultModel" -NotePropertyValue $normalizedValue
    }

    $jsonConfig | ConvertTo-Json -Depth 20 | Set-Content -Path $settingsPath -Encoding UTF8
    return $normalizedValue
}
