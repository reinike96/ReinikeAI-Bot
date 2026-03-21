param(
    [Parameter(Mandatory = $false)]
    [string]$StartUrl = "about:blank"
)

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $projectRoot "config\Load-BotConfig.ps1")
$botConfig = Import-BotSettings -ProjectRoot $projectRoot

function Resolve-ChromeLaunchProfile {
    param([string]$ConfiguredPath)

    if ([string]::IsNullOrWhiteSpace($ConfiguredPath)) {
        throw "browser.chromeProfileDir is empty."
    }

    $normalized = $ConfiguredPath.TrimEnd('\', '/')
    $baseName = Split-Path -Leaf $normalized
    $parentDir = Split-Path -Parent $normalized
    $grandParentName = Split-Path -Leaf $parentDir

    if ($grandParentName -and $grandParentName.ToLowerInvariant() -eq "user data" -and $baseName) {
        return [PSCustomObject]@{
            UserDataDir      = $parentDir
            ProfileDirectory = $baseName
        }
    }

    return [PSCustomObject]@{
        UserDataDir      = $normalized
        ProfileDirectory = ""
    }
}

function Test-DebugPortReady {
    param([int]$Port)

    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/json/version" -UseBasicParsing -TimeoutSec 2
        return ($response.StatusCode -eq 200)
    }
    catch {
        return $false
    }
}

$chromeExecutable = $botConfig.Browser.ChromeExecutable
if (-not (Test-Path $chromeExecutable)) {
    throw "Chrome executable not found: $chromeExecutable"
}

$launchProfile = Resolve-ChromeLaunchProfile -ConfiguredPath $botConfig.Browser.ChromeProfileDir
New-Item -ItemType Directory -Force -Path $launchProfile.UserDataDir | Out-Null

$debugPort = [int]$botConfig.Browser.DebugPort
if (Test-DebugPortReady -Port $debugPort) {
    Write-Host "[BotChrome] Chrome is already exposing the debugger on port $debugPort." -ForegroundColor Green
    exit 0
}

$args = @(
    "--remote-debugging-port=$debugPort",
    "--user-data-dir=""$($launchProfile.UserDataDir)""",
    "--no-first-run",
    "--no-default-browser-check",
    "--new-window"
)

if (-not [string]::IsNullOrWhiteSpace($launchProfile.ProfileDirectory)) {
    $args += "--profile-directory=""$($launchProfile.ProfileDirectory)"""
}

if (-not [string]::IsNullOrWhiteSpace($StartUrl)) {
    $args += $StartUrl
}

Start-Process -FilePath $chromeExecutable -ArgumentList ($args -join ' ') | Out-Null
Write-Host "[BotChrome] Chrome launched with remote debugging on port $debugPort." -ForegroundColor Green
Write-Host "[BotChrome] Profile: $($botConfig.Browser.ChromeProfileDir)" -ForegroundColor Cyan
