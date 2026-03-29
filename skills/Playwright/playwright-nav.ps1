param (
    [Parameter(Mandatory = $true)]
    [ValidateSet("Screenshot", "GetContent", "Download", "SearchGoogle", "GetScreenshot", "GoogleTopResultsScreenshots", "KeepOpen")]
    [string]$Action,

    [Parameter(Mandatory = $true)]
    [string]$Url,

    [Parameter(Mandatory = $false)]
    [string]$Out,
    
    [Parameter(Mandatory = $false)]
    [switch]$Headless
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

        if (Test-Path $candidate) {
            return (Resolve-Path $candidate).Path
        }
    }

    foreach ($candidate in $Candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        try {
            $whereResult = & where.exe $candidate 2>$null
            if ($LASTEXITCODE -eq 0) {
                $resolved = @($whereResult | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) | Select-Object -First 1
                if ($resolved -and (Test-Path $resolved)) {
                    return $resolved
                }
            }
        }
        catch {}
    }

    $fallbackPaths = @()
    foreach ($candidate in $Candidates) {
        switch -Regex ($candidate.ToLowerInvariant()) {
            '^node(\.exe)?$' {
                $fallbackPaths += @(
                    'C:\Program Files\nodejs\node.exe',
                    (Join-Path ${env:ProgramFiles(x86)} 'nodejs\node.exe')
                )
            }
            '^python(\.exe)?$' {
                $fallbackPaths += @(
                    'C:\Python313\python.exe',
                    'C:\Python312\python.exe',
                    'C:\Python311\python.exe',
                    (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python313\python.exe'),
                    (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'),
                    (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python311\python.exe')
                )
            }
            '^py(\.exe)?$' {
                $fallbackPaths += @(
                    'C:\Windows\py.exe',
                    'C:\Windows\System32\py.exe'
                )
            }
        }
    }

    foreach ($path in @($fallbackPaths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        if (Test-Path $path) {
            return $path
        }
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
elseif ($Action -eq "GoogleTopResultsScreenshots" -and -not $Out) {
    $Out = $botConfig.Paths.ArchivesDir
    Write-Host "[Playwright] Missing -Out parameter. Using default directory: $Out" -ForegroundColor Yellow
}

if ($Out) {
    if (-not [System.IO.Path]::IsPathRooted($Out)) {
        $Out = Join-Path $projectRoot $Out
    }

    if ($Action -eq "Download" -or $Action -eq "GoogleTopResultsScreenshots") {
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
if ($Headless) {
    Write-Host "[Playwright] Running in HEADLESS mode" -ForegroundColor Yellow
}

$env:CHROME_EXECUTABLE = $botConfig.Browser.ChromeExecutable
$env:CHROME_PROFILE_DIR = $botConfig.Browser.ChromeProfileDir
$env:PLAYWRIGHT_PROFILE_DIR = $botConfig.Browser.PlaywrightProfileDir
$env:BROWSER_LOCALE = $botConfig.Browser.Locale
$env:BROWSER_TIMEZONE = $botConfig.Browser.Timezone
$env:BROWSER_DEBUG_PORT = "$($botConfig.Browser.DebugPort)"
$env:BROWSER_KEEP_OPEN = if ([bool]$botConfig.Browser.KeepOpen) { "true" } else { "false" }
$env:PYTHONIOENCODING = "utf-8"
$env:PYTHONUTF8 = "1"
$env:BOT_PROJECT_ROOT = $projectRoot
$nodeExe = Resolve-ExecutablePath -Candidates @("node.exe", "node")
$pythonExe = Resolve-ExecutablePath -Candidates @("python.exe", "python", "py.exe", "py")

$headlessArg = if ($Headless) { "true" } else { "false" }

# Try JavaScript (Chromium with Chrome profile) first
$jsScript = Join-Path $scriptDir "browser-helper.js"
if (-not $nodeExe) {
    Write-Host "[Playwright] Node.js executable not found." -ForegroundColor Red
    $LASTEXITCODE = 1
}
elseif ($null -ne $Out) {
    & $nodeExe "$jsScript" "$Action" "$Url" "$Out" "$headlessArg"
}
else {
    & $nodeExe "$jsScript" "$Action" "$Url" "" "$headlessArg"
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
            & $pythonExe -3 "$pythonScript" "$Action" "$Url" "$Out" "$headlessArg"
        }
        else {
            & $pythonExe -3 "$pythonScript" "$Action" "$Url" "" "$headlessArg"
        }
    }
    elseif ($null -ne $Out) {
        & $pythonExe "$pythonScript" "$Action" "$Url" "$Out" "$headlessArg"
    }
    else {
        & $pythonExe "$pythonScript" "$Action" "$Url" "" "$headlessArg"
    }
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Playwright execution failed in both modes."
        exit $LASTEXITCODE
    }
}
