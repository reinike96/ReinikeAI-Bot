function Invoke-ParsedAction {
    param(
        [object]$Item,
        [string]$ChatId,
        [int]$LastUserIndex
    )

    $result = [ordered]@{
        RequiresLoop = $false
        PendingButtons = $null
        Blocked = $false
        BlockedTag = $null
    }

    if ($Item.ActionType -eq "OPENCODE") {
        $typeAndMcps = $Item.Route
        $taskDescription = $Item.Task

        [array]$mcps = @()
        if ($typeAndMcps -match 'chat\s+(.+)') {
            $mcps = $Matches[1].Split(',') | ForEach-Object { $_.Trim() }
        }

        if (Test-OpenCodeTaskAlreadyDone -ChatId $ChatId -LastUserIndex $LastUserIndex -Task $taskDescription) {
            Invoke-OpenCodeTaskGuard -ChatId $ChatId -Task $taskDescription
            $result.RequiresLoop = $true
            return [PSCustomObject]$result
        }

        $plan = New-OpenCodeExecutionPlan -Task $taskDescription -EnableMCPs $mcps

        $emojiHourglass = [char]::ConvertFromUtf32(0x23F3)
        $capabilityRisk = Get-CapabilityRiskProfile -Capability $plan.Capability
        $msgStatus = "$emojiHourglass Delegating to OpenCode ($($plan.Capability), risk: $($capabilityRisk.Level)): $taskDescription"

        if ($plan.Agent) {
            $newJob = Start-OpenCodeJob -TaskDescription $taskDescription -ChatId $ChatId -EnableMCPs $plan.EnableMCPs -Agent $plan.Agent -TimeoutSec $plan.ExpectedTimeoutSec
        }
        else {
            $newJob = Start-OpenCodeJob -TaskDescription $taskDescription -ChatId $ChatId -EnableMCPs $plan.EnableMCPs -Model $plan.Model -TimeoutSec $plan.ExpectedTimeoutSec
        }
        if (-not [string]::IsNullOrWhiteSpace($plan.Label)) {
            $newJob.Label = $plan.Label
        }
        $newJob.Capability = $plan.Capability
        $newJob.CapabilityRisk = $capabilityRisk.Level
        $newJob.ExecutionMode = $plan.ExecutionMode
        Update-TelegramStatus -job $newJob -text $msgStatus
        Add-ActiveJob -JobRecord $newJob
        Write-JobsFile
        return [PSCustomObject]$result
    }

    if ($Item.ActionType -eq "CMD") {
        $cmd = $Item.Command
        Write-Host "[ACTION] CMD: '$cmd'" -ForegroundColor DarkYellow

        if ($cmd -match '(?i)OpenCode-Task') {
            $label = "OpenCode Task"
            if ($cmd -match '([a-zA-Z0-9_-]+\.ps1)') { $label = $Matches[1] }
            $existingJob = Get-ActiveJobs | Where-Object { $_.Type -eq 'Script' -and $_.ChatId -eq $ChatId }
            if ($null -ne $existingJob) {
                Add-ChatMemory -chatId $ChatId -role "user" -content "[System]: There is already an OpenCode task running. Wait for it to finish."
            }
            else {
                $emojiHourglass2 = [char]::ConvertFromUtf32(0x23F3)
                $msgStatus = "$emojiHourglass2 Running $label in the background..."
                Send-TelegramText -chatId $ChatId -text $msgStatus
                Add-ActiveJob -JobRecord (Start-ScriptJob -scriptCmd $cmd -chatId $ChatId -taskLabel $label)
                Write-JobsFile
            }
            return [PSCustomObject]$result
        }

        $riskProfile = Get-CommandRiskProfile -Command $cmd
        if ($riskProfile.Level -eq "confirm") {
            $confirmationId = [guid]::NewGuid().ToString("N")
            Add-PendingConfirmation -ConfirmationId $confirmationId -Payload @{
                Command   = $cmd
                ChatId    = $ChatId
                CreatedAt = Get-Date
            }
            $buttons = New-ConfirmationButtons -ConfirmData "confirm_cmd:$confirmationId" -CancelData "cancel_cmd:$confirmationId"
            $confirmText = "*Confirmation required*`nReason: $($riskProfile.Reason)`n`nCommand:`n``$cmd``"
            Send-TelegramText -chatId $ChatId -text $confirmText -buttons $buttons
            Add-ChatMemory -chatId $ChatId -role "user" -content "[SYSTEM]: A sensitive command is waiting for user confirmation: $cmd"
            return [PSCustomObject]$result
        }

        $cmdRes = Run-PCAction -actionStr $cmd -chatId $ChatId
        Add-ChatMemory -chatId $ChatId -role "user" -content "[SYSTEM - CMD RESULT]:`n$cmdRes`n`nAnalyze the result above and reply to the user. Do not repeat the command."
        $result.RequiresLoop = $true
        return [PSCustomObject]$result
    }

    if ($Item.ActionType -eq "PW_CONTENT") {
        $url = $Item.Url
        Write-Host "[ACTION] PW_CONTENT: $url" -ForegroundColor Cyan
        Send-TelegramTyping -chatId $ChatId
        $pwRes = Run-PCAction -actionStr "powershell -File .\skills\Playwright\playwright-nav.ps1 -Action GetContent -Url '$url'" -chatId $ChatId
        Add-ChatMemory -chatId $ChatId -role "user" -content "[SYSTEM - WEB CONTENT FROM $url]:`n$pwRes`n`nAnalyze this content and reply to the user."
        $result.RequiresLoop = $true
        return [PSCustomObject]$result
    }

    if ($Item.ActionType -eq "PW_SCREENSHOT") {
        $url = $Item.Url
        Write-Host "[ACTION] PW_SCREENSHOT: $url" -ForegroundColor Cyan
        Send-TelegramTyping -chatId $ChatId

        $tempFolder = "$env:TEMP\ReinikeBot"
        if (-not (Test-Path $tempFolder)) { New-Item -Path $tempFolder -ItemType Directory | Out-Null }
        $shotPath = Join-Path $tempFolder "web_ss.png"

        $pwRes = Run-PCAction -actionStr "powershell -File .\skills\Playwright\playwright-nav.ps1 -Action Screenshot -Url '$url' -Out '$shotPath'" -chatId $ChatId
        if (Test-Path $shotPath) {
            Send-TelegramPhoto -chatId $ChatId -filePath $shotPath
            $base64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($shotPath))
            $content = @(
                @{ type = "text"; text = "Here is the screenshot of $url. Analyze it and reply to the user." },
                @{ type = "image_url"; image_url = @{ url = "data:image/jpeg;base64,$base64" } }
            )
            Add-ChatMemory -chatId $ChatId -role "user" -content $content
        }
        else {
            Add-ChatMemory -chatId $ChatId -role "user" -content "[SYSTEM - ERROR]: Could not capture $url. Playwright result: $pwRes"
        }
        $result.RequiresLoop = $true
        return [PSCustomObject]$result
    }

    if ($Item.ActionType -eq "SCREENSHOT") {
        $tempFolder = "$env:TEMP\ReinikeBot"
        if (-not (Test-Path $tempFolder)) { New-Item -Path $tempFolder -ItemType Directory | Out-Null }
        $shotPath = Join-Path $tempFolder "ss.png"
        Run-PCAction -actionStr "[SCREENSHOT]" -chatId $ChatId
        Send-TelegramPhoto -chatId $ChatId -filePath $shotPath

        Write-Host "[ACTION] SCREENSHOT captured and attached to orchestrator." -ForegroundColor Cyan
        $base64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($shotPath))
        $content = @(
            @{ type = "text"; text = "Here is the screenshot you requested. Analyze it and reply to the user." },
            @{ type = "image_url"; image_url = @{ url = "data:image/jpeg;base64,$base64" } }
        )
        Add-ChatMemory -chatId $ChatId -role "user" -content $content
        $result.RequiresLoop = $true
        return [PSCustomObject]$result
    }

    if ($Item.ActionType -eq "STATUS") {
        $statusRes = Run-PCAction -actionStr "powershell -File .\skills\opencode\OpenCode-Status.ps1" -chatId $ChatId
        Add-ChatMemory -chatId $ChatId -role "user" -content "CURRENT TASK STATUS:`n$statusRes"
        $result.RequiresLoop = $true
        return [PSCustomObject]$result
    }

    if ($Item.ActionType -eq "BUTTONS") {
        if ($Item.PSObject.Properties["Buttons"]) {
            $result.PendingButtons = @{ text = $Item.Text; buttons = @($Item.Buttons) }
        }
        else {
            $result.PendingButtons = @{ text = $Item.Text; json = $Item.Json }
        }
        Write-Host "[ACTION] Native buttons detected: $($Item.Text)" -ForegroundColor Cyan
        return [PSCustomObject]$result
    }

    return [PSCustomObject]$result
}
