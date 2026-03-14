<#
.SYNOPSIS
Busca correos en Outlook con criterios avanzados.

.PARAMETER Query
Busqueda general avanzada (AQS). Ej: "from:Juan subject:Factura"

.PARAMETER Sender
Filtrar por remitente.

.PARAMETER Subject
Filtrar por asunto.

.PARAMETER Body
Filtrar por contenido del mensaje.

.PARAMETER DaysBack
Cuantos dias atras buscar (por defecto 7).

.PARAMETER UnreadOnly
Mostrar solo correos no leidos.

.PARAMETER MaxResults
Numero maximo de resultados (por defecto 10).

.PARAMETER Account
Filtro de cuenta especifica.

.EXAMPLE
.\search-outlook-emails.ps1 -Query "importante"
#>

param(
    [string]$Query = "",
    [string]$Sender = "",
    [string]$Subject = "",
    [string]$Body = "",
    [int]$DaysBack = 7,
    [switch]$UnreadOnly,
    [int]$MaxResults = 10,
    [string]$Account = ""
)

$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Release-Object {
    param([object]$obj)
    if ($null -ne $obj) {
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($obj) | Out-Null
    }
}

try {
    $Outlook = New-Object -ComObject Outlook.Application -ErrorAction Stop
}
catch {
    Write-Host "Error: No se pudo conectar a Outlook." -ForegroundColor Red
    exit 1
}

$Namespace = $Outlook.GetNamespace("MAPI")
$startDate = (Get-Date).AddDays(-$DaysBack).ToString("dd/MM/yyyy HH:mm")

Write-Host "Buscando correos (ultimos $DaysBack dias)..." -ForegroundColor Cyan

$results = @()

foreach ($folder in $Namespace.Folders) {
    if ($folder.Name -match "Calendar|Notes|Contacts|Feed") { continue }
    if ($Account -and $folder.Name -notlike "*$Account*") { continue }

    try {
        $inbox = $folder.Folders.Item("Inbox")
        $items = $inbox.Items
        $items.Sort("[ReceivedTime]", $true)

        # Construir filtro DASL para mayor precision
        $filter = "[ReceivedTime] >= '$startDate'"
        if ($UnreadOnly) {
            $filter += " AND [Unread] = $true"
        }
        
        $filtered = $items.Restrict($filter)
        
        foreach ($item in $filtered) {
            if ($results.Count -ge $MaxResults) { break }
            
            try {
                $match = $true
                if ($Sender -and $item.SenderName -notlike "*$Sender*" -and $item.SenderEmailAddress -notlike "*$Sender*") { $match = $false }
                if ($Subject -and $item.Subject -notlike "*$Subject*") { $match = $false }
                if ($Body -and $item.Body -notlike "*$Body*") { $match = $false }
                if ($Query -and $item.Subject -notlike "*$Query*" -and $item.Body -notlike "*$Query*") { $match = $false }

                if ($match) {
                    $preview = if ($item.Body) { 
                        $b = $item.Body.Trim()
                        if ($b.Length -gt 200) { $b.Substring(0, 200) + "..." } else { $b }
                    }
                    else { "" }

                    $results += [PSCustomObject]@{
                        Account = $folder.Name
                        Subject = $item.Subject
                        From    = $item.SenderName + " <" + $item.SenderEmailAddress + ">"
                        Date    = $item.ReceivedTime.ToString("dd/MM/yyyy HH:mm")
                        Unread  = $item.Unread
                        Preview = $preview.Replace("`r`n", " ").Replace("`n", " ")
                    }
                }
            }
            catch {}
        }
        Release-Object $inbox
    }
    catch {}
}

if ($results.Count -eq 0) {
    Write-Host "No se encontraron correos con los filtros especificados." -ForegroundColor Yellow
}
else {
    $results | ForEach-Object {
        $status = if ($_.Unread) { "[NO LEIDO]" } else { "[leido]" }
        Write-Host "----------------------------------------" -ForegroundColor Gray
        Write-Host "$status $($_.Subject)" -ForegroundColor $(if ($_.Unread) { "White" } else { "DarkGray" })
        Write-Host "De: $($_.From)" -ForegroundColor Cyan
        Write-Host "Fecha: $($_.Date) | Cuenta: $($_.Account)" -ForegroundColor DarkGray
        Write-Host "Vista previa: $($_.Preview)" -ForegroundColor Gray
    }
    Write-Host "----------------------------------------" -ForegroundColor Gray
    Write-Host "Total: $($results.Count) resultados." -ForegroundColor Green
}

Release-Object $Namespace
Release-Object $Outlook
