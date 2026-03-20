function Get-CommandRiskProfile {
    param([string]$Command)

    if ([string]::IsNullOrWhiteSpace($Command)) {
        return [PSCustomObject]@{
            Level   = "safe"
            Reason  = "Empty command"
            Summary = ""
        }
    }

    $trimmed = $Command.Trim()
    $patterns = @(
        @{ Pattern = '(?i)\b(npm|pip|pip3|winget|choco|scoop|brew)\s+(install|uninstall|upgrade|update)\b'; Reason = "Installs or changes software packages"; Level = "block" }
        @{ Pattern = '(?i)\b(invoke-expression|iex)\b'; Reason = "Executes dynamic script content"; Level = "block" }
        @{ Pattern = '(?i)\b(remove-item|del|erase|rmdir|rd)\b'; Reason = "Deletes files or directories"; Level = "confirm" }
        @{ Pattern = '(?i)\b(stop-process|taskkill|kill|shutdown|restart-computer|stop-computer|logoff)\b'; Reason = "Stops processes or restarts the system"; Level = "confirm" }
        @{ Pattern = '(?i)\b(format-volume|clear-disk|diskpart)\b'; Reason = "Touches disk state"; Level = "block" }
        @{ Pattern = '(?i)\b(set-content|add-content|out-file|move-item|rename-item|copy-item)\b'; Reason = "Modifies files"; Level = "confirm" }
        @{ Pattern = '(?i)\b(reg add|reg delete|set-itemproperty|new-itemproperty|remove-itemproperty)\b'; Reason = "Modifies registry or system settings"; Level = "block" }
        @{ Pattern = '(?i)skills\\Outlook\\(delete|clean-spam|delete-suspected-spam)'; Reason = "Deletes Outlook data"; Level = "confirm" }
        @{ Pattern = '(?i)send-outlook-email\.ps1'; Reason = "Sends email from Outlook"; Level = "confirm" }
        @{ Pattern = '(?i)skills\\Windows_Use\\Invoke-WindowsUse\.ps1'; Reason = "Controls the live Windows desktop through Windows-Use"; Level = "confirm" }
        @{ Pattern = '(?i)\b(invoke-webrequest|curl|wget)\b'; Reason = "Downloads or posts data over the network"; Level = "confirm" }
        @{ Pattern = '(?i)\b(start-process)\b'; Reason = "Launches a new process"; Level = "confirm" }
        @{ Pattern = '(?i)skills\\Cron_Tasks\\Register-ScheduledAutomation\.ps1'; Reason = "Creates or updates a scheduled task"; Level = "confirm" }
        @{ Pattern = '(?i)skills\\Cron_Tasks\\Remove-ScheduledAutomation\.ps1'; Reason = "Removes a scheduled task"; Level = "confirm" }
    )

    foreach ($rule in $patterns) {
        if ($trimmed -match $rule.Pattern) {
            return [PSCustomObject]@{
                Level   = $(if ($rule.Level) { $rule.Level } else { "confirm" })
                Reason  = $rule.Reason
                Summary = $trimmed
            }
        }
    }

    return [PSCustomObject]@{
        Level   = "safe"
        Reason  = "No dangerous pattern matched"
        Summary = $trimmed
    }
}

function New-ConfirmationButtons {
    param(
        [string]$ConfirmData,
        [string]$CancelData
    )

    return @(
        [PSCustomObject]@{ text = "Approve"; callback_data = $ConfirmData },
        [PSCustomObject]@{ text = "Cancel"; callback_data = $CancelData }
    )
}
