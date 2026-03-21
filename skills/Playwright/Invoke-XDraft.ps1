param(
    [Parameter(Mandatory = $false)]
    [Alias("Text")]
    [string]$TaskText = "",

    [Parameter(Mandatory = $false)]
    [string]$TaskFile = ""
)

$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
. (Join-Path $projectRoot "config\Load-BotConfig.ps1")
$botConfig = Import-BotSettings -ProjectRoot $projectRoot

function Get-XPostContent {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }

    $stopMarkers = '(?:instructions:|instrucciones:|steps:|pasos:|navigate to|ve a x|go to x|go to twitter|si x|if x|important:|importante:|\[login_required\])'
    $contentHeaders = '(?:exactly this:|contenido del post(?:\s*\([^)]*\))?(?:\s+es)?:|texto del post(?:\s*\([^)]*\))?:|este es el post:|this is the post:)'
    $patterns = @(
        "(?s)$contentHeaders\s*---\s*(?<body>.+?)\s*---",
        '(?s)---\s*(?<body>.+?)\s*---',
        "(?s)$contentHeaders\s*(?<body>.+?)(?:\n\s*$stopMarkers|$)"
    )

    foreach ($pattern in $patterns) {
        if ($Text -match $pattern) {
            $candidate = $Matches["body"].Trim()
            if (-not [string]::IsNullOrWhiteSpace($candidate) -and -not (Test-LooksLikeXMetaText -Text $candidate)) {
                return $candidate
            }
        }
    }

    return ""
}

function Test-LooksLikeXMetaText {
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
        'detente y usa',
        'detente y marca',
        'deja el botón',
        'post button visible',
        'create a thread',
        'no publiques',
        'do not publish'
    )

    $hits = 0
    foreach ($pattern in $metaPatterns) {
        if ($sample -match $pattern) {
            $hits++
        }
    }

    return ($hits -ge 2)
}

function Get-XDraftMode {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return "single"
    }

    $normalized = $Text.ToLowerInvariant()
    if ($normalized -match '\bthread\b|hilo|multi-post|multiple posts|serie de posts') {
        return "thread"
    }

    return "single"
}

function Get-TextElementCount {
    param([string]$Text)

    if ($null -eq $Text) {
        return 0
    }

    return ([System.Globalization.StringInfo]::new($Text)).LengthInTextElements
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
    throw "X task text is empty."
}

$postContent = Get-XPostContent -Text $effectiveTaskText
if ([string]::IsNullOrWhiteSpace($postContent)) {
    $postContent = $effectiveTaskText.Trim()
}
if ([string]::IsNullOrWhiteSpace($postContent)) {
    throw "Could not extract the X post content from the task."
}

$draftMode = Get-XDraftMode -Text $effectiveTaskText
$characterCount = Get-TextElementCount -Text $postContent
if ($draftMode -ne "thread" -and $characterCount -gt 280) {
    throw "X post content is $characterCount characters long. A single X post must be 280 characters or fewer. Ask for a shorter post or explicitly request a thread."
}

$archivesDir = $botConfig.Paths.ArchivesDir
New-Item -ItemType Directory -Force -Path $archivesDir | Out-Null

$contentPath = Join-Path $archivesDir "x-post-content.txt"
$statePath = Join-Path $archivesDir "x-draft-state.json"
$screenshotPath = Join-Path $archivesDir "x-post-draft.png"
$nodeScript = Join-Path $scriptDir "x-post.js"
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
$env:X_DRAFT_MODE = $draftMode
$env:BOT_PROJECT_ROOT = $projectRoot

& $nodeExe $nodeScript --content $contentPath --state $statePath --screenshot $screenshotPath --port "$($botConfig.Browser.DebugPort)"
if ($LASTEXITCODE -ne 0) {
    throw "X draft helper failed with exit code $LASTEXITCODE."
}
