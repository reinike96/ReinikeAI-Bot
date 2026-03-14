function Get-StructuredPayloadText {
    param([string]$Response)

    if ([string]::IsNullOrWhiteSpace($Response)) {
        return $null
    }

    $trimmed = $Response.Trim()
    if ($trimmed -match '(?is)^```json\s*(\{.*\})\s*```$') {
        return $Matches[1].Trim()
    }
    if ($trimmed -match '(?is)^(\{.*\})$') {
        return $Matches[1].Trim()
    }

    return $null
}

function Get-OpenCodeTaskFromActionPayload {
    param([object]$Action)

    if ($null -eq $Action) {
        return ""
    }

    if ($Action.PSObject.Properties["task"] -and -not [string]::IsNullOrWhiteSpace("$($Action.task)")) {
        return "$($Action.task)"
    }

    if ($Action.PSObject.Properties["command"] -and -not [string]::IsNullOrWhiteSpace("$($Action.command)")) {
        $commandValue = "$($Action.command)".Trim()
        if ($commandValue -match '^(?is)(?:chat|build|browser|docs|sheets|computer|social)\s*\|\s*(.+)$') {
            return $Matches[1].Trim()
        }

        return $commandValue
    }

    return ""
}

function Convert-StructuredResponseToActions {
    param([string]$Response)

    $payloadText = Get-StructuredPayloadText -Response $Response
    if ([string]::IsNullOrWhiteSpace($payloadText)) {
        return $null
    }

    try {
        $payload = $payloadText | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return $null
    }

    if ($null -eq $payload) {
        return $null
    }

    $items = @()

    $reply = if ($payload.PSObject.Properties["reply"]) { "$($payload.reply)" } else { "" }
    if (-not [string]::IsNullOrWhiteSpace($reply)) {
        $items += [PSCustomObject]@{
            Kind    = "text"
            Content = $reply
        }
    }

    $actions = if ($payload.PSObject.Properties["actions"]) { @($payload.actions) } else { @() }
    foreach ($action in $actions) {
        if ($null -eq $action) { continue }
        $actionType = if ($action.PSObject.Properties["type"]) { "$($action.type)".ToUpperInvariant() } else { "" }
        if ([string]::IsNullOrWhiteSpace($actionType)) { continue }

        $item = [ordered]@{
            Kind       = "action"
            ActionType = $actionType
            Raw        = $payloadText
        }

        switch ($actionType) {
            "CMD" { $item["Command"] = "$($action.command)" }
            "OPENCODE" {
                $item["Route"] = if ($action.PSObject.Properties["route"]) { "$($action.route)" } else { "chat" }
                $item["Task"] = Get-OpenCodeTaskFromActionPayload -Action $action
            }
            "PW_CONTENT" { $item["Url"] = "$($action.url)" }
            "PW_SCREENSHOT" { $item["Url"] = "$($action.url)" }
            "BUTTONS" {
                $item["Text"] = "$($action.text)"
                $item["Buttons"] = @($action.buttons)
            }
            "STATUS" { }
            "SCREENSHOT" { }
            default { continue }
        }

        $items += [PSCustomObject]$item
    }

    return $items
}

function Convert-InlineStructuredActions {
    param([string]$Response)

    $items = @()
    if ([string]::IsNullOrWhiteSpace($Response)) {
        return $null
    }

    $candidateMatches = @()
    for ($start = 0; $start -lt $Response.Length; $start++) {
        if ($Response[$start] -ne '{') { continue }

        $depth = 0
        $inString = $false
        $escaped = $false

        for ($index = $start; $index -lt $Response.Length; $index++) {
            $char = $Response[$index]

            if ($escaped) {
                $escaped = $false
                continue
            }

            if ($char -eq '\') {
                $escaped = $true
                continue
            }

            if ($char -eq '"') {
                $inString = -not $inString
                continue
            }

            if ($inString) {
                continue
            }

            if ($char -eq '{') { $depth++ }
            if ($char -eq '}') { $depth-- }

            if ($depth -eq 0) {
                $candidateText = $Response.Substring($start, $index - $start + 1)
                if ($candidateText -match '(?is)"type"\s*:\s*"(BUTTONS|CMD|OPENCODE|PW_CONTENT|PW_SCREENSHOT|SCREENSHOT|STATUS)"') {
                    $candidateMatches += [PSCustomObject]@{
                        Index  = $start
                        Length = ($index - $start + 1)
                        Value  = $candidateText
                    }
                }
                break
            }
        }
    }

    if ($candidateMatches.Count -eq 0) {
        return $null
    }

    $lastPos = 0
    foreach ($match in ($candidateMatches | Sort-Object Index -Unique)) {
        if ($match.Index -gt $lastPos) {
            $textChunk = $Response.Substring($lastPos, $match.Index - $lastPos)
            if (-not [string]::IsNullOrWhiteSpace($textChunk)) {
                $items += [PSCustomObject]@{
                    Kind    = "text"
                    Content = $textChunk
                }
            }
        }

        try {
            $action = $match.Value | ConvertFrom-Json -ErrorAction Stop
            $actionType = if ($action.PSObject.Properties["type"]) { "$($action.type)".ToUpperInvariant() } else { "" }
            if (-not [string]::IsNullOrWhiteSpace($actionType)) {
                $item = [ordered]@{
                    Kind       = "action"
                    ActionType = $actionType
                    Raw        = $match.Value
                }

                switch ($actionType) {
                    "CMD" { $item["Command"] = "$($action.command)" }
                    "OPENCODE" {
                        $item["Route"] = if ($action.PSObject.Properties["route"]) { "$($action.route)" } else { "chat" }
                        $item["Task"] = Get-OpenCodeTaskFromActionPayload -Action $action
                    }
                    "PW_CONTENT" { $item["Url"] = "$($action.url)" }
                    "PW_SCREENSHOT" { $item["Url"] = "$($action.url)" }
                    "BUTTONS" {
                        $item["Text"] = "$($action.text)"
                        $item["Buttons"] = @($action.buttons)
                    }
                    "STATUS" { }
                    "SCREENSHOT" { }
                    default { }
                }

                $items += [PSCustomObject]$item
            }
        }
        catch {
            $items += [PSCustomObject]@{
                Kind    = "text"
                Content = $match.Value
            }
        }

        $lastPos = $match.Index + $match.Length
    }

    if ($lastPos -lt $Response.Length) {
        $tail = $Response.Substring($lastPos)
        if (-not [string]::IsNullOrWhiteSpace($tail)) {
            $items += [PSCustomObject]@{
                Kind    = "text"
                Content = $tail
            }
        }
    }

    return $items
}

function Convert-AIResponseToActions {
    param([string]$Response)

    $items = @()
    if ([string]::IsNullOrWhiteSpace($Response)) {
        return $items
    }

    $structuredItems = Convert-StructuredResponseToActions -Response $Response
    if ($null -ne $structuredItems) {
        return @($structuredItems)
    }

    $inlineStructuredItems = Convert-InlineStructuredActions -Response $Response
    if ($null -ne $inlineStructuredItems) {
        return @($inlineStructuredItems)
    }

    $tagPattern = '(?is)\[BUTTONS:.*?(?=\]\]|\]$)(?:\]\]|\])|\[(OPENCODE|CMD|SCREENSHOT|STATUS|PW_CONTENT|PW_SCREENSHOT).*?\]'
    $matches = [regex]::Matches($Response, $tagPattern)
    $lastPos = 0

    foreach ($match in $matches) {
        if ($match.Index -gt $lastPos) {
            $textChunk = $Response.Substring($lastPos, $match.Index - $lastPos)
            if (-not [string]::IsNullOrWhiteSpace($textChunk)) {
                $items += [PSCustomObject]@{
                    Kind    = "text"
                    Content = $textChunk
                }
            }
        }

        $tag = $match.Value
        $postText = $Response.Substring($match.Index + $match.Length)
        $preText = $Response.Substring(0, $match.Index)
        $isEscaped = ($preText -match '`$') -and ($postText -match '^`')
        $isPlaceholder = ($tag -match '^\[(CMD|OPENCODE|STATUS):\s*\.{3,}\s*\]$') -or ($tag -match '^\[(CMD|OPENCODE):\s*\]$')

        if ($isEscaped -or $isPlaceholder) {
            $items += [PSCustomObject]@{
                Kind    = "text"
                Content = $tag
            }
            $lastPos = $match.Index + $match.Length
            continue
        }

        if ($tag -match '(?is)^\[BUTTONS:\s*(.+?)\s*\|\s*(.+?)(?=\]\]|\]$)(?:\]\]|\])$') {
            $items += [PSCustomObject]@{
                Kind       = "action"
                ActionType = "BUTTONS"
                Raw        = $tag
                Text       = $Matches[1].Trim()
                Json       = $Matches[2].Trim()
            }
        }
        elseif ($tag -match '(?is)^\[OPENCODE:\s*(.+?)\s*\|\s*(.+?)\]$') {
            $items += [PSCustomObject]@{
                Kind       = "action"
                ActionType = "OPENCODE"
                Raw        = $tag
                Route      = $Matches[1].Trim()
                Task       = $Matches[2].Trim()
            }
        }
        elseif ($tag -match '(?is)^\[CMD:\s*(.+?)\s*\]$') {
            $items += [PSCustomObject]@{
                Kind       = "action"
                ActionType = "CMD"
                Raw        = $tag
                Command    = $Matches[1].Trim(' ', '`', '(', ')')
            }
        }
        elseif ($tag -match '(?is)^\[PW_CONTENT:\s*(.+?)\s*\]$') {
            $items += [PSCustomObject]@{
                Kind       = "action"
                ActionType = "PW_CONTENT"
                Raw        = $tag
                Url        = $Matches[1].Trim()
            }
        }
        elseif ($tag -match '(?is)^\[PW_SCREENSHOT:\s*(.+?)\s*\]$') {
            $items += [PSCustomObject]@{
                Kind       = "action"
                ActionType = "PW_SCREENSHOT"
                Raw        = $tag
                Url        = $Matches[1].Trim()
            }
        }
        elseif ($tag -match '(?is)^\[SCREENSHOT\]$') {
            $items += [PSCustomObject]@{
                Kind       = "action"
                ActionType = "SCREENSHOT"
                Raw        = $tag
            }
        }
        elseif ($tag -match '(?is)^\[STATUS\]$') {
            $items += [PSCustomObject]@{
                Kind       = "action"
                ActionType = "STATUS"
                Raw        = $tag
            }
        }
        else {
            $items += [PSCustomObject]@{
                Kind    = "text"
                Content = $tag
            }
        }

        $lastPos = $match.Index + $match.Length
    }

    if ($lastPos -lt $Response.Length) {
        $tail = $Response.Substring($lastPos)
        if (-not [string]::IsNullOrWhiteSpace($tail)) {
            $items += [PSCustomObject]@{
                Kind    = "text"
                Content = $tail
            }
        }
    }

    return $items
}
