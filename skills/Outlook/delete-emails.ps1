param(
    [string]$Sender,
    [string]$Subject,
    [string[]]$Keywords,
    [int]$DaysBack = 0,
    [switch]$WhatIf = $false
)

$ErrorActionPreference = "Continue"

function Get-OutlookApplication {
    try {
        $outlook = New-Object -ComObject Outlook.Application
        return $outlook
    }
    catch {
        Write-Host "Error: No se pudo iniciar Outlook. Asegúrate de que Outlook esté instalado y abierto." -ForegroundColor Red
        exit 1
    }
}

function Get-AllFolders {
    param([object]$Folder)
    
    $folders = @($Folder)
    try {
        foreach ($subFolder in $Folder.Folders) {
            $folders += Get-AllFolders -Folder $subFolder
        }
    }
    catch {
    }
    return $folders
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "       Eliminación de Correos " -ForegroundColor          Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($Sender) { Write-Host "  Remitente (parcial): $Sender" -ForegroundColor Gray }
if ($Subject) { Write-Host "  Asunto (parcial): $Subject" -ForegroundColor Gray }
if ($Keywords) { Write-Host "  Palabras clave: $($Keywords -join ', ')" -ForegroundColor Gray }

Write-Host ""
Write-Host "Modo: $(if ($WhatIf) { 'SIMULACIÓN (WhatIf)' } else { 'EJECUCIÓN REAL' })" -ForegroundColor $(if ($WhatIf) { 'Yellow' } else { 'Green' })
Write-Host ""

if (-not $Sender -and -not $Subject -and -not $Keywords) {
    Write-Host "Error: Debes especificar al menos un filtro (Sender, Subject o Keywords)" -ForegroundColor Red
    exit 1
}

$outlook = Get-OutlookApplication

try {
    $namespace = $outlook.GetNamespace("MAPI")
    $accounts = $namespace.Accounts

    Write-Host "Cuentas encontradas: $($accounts.Count)" -ForegroundColor Gray
    Write-Host ""

    $totalDeleted = 0
    $totalMatched = 0
    $accountResults = @()

    foreach ($account in $accounts) {
        $accountName = $account.DisplayName

        if ($accountName -match "Calendar") {
            Write-Host "[SKIP] Cuenta ignorada (Calendar): $accountName" -ForegroundColor DarkGray
            continue
        }

        Write-Host "Procesando cuenta: $accountName" -ForegroundColor White

        try {
            $rootFolder = $account.RootFolder
            $allFolders = Get-AllFolders -Folder $rootFolder

            $accountDeleted = 0
            $accountMatched = 0
            $processedFolders = 0

            foreach ($folder in $allFolders) {
                try {
                    $items = $folder.Items
                    $count = $items.Count

                    if ($count -eq 0) {
                        continue
                    }

                    $itemsToDelete = @()

                    foreach ($item in $items) {
                        try {
                            if ($DaysBack -gt 0) {
                                $cutoffDate = (Get-Date).AddDays(-$DaysBack)
                                if ($item.ReceivedTime -lt $cutoffDate) { continue }
                            }
                            $matchSender = $false
                            $matchSubject = $false
                            $matchKeywords = $false

                            if ($Sender) {
                                if ($item.SenderName -like "*$Sender*" -or $item.SenderEmailAddress -like "*$Sender*") {
                                    $matchSender = $true
                                }
                            }
                            else {
                                $matchSender = $true
                            }

                            if ($Subject) {
                                if ($item.Subject -like "*$Subject*") {
                                    $matchSubject = $true
                                }
                            }
                            else {
                                $matchSubject = $true
                            }

                            if ($Keywords -and $Keywords.Count -gt 0) {
                                $itemBody = ""
                                try {
                                    if ($item.Body) {
                                        $itemBody = $item.Body
                                    }
                                    elseif ($item.HTMLBody) {
                                        $itemBody = $item.HTMLBody
                                    }
                                }
                                catch {
                                }

                                foreach ($keyword in $Keywords) {
                                    if ($itemBody -like "*$keyword*") {
                                        $matchKeywords = $true
                                        break
                                    }
                                }
                            }
                            else {
                                $matchKeywords = $true
                            }

                            if ($matchSender -and $matchSubject -and $matchKeywords) {
                                $itemsToDelete += $item
                                $accountMatched++
                            }
                        }
                        catch {
                            continue
                        }
                    }

                    if ($itemsToDelete.Count -gt 0) {
                        if ($WhatIf) {
                            Write-Host "  [WhatIf] Carpeta '$($folder.Name)': Se eliminarían $($itemsToDelete.Count) correos" -ForegroundColor Yellow
                            $accountDeleted += $itemsToDelete.Count
                        }
                        else {
                            $deleted = 0
                            $failed = 0
                            foreach ($item in $itemsToDelete) {
                                try {
                                    $item.Delete()
                                    $deleted++
                                }
                                catch {
                                    $failed++
                                }
                            }
                            Write-Host "  [DONE] Carpeta '$($folder.Name)': Eliminados: $deleted" -ForegroundColor Green
                            if ($failed -gt 0) {
                                Write-Host "  [WARN] Fallidos: $failed" -ForegroundColor Yellow
                            }
                            $accountDeleted += $deleted
                        }
                    }

                    $processedFolders++
                }
                catch {
                    continue
                }
            }

            Write-Host "  Carpetas procesadas: $processedFolders | Coincidencias: $accountMatched | Eliminados: $accountDeleted" -ForegroundColor Gray

            $accountResults += @{
                AccountName = $accountName
                Matched     = $accountMatched
                Deleted     = $accountDeleted
            }
            $totalDeleted += $accountDeleted
            $totalMatched += $accountMatched
        }
        catch {
            Write-Host "  [ERROR] Error al procesar cuenta: $_" -ForegroundColor Red
            $accountResults += @{
                AccountName = $accountName
                Matched     = 0
                Deleted     = 0
            }
        }

        Write-Host ""
    }

    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "           RESUMEN FINAL               " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    foreach ($result in $accountResults) {
        Write-Host "  $($result.AccountName)" -ForegroundColor White
        Write-Host "    Coincidencias: $($result.Matched) | Eliminados: $($result.Deleted)" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "Total de correos encontrados: $totalMatched" -ForegroundColor Cyan
    Write-Host "Total de correos eliminados: $totalDeleted" -ForegroundColor $(if ($totalDeleted -gt 0) { "Green" } else { "Gray" })
    Write-Host ""
}
catch {
    Write-Host "Error general: $_" -ForegroundColor Red
}
finally {
    if ($outlook) {
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($outlook) | Out-Null
    }
}
