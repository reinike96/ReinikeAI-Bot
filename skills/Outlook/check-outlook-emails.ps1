<#
.SYNOPSIS
Revisa correos recibidos en Outlook para una fecha o ventana de tiempo.

.DESCRIPTION
Lee Outlook Desktop via COM, recorre las cuentas/stores reales configuradas y
devuelve correos recibidos dentro del rango solicitado. El modo JSON emite solo
JSON limpio por stdout para que otros componentes puedan parsearlo sin ruido.

.PARAMETER ShowAllAccounts
Muestra todas las cuentas aunque no tengan correos en el rango.

.PARAMETER ExportToCSV
Exporta los resultados a CSV en el escritorio.

.PARAMETER DateFilter
Fecha exacta a consultar. Si se indica, el rango es desde las 00:00 locales
hasta antes de las 00:00 del día siguiente.

.PARAMETER ShowRecent
Muestra los N correos más recientes por cuenta para diagnóstico.

.PARAMETER IncludeJunk
Incluye Junk/Spam/Correo no deseado. Por defecto no se incluye.

.PARAMETER QuickCheck
Modo rápido: últimas 24 horas, solo Inbox principal, sin subcarpetas ni Junk.

.PARAMETER Account
Filtra por una cuenta concreta (nombre visible o SMTP).

.PARAMETER JSON
Devuelve solo JSON limpio por stdout.

.PARAMETER IncludeBody
Incluye el cuerpo del correo en los resultados.

.PARAMETER Sync
Intenta lanzar la sincronización de todos los SyncObjects antes de consultar.

.PARAMETER MaxExecutionSeconds
Límite blando para evitar ejecuciones colgadas.
#>

param(
    [bool]$ShowAllAccounts = $true,
    [bool]$ExportToCSV = $false,
    [Nullable[datetime]]$DateFilter = $null,
    [int]$ShowRecent = 0,
    [bool]$IncludeJunk = $false,
    [switch]$QuickCheck,
    [string]$Account = "",
    [switch]$JSON,
    [switch]$IncludeBody,
    [switch]$Sync,
    [int]$MaxExecutionSeconds = 90
)

$OutputEncoding = [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

function Release-Object {
    param([object]$Object)

    if ($null -eq $Object) {
        return
    }

    try {
        if ([System.Runtime.InteropServices.Marshal]::IsComObject($Object)) {
            [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($Object)
        }
    }
    catch {
    }
}

function Write-Status {
    param(
        [string]$Message,
        [string]$Color = 'Gray'
    )

    if ($JSON) {
        return
    }

    Write-Host $Message -ForegroundColor $Color
}

function Write-Fatal {
    param([string]$Message)

    if ($JSON) {
        [Console]::Error.WriteLine($Message)
    }
    else {
        Write-Host $Message -ForegroundColor Red
    }
}

function Test-IsValidStoreName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }

    return $Name -notmatch '^(Calendar|Internet Calendar|Internet Calendars|Feed|Feeds|Notes|Contacts)$'
}

function Test-ShouldSkipFolder {
    param(
        [object]$Folder,
        [bool]$IncludeJunkFolder
    )

    $folderName = $Folder.Name

    if ([string]::IsNullOrWhiteSpace($folderName)) {
        return $true
    }

    $systemPattern = '^(Calendar|Notes|Contacts|Journal|Tasks|Outbox|Sync Issues.*|Yammer Root|Conversation History|RSS Subscriptions|Suscripciones de RSS|ExternalContacts|Agent Registry Contacts|PersonMetadata|MeContact|Conversation Action Settings|Configuraci[oó]n de pasos r[aá]pidos)$'
    if ($folderName -match $systemPattern) {
        return $true
    }

    $trashPattern = '^(Deleted Items|Elementos eliminados|Trash|Papelera|Bin)$'
    if ($folderName -match $trashPattern) {
        return $true
    }

    $sentDraftsPattern = '^(Sent|Sent Items|Sent Mail|Enviados|Drafts|Borradores|Draft)$'
    if ($folderName -match $sentDraftsPattern) {
        return $true
    }

    $archivePattern = '^(Archive|Archivos)$'
    if ($folderName -match $archivePattern) {
        return $true
    }

    $junkPattern = '^(Junk|Junk Email|Correo no deseado|Spam)$'
    if (-not $IncludeJunkFolder -and $folderName -match $junkPattern) {
        return $true
    }

    return $false
}

function Test-ShouldStop {
    if ($MaxExecutionSeconds -le 0) {
        return $false
    }

    return $stopwatch.Elapsed.TotalSeconds -ge $MaxExecutionSeconds
}

function Get-OutlookApplication {
    try {
        $app = New-Object -ComObject Outlook.Application -ErrorAction Stop
        Write-Status 'Conectado a Outlook.' 'Green'
        return $app
    }
    catch {
        $outlookPath = 'C:\Program Files\Microsoft Office\root\Office16\OUTLOOK.EXE'
        if (Test-Path $outlookPath) {
            Write-Status 'Iniciando Outlook...' 'Yellow'
            Start-Process $outlookPath -ArgumentList '/automation' -WindowStyle Hidden
            Start-Sleep -Seconds 4
        }

        try {
            $app = New-Object -ComObject Outlook.Application -ErrorAction Stop
            Write-Status 'Conectado a Outlook.' 'Green'
            return $app
        }
        catch {
            Write-Fatal 'ERROR: No se pudo conectar a Outlook.'
            exit 1
        }
    }
}

function Start-OutlookSync {
    param([object]$Namespace)

    if (-not $Sync) {
        return
    }

    Write-Status 'Sincronizando Outlook...' 'Cyan'

    try {
        foreach ($syncObject in @($Namespace.SyncObjects)) {
            try {
                $syncObject.Start()
            }
            catch {
            }
            finally {
                Release-Object $syncObject
            }
        }
        Start-Sleep -Seconds 5
    }
    catch {
        Write-Status 'No se pudo iniciar la sincronizacion automatica.' 'Yellow'
    }
}

function Resolve-StoreTarget {
    param(
        [object]$Store,
        [object[]]$Accounts,
        [string]$AccountFilter
    )

    $rootFolder = $null
    try {
        $rootFolder = $Store.GetRootFolder()
        $rootName = $rootFolder.Name
    }
    catch {
        $rootName = $null
    }

    $storeDisplayName = $Store.DisplayName
    $accountName = if ($storeDisplayName) { $storeDisplayName } elseif ($rootName) { $rootName } else { '' }
    $smtpAddress = ''

    foreach ($accountObj in $Accounts) {
        try {
            $deliveryStore = $null
            try {
                $deliveryStore = $accountObj.DeliveryStore
            }
            catch {
            }

            $isMatch = $false
            if ($deliveryStore -and $deliveryStore.StoreID -eq $Store.StoreID) {
                $isMatch = $true
            }
            elseif ($accountObj.SmtpAddress -and ($accountObj.SmtpAddress -eq $storeDisplayName -or $accountObj.SmtpAddress -eq $rootName)) {
                $isMatch = $true
            }
            elseif ($accountObj.DisplayName -and ($accountObj.DisplayName -eq $storeDisplayName -or $accountObj.DisplayName -eq $rootName)) {
                $isMatch = $true
            }

            if ($isMatch) {
                if ($accountObj.DisplayName) {
                    $accountName = $accountObj.DisplayName
                }
                if ($accountObj.SmtpAddress) {
                    $smtpAddress = $accountObj.SmtpAddress
                }
                break
            }
        }
        catch {
        }
    }

    if (-not (Test-IsValidStoreName -Name $accountName)) {
        Release-Object $rootFolder
        return $null
    }

    if ($AccountFilter) {
        $matchesFilter = $false
        foreach ($candidate in @($accountName, $smtpAddress, $storeDisplayName, $rootName)) {
            if ($candidate -and $candidate -like "*$AccountFilter*") {
                $matchesFilter = $true
                break
            }
        }

        if (-not $matchesFilter) {
            Release-Object $rootFolder
            return $null
        }
    }

    Release-Object $rootFolder

    return [PSCustomObject]@{
        AccountName     = $accountName
        SmtpAddress     = $smtpAddress
        StoreDisplayName = $storeDisplayName
        Store           = $Store
    }
}

function Get-StoreTargets {
    param(
        [object]$Namespace,
        [string]$AccountFilter
    )

    $targets = @()
    $seenStoreIds = New-Object 'System.Collections.Generic.HashSet[string]'
    $accounts = @($Namespace.Accounts)

    foreach ($store in @($Namespace.Stores)) {
        try {
            if ($seenStoreIds.Contains($store.StoreID)) {
                continue
            }

            $target = Resolve-StoreTarget -Store $store -Accounts $accounts -AccountFilter $AccountFilter
            if ($null -eq $target) {
                continue
            }

            [void]$seenStoreIds.Add($store.StoreID)
            $targets += $target
        }
        catch {
        }
    }

    return $targets
}

function Get-InboxFolder {
    param([object]$Store)

    try {
        $inbox = $Store.GetDefaultFolder(6)
        if ($inbox) {
            return $inbox
        }
    }
    catch {
    }

    $rootFolder = $null
    try {
        $rootFolder = $Store.GetRootFolder()
        foreach ($candidateName in @('Inbox', 'Bandeja de entrada', 'Posteingang')) {
            try {
                $inbox = $rootFolder.Folders.Item($candidateName)
                if ($inbox) {
                    return $inbox
                }
            }
            catch {
            }
        }
    }
    finally {
        Release-Object $rootFolder
    }

    return $null
}

function Add-MailResult {
    param(
        [object]$Mail,
        [object]$Folder,
        [string]$AccountName,
        [string]$SmtpAddress,
        [string]$StoreDisplayName,
        [ref]$EmailList,
        [System.Collections.Generic.HashSet[string]]$SeenEntryIds
    )

    try {
        if ($Mail.Class -ne 43) {
            return $false
        }

        $entryId = $Mail.EntryID
        if (-not [string]::IsNullOrWhiteSpace($entryId) -and $SeenEntryIds.Contains($entryId)) {
            return $false
        }

        $receivedTime = [datetime]$Mail.ReceivedTime
        $localTime = [datetime]$receivedTime.ToLocalTime()
        $folderPath = $null
        try {
            $folderPath = $Folder.FolderPath
        }
        catch {
            $folderPath = $Folder.Name
        }

        if (-not [string]::IsNullOrWhiteSpace($entryId)) {
            [void]$SeenEntryIds.Add($entryId)
        }

        $EmailList.Value += [PSCustomObject]@{
            Cuenta     = $AccountName
            CuentaSmtp = $SmtpAddress
            Store      = $StoreDisplayName
            Carpeta    = if ($folderPath) { $folderPath } else { $Folder.Name }
            Asunto     = if ($Mail.Subject) { $Mail.Subject } else { '(Sin asunto)' }
            De         = if ($Mail.SenderName) { $Mail.SenderName } else { $Mail.SenderEmailAddress }
            Fecha      = $localTime.ToString('dd/MM/yyyy HH:mm:ss')
            FechaIso   = $localTime.ToString('o')
            Leido      = $Mail.UnRead -eq $false
            Link       = $entryId
            Cuerpo     = if ($IncludeBody) { $Mail.Body } else { $null }
        }

        return $true
    }
    catch {
        return $false
    }
}

function Get-FolderEmails {
    param(
        [object]$Folder,
        [datetime]$StartDate,
        [datetime]$EndDate,
        [string]$AccountName,
        [string]$SmtpAddress,
        [string]$StoreDisplayName,
        [ref]$EmailList,
        [bool]$IncludeJunkFolder,
        [bool]$Recursive,
        [System.Collections.Generic.HashSet[string]]$SeenEntryIds
    )

    if (Test-ShouldSkipFolder -Folder $Folder -IncludeJunkFolder $IncludeJunkFolder) {
        return 0
    }

    if (Test-ShouldStop) {
        return 0
    }

    $count = 0
    $items = $null

    try {
        $items = $Folder.Items
        $items.Sort('[ReceivedTime]', $true)

        foreach ($mail in $items) {
            try {
                if ($mail.Class -ne 43) {
                    continue
                }

                $receivedTime = [datetime]$mail.ReceivedTime

                if ($receivedTime -ge $EndDate) {
                    continue
                }

                if ($receivedTime -lt $StartDate) {
                    break
                }

                if (Add-MailResult -Mail $mail -Folder $Folder -AccountName $AccountName -SmtpAddress $SmtpAddress -StoreDisplayName $StoreDisplayName -EmailList $EmailList -SeenEntryIds $SeenEntryIds) {
                    $count++
                }
            }
            catch {
            }
            finally {
                Release-Object $mail
            }
        }
    }
    catch {
        Write-Status "    Advertencia: Error al procesar carpeta '$($Folder.Name)': $($_.Exception.Message)" 'Yellow'
    }
    finally {
        Release-Object $items
    }

    if (-not $Recursive -or (Test-ShouldStop)) {
        return $count
    }

    try {
        foreach ($subFolder in @($Folder.Folders)) {
            try {
                $count += Get-FolderEmails -Folder $subFolder -StartDate $StartDate -EndDate $EndDate -AccountName $AccountName -SmtpAddress $SmtpAddress -StoreDisplayName $StoreDisplayName -EmailList $EmailList -IncludeJunkFolder $IncludeJunkFolder -Recursive:$Recursive -SeenEntryIds $SeenEntryIds
            }
            finally {
                Release-Object $subFolder
            }

            if (Test-ShouldStop) {
                break
            }
        }
    }
    catch {
    }

    return $count
}

function Show-RecentEmails {
    param(
        [object]$Folder,
        [int]$Limit,
        [string]$AccountName,
        [string]$SmtpAddress,
        [string]$StoreDisplayName,
        [ref]$EmailList,
        [bool]$IncludeJunkFolder,
        [System.Collections.Generic.HashSet[string]]$SeenEntryIds
    )

    if ($Limit -le 0 -or (Test-ShouldSkipFolder -Folder $Folder -IncludeJunkFolder $IncludeJunkFolder)) {
        return 0
    }

    $shown = 0
    $items = $null

    try {
        $items = $Folder.Items
        $items.Sort('[ReceivedTime]', $true)

        foreach ($mail in $items) {
            if ($shown -ge $Limit -or (Test-ShouldStop)) {
                break
            }

            try {
                if (Add-MailResult -Mail $mail -Folder $Folder -AccountName $AccountName -SmtpAddress $SmtpAddress -StoreDisplayName $StoreDisplayName -EmailList $EmailList -SeenEntryIds $SeenEntryIds) {
                    $shown++
                }
            }
            finally {
                Release-Object $mail
            }
        }
    }
    catch {
        Write-Status "    Advertencia: Error al procesar carpeta '$($Folder.Name)': $($_.Exception.Message)" 'Yellow'
    }
    finally {
        Release-Object $items
    }

    return $shown
}

$Outlook = Get-OutlookApplication
$Namespace = $Outlook.GetNamespace('MAPI')
Start-OutlookSync -Namespace $Namespace

$accountFilter = $Account.Trim()
$storeTargets = Get-StoreTargets -Namespace $Namespace -AccountFilter $accountFilter

if (-not $JSON) {
    Write-Host "Zona horaria: $([System.TimeZoneInfo]::Local.DisplayName)" -ForegroundColor Cyan
    Write-Host "Tiempo ejecucion inicial: $($stopwatch.ElapsedMilliseconds)ms" -ForegroundColor DarkGray

    if ($accountFilter) {
        Write-Host "Filtrando cuenta: $accountFilter" -ForegroundColor Cyan
    }
}

if ($ShowRecent -gt 0) {
    Write-Status "`n=== ULTIMOS $ShowRecent CORREOS POR CUENTA ===" 'Magenta'
    Write-Status "Cuentas disponibles: $($storeTargets.Count)`n" 'Cyan'

    $recentEmails = @()
    $recentSeenEntryIds = New-Object 'System.Collections.Generic.HashSet[string]'

    foreach ($target in $storeTargets) {
        if (Test-ShouldStop) {
            Write-Status 'Límite de tiempo alcanzado, deteniendo lectura.' 'Yellow'
            break
        }

        $inbox = $null
        try {
            $inbox = Get-InboxFolder -Store $target.Store
            if ($null -eq $inbox) {
                Write-Status "Cuenta: $($target.AccountName) - Error accediendo Inbox" 'Red'
                continue
            }

            Write-Status "Cuenta: $($target.AccountName)" 'White'
            [void](Show-RecentEmails -Folder $inbox -Limit $ShowRecent -AccountName $target.AccountName -SmtpAddress $target.SmtpAddress -StoreDisplayName $target.StoreDisplayName -EmailList ([ref]$recentEmails) -IncludeJunkFolder $IncludeJunk -SeenEntryIds $recentSeenEntryIds)
        }
        finally {
            Release-Object $inbox
        }
    }

    $counter = 1
    foreach ($email in ($recentEmails | Sort-Object FechaIso -Descending | Select-Object -First 50)) {
        $readStatus = if ($email.Leido) { '[leido]' } else { '[NO LEIDO]' }
        Write-Status "  $counter. $readStatus $($email.Asunto)" $(if ($email.Leido) { 'Gray' } else { 'Yellow' })
        Write-Status "       De: $($email.De)" 'DarkGray'
        Write-Status "       Fecha: $($email.Fecha)" 'DarkGray'
        Write-Status "       Carpeta: $($email.Carpeta)" 'DarkGray'
        $counter++
    }

    Write-Status "`n=== RESUMEN ===" 'Magenta'
    Write-Status "Total correos mostrados: $($recentEmails.Count)" 'Green'
    Write-Status "Tiempo total: $([math]::Round($stopwatch.Elapsed.TotalSeconds, 1))s" 'Cyan'

    Release-Object $Namespace
    Release-Object $Outlook
    if (-not $JSON) {
        Write-Status "`nListo." 'Cyan'
    }
    exit
}

$useDateFilter = $null -ne $DateFilter
if ($useDateFilter) {
    $startDate = ([datetime]$DateFilter).Date
    $endDate = $startDate.AddDays(1)
    $dateRangeDescription = $startDate.ToString('dd/MM/yyyy')
}
elseif ($QuickCheck) {
    $startDate = (Get-Date).AddHours(-24)
    $endDate = Get-Date
    $dateRangeDescription = 'ultimas 24 horas (QuickCheck)'
}
else {
    $startDate = (Get-Date).AddHours(-48)
    $endDate = Get-Date
    $dateRangeDescription = 'ultimas 48 horas'
}

Write-Status "`n=== CORREOS DE $dateRangeDescription ===" 'Magenta'
Write-Status "Cuentas: $($storeTargets.Count)" 'Cyan'

$foundEmails = @()
$seenEntryIds = New-Object 'System.Collections.Generic.HashSet[string]'
$accountSummaries = @()

foreach ($target in $storeTargets) {
    if (Test-ShouldStop) {
        Write-Status 'Límite de tiempo alcanzado, deteniendo lectura.' 'Yellow'
        break
    }

    $inbox = $null
    $emailCount = 0
    $errorMessage = $null

    try {
        $inbox = Get-InboxFolder -Store $target.Store
        if ($null -eq $inbox) {
            $errorMessage = 'No se pudo acceder al Inbox'
        }
        else {
            $recursive = -not $QuickCheck
            $includeJunkForAccount = $IncludeJunk -and -not $QuickCheck
            $emailCount = Get-FolderEmails -Folder $inbox -StartDate $startDate -EndDate $endDate -AccountName $target.AccountName -SmtpAddress $target.SmtpAddress -StoreDisplayName $target.StoreDisplayName -EmailList ([ref]$foundEmails) -IncludeJunkFolder $includeJunkForAccount -Recursive:$recursive -SeenEntryIds $seenEntryIds
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
    }
    finally {
        Release-Object $inbox
    }

    $accountSummaries += [PSCustomObject]@{
        Name        = $target.AccountName
        SmtpAddress = $target.SmtpAddress
        Store       = $target.StoreDisplayName
        Emails      = $emailCount
        Error       = $errorMessage
    }

    if ($emailCount -gt 0 -or $ShowAllAccounts) {
        Write-Status "Cuenta: $($target.AccountName)" 'White'
        if ($errorMessage) {
            Write-Status "  Error: $errorMessage" 'Red'
        }
        else {
            Write-Status "  Correos: $emailCount" $(if ($emailCount -gt 0) { 'Green' } else { 'Gray' })

            if ($emailCount -gt 0) {
                $mailNumber = 1
                foreach ($mail in ($foundEmails | Where-Object { $_.Cuenta -eq $target.AccountName } | Sort-Object FechaIso -Descending)) {
                    $readStatus = if ($mail.Leido) { '[leido]' } else { '[NO LEIDO]' }
                    $mailTime = ([datetime]$mail.FechaIso).ToString('HH:mm:ss')
                    Write-Status "    $mailNumber. $readStatus $($mail.Asunto)" $(if ($mail.Leido) { 'Gray' } else { 'Yellow' })
                    Write-Status "       De: $($mail.De)" 'DarkGray'
                    Write-Status "       Hora: $mailTime" 'DarkGray'
                    Write-Status "       Carpeta: $($mail.Carpeta)" 'DarkGray'
                    $mailNumber++
                }
            }
        }
        Write-Status '' 'Gray'
    }
}

$foundEmails = $foundEmails | Sort-Object FechaIso -Descending
$totalEmails = $foundEmails.Count

if ($ExportToCSV -and $totalEmails -gt 0) {
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $csvPath = [Environment]::GetFolderPath('Desktop') + "\correos_$timestamp.csv"
    $foundEmails | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    Write-Status "Exportado a: $csvPath" 'Green'
}

if ($JSON) {
    [PSCustomObject]@{
        Query = [PSCustomObject]@{
            Start               = $startDate.ToString('o')
            End                 = $endDate.ToString('o')
            DateFilter          = if ($useDateFilter) { $startDate.ToString('yyyy-MM-dd') } else { $null }
            QuickCheck          = [bool]$QuickCheck
            IncludeJunk         = [bool]$IncludeJunk
            IncludeBody         = [bool]$IncludeBody
            Account             = if ($accountFilter) { $accountFilter } else { $null }
            SyncRequested       = [bool]$Sync
            MaxExecutionSeconds = $MaxExecutionSeconds
        }
        Accounts = $accountSummaries
        TotalEmails = $totalEmails
        Emails = $foundEmails
    } | ConvertTo-Json -Depth 6

    Release-Object $Namespace
    Release-Object $Outlook
    exit
}

Write-Status '=== RESUMEN ===' 'Magenta'
Write-Status "Total correos: $totalEmails" $(if ($totalEmails -gt 0) { 'Green' } else { 'Yellow' })
Write-Status "Tiempo total: $([math]::Round($stopwatch.Elapsed.TotalSeconds, 1))s" 'Cyan'

Release-Object $Namespace
Release-Object $Outlook

Write-Status "`nListo." 'Cyan'
