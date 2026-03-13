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
        @{ Pattern = '(?i)\b(remove-item|del|erase|rmdir|rd)\b'; Reason = "Deletes files or directories" }
        @{ Pattern = '(?i)\b(stop-process|taskkill|kill|shutdown|restart-computer|stop-computer|logoff)\b'; Reason = "Stops processes or restarts the system" }
        @{ Pattern = '(?i)\b(format-volume|clear-disk|diskpart)\b'; Reason = "Touches disk state" }
        @{ Pattern = '(?i)\b(set-content|add-content|out-file|move-item|rename-item|copy-item)\b'; Reason = "Modifies files" }
        @{ Pattern = '(?i)\b(reg add|reg delete|set-itemproperty|new-itemproperty|remove-itemproperty)\b'; Reason = "Modifies registry or system settings" }
        @{ Pattern = '(?i)skills\\Outlook\\(delete|clean-spam|delete-suspected-spam)'; Reason = "Deletes Outlook data" }
        @{ Pattern = '(?i)send-outlook-email\.ps1'; Reason = "Sends email from Outlook" }
        @{ Pattern = '(?i)\b(invoke-webrequest|curl|wget)\b'; Reason = "Downloads or posts data over the network" }
    )

    foreach ($rule in $patterns) {
        if ($trimmed -match $rule.Pattern) {
            return [PSCustomObject]@{
                Level   = "confirm"
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

