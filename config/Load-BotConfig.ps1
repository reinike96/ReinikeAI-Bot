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
            PrimaryModel     = Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "BOT_PRIMARY_MODEL" -JsonPath "llm.primaryModel" -DefaultValue "google/gemini-3.1-flash-lite-preview"
            SecondaryModel   = Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "BOT_SECONDARY_MODEL" -JsonPath "llm.secondaryModel" -DefaultValue "qwen/qwen3.5-27b"
            ReasoningEffort  = Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "BOT_REASONING_EFFORT" -JsonPath "llm.reasoningEffort" -DefaultValue "low"
            ResponseLanguage = Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "BOT_RESPONSE_LANGUAGE" -JsonPath "llm.responseLanguage" -DefaultValue "English"
        }
        OpenCode = [PSCustomObject]@{
            ApiKey         = Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "OPENCODE_API_KEY" -JsonPath "opencode.apiKey" -DefaultValue ""
            ServerPassword = Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "OPENCODE_SERVER_PASSWORD" -JsonPath "opencode.serverPassword" -DefaultValue ""
            Host           = Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "OPENCODE_HOST" -JsonPath "opencode.host" -DefaultValue "127.0.0.1"
            Port           = [int](Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "OPENCODE_PORT" -JsonPath "opencode.port" -DefaultValue 4096)
            Command        = Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "OPENCODE_COMMAND" -JsonPath "opencode.command" -DefaultValue "opencode"
            ConfigPath     = Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "OPENCODE_CONFIG_PATH" -JsonPath "opencode.configPath" -DefaultValue (Join-Path $env:USERPROFILE ".config\opencode\opencode.json")
            DefaultModel   = Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "OPENCODE_DEFAULT_MODEL" -JsonPath "opencode.defaultModel" -DefaultValue "opencode/MiMo-V2-Pro-Free"
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
        }
        WindowsUse = [PSCustomObject]@{
            Enabled       = [System.Convert]::ToBoolean((Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "WINDOWS_USE_ENABLED" -JsonPath "windowsUse.enabled" -DefaultValue $false))
            PythonCommand = Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "WINDOWS_USE_PYTHON_COMMAND" -JsonPath "windowsUse.pythonCommand" -DefaultValue "python"
            Provider      = Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "WINDOWS_USE_PROVIDER" -JsonPath "windowsUse.provider" -DefaultValue "openrouter"
            Model         = Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "WINDOWS_USE_MODEL" -JsonPath "windowsUse.model" -DefaultValue (Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "BOT_PRIMARY_MODEL" -JsonPath "llm.primaryModel" -DefaultValue "google/gemini-3.1-flash-lite-preview")
            Browser       = Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "WINDOWS_USE_BROWSER" -JsonPath "windowsUse.browser" -DefaultValue "edge"
            MaxSteps      = [int](Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "WINDOWS_USE_MAX_STEPS" -JsonPath "windowsUse.maxSteps" -DefaultValue 30)
            UseVision     = [System.Convert]::ToBoolean((Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "WINDOWS_USE_USE_VISION" -JsonPath "windowsUse.useVision" -DefaultValue $false))
            Experimental  = [System.Convert]::ToBoolean((Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "WINDOWS_USE_EXPERIMENTAL" -JsonPath "windowsUse.experimental" -DefaultValue $false))
        }
        Paths = [PSCustomObject]@{
            WorkDir          = $root
            ArchivesDir      = Join-Path $root "archives"
            DownloadsDir     = $downloadsDir
            PersonalDataFile = Get-ResolvedConfigValue -JsonConfig $jsonConfig -EnvName "PERSONAL_DATA_FILE" -JsonPath "paths.personalDataFile" -DefaultValue (Join-Path $root "PERSONAL DATA.local.md")
        }
    }
}
