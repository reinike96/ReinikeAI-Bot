param(
    [Parameter(Mandatory = $false)]
    [string]$TaskText = "",

    [Parameter(Mandatory = $false)]
    [string]$TaskFile = ""
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

    foreach ($path in @(
        'C:\Program Files\nodejs\node.exe',
        'C:\Program Files (x86)\nodejs\node.exe'
    )) {
        if (Test-Path $path) {
            return $path
        }
    }

    return $null
}

function Read-Utf8TextFile {
    param([string]$Path)

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    return [System.IO.File]::ReadAllText($Path, $utf8)
}

function Write-Utf8TextFile {
    param(
        [string]$Path,
        [string]$Text
    )

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Text, $utf8)
}

$effectiveTaskText = $TaskText
if (-not [string]::IsNullOrWhiteSpace($TaskFile)) {
    if (-not (Test-Path $TaskFile)) {
        throw "Task file not found: $TaskFile"
    }

    $effectiveTaskText = Read-Utf8TextFile -Path $TaskFile
}

if ([string]::IsNullOrWhiteSpace($effectiveTaskText)) {
    throw "Interactive web task text is empty."
}

$archivesDir = $botConfig.Paths.ArchivesDir
New-Item -ItemType Directory -Force -Path $archivesDir | Out-Null

$taskCopyPath = Join-Path $archivesDir "web-interactive-task.txt"
$statePath = Join-Path $archivesDir "web-interactive-state.json"
$screenshotPath = Join-Path $archivesDir "web-interactive.png"
$nodeScript = Join-Path $scriptDir "web-interactive.js"
$nodeExe = Resolve-ExecutablePath -Candidates @("node.exe", "node")

if (-not $nodeExe) {
    throw "Node.js executable not found."
}

Write-Utf8TextFile -Path $taskCopyPath -Text $effectiveTaskText

$env:CHROME_EXECUTABLE = $botConfig.Browser.ChromeExecutable
$env:CHROME_PROFILE_DIR = $botConfig.Browser.ChromeProfileDir
$env:PLAYWRIGHT_PROFILE_DIR = $botConfig.Browser.PlaywrightProfileDir
$env:BROWSER_LOCALE = $botConfig.Browser.Locale
$env:BROWSER_TIMEZONE = $botConfig.Browser.Timezone
$env:BROWSER_DEBUG_PORT = "$($botConfig.Browser.DebugPort)"
$env:BROWSER_KEEP_OPEN = if ([bool]$botConfig.Browser.KeepOpen) { "true" } else { "false" }
$env:BOT_PROJECT_ROOT = $projectRoot

& $nodeExe $nodeScript --task $taskCopyPath --state $statePath --screenshot $screenshotPath --port "$($botConfig.Browser.DebugPort)"
if ($LASTEXITCODE -ne 0) {
    throw "Interactive web helper failed with exit code $LASTEXITCODE."
}
