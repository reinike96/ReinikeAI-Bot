<#
.SYNOPSIS
Envia un correo electronico usando Microsoft Outlook.

.PARAMETER To
Direccion(es) de correo del destinatario, separadas por punto y coma.

.PARAMETER Subject
Asunto del correo.

.PARAMETER Body
Contenido del correo (texto plano o HTML).

.PARAMETER Attachments
Ruta(s) de archivos a adjuntar, separadas por coma.

.PARAMETER Account
Nombre o direccion de la cuenta desde la que enviar (opcional).

.EXAMPLE
.\send-outlook-email.ps1 -To "alex@example.com" -Subject "Hola" -Body "Este es un mensaje de prueba."
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$To,

    [Parameter(Mandatory = $true)]
    [string]$Subject,

    [Parameter(Mandatory = $true)]
    [string]$Body,

    [string[]]$Attachments = @(),

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
    Write-Host "Conectando a Outlook..." -ForegroundColor Cyan
    $Outlook = New-Object -ComObject Outlook.Application -ErrorAction Stop
}
catch {
    Write-Host "Error: No se pudo conectar a Outlook." -ForegroundColor Red
    exit 1
}

try {
    $Mail = $Outlook.CreateItem(0) # 0 = olMailItem
    
    # Seleccionar cuenta si se especifica
    if ($Account) {
        $Namespace = $Outlook.GetNamespace("MAPI")
        $found = $false
        foreach ($acc in $Namespace.Accounts) {
            if ($acc.DisplayName -like "*$Account*" -or $acc.SmtpAddress -eq $Account) {
                $Mail.SendUsingAccount = $acc
                Write-Host "Usando cuenta: $($acc.DisplayName)" -ForegroundColor Gray
                $found = $true
                break
            }
        }
        if (-not $found) {
            Write-Host "Advertencia: No se encontro la cuenta '$Account'. Se usara la predeterminada." -ForegroundColor Yellow
        }
    }

    $Mail.To = $To
    $Mail.Subject = $Subject
    
    # Detectar si el cuerpo es HTML
    if ($Body -match "<[a-z][\s\S]*>") {
        $Mail.HTMLBody = $Body
    }
    else {
        $Mail.Body = $Body
    }

    # Adjuntar archivos
    foreach ($path in $Attachments) {
        if ($path.Trim()) {
            $absPath = Resolve-Path $path.Trim()
            if (Test-Path $absPath) {
                $Mail.Attachments.Add($absPath.ToString())
                Write-Host "Adjuntado: $absPath" -ForegroundColor Gray
            }
            else {
                Write-Host "Error: No se encontro el archivo $path" -ForegroundColor Red
            }
        }
    }

    Write-Host "Enviando correo a: $To..." -ForegroundColor Green
    $Mail.Send()
    Write-Host "Correo enviado exitosamente." -ForegroundColor Green

}
catch {
    Write-Host "Error al enviar el correo: $_" -ForegroundColor Red
    exit 1
}
finally {
    Release-Object $Mail
    # No cerramos Outlook por si esta abierto por el usuario
}
