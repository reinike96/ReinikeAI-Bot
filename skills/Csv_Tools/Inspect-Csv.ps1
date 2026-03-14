param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [int]$SampleRows = 5
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))

if (-not [System.IO.Path]::IsPathRooted($Path)) {
    $Path = Join-Path $projectRoot $Path
}

$Path = [System.IO.Path]::GetFullPath($Path)
if (-not (Test-Path $Path)) {
    throw "CSV file not found: $Path"
}

$rows = @(Import-Csv -Path $Path)
$rowCount = $rows.Count
$columns = @()
if ($rowCount -gt 0) {
    $columns = @($rows[0].PSObject.Properties.Name)
}
else {
    $header = Get-Content -Path $Path -TotalCount 1
    if (-not [string]::IsNullOrWhiteSpace($header)) {
        $columns = @($header -split ",")
    }
}

$sample = @($rows | Select-Object -First $SampleRows)
$nullCounts = [ordered]@{}
foreach ($column in $columns) {
    $nullCounts[$column] = @($rows | Where-Object { [string]::IsNullOrWhiteSpace($_.$column) }).Count
}

[PSCustomObject]@{
    Path = $Path
    RowCount = $rowCount
    ColumnCount = $columns.Count
    Columns = $columns
    EmptyValueCounts = $nullCounts
    SampleRows = $sample
} | ConvertTo-Json -Depth 6
