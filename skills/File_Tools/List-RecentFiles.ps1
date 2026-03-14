param(
    [string]$Directory = "",
    [int]$Top = 10,
    [string]$Filter = "*"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
. (Join-Path $projectRoot "config\Load-BotConfig.ps1")
$botConfig = Import-BotSettings -ProjectRoot $projectRoot

if ([string]::IsNullOrWhiteSpace($Directory)) {
    $Directory = $botConfig.Paths.ArchivesDir
}
elseif (-not [System.IO.Path]::IsPathRooted($Directory)) {
    $Directory = Join-Path $projectRoot $Directory
}

$Directory = [System.IO.Path]::GetFullPath($Directory)
if (-not (Test-Path $Directory)) {
    throw "Directory not found: $Directory"
}

$items = Get-ChildItem -Path $Directory -File -Filter $Filter -ErrorAction Stop |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First $Top FullName, Name, Length, LastWriteTime

[PSCustomObject]@{
    Directory = $Directory
    Count = $items.Count
    Files = @($items | ForEach-Object {
        [PSCustomObject]@{
            Name = $_.Name
            FullName = $_.FullName
            SizeMB = [Math]::Round(($_.Length / 1MB), 2)
            LastWriteTime = $_.LastWriteTime.ToString("o")
        }
    })
} | ConvertTo-Json -Depth 5
