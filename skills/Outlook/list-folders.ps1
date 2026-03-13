# List Outlook folders script
# Lists all first-level and subfolders for each Outlook account (excluding Calendar)

$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding("utf-8")

Write-Host "=== LISTANDO CARPETAS DE OUTLOOK ===" -ForegroundColor Cyan
Write-Host ""

try {
    $outlook = New-Object -ComObject Outlook.Application
    $namespace = $outlook.GetNamespace("MAPI")
    
    $accounts = $namespace.Accounts
    
    function Get-FolderTree {
        param (
            $folder,
            [int]$indent = 0
        )
        
        $prefix = "  " * $indent
        $folderName = $folder.Name
        
        if ($folderName -ne "Calendar") {
            Write-Host "$prefix$folderName" -ForegroundColor Yellow
        }
        
        try {
            if ($folder.Folders.Count -gt 0) {
                foreach ($subfolder in $folder.Folders) {
                    Get-FolderTree -folder $subfolder -indent ($indent + 1)
                }
            }
        } catch {
        }
    }
    
    function Get-AllFolders {
        param (
            $store
        )
        
        try {
            $rootFolder = $store.GetRootFolder()
            Write-Host "Raiz: $($rootFolder.Name)" -ForegroundColor Magenta
            
            if ($rootFolder.Folders.Count -gt 0) {
                foreach ($folder in $rootFolder.Folders) {
                    if ($folder.Name -ne "Calendar") {
                        Get-FolderTree -folder $folder -indent 1
                    }
                }
            }
        } catch {
            Write-Host "  Error al obtener carpetas: $_" -ForegroundColor DarkGray
        }
    }
    
    $accountNum = 1
    foreach ($account in $accounts) {
        $accountEmail = $account.SmtpAddress
        Write-Host "--- Cuenta $accountNum : $accountEmail ---" -ForegroundColor Green
        Write-Host ""
        
        try {
            $stores = $namespace.Stores
            foreach ($store in $stores) {
                if ($store.DisplayName -like "*$accountEmail*" -or $store.DisplayName -eq $accountEmail) {
                    Get-AllFolders -store $store
                }
            }
        } catch {
            Write-Host "  (No se pudo acceder a carpetas)" -ForegroundColor DarkGray
        }
        
        Write-Host ""
        $accountNum++
    }
    
    Write-Host "=== FIN DEL LISTADO ===" -ForegroundColor Cyan
    
    $outlook.Quit()
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($namespace) | Out-Null
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($outlook) | Out-Null
    
} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
    exit 1
}
