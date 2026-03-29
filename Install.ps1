param(
    [switch]$SkipNetworkChecks
)

$ErrorActionPreference = "Stop"

trap {
    Write-Host ""
    Write-Host "[Setup] A fatal error occurred:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "The installer stopped before completion." -ForegroundColor Yellow
    Write-Host "Press Enter to close this window." -ForegroundColor Yellow
    Read-Host | Out-Null
    break
}

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$configDir = Join-Path $projectRoot "config"
$archivesDir = Join-Path $projectRoot "archives"
$profilesDir = Join-Path $projectRoot "profiles"
$playwrightProfileDir = Join-Path $profilesDir "playwright"
$externalDir = Join-Path $projectRoot "external"
$externalMcpDir = Join-Path $externalDir "mcp"
$settingsExample = Join-Path $configDir "settings.example.json"
$settingsLocal = Join-Path $configDir "settings.json"
$opencodeExample = Join-Path $configDir "opencode.example.json"
$packageJsonPath = Join-Path $projectRoot "package.json"
$personalDataPath = Join-Path $projectRoot "PERSONAL DATA.local.md"
$defaultOpenCodeConfigPath = Join-Path $env:USERPROFILE ".config\opencode\opencode.json"

. (Join-Path $projectRoot "config\Load-BotConfig.ps1")
. (Join-Path $projectRoot "runtime\CapabilityPacks.ps1")
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

function Test-UsablePathString {
    param([string]$PathValue)

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $false
    }

    if ($PathValue -match '<|>|YOUR_USER|PASTE_') {
        return $false
    }

    try {
        [void][System.IO.Path]::GetFullPath($PathValue)
        return $true
    }
    catch {
        return $false
    }
}

function Get-PythonCommandName {
    if (Test-CommandAvailable -Name "python") { return "python" }
    if (Test-CommandAvailable -Name "py") { return "py" }
    return $null
}

function Get-DetectedPythonCommandPath {
    $pythonInfo = Get-Command "python" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pythonInfo -and -not [string]::IsNullOrWhiteSpace($pythonInfo.Source)) {
        return $pythonInfo.Source
    }

    $pyInfo = Get-Command "py" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pyInfo -and -not [string]::IsNullOrWhiteSpace($pyInfo.Source)) {
        return $pyInfo.Source
    }

    return $null
}

function Get-NpmCommandPath {
    param([string]$CommandName)

    $npmBin = Join-Path $env:APPDATA "npm"
    $cmdPath = Join-Path $npmBin "$CommandName.cmd"
    if (Test-Path $cmdPath) {
        return $cmdPath
    }

    return $CommandName
}

function Ensure-GitRepository {
    param(
        [string]$RepositoryUrl,
        [string]$TargetPath
    )

    if (-not (Test-CommandAvailable -Name "git")) {
        throw "git is required to clone $RepositoryUrl."
    }

    if (Test-Path (Join-Path $TargetPath ".git")) {
        Push-Location $TargetPath
        try {
            & git pull --ff-only
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to update repository at $TargetPath."
            }
        }
        finally {
            Pop-Location
        }
    }
    else {
        Ensure-Directory -Path (Split-Path -Parent $TargetPath)
        & git clone $RepositoryUrl $TargetPath
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to clone $RepositoryUrl."
        }
    }
}

function Set-OpenCodeMcpServerDefinition {
    param(
        [object]$ConfigJson,
        [string]$ServerName,
        [object]$Definition
    )

    if (-not $ConfigJson.PSObject.Properties["mcp"]) {
        $ConfigJson | Add-Member -NotePropertyName "mcp" -NotePropertyValue ([pscustomobject]@{})
    }

    $existing = $ConfigJson.mcp.PSObject.Properties[$ServerName]
    if ($existing) {
        $existing.Value = $Definition
    }
    else {
        $ConfigJson.mcp | Add-Member -NotePropertyName $ServerName -NotePropertyValue $Definition
    }
}

function Remove-OpenCodeMcpServerDefinition {
    param(
        [object]$ConfigJson,
        [string]$ServerName
    )

    if ($ConfigJson.PSObject.Properties["mcp"]) {
        $ConfigJson.mcp.PSObject.Properties.Remove($ServerName)
    }
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

    $jsonText = $Data | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($Path, $jsonText, (New-Object System.Text.UTF8Encoding($false)))
}

function Install-DeepResearchPack {
    param(
        [string]$ProjectRoot,
        [string]$PythonCommand = ""
    )

    $vendorRoot = Join-Path $ProjectRoot "vendor\deep-research-skills\opencode"
    $skillsSource = Join-Path $vendorRoot "skills"
    $agentsSource = Join-Path $vendorRoot "agents"

    if (-not (Test-Path $skillsSource) -or -not (Test-Path $agentsSource)) {
        throw "Deep Research vendor files are missing from the repository."
    }

    $claudeSkillsDir = Join-Path $env:USERPROFILE ".claude\skills"
    $openCodeAgentsDir = Join-Path $env:USERPROFILE ".config\opencode\agents"
    $openCodeModulesDir = Join-Path $openCodeAgentsDir "web-search-modules"

    Ensure-Directory -Path $claudeSkillsDir
    Ensure-Directory -Path $openCodeAgentsDir
    Ensure-Directory -Path $openCodeModulesDir

    foreach ($skillDirName in @("research", "research-add-items", "research-add-fields", "research-deep", "research-report")) {
        $source = Join-Path $skillsSource $skillDirName
        $destination = Join-Path $claudeSkillsDir $skillDirName
        if (Test-Path $destination) {
            Remove-Item -Path $destination -Recurse -Force
        }
        Copy-Item -Path $source -Destination $destination -Recurse -Force
    }

    Copy-Item -Path (Join-Path $agentsSource "web-search.md") -Destination (Join-Path $openCodeAgentsDir "web-search.md") -Force
    Copy-Item -Path (Join-Path $agentsSource "web-search-modules\*") -Destination $openCodeModulesDir -Recurse -Force

    $pipInstalled = $false
    $resolvedPython = $PythonCommand
    if ([string]::IsNullOrWhiteSpace($resolvedPython)) {
        $resolvedPython = Get-PythonCommandName
    }
    if (-not [string]::IsNullOrWhiteSpace($resolvedPython)) {
        try {
            & $resolvedPython -m pip install pyyaml
            $pipInstalled = ($LASTEXITCODE -eq 0)
        }
        catch {
            $pipInstalled = $false
        }
    }

    return [PSCustomObject]@{
        Success = $true
        Message = "Deep Research pack installed into ~/.claude/skills and ~/.config/opencode/agents. Set OPENCODE_ENABLE_EXA=1 before using web search in OpenCode."
        PyYamlInstalled = $pipInstalled
    }
}

function Update-OpenCodeAgentPackToggles {
    param(
        [string]$ConfigPath,
        [hashtable]$PackSelections
    )

    if (-not (Test-Path $ConfigPath)) {
        return $false
    }

    $json = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
    $registry = Get-CapabilityPackRegistry

    foreach ($pack in $registry) {
        $enabled = [bool]$PackSelections[$pack.SettingKey]
        $agentProp = $json.agent.PSObject.Properties[$pack.Agent]
        if (-not $agentProp) {
            continue
        }

        foreach ($flag in $pack.ToolFlags) {
            $toolProp = $agentProp.Value.tools.PSObject.Properties[$flag]
            if ($toolProp) {
                $toolProp.Value = $enabled
            }
        }
    }

    $jsonText = $json | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($ConfigPath, $jsonText, (New-Object System.Text.UTF8Encoding($false)))
    return $true
}

function Install-CapabilityPack {
    param(
        [string]$PackName
    )

    Ensure-Directory -Path $externalDir
    Ensure-Directory -Path $externalMcpDir

    switch ($PackName) {
        "browser" {
            $ok = Install-PlaywrightNodeDependencies -ProjectRoot $projectRoot
            return [PSCustomObject]@{
                Success = $ok
                Message = if ($ok) { "Browser pack prepared with local Playwright dependencies." } else { "Browser pack setup failed." }
                McpDefinitions = @{}
            }
        }
        "docs" {
            $pythonCmd = Get-PythonCommandName
            if (-not $pythonCmd) {
                throw "Python is required for the docs pack."
            }
            $pdfRepo = Join-Path $externalMcpDir "file-converter-mcp"
            $wordRepo = Join-Path $externalMcpDir "Office-Word-MCP-Server"

            Ensure-GitRepository -RepositoryUrl "https://github.com/hannesrudolph/file-converter-mcp.git" -TargetPath $pdfRepo
            Push-Location $pdfRepo
            try {
                & $pythonCmd -m pip install -e .
                if ($LASTEXITCODE -ne 0) { throw "pip install failed for the PDF/file converter MCP." }
            }
            finally {
                Pop-Location
            }

            Ensure-GitRepository -RepositoryUrl "https://github.com/GongRzhe/Office-Word-MCP-Server.git" -TargetPath $wordRepo
            Push-Location $wordRepo
            try {
                & $pythonCmd -m pip install -r requirements.txt
                if ($LASTEXITCODE -ne 0) { throw "pip install failed for the Word MCP." }
            }
            finally {
                Pop-Location
            }

            return [PSCustomObject]@{
                Success = $true
                Message = "Docs pack installed."
                McpDefinitions = @{
                    file_converter = [pscustomobject]@{ type = "local"; enabled = $true; command = @($pythonCmd, "-X", "utf8", (Join-Path $pdfRepo "file_converter_server.py")) }
                    word_document = [pscustomobject]@{ type = "local"; enabled = $true; command = @($pythonCmd, "-X", "utf8", (Join-Path $wordRepo "word_mcp_server.py")) }
                }
            }
        }
        "sheets" {
            & npm install -g @guillehr2/excel-mcp-server
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to install the sheets pack."
            }
            return [PSCustomObject]@{
                Success = $true
                Message = "Sheets pack installed."
                McpDefinitions = @{
                    excel_master = [pscustomobject]@{ type = "local"; enabled = $true; command = @(Get-NpmCommandPath -CommandName "excel-mcp-server") }
                }
            }
        }
        "computer" {
            & npm install -g mcp-control
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to install the computer pack."
            }
            return [PSCustomObject]@{
                Success = $true
                Message = "Computer pack installed."
                McpDefinitions = @{
                    computer_control = [pscustomobject]@{ type = "local"; enabled = $true; command = @(Get-NpmCommandPath -CommandName "mcp-control") }
                }
            }
        }
        "social" {
            & npm install -g playwriter
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to install the social pack."
            }
            return [PSCustomObject]@{
                Success = $true
                Message = "Social pack installed. Some workflows may still require manual browser-extension or session setup."
                McpDefinitions = @{
                    playwriter = [pscustomobject]@{ type = "local"; enabled = $true; command = @(Get-NpmCommandPath -CommandName "playwriter") }
                }
            }
        }
        "research" {
            $pythonCmd = Get-PythonCommandName
            $result = Install-DeepResearchPack -ProjectRoot $projectRoot -PythonCommand $pythonCmd
            return [PSCustomObject]@{
                Success = $result.Success
                Message = $result.Message
                PyYamlInstalled = $result.PyYamlInstalled
                McpDefinitions = @{}
            }
        }
        default {
            throw "Unknown capability pack: $PackName"
        }
    }
}

function Sync-InstalledCapabilityPacks {
    param(
        [string]$ConfigPath,
        [hashtable]$PackSelections,
        [hashtable]$InstallResults
    )

    if (-not (Test-Path $ConfigPath)) {
        return $false
    }

    $json = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json

    foreach ($packName in $PackSelections.Keys) {
        $enabled = [bool]$PackSelections[$packName]
        $installResult = $InstallResults[$packName]

        switch ($packName) {
            "docs" {
                if ($enabled -and $installResult -and $installResult.Success) {
                    Set-OpenCodeMcpServerDefinition -ConfigJson $json -ServerName "file_converter" -Definition $installResult.McpDefinitions.file_converter
                    Set-OpenCodeMcpServerDefinition -ConfigJson $json -ServerName "word_document" -Definition $installResult.McpDefinitions.word_document
                }
                else {
                    Remove-OpenCodeMcpServerDefinition -ConfigJson $json -ServerName "file_converter"
                    Remove-OpenCodeMcpServerDefinition -ConfigJson $json -ServerName "word_document"
                }
            }
            "sheets" {
                if ($enabled -and $installResult -and $installResult.Success) {
                    Set-OpenCodeMcpServerDefinition -ConfigJson $json -ServerName "excel_master" -Definition $installResult.McpDefinitions.excel_master
                }
                else {
                    Remove-OpenCodeMcpServerDefinition -ConfigJson $json -ServerName "excel_master"
                }
            }
            "computer" {
                if ($enabled -and $installResult -and $installResult.Success) {
                    Set-OpenCodeMcpServerDefinition -ConfigJson $json -ServerName "computer_control" -Definition $installResult.McpDefinitions.computer_control
                }
                else {
                    Remove-OpenCodeMcpServerDefinition -ConfigJson $json -ServerName "computer_control"
                }
            }
            "social" {
                if ($enabled -and $installResult -and $installResult.Success) {
                    Set-OpenCodeMcpServerDefinition -ConfigJson $json -ServerName "playwriter" -Definition $installResult.McpDefinitions.playwriter
                }
                else {
                    Remove-OpenCodeMcpServerDefinition -ConfigJson $json -ServerName "playwriter"
                }
            }
        }
    }

    $jsonText = $json | ConvertTo-Json -Depth 25
    [System.IO.File]::WriteAllText($ConfigPath, $jsonText, (New-Object System.Text.UTF8Encoding($false)))
    return $true
}

function Sync-OpenCodeConfigTemplate {
    param(
        [string]$TemplatePath,
        [string]$ConfiguredPath
    )

    if (-not (Test-Path $TemplatePath)) {
        return $false
    }

    $canonicalPath = Join-Path $env:USERPROFILE ".config\opencode\opencode.json"
    Ensure-Directory -Path (Split-Path -Parent $canonicalPath)

    Copy-Item $TemplatePath $canonicalPath -Force
    $compatPath = Join-Path $env:USERPROFILE ".config\opencode\config.json"
    Copy-Item $TemplatePath $compatPath -Force
    if (-not [string]::IsNullOrWhiteSpace($ConfiguredPath) -and $ConfiguredPath -ne $canonicalPath -and $ConfiguredPath -ne $compatPath) {
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
$openCodeConfigPath = if (Test-UsablePathString -PathValue $currentSettings.OpenCode.ConfigPath) { $currentSettings.OpenCode.ConfigPath } else { $defaultOpenCodeConfigPath }
if ([System.IO.Path]::GetFileName($openCodeConfigPath) -ieq "opencode.json") {
    $openCodeConfigPath = Join-Path (Split-Path -Parent $openCodeConfigPath) "config.json"
}
Write-Host "[Setup] OpenCode user config path: $openCodeConfigPath" -ForegroundColor Green

Ensure-Directory -Path $playwrightProfileInput
Ensure-Directory -Path (Split-Path -Parent $openCodeConfigPath)

Write-Host ""
Write-Host "Step 4: Optional OpenCode capability packs" -ForegroundColor Green
$currentPackDefaults = @{
    browser = $true
    docs = $false
    sheets = $false
    computer = $false
    social = $false
    research = $false
}
if ($currentSettings.OpenCode -and $currentSettings.OpenCode.Packs) {
    if ($null -ne $currentSettings.OpenCode.Packs.Browser) { $currentPackDefaults.browser = [bool]$currentSettings.OpenCode.Packs.Browser }
    if ($null -ne $currentSettings.OpenCode.Packs.Docs) { $currentPackDefaults.docs = [bool]$currentSettings.OpenCode.Packs.Docs }
    if ($null -ne $currentSettings.OpenCode.Packs.Sheets) { $currentPackDefaults.sheets = [bool]$currentSettings.OpenCode.Packs.Sheets }
    if ($null -ne $currentSettings.OpenCode.Packs.Computer) { $currentPackDefaults.computer = [bool]$currentSettings.OpenCode.Packs.Computer }
    if ($null -ne $currentSettings.OpenCode.Packs.Social) { $currentPackDefaults.social = [bool]$currentSettings.OpenCode.Packs.Social }
    if ($null -ne $currentSettings.OpenCode.Packs.Research) { $currentPackDefaults.research = [bool]$currentSettings.OpenCode.Packs.Research }
}
$packSelections = @{
    browser = Read-BooleanAnswer -Prompt "Enable the browser pack (general browsing and screenshots)?" -Default $currentPackDefaults.browser
    docs = Read-BooleanAnswer -Prompt "Enable the docs pack (PDF and Word workflows)?" -Default $currentPackDefaults.docs
    sheets = Read-BooleanAnswer -Prompt "Enable the sheets pack (Excel and CSV workflows)?" -Default $currentPackDefaults.sheets
    computer = Read-BooleanAnswer -Prompt "Enable the computer pack (mouse, keyboard, desktop control)?" -Default $currentPackDefaults.computer
    social = Read-BooleanAnswer -Prompt "Enable the social pack (LinkedIn and X style workflows)?" -Default $currentPackDefaults.social
    research = Read-BooleanAnswer -Prompt "Enable the Deep Research pack (structured research workflows for OpenCode)?" -Default $currentPackDefaults.research
}
$packInstallResults = @{}
foreach ($packName in $packSelections.Keys) {
    if (-not [bool]$packSelections[$packName]) {
        continue
    }

    if (-not (Read-BooleanAnswer -Prompt "Install the $packName capability pack now?" -Default $true)) {
        continue
    }

    try {
        $packInstallResults[$packName] = Install-CapabilityPack -PackName $packName
        Write-Host "[Setup] $($packInstallResults[$packName].Message)" -ForegroundColor Green
    }
    catch {
        Write-Host "[Setup] Failed to install $packName pack: $($_.Exception.Message)" -ForegroundColor Yellow
        $packInstallResults[$packName] = [PSCustomObject]@{
            Success = $false
            Message = $_.Exception.Message
            McpDefinitions = @{}
        }
    }
}

Write-Host ""
Write-Host "Step 5: Personal data file" -ForegroundColor Green
$fillPersonalData = Read-BooleanAnswer -Prompt "Do you want to populate PERSONAL DATA.local.md now?" -Default $true

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
        authorizedChatIds = @($defaultChatId)
        authorizedUserIds = @()
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
        packs = [ordered]@{
            browser = [bool]$packSelections.browser
            docs = [bool]$packSelections.docs
            sheets = [bool]$packSelections.sheets
            computer = [bool]$packSelections.computer
            social = [bool]$packSelections.social
            research = [bool]$packSelections.research
        }
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
        Update-OpenCodeAgentPackToggles -ConfigPath $defaultOpenCodeConfigPath -PackSelections $packSelections | Out-Null
        if ($openCodeConfigPath -ne $defaultOpenCodeConfigPath) {
            Update-OpenCodeAgentPackToggles -ConfigPath $openCodeConfigPath -PackSelections $packSelections | Out-Null
        }
        Sync-InstalledCapabilityPacks -ConfigPath $defaultOpenCodeConfigPath -PackSelections $packSelections -InstallResults $packInstallResults | Out-Null
        if ($openCodeConfigPath -ne $defaultOpenCodeConfigPath) {
            Sync-InstalledCapabilityPacks -ConfigPath $openCodeConfigPath -PackSelections $packSelections -InstallResults $packInstallResults | Out-Null
        }
        Write-Host "[Setup] Copied OpenCode user config template to $openCodeConfigPath" -ForegroundColor Green
        if ($openCodeConfigPath -ne $defaultOpenCodeConfigPath) {
            Write-Host "[Setup] Synced canonical OpenCode config: $defaultOpenCodeConfigPath" -ForegroundColor Green
        }
        Write-Host "[Setup] Applied selected capability pack toggles and MCP definitions to the OpenCode config." -ForegroundColor Green
    }
}

Write-PersonalDataFile -Path $personalDataPath -Profile $personalProfile
Write-Host "[Setup] Updated PERSONAL DATA.local.md" -ForegroundColor Green

if (-not $SkipNetworkChecks) {
    Write-Host ""
    Write-Host "Step 6: Connectivity checks" -ForegroundColor Green

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
Write-Host "- Updated PERSONAL DATA.local.md with your local information."
Write-Host "- Copied the OpenCode user config template."
Write-Host "- Applied OpenCode capability pack toggles for the selected agents."
if ([bool]$packSelections.research) {
    Write-Host "- Installed the Deep Research pack into the local OpenCode skill and agent paths."
    Write-Host "- Remember to set OPENCODE_ENABLE_EXA=1 in the shell that runs OpenCode." -ForegroundColor Yellow
}
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Green
Write-Host "1. Start the bot with .\RunBot.bat"
Write-Host "2. Send /start in Telegram"
Write-Host "3. Send /doctor to verify the runtime end-to-end"
