param(
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

function Get-JunkFolder {
    param(
        [object]$Account,
        [string]$AccountName
    )

    $folderNames = @("Junk Email", "Junk", "Correo no deseado", "Spam")

    foreach ($folderName in $folderNames) {
        try {
            $folder = $Account.Folders.Item($folderName)
            if ($folder) {
                return $folder
            }
        }
        catch {
            continue
        }
    }

    try {
        $rootFolder = $Account.RootFolder
        $allFolders = Get-AllFolders -Folder $rootFolder
        
        foreach ($folder in $allFolders) {
            foreach ($folderName in $folderNames) {
                if ($folder.Name -eq $folderName) {
                    return $folder
                }
            }
        }
    }
    catch {
    }

    return $null
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
Write-Host "  Limpieza de Correos Spam en Outlook  " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Modo: $(if ($WhatIf) { 'SIMULACIÓN (WhatIf)' } else { 'EJECUCIÓN REAL' })" -ForegroundColor $(if ($WhatIf) { 'Yellow' } else { 'Green' })
Write-Host ""

$outlook = Get-OutlookApplication

try {
    $namespace = $outlook.GetNamespace("MAPI")
    $accounts = $namespace.Accounts

    Write-Host "Cuentas encontradas: $($accounts.Count)" -ForegroundColor Gray
    Write-Host ""

    $totalDeleted = 0
    $accountResults = @()

    foreach ($account in $accounts) {
        $accountName = $account.DisplayName

        if ($accountName -match "Calendar") {
            Write-Host "[SKIP] Cuenta ignorada (Calendar): $accountName" -ForegroundColor DarkGray
            continue
        }

        Write-Host "Procesando cuenta: $accountName" -ForegroundColor White

        $junkFolder = Get-JunkFolder -Account $account -AccountName $accountName

        if (-not $junkFolder) {
            Write-Host "  [WARN] No se encontró carpeta Junk para esta cuenta" -ForegroundColor Yellow
            $accountResults += @{
                AccountName = $accountName
                Status = "Sin carpeta Junk"
                Deleted = 0
            }
            continue
        }

        try {
            $items = $junkFolder.Items
            $count = $items.Count

            if ($count -eq 0) {
                Write-Host "  [OK] La carpeta Junk está vacía" -ForegroundColor Green
                $accountResults += @{
                    AccountName = $accountName
                    Status = "Vacía"
                    Deleted = 0
                }
            }
            else {
                Write-Host "  Correos encontrados en Junk: $count" -ForegroundColor Gray

                if ($WhatIf) {
                    Write-Host "  [WhatIf] Se eliminarían $count correos" -ForegroundColor Yellow
                    $accountResults += @{
                        AccountName = $accountName
                        Status = "Simulado"
                        Deleted = $count
                    }
                    $totalDeleted += $count
                }
                else {
                    $deleted = 0
                    $failed = 0

                    try {
                        $items.DeleteAll()
                        $deleted = $count
                    }
                    catch {
                        for ($i = $items.Count; $i -ge 1; $i--) {
                            try {
                                $items.Item($i).Delete()
                                $deleted++
                            }
                            catch {
                                $failed++
                            }
                        }
                    }

                    Write-Host "  [DONE] Eliminados: $deleted" -ForegroundColor Green
                    if ($failed -gt 0) {
                        Write-Host "  [WARN] Fallidos: $failed" -ForegroundColor Yellow
                    }

                    $accountResults += @{
                        AccountName = $accountName
                        Status = "Completado"
                        Deleted = $deleted
                    }
                    $totalDeleted += $deleted
                }
            }
        }
        catch {
            Write-Host "  [ERROR] Error al acceder a la carpeta Junk: $_" -ForegroundColor Red
            $accountResults += @{
                AccountName = $accountName
                Status = "Error"
                Deleted = 0
            }
        }

        Write-Host ""
    }

    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "           RESUMEN FINAL               " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    foreach ($result in $accountResults) {
        $color = if ($result.Status -eq "Error") { "Red" } elseif ($result.Status -eq "Sin carpeta Junk") { "Yellow" } elseif ($result.Status -eq "Vacía") { "Green" } else { "White" }
        Write-Host "  $($result.AccountName)" -ForegroundColor $color
        Write-Host "    Estado: $($result.Status) | Eliminados: $($result.Deleted)" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "Total de correos borrados: $totalDeleted" -ForegroundColor $(if ($totalDeleted -gt 0) { "Green" } else { "Gray" })
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
