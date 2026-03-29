param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [string]$Caption = "",
    [string]$ChatId = ""
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$targetScript = Join-Path $scriptDir "SendFile.ps1"

& $targetScript -FilePath $FilePath -Caption $Caption -ChatId $ChatId
exit $LASTEXITCODE
