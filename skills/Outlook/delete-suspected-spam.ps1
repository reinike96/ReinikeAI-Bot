param(
    [switch]$Auto
)

$spamPhrases = @("ever wonder", "congratulations", "claim your", "urgent", "verify your", "you have won", "free money", "act now", "limited time", "click here", "subscribe now")
$genericSubjects = @("hello", "hi", "newsletter", "update", "notice", "message", "information", "urgent matter")

function Get-OutlookApplication {
    try {
        return New-Object -ComObject Outlook.Application
    }
    catch {
        Write-Host "Error: No se pudo conectar a Outlook. Asegurate de que Outlook esté instalado y abierto." -ForegroundColor Red
        exit 1
    }
}

function Test-OfficialDomain {
    param(
        [string]$Email,
        [string[]]$OfficialDomains
    )
    
    $domain = ($Email -split "@")[1]
    if ($domain) {
        $domain = $domain.ToLower()
        foreach ($official in $OfficialDomains) {
            if ($domain -eq $official.ToLower() -or $domain.EndsWith(".$($official.ToLower())")) {
                return $true
            }
        }
    }
    return $false
}

function Test-SuspiciousEmail {
    param(
        [string]$Subject,
        [string]$SenderEmail,
        [bool]$IsUnread,
        [string[]]$OfficialDomains
    )
    
    $subjectLower = $Subject.ToLower()
    
    foreach ($phrase in $spamPhrases) {
        if ($subjectLower -match [regex]::Escape($phrase)) {
            return $true
        }
    }
    
    if (-not (Test-OfficialDomain -Email $SenderEmail -OfficialDomains $OfficialDomains)) {
        if ($SenderEmail -match "@" -and $SenderEmail -notmatch "noreply|no-reply|donotreply") {
            return $true
        }
    }
    
    if ($IsUnread) {
        foreach ($generic in $genericSubjects) {
            if ($subjectLower -eq $generic) {
                return $true
            }
        }
    }
    
    return $false
}

$outlook = Get-OutlookApplication
$namespace = $outlook.GetNamespace("MAPI")

$accounts = $namespace.Accounts
$suspiciousEmails = @()
$deletedCount = 0

Write-Host "`n=== Buscando correos sospechosos de spam ===" -ForegroundColor Cyan

foreach ($account in $accounts) {
    $accountName = $account.DisplayName
    
    if ($accountName -eq "Calendar") {
        continue
    }
    
    Write-Host "`nProcesando cuenta: $accountName" -ForegroundColor Yellow
    
    try {
        $inbox = $namespace.GetDefaultFolder(6).Folders | Where-Object { $_.Name -eq "Inbox" }
        
        if (-not $inbox) {
            $inbox = $namespace.GetDefaultFolder(6)
        }
        
        $emails = $inbox.Items
        
        foreach ($email in $emails) {
            if ($email.Class -ne 43) {
                continue
            }
            
            $sender = $email.SenderEmailAddress
            $subject = $email.Subject
            $isUnread = $email.UnRead
            
            $officialDomains = @("microsoft.com", "google.com", "apple.com", "amazon.com", "outlook.com", "yahoo.com", "github.com", "linkedin.com", "dropbox.com", "zoom.us")
            
            if (Test-SuspiciousEmail -Subject $subject -SenderEmail $sender -IsUnread $isUnread -OfficialDomains $officialDomains) {
                $suspiciousEmails += [PSCustomObject]@{
                    Account = $accountName
                    Subject = $subject
                    Sender = $sender
                    Received = $email.ReceivedTime
                    Unread = $isUnread
                    Email = $email
                }
            }
        }
    }
    catch {
        Write-Host "  Error al procesar cuenta $accountName : $_" -ForegroundColor Red
    }
}

Write-Host "`n=== Correos marcados como SPAM ($($suspiciousEmails.Count)) ===" -ForegroundColor Cyan
Write-Host ""

if ($suspiciousEmails.Count -eq 0) {
    Write-Host "No se encontraron correos sospechosos de spam." -ForegroundColor Green
}
else {
    $suspiciousEmails | Format-Table -AutoSize -Property Account, Subject, Sender, Received, Unread
    
    $confirm = $Auto
    
    if (-not $Auto) {
        Write-Host ""
        $response = Read-Host "Eliminar $($suspiciousEmails.Count) correos sospechosos? (S/N)"
        if ($response -eq "S" -or $response -eq "s") {
            $confirm = $true
        }
    }
    
    if ($confirm) {
        Write-Host "`nEliminando correos..." -ForegroundColor Yellow
        
        foreach ($item in $suspiciousEmails) {
            try {
                $item.Email.Delete()
                $deletedCount++
                Write-Host "  Eliminado: $($item.Subject)" -ForegroundColor DarkGray
            }
            catch {
                Write-Host "  Error al eliminar: $($item.Subject) - $_" -ForegroundColor Red
            }
        }
        
        Write-Host "`n=== Resumen ===" -ForegroundColor Cyan
        Write-Host "Total de correos eliminados: $deletedCount" -ForegroundColor Green
    }
    else {
        Write-Host "`nOperación cancelada. No se eliminó ningún correo." -ForegroundColor Yellow
    }
}

Write-Host ""
$outlook.Quit()
