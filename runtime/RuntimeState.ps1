function Get-RuntimeContext {
    if ($null -eq $script:RuntimeContext) {
        throw "Runtime context has not been initialized."
    }

    return $script:RuntimeContext
}

function Initialize-RuntimeState {
    param(
        [object]$BotConfig
    )

    $script:RuntimeContext = [ordered]@{
        CurrentMainModel       = $BotConfig.LLM.PrimaryModel
        SecondaryMainModel     = $BotConfig.LLM.SecondaryModel
        CurrentReasoningEffort = $BotConfig.LLM.ReasoningEffort
        ActiveJobs             = @()
        PendingChats           = @()
        PendingConfirmations   = @{}
        LastExecutedTags       = @{}
    }
}

function Get-CurrentMainModel {
    return (Get-RuntimeContext).CurrentMainModel
}

function Get-SecondaryMainModel {
    return (Get-RuntimeContext).SecondaryMainModel
}

function Get-CurrentReasoningEffort {
    return (Get-RuntimeContext).CurrentReasoningEffort
}

function Set-CurrentReasoningEffort {
    param([string]$Value)

    (Get-RuntimeContext).CurrentReasoningEffort = $Value
}

function Get-ActiveJobs {
    return @((Get-RuntimeContext).ActiveJobs)
}

function Add-ActiveJob {
    param([object]$JobRecord)

    $ctx = Get-RuntimeContext
    $ctx.ActiveJobs = @($ctx.ActiveJobs) + $JobRecord
}

function Remove-ActiveJobById {
    param([object]$JobId)

    $ctx = Get-RuntimeContext
    $ctx.ActiveJobs = @($ctx.ActiveJobs | Where-Object { $_.Job.Id -ne $JobId })
}

function Get-PendingChats {
    return @((Get-RuntimeContext).PendingChats)
}

function Add-PendingChatId {
    param([string]$ChatId)

    $ctx = Get-RuntimeContext
    if ($ctx.PendingChats -notcontains $ChatId) {
        $ctx.PendingChats += $ChatId
    }
}

function Pop-PendingChat {
    $ctx = Get-RuntimeContext
    if ($ctx.PendingChats.Count -eq 0) {
        return $null
    }

    $chatId = $ctx.PendingChats[0]
    $ctx.PendingChats = @($ctx.PendingChats | Where-Object { $_ -ne $chatId })
    return $chatId
}

function Get-PendingConfirmations {
    return (Get-RuntimeContext).PendingConfirmations
}

function Add-PendingConfirmation {
    param(
        [string]$ConfirmationId,
        [hashtable]$Payload
    )

    (Get-RuntimeContext).PendingConfirmations[$ConfirmationId] = $Payload
}

function Remove-PendingConfirmation {
    param([string]$ConfirmationId)

    $confirmations = Get-PendingConfirmations
    if ($confirmations.ContainsKey($ConfirmationId)) {
        $payload = $confirmations[$ConfirmationId]
        $confirmations.Remove($ConfirmationId)
        return $payload
    }

    return $null
}

function Reset-LastExecutedTags {
    (Get-RuntimeContext).LastExecutedTags = @{}
}
