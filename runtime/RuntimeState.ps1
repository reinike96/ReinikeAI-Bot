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
        WindowsUseApprovals    = @{}
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

function Get-WindowsUseApprovals {
    return (Get-RuntimeContext).WindowsUseApprovals
}

function Get-WindowsUseTaskTextFromCommand {
    param([string]$Command)

    if ([string]::IsNullOrWhiteSpace($Command)) {
        return ""
    }

    if ($Command -match '-Task\s+"([^"]*)"') {
        return "$($Matches[1])"
    }

    if ($Command -match "-Task\s+'([^']*)'") {
        return "$($Matches[1])"
    }

    return ""
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

function Get-WindowsUseApprovalScopeTokens {
    param([hashtable]$Approval)

    if ($null -eq $Approval) {
        return @()
    }

    $scopeParts = @()
    if ($Approval.ContainsKey("ScopeText") -and -not [string]::IsNullOrWhiteSpace("$($Approval.ScopeText)")) {
        $scopeParts += "$($Approval.ScopeText)"
    }
    if ($Approval.ContainsKey("Command")) {
        $taskText = Get-WindowsUseTaskTextFromCommand -Command "$($Approval.Command)"
        if (-not [string]::IsNullOrWhiteSpace($taskText)) {
            $scopeParts += $taskText
        }
    }

    $allTokens = @()
    foreach ($part in $scopeParts) {
        $allTokens += @(Get-TextSimilarityTokens -Text $part)
    }
    return @($allTokens | Select-Object -Unique)
}

function Set-WindowsUseApproval {
    param(
        [string]$ChatId,
        [string]$UserId = "",
        [string]$Command = "",
        [string]$ScopeText = ""
    )

    if ([string]::IsNullOrWhiteSpace($ChatId)) {
        return
    }

    (Get-WindowsUseApprovals)[$ChatId] = @{
        ChatId = $ChatId
        UserId = $UserId
        Command = $Command
        ScopeText = $ScopeText
        GrantedAt = Get-Date
    }
}

function Clear-WindowsUseApproval {
    param([string]$ChatId)

    if ([string]::IsNullOrWhiteSpace($ChatId)) {
        return
    }

    $approvals = Get-WindowsUseApprovals
    if ($approvals.ContainsKey($ChatId)) {
        $approvals.Remove($ChatId) | Out-Null
    }
}

function Test-WindowsUseApprovalActive {
    param(
        [string]$ChatId,
        [string]$UserId = "",
        [string]$Command = ""
    )

    if ([string]::IsNullOrWhiteSpace($ChatId)) {
        return $false
    }

    $approvals = Get-WindowsUseApprovals
    if (-not $approvals.ContainsKey($ChatId)) {
        return $false
    }

    $approval = $approvals[$ChatId]
    if ($null -eq $approval) {
        return $false
    }

    if (-not [string]::IsNullOrWhiteSpace($UserId) -and -not [string]::IsNullOrWhiteSpace("$($approval.UserId)") -and "$($approval.UserId)" -ne "$UserId") {
        return $false
    }

    $grantedAt = $approval.GrantedAt
    if ($null -eq $grantedAt) {
        return $false
    }

    if (((Get-Date) - $grantedAt).TotalMinutes -gt 15) {
        Clear-WindowsUseApproval -ChatId $ChatId
        return $false
    }

    if (-not [string]::IsNullOrWhiteSpace($Command)) {
        $scopeTokens = @(Get-WindowsUseApprovalScopeTokens -Approval $approval)
        $candidateTask = Get-WindowsUseTaskTextFromCommand -Command $Command
        $candidateText = if ([string]::IsNullOrWhiteSpace($candidateTask)) { $Command } else { $candidateTask }
        $candidateTokens = @(Get-TextSimilarityTokens -Text $candidateText)
        $importantTokens = @($candidateTokens | Where-Object { ($_.Length -ge 4) -or ($_ -match '^\d+$') })

        if ($importantTokens.Count -eq 0) {
            $importantTokens = $candidateTokens
        }

        if ($importantTokens.Count -eq 0 -or $scopeTokens.Count -eq 0) {
            return $false
        }

        $matches = @($importantTokens | Where-Object { $scopeTokens -contains $_ })
        $coverage = $matches.Count / [double]$importantTokens.Count
        if ($coverage -lt 0.72) {
            return $false
        }
    }

    return $true
}

function Reset-LastExecutedTags {
    (Get-RuntimeContext).LastExecutedTags = @{}
}
