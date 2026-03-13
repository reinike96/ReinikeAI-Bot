param (
    [Parameter(Mandatory = $true)]
    [ValidateSet("Screenshot", "GetContent", "Download", "SearchGoogle", "GetScreenshot")]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [string]$Url,

    [Parameter(Mandatory = $false)]
    [string]$Out
)

$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
. (Join-Path $projectRoot "config\Load-BotConfig.ps1")
$botConfig = Import-BotSettings -ProjectRoot $projectRoot

function Resolve-ExecutablePath {
    param([string[]]$Candidates)

    foreach ($candidate in $Candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        try {
            $cmd = Get-Command $candidate -ErrorAction Stop | Select-Object -First 1
            if ($cmd -and -not [string]::IsNullOrWhiteSpace($cmd.Source)) {
                return $cmd.Source
            }
        }
        catch {}
    }

    return $null
}

# Alias GetScreenshot to Screenshot
if ($Action -eq "GetScreenshot") {
    $Action = "Screenshot"
}

# Redirect Google Search URLs to SearchGoogle action
if ($Url -like "*google.com/search?q=*") {
    $parts = $Url -split "q="
    $query = $parts[1].Split("&")[0]
    $Url = [uri]::UnescapeDataString($query)
    $Action = "SearchGoogle"
    Write-Host "[Playwright] Redirecting Google URL to SearchGoogle..." -ForegroundColor Yellow
}

# Handle missing -Out with a default path
if (($Action -eq "Screenshot" -or $Action -eq "SearchGoogle" -or $Action -eq "Download") -and -not $Out) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $Out = Join-Path $botConfig.Paths.ArchivesDir "browser_output_$timestamp.png"
    Write-Host "[Playwright] Missing -Out parameter. Using default: $Out" -ForegroundColor Yellow
}

if ($Out) {
    if (-not [System.IO.Path]::IsPathRooted($Out)) {
        $Out = Join-Path $projectRoot $Out
    }

    if ($Action -eq "Download") {
        New-Item -ItemType Directory -Force -Path $Out | Out-Null
    }
    else {
        $outDir = Split-Path -Parent $Out
        if (-not [string]::IsNullOrWhiteSpace($outDir)) {
            New-Item -ItemType Directory -Force -Path $outDir | Out-Null
        }
    }
}

Write-Host "[Playwright] Executing $Action on $Url" -ForegroundColor Cyan

$env:CHROME_EXECUTABLE = $botConfig.Browser.ChromeExecutable
$env:CHROME_PROFILE_DIR = $botConfig.Browser.ChromeProfileDir
$env:PLAYWRIGHT_PROFILE_DIR = $botConfig.Browser.PlaywrightProfileDir
$env:BROWSER_LOCALE = $botConfig.Browser.Locale
$env:BROWSER_TIMEZONE = $botConfig.Browser.Timezone
$env:BOT_PROJECT_ROOT = $projectRoot
$nodeExe = Resolve-ExecutablePath -Candidates @("node.exe", "node")
$pythonExe = Resolve-ExecutablePath -Candidates @("python.exe", "python", "py.exe", "py")

# Try JavaScript (Chromium with Chrome profile) first
$jsScript = Join-Path $scriptDir "browser-helper.js"
if (-not $nodeExe) {
    Write-Host "[Playwright] Node.js executable not found." -ForegroundColor Red
    $LASTEXITCODE = 1
}
elseif ($null -ne $Out) {
    & $nodeExe "$jsScript" "$Action" "$Url" "$Out"
}
else {
    & $nodeExe "$jsScript" "$Action" "$Url"
}

# If failed, try Python (Stealth mode)
if ($LASTEXITCODE -ne 0) {
    Write-Host "[Playwright] JavaScript failed. Trying Stealth mode (Python)..." -ForegroundColor Yellow
    
    $pythonScript = Join-Path $scriptDir "browser_helper.py"
    if (-not $pythonExe) {
        Write-Host "[Playwright] Python executable not found." -ForegroundColor Red
        $LASTEXITCODE = 1
    }
    elseif ($pythonExe -like "*\\py.exe" -or $pythonExe -like "*\\py") {
        if ($null -ne $Out) {
            & $pythonExe -3 "$pythonScript" "$Action" "$Url" "$Out"
        }
        else {
            & $pythonExe -3 "$pythonScript" "$Action" "$Url"
        }
    }
    elseif ($null -ne $Out) {
        & $pythonExe "$pythonScript" "$Action" "$Url" "$Out"
    }
    else {
        & $pythonExe "$pythonScript" "$Action" "$Url"
    }
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Playwright execution failed in both modes."
        exit $LASTEXITCODE
    }
}
