param(
    [switch]$SkipNetworkChecks
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$configDir = Join-Path $projectRoot "config"
$archivesDir = Join-Path $projectRoot "archives"
$profilesDir = Join-Path $projectRoot "profiles"
$playwrightProfileDir = Join-Path $profilesDir "playwright"
$settingsExample = Join-Path $configDir "settings.example.json"
$settingsLocal = Join-Path $configDir "settings.json"
$opencodeExample = Join-Path $configDir "opencode.example.json"
$packageJsonPath = Join-Path $projectRoot "package.json"
$personalDataPath = Join-Path $projectRoot "PERSONAL DATA.md"
$defaultOpenCodeConfigPath = Join-Path $env:USERPROFILE ".config\opencode\config.json"

. (Join-Path $projectRoot "config\Load-BotConfig.ps1")
if (Test-Path (Join-Path $projectRoot "Logo.ps1")) {
    & (Join-Path $projectRoot "Logo.ps1")
}

function Test-CommandAvailable {
    param([string]$Name)

    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Read-BooleanAnswer {
    param(
        [string]$Prompt,
        [bool]$Default = $true
    )

    $suffix = if ($Default) { "[Y/n]" } else { "[y/N]" }
    $raw = Read-Host "$Prompt $suffix"
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $Default
    }

    return $raw.Trim().ToLowerInvariant() -in @("y", "yes")
}

function Read-ValuePrompt {
    param(
        [string]$Prompt,
        [string]$DefaultValue = "",
        [switch]$Required,
        [switch]$Secret
    )

    while ($true) {
        $fullPrompt = if ([string]::IsNullOrWhiteSpace($DefaultValue)) { $Prompt } else { "$Prompt [$DefaultValue]" }
        $value = if ($Secret) { Read-Host $fullPrompt } else { Read-Host $fullPrompt }

        if ([string]::IsNullOrWhiteSpace($value)) {
            $value = $DefaultValue
        }

        if (-not $Required -or -not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }

        Write-Host "This value is required." -ForegroundColor Yellow
    }
}

function Ensure-Directory {
    param([string]$Path)

    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Get-DetectedChromeExecutable {
    $candidates = @(
        "C:\Program Files\Google\Chrome\Application\chrome.exe",
        "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
        (Join-Path $env:LOCALAPPDATA "Google\Chrome\Application\chrome.exe")
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $null
}

function Get-DetectedChromeProfileDir {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data\Default"),
        (Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data\Profile 1")
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $null
}

function Install-OpenCodeIfNeeded {
    param([string]$CommandName)

    if (Test-CommandAvailable -Name $CommandName) {
        Write-Host "[Setup] OpenCode command already available." -ForegroundColor Green
        return $true
    }

    Write-Host "[Setup] OpenCode command '$CommandName' was not found." -ForegroundColor Yellow
    if (-not (Read-BooleanAnswer -Prompt "Install OpenCode globally with npm now?" -Default $true)) {
        return $false
    }

    if (-not (Test-CommandAvailable -Name "npm")) {
        Write-Host "[Setup] npm is not available, so OpenCode cannot be installed automatically." -ForegroundColor Red
        return $false
    }

    & npm install -g opencode-ai
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[Setup] OpenCode installation failed." -ForegroundColor Red
        return $false
    }

    $commandFound = Test-CommandAvailable -Name $CommandName
    Write-Host $(if ($commandFound) { "[Setup] OpenCode installed successfully." } else { "[Setup] OpenCode install finished, but the command is still not available in PATH." }) -ForegroundColor $(if ($commandFound) { "Green" } else { "Yellow" })
    return $commandFound
}

function Install-PlaywrightNodeDependencies {
    param([string]$ProjectRoot)

    if (-not (Test-Path $packageJsonPath)) {
        Write-Host "[Setup] package.json is missing, so Node Playwright dependencies cannot be installed automatically." -ForegroundColor Red
        return $false
    }

    if (-not (Test-CommandAvailable -Name "npm")) {
        Write-Host "[Setup] npm is not available, so Node Playwright dependencies cannot be installed." -ForegroundColor Red
        return $false
    }

    Push-Location $ProjectRoot
    try {
        & npm install
        return $LASTEXITCODE -eq 0
    }
    finally {
        Pop-Location
    }
}

function Install-PythonPlaywrightFallback {
    $pythonCmd = $null
    if (Test-CommandAvailable -Name "python") {
        $pythonCmd = @("python")
    }
    elseif (Test-CommandAvailable -Name "py") {
        $pythonCmd = @("py")
    }

    if ($null -eq $pythonCmd) {
        Write-Host "[Setup] Python is not available. Skipping the optional Python Playwright fallback." -ForegroundColor Yellow
        return $false
    }

    if (Test-CommandAvailable -Name "pip") {
        & pip install playwright playwright-stealth
        if ($LASTEXITCODE -ne 0) { return $false }
    }
    else {
        & $pythonCmd[0] -m pip install playwright playwright-stealth
        if ($LASTEXITCODE -ne 0) { return $false }
    }

    & $pythonCmd[0] -m playwright install chromium
    return $LASTEXITCODE -eq 0
}

function Test-TelegramBotToken {
    param([string]$BotToken)

    try {
        $response = Invoke-RestMethod -Uri "https://api.telegram.org/bot$BotToken/getMe" -Method Get -TimeoutSec 20
        return $response.ok
    }
    catch {
        return $false
    }
}

function Test-TelegramChatAccess {
    param(
        [string]$BotToken,
        [string]$ChatId
    )

    try {
        $response = Invoke-RestMethod -Uri "https://api.telegram.org/bot$BotToken/getChat?chat_id=$ChatId" -Method Get -TimeoutSec 20
        return $response.ok
    }
    catch {
        return $false
    }
}

function Test-OpenRouterKey {
    param([string]$ApiKey)

    try {
        $headers = @{ Authorization = "Bearer $ApiKey" }
        $response = Invoke-RestMethod -Uri "https://openrouter.ai/api/v1/models" -Headers $headers -Method Get -TimeoutSec 20
        return $null -ne $response.data
    }
    catch {
        return $false
    }
}

function Save-JsonFile {
    param(
        [string]$Path,
        [object]$Data
    )

    $Data | ConvertTo-Json -Depth 10 | Set-Content -Path $Path -Encoding UTF8
}

function Sync-OpenCodeConfigTemplate {
    param(
        [string]$TemplatePath,
        [string]$ConfiguredPath
    )

    if (-not (Test-Path $TemplatePath)) {
        return $false
    }

    $canonicalPath = Join-Path $env:USERPROFILE ".config\opencode\config.json"
    Ensure-Directory -Path (Split-Path -Parent $canonicalPath)

    Copy-Item $TemplatePath $canonicalPath -Force
    if (-not [string]::IsNullOrWhiteSpace($ConfiguredPath) -and $ConfiguredPath -ne $canonicalPath) {
        Ensure-Directory -Path (Split-Path -Parent $ConfiguredPath)
        Copy-Item $TemplatePath $ConfiguredPath -Force
    }

    return $true
}

function Write-PersonalDataFile {
    param(
        [string]$Path,
        [hashtable]$Profile
    )

    $content = @"
# Personal Data

This file is local-only and is used by the bot for forms and user-specific tasks.

Never commit real personal information to the repository.

## Identity

- Full name: $($Profile.FullName)
- Preferred name: $($Profile.PreferredName)
- Date of birth: $($Profile.DateOfBirth)
- Place of birth: $($Profile.PlaceOfBirth)
- Nationality: $($Profile.Nationality)

## Contact

- Address: $($Profile.Address)
- Phone: $($Profile.Phone)
- Email: $($Profile.Email)

## Government and Insurance

- Health insurance number: $($Profile.HealthInsuranceNumber)
- Pension number: $($Profile.PensionNumber)
- Tax ID / national ID: $($Profile.TaxId)

## Banking

- Bank: $($Profile.Bank)
- Account holder: $($Profile.AccountHolder)
- IBAN: $($Profile.IBAN)
- BIC: $($Profile.BIC)

## Professional Profile

- Occupation: $($Profile.Occupation)
- Specialization: $($Profile.Specialization)
- Notes for forms: $($Profile.FormNotes)
"@

    Set-Content -Path $Path -Value $content -Encoding UTF8
}

Write-Host "ReinikeAI interactive setup" -ForegroundColor Cyan
Write-Host "==========================" -ForegroundColor Cyan
Write-Host ""

Ensure-Directory -Path $archivesDir
Ensure-Directory -Path $profilesDir
Ensure-Directory -Path $playwrightProfileDir

if (-not (Test-Path $settingsLocal)) {
    Copy-Item $settingsExample $settingsLocal
    Write-Host "[Setup] Created config/settings.json from the example template." -ForegroundColor Yellow
}

$existingConfig = $null
if (Test-Path $settingsLocal) {
    $existingRaw = Get-Content $settingsLocal -Raw -ErrorAction SilentlyContinue
    if (-not [string]::IsNullOrWhiteSpace($existingRaw)) {
        $existingConfig = $existingRaw | ConvertFrom-Json
    }
}

$currentSettings = Import-BotSettings -ProjectRoot $projectRoot

Write-Host ""
Write-Host "Step 1: Tooling" -ForegroundColor Green
$opencodeCommand = "opencode"
$openCodeReady = Install-OpenCodeIfNeeded -CommandName $opencodeCommand
if (-not $openCodeReady) {
    $opencodeCommand = Read-ValuePrompt -Prompt "OpenCode command name (custom command or full path)" -DefaultValue $(if ([string]::IsNullOrWhiteSpace($currentSettings.OpenCode.Command)) { "opencode" } else { $currentSettings.OpenCode.Command }) -Required
}

$installPlaywrightNode = Read-BooleanAnswer -Prompt "Install or refresh local Playwright Node dependencies?" -Default $true
if ($installPlaywrightNode) {
    $playwrightNodeOk = Install-PlaywrightNodeDependencies -ProjectRoot $projectRoot
    Write-Host $(if ($playwrightNodeOk) { "[Setup] Playwright Node dependencies installed." } else { "[Setup] Failed to install Playwright Node dependencies." }) -ForegroundColor $(if ($playwrightNodeOk) { "Green" } else { "Red" })
}

$installPlaywrightPython = Read-BooleanAnswer -Prompt "Install the optional Python Playwright fallback too?" -Default $false
if ($installPlaywrightPython) {
    $playwrightPythonOk = Install-PythonPlaywrightFallback
    Write-Host $(if ($playwrightPythonOk) { "[Setup] Python Playwright fallback installed." } else { "[Setup] Python Playwright fallback was not installed successfully." }) -ForegroundColor $(if ($playwrightPythonOk) { "Green" } else { "Yellow" })
}

Write-Host ""
Write-Host "Step 2: Telegram and API credentials" -ForegroundColor Green
$botToken = Read-ValuePrompt -Prompt "Telegram bot token" -DefaultValue $currentSettings.Telegram.BotToken -Required
$defaultChatId = Read-ValuePrompt -Prompt "Telegram default chat ID" -DefaultValue $currentSettings.Telegram.DefaultChatId -Required
$startupChatId = Read-ValuePrompt -Prompt "Telegram startup chat ID" -DefaultValue $(if ($currentSettings.Telegram.StartupChatId) { $currentSettings.Telegram.StartupChatId } else { $defaultChatId }) -Required
$openRouterApiKey = Read-ValuePrompt -Prompt "OpenRouter API key" -DefaultValue $currentSettings.LLM.OpenRouterApiKey -Required -Secret
$openCodeApiKey = Read-ValuePrompt -Prompt "OpenCode API key" -DefaultValue $currentSettings.OpenCode.ApiKey -Required -Secret
$serverPassword = Read-ValuePrompt -Prompt "OpenCode local server password" -DefaultValue $(if ($currentSettings.OpenCode.ServerPassword) { $currentSettings.OpenCode.ServerPassword } else { [guid]::NewGuid().ToString("N").Substring(0, 20) }) -Required -Secret
$responseLanguage = Read-ValuePrompt -Prompt "Orchestrator response language" -DefaultValue $(if ($currentSettings.LLM.ResponseLanguage) { $currentSettings.LLM.ResponseLanguage } else { "English" }) -Required

Write-Host ""
Write-Host "Step 3: Local paths and browser setup" -ForegroundColor Green
$detectedChromeExecutable = Get-DetectedChromeExecutable
$chromeExecutable = if ($detectedChromeExecutable) { $detectedChromeExecutable } elseif (-not [string]::IsNullOrWhiteSpace($currentSettings.Browser.ChromeExecutable)) { $currentSettings.Browser.ChromeExecutable } else { "" }
if (-not [string]::IsNullOrWhiteSpace($chromeExecutable)) {
    Write-Host "[Setup] Chrome executable detected: $chromeExecutable" -ForegroundColor Green
}
else {
    $chromeExecutable = Read-ValuePrompt -Prompt "Chrome executable path (detection failed, enter a path manually)" -DefaultValue "" -Required
}

$detectedChromeProfileDir = Get-DetectedChromeProfileDir
$chromeProfileDir = if ($detectedChromeProfileDir) { $detectedChromeProfileDir } elseif (-not [string]::IsNullOrWhiteSpace($currentSettings.Browser.ChromeProfileDir)) { $currentSettings.Browser.ChromeProfileDir } else { "" }
if (-not [string]::IsNullOrWhiteSpace($chromeProfileDir)) {
    Write-Host "[Setup] Chrome profile detected: $chromeProfileDir" -ForegroundColor Green
}
else {
    $chromeProfileDir = Read-ValuePrompt -Prompt "Chrome profile directory (detection failed, enter a path manually)" -DefaultValue "" -Required
}

$playwrightProfileInput = $playwrightProfileDir
Write-Host "[Setup] Playwright profile directory: $playwrightProfileInput" -ForegroundColor Green
$downloadsDir = $archivesDir
Write-Host "[Setup] Download/output directory: $downloadsDir" -ForegroundColor Green
$openCodeConfigPath = if (-not [string]::IsNullOrWhiteSpace($currentSettings.OpenCode.ConfigPath) -and $currentSettings.OpenCode.ConfigPath -notmatch 'YOUR_USER') { $currentSettings.OpenCode.ConfigPath } else { $defaultOpenCodeConfigPath }
if ([System.IO.Path]::GetFileName($openCodeConfigPath) -ieq "opencode.json") {
    $openCodeConfigPath = Join-Path (Split-Path -Parent $openCodeConfigPath) "config.json"
}
Write-Host "[Setup] OpenCode user config path: $openCodeConfigPath" -ForegroundColor Green

Ensure-Directory -Path $playwrightProfileInput
Ensure-Directory -Path (Split-Path -Parent $openCodeConfigPath)

Write-Host ""
Write-Host "Step 4: Personal data file" -ForegroundColor Green
$fillPersonalData = Read-BooleanAnswer -Prompt "Do you want to populate PERSONAL DATA.md now?" -Default $true

$personalProfile = @{
    FullName = "Not set"
    PreferredName = "Not set"
    DateOfBirth = "Not set"
    PlaceOfBirth = "Not set"
    Nationality = "Not set"
    Address = "Not set"
    Phone = "Not set"
    Email = "Not set"
    HealthInsuranceNumber = "Not set"
    PensionNumber = "Not set"
    TaxId = "Not set"
    Bank = "Not set"
    AccountHolder = "Not set"
    IBAN = "Not set"
    BIC = "Not set"
    Occupation = "Not set"
    Specialization = "Not set"
    FormNotes = "Not set"
}

if ($fillPersonalData) {
    $personalProfile.FullName = Read-ValuePrompt -Prompt "Full name" -DefaultValue ""
    $personalProfile.PreferredName = Read-ValuePrompt -Prompt "Preferred name" -DefaultValue ""
    $personalProfile.Email = Read-ValuePrompt -Prompt "Email" -DefaultValue ""
    $personalProfile.Phone = Read-ValuePrompt -Prompt "Phone" -DefaultValue ""
    $personalProfile.Address = Read-ValuePrompt -Prompt "Address" -DefaultValue ""
    $personalProfile.DateOfBirth = Read-ValuePrompt -Prompt "Date of birth (YYYY-MM-DD)" -DefaultValue ""
    $personalProfile.PlaceOfBirth = Read-ValuePrompt -Prompt "Place of birth" -DefaultValue ""
    $personalProfile.Nationality = Read-ValuePrompt -Prompt "Nationality" -DefaultValue ""
    $personalProfile.Occupation = Read-ValuePrompt -Prompt "Occupation" -DefaultValue ""
    $personalProfile.Specialization = Read-ValuePrompt -Prompt "Specialization" -DefaultValue ""
    $personalProfile.HealthInsuranceNumber = Read-ValuePrompt -Prompt "Health insurance number" -DefaultValue ""
    $personalProfile.PensionNumber = Read-ValuePrompt -Prompt "Pension number" -DefaultValue ""
    $personalProfile.TaxId = Read-ValuePrompt -Prompt "Tax ID / national ID" -DefaultValue ""
    $personalProfile.Bank = Read-ValuePrompt -Prompt "Bank name" -DefaultValue ""
    $personalProfile.AccountHolder = Read-ValuePrompt -Prompt "Account holder" -DefaultValue $(if ($personalProfile.FullName) { $personalProfile.FullName } else { "" })
    $personalProfile.IBAN = Read-ValuePrompt -Prompt "IBAN" -DefaultValue ""
    $personalProfile.BIC = Read-ValuePrompt -Prompt "BIC" -DefaultValue ""
    $personalProfile.FormNotes = Read-ValuePrompt -Prompt "Form notes" -DefaultValue ""
}

$settingsObject = [ordered]@{
    telegram = [ordered]@{
        botToken = $botToken
        defaultChatId = $defaultChatId
        startupChatId = $startupChatId
    }
    llm = [ordered]@{
        openRouterApiKey = $openRouterApiKey
        primaryModel = $currentSettings.LLM.PrimaryModel
        secondaryModel = $currentSettings.LLM.SecondaryModel
        reasoningEffort = $currentSettings.LLM.ReasoningEffort
        responseLanguage = $responseLanguage
    }
    opencode = [ordered]@{
        apiKey = $openCodeApiKey
        serverPassword = $serverPassword
        host = $currentSettings.OpenCode.Host
        port = $currentSettings.OpenCode.Port
        command = $opencodeCommand
        configPath = $openCodeConfigPath
        defaultModel = $currentSettings.OpenCode.DefaultModel
    }
    browser = [ordered]@{
        chromeExecutable = $chromeExecutable
        chromeProfileDir = $chromeProfileDir
        playwrightProfileDir = $playwrightProfileInput
        locale = $currentSettings.Browser.Locale
        timezone = $currentSettings.Browser.Timezone
    }
    paths = [ordered]@{
        downloadsDir = $downloadsDir
        personalDataFile = $personalDataPath
    }
}

Save-JsonFile -Path $settingsLocal -Data $settingsObject
Write-Host "[Setup] Updated config/settings.json" -ForegroundColor Green

if (Test-Path $opencodeExample) {
    $copied = Sync-OpenCodeConfigTemplate -TemplatePath $opencodeExample -ConfiguredPath $openCodeConfigPath
    if ($copied) {
        Write-Host "[Setup] Copied OpenCode user config template to $openCodeConfigPath" -ForegroundColor Green
        if ($openCodeConfigPath -ne $defaultOpenCodeConfigPath) {
            Write-Host "[Setup] Synced canonical OpenCode config: $defaultOpenCodeConfigPath" -ForegroundColor Green
        }
    }
}

Write-PersonalDataFile -Path $personalDataPath -Profile $personalProfile
Write-Host "[Setup] Updated PERSONAL DATA.md" -ForegroundColor Green

if (-not $SkipNetworkChecks) {
    Write-Host ""
    Write-Host "Step 5: Connectivity checks" -ForegroundColor Green

    $telegramTokenOk = Test-TelegramBotToken -BotToken $botToken
    Write-Host $(if ($telegramTokenOk) { "[Check] Telegram bot token is valid." } else { "[Check] Telegram bot token validation failed." }) -ForegroundColor $(if ($telegramTokenOk) { "Green" } else { "Red" })

    $telegramChatOk = Test-TelegramChatAccess -BotToken $botToken -ChatId $startupChatId
    Write-Host $(if ($telegramChatOk) { "[Check] Telegram startup chat is reachable." } else { "[Check] Telegram startup chat check failed. Make sure you started a chat with the bot and the chat ID is correct." }) -ForegroundColor $(if ($telegramChatOk) { "Green" } else { "Yellow" })

    $openRouterOk = Test-OpenRouterKey -ApiKey $openRouterApiKey
    Write-Host $(if ($openRouterOk) { "[Check] OpenRouter API key is valid." } else { "[Check] OpenRouter API key validation failed." }) -ForegroundColor $(if ($openRouterOk) { "Green" } else { "Red" })
}

Write-Host ""
Write-Host "Setup complete." -ForegroundColor Green
Write-Host "What was done:" -ForegroundColor Cyan
Write-Host "- Created or verified archives and profile folders."
Write-Host "- Installed or checked OpenCode and Playwright dependencies."
Write-Host "- Wrote config/settings.json with your local values."
Write-Host "- Updated PERSONAL DATA.md with your local information."
Write-Host "- Copied the OpenCode user config template."
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Green
Write-Host "1. Start the bot with .\RunBot.bat"
Write-Host "2. Send /start in Telegram"
Write-Host "3. Send /doctor to verify the runtime end-to-end"
