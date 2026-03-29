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
        MultimodalModel        = $BotConfig.LLM.MultimodalModel
        CurrentReasoningEffort = $BotConfig.LLM.ReasoningEffort
        ActiveJobs             = @()
        ActiveProcesses        = @()
        ParallelOpenCodeGroups = @{}
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

function Get-MultimodalModel {
    return (Get-RuntimeContext).MultimodalModel
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

function Get-ActiveProcesses {
    return @((Get-RuntimeContext).ActiveProcesses)
}

function Get-ParallelOpenCodeGroups {
    return (Get-RuntimeContext).ParallelOpenCodeGroups
}

function Get-ParallelOpenCodeGroup {
    param([string]$GroupId)

    if ([string]::IsNullOrWhiteSpace($GroupId)) {
        return $null
    }

    $groups = Get-ParallelOpenCodeGroups
    if ($groups.ContainsKey($GroupId)) {
        return $groups[$GroupId]
    }

    return $null
}

function Add-ParallelOpenCodeGroup {
    param(
        [string]$GroupId,
        [object]$GroupRecord
    )

    if ([string]::IsNullOrWhiteSpace($GroupId) -or $null -eq $GroupRecord) {
        return
    }

    (Get-ParallelOpenCodeGroups)[$GroupId] = $GroupRecord
}

function Remove-ParallelOpenCodeGroup {
    param([string]$GroupId)

    $groups = Get-ParallelOpenCodeGroups
    if ($groups.ContainsKey($GroupId)) {
        $group = $groups[$GroupId]
        $groups.Remove($GroupId)
        return $group
    }

    return $null
}

function Add-ActiveProcess {
    param([hashtable]$ProcessRecord)

    if ($null -eq $ProcessRecord) {
        return
    }

    $ctx = Get-RuntimeContext
    $ctx.ActiveProcesses = @($ctx.ActiveProcesses) + $ProcessRecord
}

function Remove-ActiveProcessByPid {
    param([int]$TargetPid)

    $ctx = Get-RuntimeContext
    $ctx.ActiveProcesses = @($ctx.ActiveProcesses | Where-Object { [int]$_.Pid -ne $TargetPid })
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

function Find-PendingConfirmation {
    param(
        [string]$ChatId,
        [string]$Command = ""
    )

    foreach ($entry in @((Get-PendingConfirmations).GetEnumerator())) {
        $payload = $entry.Value
        if ($null -eq $payload) {
            continue
        }

        if ("$($payload.ChatId)" -ne "$ChatId") {
            continue
        }

        if ([string]::IsNullOrWhiteSpace($Command) -or "$($payload.Command)" -eq "$Command") {
            return [PSCustomObject]@{
                ConfirmationId = "$($entry.Key)"
                Payload = $payload
            }
        }
    }

    return $null
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

function Get-TextSimilarityTokens {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return @()
    }

    $normalized = $Text.ToLowerInvariant() -replace '[^a-z0-9]+', ' '
    $tokens = @($normalized -split '\s+' | Where-Object {
        (-not [string]::IsNullOrWhiteSpace($_)) -and (($_.Length -ge 3) -or ($_ -match '^\d+$'))
    })
    return @($tokens | Select-Object -Unique)
}

function Reset-LastExecutedTags {
    (Get-RuntimeContext).LastExecutedTags = @{}
}
