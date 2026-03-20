function Get-OpenCodeTaskEnvelope {
    param(
        [string]$Task,
        [string]$PreferredAgent = "build",
        [string]$ExtraInstructions = ""
    )

    $normalizedTask = if ($null -ne $Task) { $Task.Trim() } else { "" }
    if ([string]::IsNullOrWhiteSpace($normalizedTask)) {
        return ""
    }

    $agentName = if ([string]::IsNullOrWhiteSpace($PreferredAgent)) { "build" } else { $PreferredAgent.Trim() }
    $routingLine = if ($agentName -eq "build") {
        "Use the build agent as the default execution route for this task."
    }
    else {
        "Use the $agentName agent for this task."
    }

    $baseText = @"
$routingLine
Only if a specialized project agent is clearly needed for part of the work, choose and use it internally as a sub-agent. Available specialized agents: browser, docs, sheets, computer, social.
Do not switch agents unless there is a concrete need.
If you cannot continue reliably without live Windows desktop control through the local Windows-Use skill, stop and return this exact block and nothing more:
[WINDOWS_USE_FALLBACK_REQUIRED]
Task: <single-line bounded Windows-Use task for the local orchestrator>
Reason: <brief reason>
Do not claim you used the local Windows-Use skill yourself.

Task:
$normalizedTask
"@.Trim()

    if (-not [string]::IsNullOrWhiteSpace($ExtraInstructions)) {
        return ($baseText + "`n`nExecution notes:`n$ExtraInstructions").Trim()
    }

    return $baseText
}

function Get-GoogleScreenshotQueryFromTask {
    param(
        [string]$Task
    )

    if ([string]::IsNullOrWhiteSpace($Task)) {
        return ""
    }

    $patterns = @(
        '(?is)search for\s+["''](?<q>[^"'']+)["'']\s+on\s+google',
        '(?is)busca(?:r)?\s+["''](?<q>[^"'']+)["'']\s+en\s+google',
        '(?is)google(?:\.com)?[, ]+\s*search(?: for)?\s+["''](?<q>[^"'']+)["'']',
        '(?is)buscar?\s+en\s+google\s+["''](?<q>[^"'']+)["'']',
        '(?is)search\s+google\s+for\s+["''](?<q>[^"'']+)["'']',
        '(?is)busca(?:r)?\s+(?<q>.+?)\s+en\s+google',
        '(?is)search for\s+(?<q>.+?)\s+on\s+google',
        '(?is)search google for\s+(?<q>.+?)(?:$|,|\.)'
    )

    foreach ($pattern in $patterns) {
        if ($Task -match $pattern) {
            $candidate = $Matches['q'].Trim(' ', '"', "'", '.', ',', ';', ':')
            if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                return $candidate
            }
        }
    }

    $quoted = [regex]::Matches($Task, '["'']([^"'']{2,80})["'']')
    if ($quoted.Count -gt 0) {
        return $quoted[0].Groups[1].Value.Trim()
    }

    return ""
}

function Test-ShouldUseLocalGoogleResultsScreenshots {
    param(
        [string]$Task
    )

    if ([string]::IsNullOrWhiteSpace($Task)) {
        return $false
    }

    $normalizedTask = $Task.ToLowerInvariant()
    $mentionsGoogle = $normalizedTask -match 'google'
    $mentionsShot = $normalizedTask -match 'screenshot|screenshots|captura|capturas|foto|fotos|image|images'
    $mentionsResults = $normalizedTask -match 'result|results|resultado|resultados|link|links|enlace|enlaces|page 1|page 2|page 3|primera|segunda|tercera'

    return ($mentionsGoogle -and $mentionsShot -and $mentionsResults)
}

function New-OpenCodeExecutionPlan {
    param(
        [string]$Task,
        [string[]]$EnableMCPs = @()
    )

    $normalizedTask = if ($null -ne $Task) { $Task.ToLowerInvariant() } else { "" }
    $capability = "general"
    $agent = "build"
    $label = "OpenCode Build"
    $riskLevel = "medium"
    $executionMode = "agent"
    $timeoutSec = 1800
    $extraInstructions = ""

    $outlookPattern = '(?i)\b(outlook|correo|correos|email|emails|mail|inbox|bandeja|unread|no le[ií]dos?|send email|send mail|reply|reply to|responder)\b'
    $explicitWebmailPattern = '(?i)\b(gmail|outlook web|outlook.com|hotmail|webmail|browser|website|site|pagina web|sitio web)\b'

    if ($normalizedTask -match $outlookPattern -and $normalizedTask -notmatch $explicitWebmailPattern) {
        $capability = "outlook"
        $extraInstructions = @"
This is an Outlook desktop workflow, not a general browser task.
Prefer the local repository Outlook scripts under .\skills\Outlook\ and Microsoft Outlook COM automation over Playwright or website navigation.
If the user asked to check or review emails, start with .\skills\Outlook\check-outlook-emails.ps1 or .\skills\Outlook\search-outlook-emails.ps1 as appropriate.
Use browser or webmail only if the user explicitly asked for Gmail, Outlook Web, outlook.com, hotmail, or another website.
"@.Trim()
    }

    $browserPattern = '(google|browser|navega|navegar|busca|buscar|search|screenshot|captura|capturas|pantallazo|playwright|web)'
    if ($capability -ne "outlook" -and $normalizedTask -match $browserPattern) {
        $capability = "browser"
        $extraInstructions = @"
For browser automation, keep using the build agent unless a specialized sub-agent is strictly necessary.
Prefer a deterministic Playwright workflow over ad-hoc visual retries.
Do not restart steps that already succeeded. If the browser is already on the Google results page, continue from there instead of reopening Google and typing the same query again.
If the task is to capture screenshots of the first Google results, prefer the local Playwright wrapper action GoogleTopResultsScreenshots.
"@.Trim()
    }

    if (Test-ShouldUseLocalGoogleResultsScreenshots -Task $Task) {
        $query = Get-GoogleScreenshotQueryFromTask -Task $Task
        if (-not [string]::IsNullOrWhiteSpace($query)) {
            $escapedQuery = $query.Replace('"', '\"')
            $capability = "browser"
            $label = "Playwright Google Results"
            $executionMode = "script"
            $timeoutSec = 600
            return [PSCustomObject]@{
                Capability = $capability
                Agent = $null
                Model = $null
                Label = $label
                RiskLevel = $riskLevel
                ExpectedTimeoutSec = $timeoutSec
                ExecutionMode = $executionMode
                EnableMCPs = @()
                DelegatedTask = $Task
                ScriptCommand = "powershell -File .\skills\Playwright\playwright-nav.ps1 -Action GoogleTopResultsScreenshots -Url `"$escapedQuery`" -Out `".\archives`""
            }
        }
    }

    $wrappedTask = Get-OpenCodeTaskEnvelope -Task $Task -PreferredAgent $agent -ExtraInstructions $extraInstructions
    if ([string]::IsNullOrWhiteSpace($wrappedTask)) {
        $wrappedTask = $Task
    }

    return [PSCustomObject]@{
        Capability = $capability
        Agent = $agent
        Model = $null
        Label = $label
        RiskLevel = $riskLevel
        ExpectedTimeoutSec = $timeoutSec
        ExecutionMode = $executionMode
        EnableMCPs = @($EnableMCPs)
        DelegatedTask = $wrappedTask
    }
}

function Get-CapabilityRiskProfile {
    param(
        [string]$Capability
    )

    switch ($Capability) {
        "computer" {
            return [PSCustomObject]@{
                Level = "high"
                Reason = "Computer-control tasks can affect live applications and the desktop."
            }
        }
        default {
            return [PSCustomObject]@{
                Level = "medium"
                Reason = "General OpenCode task with possible file or workflow side effects."
            }
        }
    }
}
