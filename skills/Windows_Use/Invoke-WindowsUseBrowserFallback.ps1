param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Content", "Screenshot")]
    [string]$Mode,

    [Parameter(Mandatory = $true)]
    [string]$Url,

    [string]$Out = ""
)

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $projectRoot "config\Load-BotConfig.ps1")
$botConfig = Import-BotSettings -ProjectRoot $projectRoot

function Take-FallbackScreenshot {
    param([string]$FilePath)

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $screen = [System.Windows.Forms.Screen]::PrimaryScreen
    $bitmap = New-Object System.Drawing.Bitmap -ArgumentList $screen.Bounds.Width, $screen.Bounds.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($screen.Bounds.Left, $screen.Bounds.Top, 0, 0, $bitmap.Size)
    $bitmap.Save($FilePath, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bitmap.Dispose()
}

$windowsUseScript = Join-Path $PSScriptRoot "Invoke-WindowsUse.ps1"
if (-not (Test-Path $windowsUseScript)) {
    Write-Error "Windows-Use wrapper not found at $windowsUseScript"
    exit 1
}

switch ($Mode) {
    "Content" {
        $task = @"
Open the URL $Url in the configured browser.
Wait until the main page is visible.
If a safe cookie or consent popup blocks the page, dismiss it.
Extract the main visible text, labels, headings, and important controls from the current page.
Return plain text only. Do not summarize unless the page is too long; if it is too long, prioritize the most relevant visible content.
"@.Trim()

        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $windowsUseScript -Task $task
        exit $LASTEXITCODE
    }
    "Screenshot" {
        if ([string]::IsNullOrWhiteSpace($Out)) {
            $tempDir = Join-Path $env:TEMP "ReinikeBot"
            New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
            $Out = Join-Path $tempDir "windows_use_browser_fallback.png"
        }

        $outDir = Split-Path -Parent $Out
        if (-not [string]::IsNullOrWhiteSpace($outDir)) {
            New-Item -ItemType Directory -Force -Path $outDir | Out-Null
        }

        $task = @"
Open the URL $Url in the configured browser.
Wait until the target page is clearly visible.
If a safe cookie or consent popup blocks the page, dismiss it.
Maximize the browser window or otherwise make the target page as visible as possible.
When the page is ready and visible, stop without closing the browser.
"@.Trim()

        $result = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $windowsUseScript -Task $task 2>&1
        $exitCode = $LASTEXITCODE
        $resultText = ($result | ForEach-Object { "$_" }) -join "`n"
        if ($exitCode -ne 0) {
            Write-Error $resultText
            exit $exitCode
        }

        Start-Sleep -Milliseconds 1200
        Take-FallbackScreenshot -FilePath $Out
        Write-Output $resultText
        Write-Output "Screenshot saved to $Out"
        exit 0
    }
}
