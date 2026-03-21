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

function Get-LinkedInPostContent {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }

    $stopMarkers = '(?:instructions:|instrucciones:|steps:|pasos:|navigate to|ve a linkedin|go to linkedin|si linkedin|if linkedin|important:|importante:|\[login_required\])'
    $patterns = @(
        '(?s)(?:exactly this:|contenido del post(?: es)?:|texto del post:)\s*---\s*(?<body>.+?)\s*---',
        '(?s)---\s*(?<body>.+?)\s*---',
        "(?s)(?:exactly this:|contenido del post(?: es)?:|texto del post:|este es el post:|this is the post:)\s*(?<body>.+?)(?:\n\s*$stopMarkers|$)"
    )

    foreach ($pattern in $patterns) {
        if ($Text -match $pattern) {
            $candidate = $Matches["body"].Trim()
            if (-not [string]::IsNullOrWhiteSpace($candidate) -and -not (Test-LooksLikeLinkedInMetaText -Text $candidate)) {
                return $candidate
            }
        }
    }

    return ""
}

function Test-LooksLikeLinkedInMetaText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }

    $sample = $Text.Trim()
    if ($sample.Length -gt 800) {
        $sample = $sample.Substring(0, 800)
    }

    if ($sample -match '(?m)^\s*1\.\s+' -and $sample -match '(?m)^\s*2\.\s+') {
        return $true
    }

    $metaPatterns = @(
        'usa el agente',
        'use the .* route',
        '\[login_required\]',
        'haz clic',
        'click en',
        'verifica que',
        'detente y marca',
        'do not publish',
        'no publiques'
    )

    $hits = 0
    foreach ($pattern in $metaPatterns) {
        if ($sample -match $pattern) {
            $hits++
        }
    }

    return ($hits -ge 2)
}

function Get-LinkedInTaskMode {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return "compose"
    }

    $normalized = $Text.ToLowerInvariant()
    $composeSignals = $normalized -match 'write|escribe|paste|pega|type|typing|texto del post|contenido del post|post text|new post|start a post|publicaci|publication|draft|borrador|composer|editor'
    $captureSignals = $normalized -match 'screenshot|captura|capture|pantallazo|screen'

    if ($composeSignals) {
        return "compose"
    }

    if ($captureSignals) {
        return "capture"
    }

    return "compose"
}

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
    throw "LinkedIn task text is empty."
}

$mode = Get-LinkedInTaskMode -Text $effectiveTaskText
$postContent = ""
if ($mode -eq "compose") {
    $postContent = Get-LinkedInPostContent -Text $effectiveTaskText
    if ([string]::IsNullOrWhiteSpace($postContent)) {
        throw "Could not extract the LinkedIn post content from the task."
    }
}

$archivesDir = $botConfig.Paths.ArchivesDir
New-Item -ItemType Directory -Force -Path $archivesDir | Out-Null

$contentPath = Join-Path $archivesDir "linkedin-post-content.txt"
$statePath = Join-Path $archivesDir "linkedin-draft-state.json"
$screenshotPath = Join-Path $archivesDir "linkedin-post-draft.png"
$nodeScript = Join-Path $scriptDir "linkedin-post.js"
$nodeExe = Resolve-ExecutablePath -Candidates @("node.exe", "node")

if (-not $nodeExe) {
    throw "Node.js executable not found."
}

Write-Utf8TextFile -Path $contentPath -Text $postContent

$env:CHROME_EXECUTABLE = $botConfig.Browser.ChromeExecutable
$env:CHROME_PROFILE_DIR = $botConfig.Browser.ChromeProfileDir
$env:PLAYWRIGHT_PROFILE_DIR = $botConfig.Browser.PlaywrightProfileDir
$env:BROWSER_LOCALE = $botConfig.Browser.Locale
$env:BROWSER_TIMEZONE = $botConfig.Browser.Timezone
$env:BROWSER_DEBUG_PORT = "$($botConfig.Browser.DebugPort)"
$env:BROWSER_KEEP_OPEN = if ([bool]$botConfig.Browser.KeepOpen) { "true" } else { "false" }
$env:BOT_PROJECT_ROOT = $projectRoot

& $nodeExe $nodeScript --mode $mode --content $contentPath --state $statePath --screenshot $screenshotPath --port "$($botConfig.Browser.DebugPort)"
if ($LASTEXITCODE -ne 0) {
    throw "LinkedIn draft helper failed with exit code $LASTEXITCODE."
}
