<# 
.SYNOPSIS
Revisa correos de Outlook recibidos en la fecha especificada en todas las cuentas configuradas.

.DESCRIPTION
Accede a Microsoft Outlook via COM para listar correos recibidos en la fecha indicada.
Optimizado para reducir timeout con QuickCheck y filtro por cuenta.

.PARAMETER ShowAllAccounts
Muestra todas las cuentas (default: true)

.PARAMETER ExportToCSV
Exporta a CSV en el escritorio (default: false)

.PARAMETER DateFilter
Fecha para filtrar correos (default: hoy)

.PARAMETER ShowRecent
Si es mayor a 0, muestra los N correos más recientes sin filtro de fecha (para diagnóstico)

.PARAMETER IncludeJunk
Incluye la carpeta Junk en la búsqueda (default: true)

.PARAMETER QuickCheck
Modo rápido: solo últimas 24h, solo Inbox principal (sin subcarpetas), sin Junk

.PARAMETER Account
Review only one specific account (example: "user@example.com")

.EXAMPLE
.\check-outlook-emails.ps1

.EXAMPLE
.\check-outlook-emails.ps1 -QuickCheck

.EXAMPLE
.\check-outlook-emails.ps1 -Account "user@example.com"

.EXAMPLE
.\check-outlook-emails.ps1 -Account "user@example.com" -QuickCheck
#>

param(
    [bool]$ShowAllAccounts = $true,
    [bool]$ExportToCSV = $false,
    [Nullable[datetime]]$DateFilter = $null,
    [int]$ShowRecent = 0,
    [bool]$IncludeJunk = $true,
    [switch]$QuickCheck,
    [string]$Account = "",
    [switch]$JSON,
    [switch]$IncludeBody,
    [switch]$Sync
)

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

function Release-Object {
    param([object]$obj)
    if ($null -ne $obj) {
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($obj) | Out-Null
    }
}

function Get-FolderEmails {
    param(
        [object]$Folder,
        [datetime]$StartDate,
        [datetime]$EndDate,
        [string]$AccountName,
        [ref]$EmailList,
        [bool]$IncludeJunk,
        [bool]$Recursive
    )
    
    $count = 0
    try {
        $items = $Folder.Items
        $startStr = $StartDate.ToString('yyyy-MM-dd HH:mm')
        $endStr = $EndDate.ToString('yyyy-MM-dd HH:mm')
        $filter = "[ReceivedTime] >= '$startStr' AND [ReceivedTime] < '$endStr'"
        
        $filtered = $items.Restrict($filter)
        $count = $filtered.Count
        
        if ($count -gt 0) {
            $emailsToProcess = @($filtered)
            foreach ($Mail in $emailsToProcess) {
                try {
                    $receivedTime = $Mail.ReceivedTime
                    if ($receivedTime -is [datetime]) {
                        $localTime = $receivedTime.ToLocalTime()
                    }
                    else {
                        $localTime = $receivedTime
                    }
                    $emailInfo = [PSCustomObject]@{
                        Cuenta  = $AccountName
                        Carpeta = $Folder.Name
                        Asunto  = if ($Mail.Subject) { $Mail.Subject } else { "(Sin asunto)" }
                        De      = if ($Mail.SenderName) { $Mail.SenderName } else { $Mail.SenderEmailAddress }
                        Fecha   = $localTime.ToString('dd/MM/yyyy HH:mm:ss')
                        Leido   = $Mail.UnRead -eq $false
                        Link    = $Mail.EntryID
                        Cuerpo  = if ($IncludeBody) { $Mail.Body } else { $null }
                    }
                    $EmailList.Value += $emailInfo
                }
                catch {
                    # Ignorar errores en邮件 individuales
                }
            }
        }
        Release-Object $filtered
        Release-Object $items
    }
    catch {
        Write-Host "    Advertencia: Error al procesar carpeta '$($Folder.Name)': $_" -ForegroundColor Yellow
    }
    
    if ($Recursive) {
        try {
            $subFolders = @($Folder.Folders)
            foreach ($SubFolder in $subFolders) {
                if (-not $IncludeJunk -and $SubFolder.Name -eq 'Junk') {
                    Release-Object $SubFolder
                    continue
                }
                if ($SubFolder.Name -match 'Calendar|Notes|Contacts') {
                    Release-Object $SubFolder
                    continue
                }
                $count += Get-FolderEmails -Folder $SubFolder -StartDate $StartDate -EndDate $EndDate -AccountName $AccountName -EmailList $EmailList -IncludeJunk $IncludeJunk -Recursive:$Recursive
                Release-Object $SubFolder
            }
        }
        catch {
            # Ignorar errores en subcarpetas
        }
    }
    
    return $count
}

function Show-RecentEmails {
    param(
        [object]$Folder,
        [int]$Limit,
        [string]$AccountName,
        [ref]$EmailList,
        [bool]$IncludeJunk
    )
    
    try {
        $items = $Folder.Items
        $items.Sort('[ReceivedTime]', $true)
        $shown = 0
        $allItems = @($items)
        foreach ($Mail in $allItems) {
            if ($shown -ge $Limit) { break }
            try {
                $receivedTime = $Mail.ReceivedTime
                if ($receivedTime -is [datetime]) {
                    $localTime = $receivedTime.ToLocalTime()
                }
                else {
                    $localTime = $receivedTime
                }
                $emailInfo = [PSCustomObject]@{
                    Cuenta  = $AccountName
                    Carpeta = $Folder.Name
                    Asunto  = if ($Mail.Subject) { $Mail.Subject } else { "(Sin asunto)" }
                    De      = if ($Mail.SenderName) { $Mail.SenderName } else { $Mail.SenderEmailAddress }
                    Fecha   = $localTime.ToString('dd/MM/yyyy HH:mm:ss')
                    Leido   = $Mail.UnRead -eq $false
                }
                $EmailList.Value += $emailInfo
                $shown++
            }
            catch {
                # Ignorar
            }
        }
        Release-Object $items
    }
    catch {
        Write-Host "    Advertencia: Error al procesar carpeta '$($Folder.Name)': $_" -ForegroundColor Yellow
    }
    
    try {
        $subFolders = @($Folder.Folders)
        foreach ($SubFolder in $subFolders) {
            if (-not $IncludeJunk -and $SubFolder.Name -eq 'Junk') {
                Release-Object $SubFolder
                continue
            }
            Show-RecentEmails -Folder $SubFolder -Limit $Limit -AccountName $AccountName -EmailList $EmailList -IncludeJunk $IncludeJunk
            Release-Object $SubFolder
        }
    }
    catch {
        # Ignorar
    }
}

function Test-IsValidAccount {
    param([string]$AccountName)
    if ($AccountName -match 'Calendar|Internet Calendar|Feed|Notes|Contacts') {
        return $false
    }
    return $true
}

try {
    $Outlook = New-Object -ComObject Outlook.Application -ErrorAction Stop
    Write-Host 'Conectado a Outlook.' -ForegroundColor Green
}
catch {
    Write-Host 'Iniciando Outlook...' -ForegroundColor Yellow
    Start-Process 'C:\Program Files\Microsoft Office\root\Office16\OUTLOOK.EXE' -ArgumentList '/automation' -WindowStyle Hidden
    Start-Sleep -Seconds 3
    try {
        $Outlook = New-Object -ComObject Outlook.Application -ErrorAction Stop
        Write-Host 'Conectado a Outlook.' -ForegroundColor Green
    }
    catch {
        Write-Host 'ERROR: No se pudo conectar a Outlook.' -ForegroundColor Red
        exit 1
    }
}

$Namespace = $Outlook.GetNamespace('MAPI')

if ($Sync) {
    Write-Host "Sincronizando Outlook..." -ForegroundColor Cyan
    try {
        $Namespace.SyncObjects.Item(1).Start()
        Start-Sleep -Seconds 2
    }
    catch {
        Write-Host "No se pudo iniciar la sincronizacion automatica." -ForegroundColor Yellow
    }
}
$Accounts = @($Namespace.Folders)

Write-Host "Zona horaria: $([System.TimeZoneInfo]::Local.DisplayName)" -ForegroundColor Cyan
Write-Host "Tiempo ejecución: $($stopwatch.ElapsedMilliseconds)ms inicial" -ForegroundColor DarkGray

$accountFilter = $Account.Trim()
if ($accountFilter) {
    Write-Host "Filtrando cuenta: $accountFilter" -ForegroundColor Cyan
}

if ($ShowRecent -gt 0) {
    Write-Host "`n=== ÚLTIMOS $ShowRecent CORREOS POR CUENTA ===" -ForegroundColor Magenta
    Write-Host "Cuentas disponibles: $($Accounts.Count)`n" -ForegroundColor Cyan
    
    $allEmails = @()
    foreach ($AccountObj in $Accounts) {
        $accountName = $AccountObj.Name
        
        if (-not (Test-IsValidAccount -AccountName $accountName)) {
            Release-Object $AccountObj
            continue
        }
        
        if ($accountFilter -and $accountName -notlike "*$accountFilter*") {
            Release-Object $AccountObj
            continue
        }
        
        try {
            $Inbox = $AccountObj.Folders.Item('Inbox')
            Write-Host "Cuenta: $accountName" -ForegroundColor White
            Show-RecentEmails -Folder $Inbox -Limit $ShowRecent -AccountName $accountName -EmailList ([ref]$allEmails) -IncludeJunk $IncludeJunk
            Release-Object $Inbox
        }
        catch {
            Write-Host "Cuenta: $accountName - Error accediendo Inbox" -ForegroundColor Red
        }
        Release-Object $AccountObj
        
        if ($stopwatch.ElapsedSeconds -gt 25) {
            Write-Host "Timeout approaching, stopping..." -ForegroundColor Yellow
            break
        }
    }
    
    $counter = 1
    foreach ($email in $allEmails | Select-Object -First 50) {
        $readStatus = if ($email.Leido) { '[leído]' } else { '[NO LEÍDO]' }
        Write-Host "  $counter. $readStatus $($email.Asunto)" -ForegroundColor $(if ($email.Leido) { 'Gray' } else { 'Yellow' })
        Write-Host "       De: $($email.De)" -ForegroundColor DarkGray
        Write-Host "       Fecha: $($email.Fecha)" -ForegroundColor DarkGray
        Write-Host "       Carpeta: $($email.Carpeta)" -ForegroundColor DarkGray
        $counter++
    }
    
    Write-Host "`n=== RESUMEN ===" -ForegroundColor Magenta
    Write-Host "Total correos mostrados: $($allEmails.Count)" -ForegroundColor Green
    Write-Host "Tiempo total: $($stopwatch.ElapsedSeconds)s" -ForegroundColor Cyan
    
    Release-Object $Namespace
    Release-Object $Outlook
    Write-Host "`nListo." -ForegroundColor Cyan
    exit
}

if ($useDateFilter) {
    $startDate = $DateFilter.Date
    $endDate = $startDate.AddDays(1)
    $dateRangeDescription = $startDate.ToString('dd/MM/yyyy')
}
elseif ($QuickCheck) {
    $startDate = (Get-Date).AddHours(-24)
    $endDate = Get-Date
    $dateRangeDescription = "últimas 24 horas (QuickCheck)"
}
else {
    $startDate = (Get-Date).AddHours(-48)
    $endDate = Get-Date
    $dateRangeDescription = "últimas 48 horas"
}

Write-Host "`n=== CORREOS DE $dateRangeDescription ===" -ForegroundColor Magenta
Write-Host "Cuentas: $($Accounts.Count)" -ForegroundColor Cyan

$foundEmails = @()

foreach ($AccountObj in $Accounts) {
    $accountName = $AccountObj.Name
    
    if (-not (Test-IsValidAccount -AccountName $accountName)) {
        Release-Object $AccountObj
        continue
    }
    
    if ($accountFilter -and $accountName -notlike "*$accountFilter*") {
        Release-Object $AccountObj
        continue
    }
    
    try {
        $Inbox = $AccountObj.Folders.Item('Inbox')
        
        $recursive = -not $QuickCheck
        $includeJunkForAccount = $IncludeJunk -and -not $QuickCheck
        
        $emailCount = Get-FolderEmails -Folder $Inbox -StartDate $startDate -EndDate $endDate -AccountName $accountName -EmailList ([ref]$foundEmails) -IncludeJunk $includeJunkForAccount -Recursive:$recursive
        
        if ($emailCount -gt 0 -or $ShowAllAccounts) {
            Write-Host "Cuenta: $accountName" -ForegroundColor White
            Write-Host "  Correos: $emailCount" -ForegroundColor $(if ($emailCount -gt 0) { 'Green' } else { 'Gray' })
            
            if ($emailCount -gt 0) {
                $mailNumber = 1
                foreach ($Mail in $foundEmails | Where-Object { $_.Cuenta -eq $accountName }) {
                    $readStatus = if ($Mail.Leido) { '[leído]' } else { '[NO LEÍDO]' }
                    Write-Host "    $mailNumber. $readStatus $($Mail.Asunto)" -ForegroundColor $(if ($Mail.Leido) { 'Gray' } else { 'Yellow' })
                    Write-Host "       De: $($Mail.De)" -ForegroundColor DarkGray
                    Write-Host "       Hora: $($Mail.Fecha.Split(' ')[1])" -ForegroundColor DarkGray
                    Write-Host "       Carpeta: $($Mail.Carpeta)" -ForegroundColor DarkGray
                    $mailNumber++
                }
            }
            Write-Host ''
        }
        
        Release-Object $Inbox
    }
    catch {
        if ($ShowAllAccounts) {
            Write-Host "Cuenta: $accountName" -ForegroundColor White
            Write-Host "  Error: No se pudo acceder" -ForegroundColor Red
            Write-Host ''
        }
    }
    Release-Object $AccountObj
    
    if ($stopwatch.ElapsedSeconds -gt 25) {
        Write-Host "Timeout approaching, deteniendo..." -ForegroundColor Yellow
        break
    }
}

$totalEmails = $foundEmails.Count
Write-Host "=== RESUMEN ===" -ForegroundColor Magenta
Write-Host "Total correos: $totalEmails" -ForegroundColor $(if ($totalEmails -gt 0) { 'Green' } else { 'Yellow' })
Write-Host "Tiempo total: $($stopwatch.ElapsedSeconds)s" -ForegroundColor Cyan

if ($ExportToCSV -and $totalEmails -gt 0) {
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $csvPath = [Environment]::GetFolderPath('Desktop') + "\correos_$timestamp.csv"
    $foundEmails | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    Write-Host "Exportado a: $csvPath" -ForegroundColor Green
}

if ($JSON) {
    $foundEmails | ConvertTo-Json -Depth 5
    Release-Object $Namespace
    Release-Object $Outlook
    exit
}

Release-Object $Namespace
Release-Object $Outlook

Write-Host "`nListo." -ForegroundColor Cyan
