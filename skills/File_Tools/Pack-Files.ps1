param(
    [Parameter(Mandatory = $true)]
    [string[]]$Path,
    [string]$OutputPath = "",
    [switch]$Overwrite
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
. (Join-Path $projectRoot "config\Load-BotConfig.ps1")
$botConfig = Import-BotSettings -ProjectRoot $projectRoot

function Resolve-InputPath {
    param([string]$Candidate)

    if ([string]::IsNullOrWhiteSpace($Candidate)) {
        throw "Empty input path is not valid."
    }

    $resolved = $Candidate
    if (-not [System.IO.Path]::IsPathRooted($Candidate)) {
        $resolved = Join-Path $projectRoot $Candidate
    }

    return [System.IO.Path]::GetFullPath($resolved)
}

$resolvedInputs = @()
foreach ($item in $Path) {
    $fullPath = Resolve-InputPath -Candidate $item
    if (-not (Test-Path $fullPath)) {
        throw "Input path not found: $fullPath"
    }
    $resolvedInputs += $fullPath
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $OutputPath = Join-Path $botConfig.Paths.ArchivesDir "bundle_$timestamp.zip"
}
elseif (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $projectRoot $OutputPath
}

$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$outputDir = Split-Path -Parent $OutputPath
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

if ((Test-Path $OutputPath) -and -not $Overwrite) {
    throw "Output archive already exists: $OutputPath. Use -Overwrite to replace it."
}

if (Test-Path $OutputPath) {
    Remove-Item $OutputPath -Force
}

Compress-Archive -Path $resolvedInputs -DestinationPath $OutputPath -Force

[PSCustomObject]@{
    OutputPath = $OutputPath
    InputCount = $resolvedInputs.Count
    Inputs = $resolvedInputs
    SizeMB = [Math]::Round(((Get-Item $OutputPath).Length / 1MB), 2)
} | ConvertTo-Json -Depth 5
