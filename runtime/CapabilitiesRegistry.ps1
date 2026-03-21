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

    $baseText = @"
Use specialized project sub-agents only if they are clearly needed for part of the work.
Available specialized agents inside OpenCode include browser, docs, sheets, computer, and social. Decide yourself whether any are needed.
Do not report success just because an action was attempted. Verify the resulting state first.
For browser, UI, and website workflows, success must be based on observable postconditions such as the expected editor being visible, the expected text appearing in the page, the expected file existing, or the expected section being active.
If the expected result cannot be verified, explicitly say the workflow ended in an ambiguous or unverified state and stop instead of improvising more actions.
Do not invoke a local Playwright skill just because the repository contains one. For public-site research, latest-item discovery, and site inspection, prefer fetch-style inspection, direct HTML/JSON/RSS/script retrieval, and static asset analysis first.
When using fetch or WebFetch on a public site, inspect the structure of the current page and its referenced assets before deriving or testing additional URLs.
Do not guess derived site routes or alternate paths before inspecting the root page and understanding how the site is structured.
If the task is to find the latest item on a public site, inspect the raw HTML of the root or known landing page before guessing additional URLs.
If markdown/text extraction hides site structure, scripts, or asset references, switch to raw HTML inspection so you can see script tags, imports, fetch targets, and static asset paths.
If the site appears to be a single-page app or a shell page, look for referenced JS, JSON, RSS, sitemap, fetch calls, imports, or data files before escalating to Playwright.
Do not assume the local Playwright capability in this repository is read-only. Local Playwright-based helpers and custom scripts may be used for interactive browser workflows before considering live desktop control.
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
    $mentionsDiscovery = $normalizedTask -match 'latest|newest|most recent|ultimo|último|encuentra|find|busca|extract|extrae|summary|resumen'
    $mentionsSource = $normalizedTask -match 'blog|article|articulo|artículo|news|noticia|post'
    $mentionsDraftTarget = $normalizedTask -match 'tweet|x\.com|twitter|linkedin|post draft|nuevo post|create a post|create a tweet|compose'

    return ($mentionsDiscovery -and $mentionsSource -and $mentionsDraftTarget)
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
        [string]$PreferredAgent = ""
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
This is a logged-in social website workflow.
Prefer browser automation inside OpenCode for website interaction, typing, clicking, and editor input.
Do not assume the repository Playwright capability is limited to read-only extraction. Local Playwright wrappers and custom Playwright scripts are valid options for interactive website workflows.
If the task first requires researching a public site to discover the latest content or extract source material, do that research without Playwright first. Only use Playwright after the final content and target page are known.
Do not request Windows-Use just because the task involves filling a website form, pressing website buttons, or pasting text into a web editor.
Only escalate to Windows-Use after a concrete browser attempt fails due to an actual blocker such as anti-bot defenses, native OS dialogs, or browser-tool limitations that were encountered in practice.
If login is required or the site is not authenticated, leave the browser open on the login page and return exactly:
[LOGIN_REQUIRED]
Site: <site name>
Reason: <brief reason>
Do not close the browser in that case.
If the task says not to publish, stop before the final publish/submit action and leave the draft ready for the user.
Preserve the provided text exactly.
Do not treat "clicked Start a post" as success by itself. Verify that the composer is visible and that the expected text appears inside it before reporting the draft ready.
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
This is a web task. Choose the simplest reliable method first.
Prefer ordinary fetch-style inspection, direct page retrieval, feeds, sitemaps, structured data, and referenced static assets/scripts before using Playwright.
If the site exposes the needed data in HTML, JSON, RSS, JS, or another static resource, extract it directly instead of opening a browser.
Use Playwright only when rendering, interaction, login state, or browser-only behavior is actually required.
The mere presence of a local Playwright skill in the repository is not a reason to use it for discovery tasks.
When using fetch or WebFetch, inspect the current page structure and the assets it references before deriving new URLs.
Do not guess multiple candidate URLs before inspecting the root page. First fetch the raw HTML of the root or known landing page and inspect its scripts, imports, data files, and fetch targets.
If the site looks like an SPA or the expected content is missing from the returned body, assume the data may live in a JS/JSON asset and investigate that path before using Playwright.
When markdown-style extraction hides implementation details, ask for raw HTML so script tags and static asset references remain visible.
When interaction is required, do not assume the repository Playwright capability is read-only. Local Playwright helpers and custom scripts can handle interactive browser actions before any desktop-control fallback.
For exploratory tasks such as finding the latest post, newest item, hidden endpoint, or site structure, investigate the site directly instead of assuming a Playwright flow.
Do not restart steps that already succeeded.
If the task is to capture screenshots of the first Google results, prefer the local Playwright wrapper action GoogleTopResultsScreenshots.
"@.Trim()
    }

    if (Test-ShouldUseLocalGoogleResultsScreenshots -Task $Task) {
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

    if ((Test-ShouldUseLocalLinkedInDraft -Task $Task) -and (Test-TaskHasEmbeddedDraftContent -Task $Task) -and -not (Test-TaskRequiresResearchBeforeDraft -Task $Task)) {
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

    if ((Test-ShouldUseLocalXDraft -Task $Task) -and (Test-TaskHasEmbeddedDraftContent -Task $Task) -and -not (Test-TaskRequiresResearchBeforeDraft -Task $Task)) {
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

    if ((Test-ShouldUseLocalInteractiveBrowserTask -Task $Task) -and -not (Test-TaskRequiresResearchBeforeDraft -Task $Task)) {
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
