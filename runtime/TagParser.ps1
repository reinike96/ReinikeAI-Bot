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

function Get-ActionPayloadList {
    param([object]$Actions)

    if ($null -eq $Actions) {
        return @()
    }

    if ($Actions -is [string]) {
        return @($Actions)
    }

    # If it's an array, return as-is
    if ($Actions -is [System.Collections.IEnumerable] -and $Actions -isnot [pscustomobject] -and $Actions -isnot [hashtable]) {
        return @($Actions)
    }

    # If it's a single object with a "type" property, wrap it in an array
    if ($Actions -is [pscustomobject] -or $Actions -is [hashtable]) {
        if ($Actions.PSObject.Properties["type"]) {
            return @($Actions)
        }
    }

    return @($Actions)
}

function Convert-StructuredPayloadObjectToItems {
    param(
        [object]$Payload,
        [string]$Raw
    )

    if ($null -eq $Payload) {
        return $null
    }

    $hasReply = $Payload.PSObject.Properties["reply"] -or $Payload.PSObject.Properties["actions"]
    if (-not $hasReply) {
        return $null
    }

    $items = @()

    $reply = if ($Payload.PSObject.Properties["reply"]) { "$($Payload.reply)" } else { "" }
    if (-not [string]::IsNullOrWhiteSpace($reply)) {
        $items += [PSCustomObject]@{
            Kind    = "text"
            Content = $reply
        }
    }

    $actions = if ($Payload.PSObject.Properties["actions"]) { Get-ActionPayloadList -Actions $Payload.actions } else { @() }
    foreach ($action in $actions) {
        if ($null -eq $action) { continue }
        $actionType = if ($action.PSObject.Properties["type"]) { "$($action.type)".ToUpperInvariant() } else { "" }
        if ([string]::IsNullOrWhiteSpace($actionType)) { continue }

        $item = [ordered]@{
            Kind       = "action"
            ActionType = $actionType
            Raw        = $Raw
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

    return Convert-StructuredPayloadObjectToItems -Payload $payload -Raw $payloadText
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
                if (
                    $candidateText -match '(?is)"type"\s*:\s*"(BUTTONS|CMD|OPENCODE|PW_CONTENT|PW_SCREENSHOT|SCREENSHOT|STATUS)"' -or
                    $candidateText -match '(?is)"reply"\s*:' -or
                    $candidateText -match '(?is)"actions"\s*:'
                ) {
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
            $candidatePayload = $match.Value | ConvertFrom-Json -ErrorAction Stop
            $structuredItems = Convert-StructuredPayloadObjectToItems -Payload $candidatePayload -Raw $match.Value
            if ($null -ne $structuredItems) {
                $items += @($structuredItems)
            }
            else {
                $actionType = if ($candidatePayload.PSObject.Properties["type"]) { "$($candidatePayload.type)".ToUpperInvariant() } else { "" }
                if (-not [string]::IsNullOrWhiteSpace($actionType)) {
                    $item = [ordered]@{
                        Kind       = "action"
                        ActionType = $actionType
                        Raw        = $match.Value
                    }

                    switch ($actionType) {
                        "CMD" { $item["Command"] = "$($candidatePayload.command)" }
                        "OPENCODE" {
                            $item["Route"] = if ($candidatePayload.PSObject.Properties["route"]) { "$($candidatePayload.route)" } else { "chat" }
                            $item["Task"] = Get-OpenCodeTaskFromActionPayload -Action $candidatePayload
                        }
                        "PW_CONTENT" { $item["Url"] = "$($candidatePayload.url)" }
                        "PW_SCREENSHOT" { $item["Url"] = "$($candidatePayload.url)" }
                        "BUTTONS" {
                            $item["Text"] = "$($candidatePayload.text)"
                            $item["Buttons"] = @($candidatePayload.buttons)
                        }
                        "STATUS" { }
                        "SCREENSHOT" { }
                        default { }
                    }

                    $items += [PSCustomObject]$item
                }
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

    $trimmedResponse = $Response.Trim()
    if ($trimmedResponse -match '(?is)^\[OPENCODE:\s*(.+?)\s*\|\s*([\s\S]+)\]$') {
        return @([PSCustomObject]@{
            Kind       = "action"
            ActionType = "OPENCODE"
            Raw        = $trimmedResponse
            Route      = $Matches[1].Trim()
            Task       = $Matches[2].Trim()
        })
    }

    $tagPattern = '(?is)\[BUTTONS:.*?\]\]|\[(OPENCODE|CMD|SCREENSHOT|STATUS|PW_CONTENT|PW_SCREENSHOT).*?\]'
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

        if ($tag -match '(?is)^\[BUTTONS:\s*(.+?)\s*\|\s*(.+)\]\]$') {
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
