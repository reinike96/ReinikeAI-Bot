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

    $skillPrefix = Get-OpenCodeSkillPrefix -Task $normalizedTask -PreferredAgent $PreferredAgent
$baseText = @"
$skillPrefix
Verify success from observed state, not attempted action.
Use `web-inspect` first for public-site discovery or latest-item tasks.
Prefer not to pull large JS/JSON/RSS/XML assets into model context when the same result can be obtained by local filtering or targeted extraction. Save tokens when possible.
For short social posts, stop at the minimum source package: title, final URL, date, and 1-3 key points.
Use `playwright` only when rendered DOM behavior or interaction is truly required.

Task:
$normalizedTask
"@.Trim()

    if (-not [string]::IsNullOrWhiteSpace($ExtraInstructions)) {
        return ($baseText + "`n`nExecution notes:`n$ExtraInstructions").Trim()
    }

    return $baseText
}

function Get-OpenCodeSkillPrefix {
    param(
        [string]$Task,
        [string]$PreferredAgent = ""
    )

    if ([string]::IsNullOrWhiteSpace($Task)) {
        return ""
    }

    $normalizedTask = $Task.ToLowerInvariant()
    $agentHint = if ([string]::IsNullOrWhiteSpace($PreferredAgent)) { "" } else { $PreferredAgent.Trim().ToLowerInvariant() }

    $mentionsSite = $normalizedTask -match 'https?://|www\.|(?:\b[a-z0-9-]+\.)+[a-z]{2,}(?:/[^\s]*)?|\bsite\b|\bwebsite\b|\bweb\b|\bsitio\b|\bp[aá]gina\b'
    $mentionsDiscovery = $normalizedTask -match 'latest|newest|most recent|ultimo|último|penultimate|penultimo|penúltimo|find|encuentra|busca|discover|inspect|inspecciona|extract|extrae|url|blog|article|articulo|artículo|news|post'
    $mentionsInteraction = $normalizedTask -match 'publish|publica|publicar|tweet|twitter|x\.com|linkedin|login|log in|sign in|draft|borrador|click|haz clic|type|typing|paste|pega|reply|comment|composer|editor'

    if ($mentionsSite -and $mentionsDiscovery) {
        return "/web-inspect"
    }

    if ($agentHint -eq "social" -or ($mentionsSite -and $mentionsInteraction)) {
        return "/playwright"
    }

    return ""
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

function Convert-ToPowerShellSingleQuotedLiteral {
    param(
        [string]$Value
    )

    if ($null -eq $Value) {
        return "''"
    }

    return "'" + $Value.Replace("'", "''") + "'"
}

function Test-ShouldUseLocalLinkedInDraft {
    param(
        [string]$Task
    )

    if ([string]::IsNullOrWhiteSpace($Task)) {
        return $false
    }

    $normalizedTask = $Task.ToLowerInvariant()
    $mentionsLinkedIn = $normalizedTask -match 'linkedin'
    $mentionsPosting = $normalizedTask -match 'post|publica|publicaci|draft|borrador|editor|composer|feed'
    $mentionsTyping = $normalizedTask -match 'write|escribe|paste|pega|type|typing|editor'
    $mentionsScreenshot = $normalizedTask -match 'screenshot|captura|capture|pantallazo|screen'
    $mentionsNoPublish = $normalizedTask -match "don't publish|do not publish|no publish|no publicar|no lo publiques|sin publicar"

    return ($mentionsLinkedIn -and $mentionsPosting -and ($mentionsTyping -or $mentionsNoPublish -or $mentionsScreenshot))
}

function Test-ShouldUseLocalXDraft {
    param(
        [string]$Task
    )

    if ([string]::IsNullOrWhiteSpace($Task)) {
        return $false
    }

    $normalizedTask = $Task.ToLowerInvariant()
    $mentionsX = $normalizedTask -match 'x\.com|twitter|\btweet\b|\bthread\b'
    $mentionsPosting = $normalizedTask -match 'tweet|thread|post|publica|publicaci|draft|borrador|editor|composer|compose'
    $mentionsTyping = $normalizedTask -match 'write|escribe|paste|pega|type|typing|editor'
    $mentionsScreenshot = $normalizedTask -match 'screenshot|captura|capture|pantallazo|screen'
    $mentionsNoPublish = $normalizedTask -match "don't publish|do not publish|no publish|no publicar|no lo publiques|sin publicar"

    return ($mentionsX -and $mentionsPosting -and ($mentionsTyping -or $mentionsNoPublish -or $mentionsScreenshot))
}

function Test-TaskHasEmbeddedDraftContent {
    param(
        [string]$Task
    )

    if ([string]::IsNullOrWhiteSpace($Task)) {
        return $false
    }

    $normalizedTask = $Task.ToLowerInvariant()
    $hasExplicitHeader = $normalizedTask -match 'contenido del post|texto del post|content of the post|post content|tweet content|comment content|message content|exactly this|this is the post|este es el post|el contenido del post debe ser|the content of the post should be|the post should be|el post debe ser'
    $hasDelimitedBlock = $normalizedTask -match '^---|\n---'
    $hasLongQuotedBlock = $Task -match '(?s)["“][^"”\r\n]{20,}.*?["”]'
    $hasMultiLineBody = $Task -match '(?s):\s*\r?\n\r?\n?.{120,}'

    return ($hasExplicitHeader -or $hasDelimitedBlock -or $hasLongQuotedBlock -or $hasMultiLineBody)
}

function Test-TaskRequiresResearchBeforeDraft {
    param(
        [string]$Task
    )

    if ([string]::IsNullOrWhiteSpace($Task)) {
        return $false
    }

    $normalizedTask = $Task.ToLowerInvariant()
    $mentionsDiscovery = $normalizedTask -match 'latest|newest|most recent|ultimo|último|penultimate|penultimo|penúltimo|previous|anterior|encuentra|find|busca|extract|extrae|summary|resumen|review|revisa|read|lee|analyze|analiza'
    $mentionsSource = $normalizedTask -match 'blog|article|articulo|artículo|news|noticia|post'
    $mentionsDraftTarget = $normalizedTask -match 'tweet|x\.com|twitter|linkedin|social post|post draft|nuevo post|create a post|create a tweet|compose|publish(?:ing)?\s+(?:a\s+)?post|publica(?:r)?\s+(?:un(?:a)?\s+)?post|publicaci[oó]n'

    return ($mentionsDiscovery -and $mentionsSource -and $mentionsDraftTarget)
}

function Test-TaskRequestsFinalPublish {
    param(
        [string]$Task
    )

    if ([string]::IsNullOrWhiteSpace($Task)) {
        return $false
    }

    $normalizedTask = $Task.ToLowerInvariant()
    $mentionsPublish = $normalizedTask -match 'publish|publica|publicar|publishing|post it|send it|submit it|click post|click publish|haz clic en publicar|pulsa publicar|presiona publicar'
    $mentionsNoPublish = $normalizedTask -match "don't publish|do not publish|no publish|no publicar|no lo publiques|sin publicar|leave it as draft|dejalo como borrador|déjalo como borrador|manual review|manually publish|manualmente"

    return ($mentionsPublish -and -not $mentionsNoPublish)
}

function Test-ShouldUseLocalInteractiveBrowserTask {
    param(
        [string]$Task
    )

    if ([string]::IsNullOrWhiteSpace($Task)) {
        return $false
    }

    $normalizedTask = $Task.ToLowerInvariant()
    $mentionsWebsite = $normalizedTask -match 'https?://|www\.|(?:\b[a-z0-9-]+\.)+[a-z]{2,}(?:/[^\s]*)?|\bbrowser\b|\bwebsite\b|\bsite\b|\bweb\b|\bsitio\b|\bp[aá]gina web\b'
    $mentionsInteraction = $normalizedTask -match 'click|haz clic|write|escribe|paste|pega|type|typing|fill|rellena|editor|textarea|form|login|log in|sign in|iniciar sesi|draft|borrador|reply|comment|composer|button|bot[oó]n|publish|publicar|message|mensaje|start a post|create a post|new post'
    $readOnlyOnly = ($normalizedTask -match 'get content|extract|extrae|extract|screenshot|captura|download|descarga|google') -and -not $mentionsInteraction

    return ($mentionsWebsite -and $mentionsInteraction -and -not $readOnlyOnly)
}

function New-OpenCodeExecutionPlan {
    param(
        [string]$Task,
        [string[]]$EnableMCPs = @(),
        [string]$PreferredAgent = "",
        [bool]$AllowLocalScriptShortcuts = $false
    )

    $normalizedTask = if ($null -ne $Task) { $Task.ToLowerInvariant() } else { "" }
    $capability = "general"
    $agent = $null
    $label = "OpenCode"
    $riskLevel = "medium"
    $executionMode = "agent"
    $timeoutSec = 1800
    $extraInstructions = ""
    $explicitAgent = if ([string]::IsNullOrWhiteSpace($PreferredAgent)) { "" } else { $PreferredAgent.Trim().ToLowerInvariant() }
    $requiresPublishApproval = Test-TaskRequestsFinalPublish -Task $Task
    if ($explicitAgent -in @("build", "browser", "docs", "sheets", "computer", "social")) {
        switch ($explicitAgent) {
            "browser" {
                $capability = "browser"
                $label = "OpenCode Browser"
            }
            "docs" {
                $capability = "docs"
                $label = "OpenCode Docs"
            }
            "sheets" {
                $capability = "sheets"
                $label = "OpenCode Sheets"
            }
            "computer" {
                $capability = "computer"
                $label = "OpenCode Computer"
            }
            "social" {
                $capability = "social"
                $label = "OpenCode Social"
                $extraInstructions = @"
This is a logged-in social workflow.
Prefer the repository Playwright helpers for X/LinkedIn, not a generic built-in browser flow.
Do not use Microsoft Edge or the system default browser for these repository Playwright workflows. Use the configured bot Chrome / Chrome-profile flow exposed by the repository helpers.
When invoking repository wrappers such as Invoke-XDraft.ps1, Invoke-LinkedInDraft.ps1, or Invoke-WebInteractive.ps1, always pass the task through a UTF-8 temporary .txt file via -TaskFile instead of inline text parameters.
If research is needed first, do that before browser interaction.
If login is required, leave the browser open and return exactly:
[LOGIN_REQUIRED]
Site: <site name>
Reason: <brief reason>
Do not close the browser in that case. Preserve provided text exactly. Use 0-3 emojis. Keep X single posts within 280 chars. Verify the visible composer/text state before reporting draft ready.
"@.Trim()
            }
        }
    }

    $outlookPattern = '(?i)\b(outlook|correo|correos|email|emails|mail|inbox|bandeja|unread|no le[ií]dos?|send email|send mail|reply|reply to|responder)\b'
    $explicitWebmailPattern = '(?i)\b(gmail|outlook web|outlook.com|hotmail|webmail|browser|website|site|pagina web|sitio web)\b'

    if ($normalizedTask -match $outlookPattern -and $normalizedTask -notmatch $explicitWebmailPattern) {
        $capability = "outlook"
        $extraInstructions = @"
This is an Outlook desktop workflow, not a general browser task.
Prefer the local repository Outlook scripts under .\skills\Outlook\ and Microsoft Outlook COM automation over Playwright or website navigation.
If the user asked to check or review emails, start with .\skills\Outlook\check-outlook-emails.ps1 or .\skills\Outlook\search-outlook-emails.ps1 as appropriate.
For "today"/"hoy" mailbox checks, prefer a bounded command such as .\skills\Outlook\check-outlook-emails.ps1 -DateFilter (Get-Date) -JSON, and add -QuickCheck when a fast inbox-only pass is acceptable.
Prefer JSON output when the goal is to summarize sender, subject, and time.
Use browser or webmail only if the user explicitly asked for Gmail, Outlook Web, outlook.com, hotmail, or another website.
"@.Trim()
    }

    $browserPattern = '(google|browser|navega|navegar|busca|buscar|search|screenshot|captura|capturas|pantallazo|playwright|web)'
    if ($capability -ne "outlook" -and $capability -ne "social" -and $normalizedTask -match $browserPattern) {
        $capability = "browser"
        $extraInstructions = @"
This is a web task. Use the simplest reliable method first.
Use `web-inspect` before broad WebFetch reads when a known page or discovered asset URL is available.
For discovery tasks, inspect root pages and referenced assets before guessing routes.
For SPA/data-file sites, inspect the asset directly and extract only needed fields.
For large JS/JSON/RSS/XML assets, prefer local filtering or targeted extraction instead of pulling the whole body into model context when that saves tokens.
When the task depends on choosing the correct item from a set, identify the candidate list first and inspect only the selected item afterward.
If you need to hand post text or long instructions to a repository script, write them to a UTF-8 temporary .txt file and pass that file path instead of inline text.
Use Playwright only when rendering or interaction is truly required.
If the downstream goal is a short post, stop at the minimum source package instead of writing a long intermediate summary.
Do not restart steps that already succeeded.
"@.Trim()
    }

    if ($AllowLocalScriptShortcuts -and (Test-ShouldUseLocalGoogleResultsScreenshots -Task $Task)) {
        $query = Get-GoogleScreenshotQueryFromTask -Task $Task
        if (-not [string]::IsNullOrWhiteSpace($query)) {
            $quotedQuery = Convert-ToPowerShellSingleQuotedLiteral -Value $query
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
                ScriptCommand = "powershell -File .\skills\Playwright\playwright-nav.ps1 -Action GoogleTopResultsScreenshots -Url $quotedQuery -Out '.\archives'"
            }
        }
    }

    if ($requiresPublishApproval) {
        $publishInstructions = @"
Do not click the final irreversible Post/Publish/Send/Submit button yourself.
Prepare and verify the draft, leave the target page open with the final button visible, and then return this exact marker block:
[PUBLISH_CONFIRMATION_REQUIRED]
Site: <site name>
Task: <single-line bounded Windows-Use task for clicking the final publish/send button in the already-open browser>
Reason: <brief reason>
If the draft could not be prepared and verified first, do not return this marker.
"@.Trim()

        if ([string]::IsNullOrWhiteSpace($extraInstructions)) {
            $extraInstructions = $publishInstructions
        }
        else {
            $extraInstructions = ($extraInstructions + "`n`n" + $publishInstructions).Trim()
        }
    }

    if ($AllowLocalScriptShortcuts -and (Test-ShouldUseLocalLinkedInDraft -Task $Task) -and (Test-TaskHasEmbeddedDraftContent -Task $Task) -and -not (Test-TaskRequiresResearchBeforeDraft -Task $Task)) {
        return [PSCustomObject]@{
            Capability = "social"
            Agent = $null
            Model = $null
            Label = "LinkedIn Draft"
            RiskLevel = $riskLevel
            ExpectedTimeoutSec = 900
            ExecutionMode = "script"
            EnableMCPs = @()
            DelegatedTask = $Task
            ScriptCommand = "powershell -File .\skills\Playwright\Invoke-LinkedInDraft.ps1"
            ScriptTaskInput = "file"
        }
    }

    if ($AllowLocalScriptShortcuts -and (Test-ShouldUseLocalXDraft -Task $Task) -and (Test-TaskHasEmbeddedDraftContent -Task $Task) -and -not (Test-TaskRequiresResearchBeforeDraft -Task $Task)) {
        return [PSCustomObject]@{
            Capability = "social"
            Agent = $null
            Model = $null
            Label = "X Draft"
            RiskLevel = $riskLevel
            ExpectedTimeoutSec = 900
            ExecutionMode = "script"
            EnableMCPs = @()
            DelegatedTask = $Task
            ScriptCommand = "powershell -File .\skills\Playwright\Invoke-XDraft.ps1"
            ScriptTaskInput = "file"
        }
    }

    if ($AllowLocalScriptShortcuts -and (Test-ShouldUseLocalInteractiveBrowserTask -Task $Task) -and -not (Test-TaskRequiresResearchBeforeDraft -Task $Task)) {
        return [PSCustomObject]@{
            Capability = "browser"
            Agent = $null
            Model = $null
            Label = "Web Interactive"
            RiskLevel = $riskLevel
            ExpectedTimeoutSec = 900
            ExecutionMode = "script"
            EnableMCPs = @()
            DelegatedTask = $Task
            ScriptCommand = "powershell -File .\skills\Playwright\Invoke-WebInteractive.ps1"
            ScriptTaskInput = "file"
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
