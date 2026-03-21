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

    function Normalize-OpenCodeTaskForGuard {
        param([string]$Text)

        if ([string]::IsNullOrWhiteSpace($Text)) {
            return ""
        }

        $normalized = $Text.ToLowerInvariant()
        $normalized = [regex]::Replace($normalized, '(?is)\bpersonal data file:\s*[^.\r\n]+\.?', ' ')
        $normalized = [regex]::Replace($normalized, '(?is)\bimportant:\s*you do not need to read the personal data file.*$', ' ')
        $normalized = [regex]::Replace($normalized, '(?is)\bif x requires login, stop and return the \[login_required\] marker\.?', ' ')
        $normalized = [regex]::Replace($normalized, '\s+', ' ').Trim()
        return $normalized
    }

    $historyCheck = Get-ChatMemory -chatId $ChatId
    $historySinceUser = if ($LastUserIndex -ge 0 -and $LastUserIndex -lt $historyCheck.Count) { $historyCheck[$LastUserIndex..($historyCheck.Count - 1)] } else { $historyCheck }
    $candidate = Normalize-OpenCodeTaskForGuard -Text $Task

    if ([string]::IsNullOrWhiteSpace($candidate)) {
        return $false
    }

    foreach ($hMsg in $historySinceUser) {
        if ($hMsg.role -ne "system") {
            continue
        }

        if ($hMsg.content -notmatch "^SYSTEM: Task '(?<doneTask>.+?)' completed by ") {
            continue
        }

        $completed = Normalize-OpenCodeTaskForGuard -Text $Matches['doneTask']
        if ([string]::IsNullOrWhiteSpace($completed)) {
            continue
        }

        if ($completed -eq $candidate) {
            return $true
        }

        if ($completed.Contains($candidate) -or $candidate.Contains($completed)) {
            return $true
        }

        $compareLength = [Math]::Min(120, [Math]::Min($completed.Length, $candidate.Length))
        if ($compareLength -ge 40) {
            $completedPrefix = $completed.Substring(0, $compareLength)
            $candidatePrefix = $candidate.Substring(0, $compareLength)
            if ($completedPrefix -eq $candidatePrefix) {
                return $true
            }
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

function Get-LatestRealUserPrompt {
    param(
        [string]$ChatId
    )

    $history = Get-ChatMemory -chatId $ChatId
    for ($i = $history.Count - 1; $i -ge 0; $i--) {
        $entry = $history[$i]
        if ($entry.role -ne "user") {
            continue
        }

        $contentText = "$($entry.content)"
        if ([string]::IsNullOrWhiteSpace($contentText)) {
            continue
        }
        if ($contentText -match '^\[(SYSTEM|BUTTON PRESSED|UNTRUSTED WEB CONTENT|SYSTEM - CMD RESULT)') {
            continue
        }

        return $contentText
    }

    return ""
}

function Test-ShouldBlockPWContentAction {
    param(
        [string]$ChatId,
        [string]$Url
    )

    if ([string]::IsNullOrWhiteSpace($ChatId) -or [string]::IsNullOrWhiteSpace($Url)) {
        return $false
    }

    $userPrompt = (Get-LatestRealUserPrompt -ChatId $ChatId).ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($userPrompt)) {
        return $false
    }

    $mentionsDiscovery = $userPrompt -match 'latest|newest|most recent|ultimo|último|encuentra|find|busca|discover|discovery|inspect|inspecciona|inspecta|explora|explore'
    $mentionsSiteContent = $userPrompt -match 'blog|article|articulo|artículo|news|noticia|post|website|site|sitio|pagina|página'
    if (-not ($mentionsDiscovery -and $mentionsSiteContent)) {
        return $false
    }

    try {
        $parsedUrl = [System.Uri]$Url
        $path = ""
        if ($null -ne $parsedUrl.AbsolutePath) {
            $path = "$($parsedUrl.AbsolutePath)".Trim().ToLowerInvariant()
        }
        if ([string]::IsNullOrWhiteSpace($path) -or $path -eq "/") {
            return $false
        }
    }
    catch {
        return $false
    }

    return $true
}
