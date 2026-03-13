param(
    [string]$LogPath = "$PSScriptRoot\..\logs",
    [string]$SkillsPath = "$PSScriptRoot\..\skills"
)

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$logFile = Join-Path $LogPath "reporte-emails_$(Get-Date -Format 'yyyyMMdd').log"
$scriptDir = $PSScriptRoot
$rootDir = (Get-Item $scriptDir).Parent.Parent
$rootDir = $rootDir.FullName

if (-not (Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}

function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$ts] $Message"
    Add-Content -Path $logFile -Value $logMessage
    Write-Host $logMessage
}

Write-Log "=== INICIANDO REPORTE DE EMAILS ==="

$outlookScript = Join-Path $rootDir "skills\Outlook\check-outlook-emails.ps1"
$telegramScript = Join-Path $rootDir "skills\Telegram_Sender\SendMessage.ps1"

if (-not (Test-Path $outlookScript)) {
    Write-Log "ERROR: No se encontro el script de Outlook: $outlookScript"
    exit 1
}

if (-not (Test-Path $telegramScript)) {
    Write-Log "ERROR: No se encontro el script de Telegram: $telegramScript"
    exit 1
}

try {
    Write-Log "Obteniendo emails de hoy..."
    
    $today = (Get-Date).ToString('yyyy-MM-dd')
    
    $outputEncoding = [System.Text.Encoding]::UTF8
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = "powershell.exe"
    $processInfo.Arguments = "-ExecutionPolicy Bypass -NoProfile -Command `"& '$outlookScript' -DateFilter '$today' -ShowAllAccounts:`$false`""
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true
    $processInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $processInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processInfo
    $process.Start() | Out-Null
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    
    $emailsText = $stdout
    
    if ($emailsText.Length -lt 100) {
        Write-Log "DEBUG: stdout muy corto o vacio: '$emailsText'"
        Write-Log "DEBUG: stderr: '$stderr'"
    }
    
    $foundEmails = @()
    
    $lines = $emailsText -split "`r?`n"
    $currentSubject = ""
    $currentFrom = ""
    $currentTime = ""
    
    foreach ($line in $lines) {
        if ($line -match "(\d+)\.\s+(.+)") {
            $currentSubject = $matches[2]
            $currentSubject = $currentSubject -replace "\s+De:.*$", ""
            $currentSubject = $currentSubject -replace "\s+Hora:.*$", ""
            $currentSubject = $currentSubject.Trim()
        }
        elseif ($line -match "De:\s+(.+)") {
            $currentFrom = $matches[1].Trim()
        }
        elseif ($line -match "Hora:\s+(.+)") {
            $currentTime = $matches[1].Trim()
            if ($currentSubject -ne "") {
                $foundEmails += [PSCustomObject]@{
                    Asunto = $currentSubject
                    De = $currentFrom
                    Hora = $currentTime
                }
                $currentSubject = ""
                $currentFrom = ""
                $currentTime = ""
            }
        }
    }
    
    Write-Log "Parseados $($foundEmails.Count) emails"
    
    if ($foundEmails.Count -eq 0) {
        Write-Log "No se encontraron emails hoy"
        
        $reporte = "[EMAIL] *Reporte de Emails - $today*`n`nNo se recibieron emails hoy. -OK-"
        
        Write-Log "Enviando reporte por Telegram..."
        & $telegramScript -Message $reporte
        Write-Log "Reporte enviado"
    } else {
        Write-Log "Se encontraron $($foundEmails.Count) emails"
        
        $reporte = "[EMAIL] *Reporte de Emails - $today*`n`n"
        $reporte += "Recibidos: $($foundEmails.Count) email(s)`n`n"
        
        $counter = 1
        foreach ($email in $foundEmails) {
            $subject = if ($email.Asunto.Length -gt 50) { $email.Asunto.Substring(0, 47) + "..." } else { $email.Asunto }
            $from = if ($email.De.Length -gt 30) { $email.De.Substring(0, 27) + "..." } else { $email.De }
            
            $reporte += "$counter. *$subject*`n"
            $reporte += "   De: $from`n"
            $reporte += "   Hora: $($email.Hora)`n`n"
            
            $counter++
        }
        
        Write-Log "Enviando reporte por Telegram..."
        & $telegramScript -Message $reporte
        Write-Log "Reporte enviado"
    }
    
} catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    
    $errorMsg = "[X] Error al generar reporte de emails: $($_.Exception.Message)"
    try {
        & $telegramScript -Message $errorMsg
    } catch {
        Write-Log "Error al enviar mensaje de error por Telegram"
    }
}

Write-Log "=== REPORTE FINALIZADO ==="
