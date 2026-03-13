function Get-LastUserActionBoundary {
    param([array]$History)

    $lastUserIndex = -1
    for ($i = $History.Count - 1; $i -ge 0; $i--) {
        if ($History[$i].role -eq "user" -and $History[$i].content -notmatch '^\[BUTTON PRESSED') {
            $lastUserIndex = $i
            break
        }
        if ($History[$i].role -eq "system" -and $History[$i].content -match 'REINICIO TOTAL COMPLETADO') {
            $lastUserIndex = $i
            break
        }
    }

    if ($lastUserIndex -eq -1) { $lastUserIndex = 0 }
    return $lastUserIndex
}

function Test-ActionAlreadyExecuted {
    param(
        [string]$Tag,
        [array]$History,
        [int]$LastUserIndex,
        [array]$CurrentTurnTags
    )

    if ($CurrentTurnTags -contains $Tag) {
        return $true
    }

    for ($i = $LastUserIndex; $i -lt ($History.Count - 1); $i++) {
        if ($History[$i].role -eq "assistant" -and $History[$i].content -match [regex]::Escape($Tag)) {
            return $true
        }
    }

    return $false
}

function Invoke-RepeatedActionGuard {
    param(
        [string]$ChatId,
        [string]$Tag
    )

    Write-Host "[GUARD] Blocking repeated action tag: $Tag" -ForegroundColor Yellow
    Add-ChatMemory -chatId $ChatId -role "user" -content "[SYSTEM]: You already attempted the action '$Tag' in this turn or it is duplicated. Do not repeat it. Reply directly with what you already know, or wait for the async result."
}

function Test-OpenCodeTaskAlreadyDone {
    param(
        [string]$ChatId,
        [int]$LastUserIndex,
        [string]$Task
    )

    $historyCheck = Get-ChatMemory -chatId $ChatId
    $historySinceUser = if ($LastUserIndex -ge 0 -and $LastUserIndex -lt $historyCheck.Count) { $historyCheck[$LastUserIndex..($historyCheck.Count - 1)] } else { $historyCheck }

    foreach ($hMsg in $historySinceUser) {
        if ($hMsg.role -eq "system" -and $hMsg.content -match "\[System - Task '" -and $hMsg.content -match [regex]::Escape($Task.Substring(0, [Math]::Min(40, $Task.Length)))) {
            return $true
        }
    }

    return $false
}

function Invoke-OpenCodeTaskGuard {
    param(
        [string]$ChatId,
        [string]$Task
    )

    Write-Host "[GUARD] Blocking repeated OpenCode task from current user turn." -ForegroundColor Yellow
    Add-ChatMemory -chatId $ChatId -role "user" -content "[SYSTEM CRITICAL]: You already ran this task after the user's latest request and the result is already above. Do not repeat it. If the user asked to retry, change the task text slightly."
}

