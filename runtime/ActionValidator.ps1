function Get-ActionSchema {
    param(
        [string]$ActionType
    )

    switch ($ActionType) {
        "CMD" {
            return [PSCustomObject]@{
                Required = @("Command")
                UrlFields = @()
            }
        }
        "OPENCODE" {
            return [PSCustomObject]@{
                Required = @("Task")
                UrlFields = @()
            }
        }
        "PW_CONTENT" {
            return [PSCustomObject]@{
                Required = @("Url")
                UrlFields = @("Url")
            }
        }
        "PW_SCREENSHOT" {
            return [PSCustomObject]@{
                Required = @("Url")
                UrlFields = @("Url")
            }
        }
        "BUTTONS" {
            return [PSCustomObject]@{
                Required = @("Text")
                UrlFields = @()
            }
        }
        "SCREENSHOT" {
            return [PSCustomObject]@{
                Required = @()
                UrlFields = @()
            }
        }
        "STATUS" {
            return [PSCustomObject]@{
                Required = @()
                UrlFields = @()
            }
        }
        default {
            return $null
        }
    }
}

function Test-ActionUrlValue {
    param(
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    return $Value -match '^(?i)https?://'
}

function Test-ActionButtonsValue {
    param(
        [object]$Item
    )

    if ($Item.PSObject.Properties["Buttons"] -and @($Item.Buttons).Count -gt 0) {
        return $true
    }

    if ($Item.PSObject.Properties["Json"] -and -not [string]::IsNullOrWhiteSpace("$($Item.Json)")) {
        return $true
    }

    return $false
}

function Test-ActionAgainstSchema {
    param(
        [object]$Item
    )

    $schema = Get-ActionSchema -ActionType $Item.ActionType
    if ($null -eq $schema) {
        return [PSCustomObject]@{
            IsValid = $false
            Error = "Unsupported action type '$($Item.ActionType)'."
        }
    }

    foreach ($field in $schema.Required) {
        if (-not $Item.PSObject.Properties[$field]) {
            return [PSCustomObject]@{
                IsValid = $false
                Error = "Missing required field '$field' for action '$($Item.ActionType)'."
            }
        }

        $value = "$($Item.$field)"
        if ([string]::IsNullOrWhiteSpace($value)) {
            return [PSCustomObject]@{
                IsValid = $false
                Error = "Field '$field' cannot be empty for action '$($Item.ActionType)'."
            }
        }
    }

    foreach ($field in $schema.UrlFields) {
        $value = "$($Item.$field)"
        if (-not (Test-ActionUrlValue -Value $value)) {
            return [PSCustomObject]@{
                IsValid = $false
                Error = "Field '$field' must be a valid http/https URL for action '$($Item.ActionType)'."
            }
        }
    }

    if ($Item.ActionType -eq "BUTTONS" -and -not (Test-ActionButtonsValue -Item $Item)) {
        return [PSCustomObject]@{
            IsValid = $false
            Error = "BUTTONS actions require either 'Buttons' entries or a JSON payload."
        }
    }

    return [PSCustomObject]@{
        IsValid = $true
        Error = $null
    }
}

function Invoke-ActionValidationGuard {
    param(
        [string]$ChatId,
        [object]$Item,
        [string]$Error
    )

    $raw = if ($Item.PSObject.Properties["Raw"]) { $Item.Raw } else { $Item.ActionType }
    Write-Host "[GUARD] Invalid action blocked: $($Item.ActionType) -> $Error" -ForegroundColor DarkYellow
    Add-ChatMemory -chatId $ChatId -role "user" -content "[SYSTEM]: The previous action was invalid and was not executed.`nAction: $raw`nReason: $Error`nFix the action and continue."
}
