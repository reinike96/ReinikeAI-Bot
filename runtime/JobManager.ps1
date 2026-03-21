function Get-WindowsUseEscalationRequest {
    param([string]$ResultText)

    if ([string]::IsNullOrWhiteSpace($ResultText)) {
        return $null
    }

    if ($ResultText -notmatch '(?s)\[WINDOWS_USE_FALLBACK_REQUIRED\]\s*Task:\s*(?<task>[^\r\n]+)\s*Reason:\s*(?<reason>[^\r\n]+)') {
        return $null
    }

    $taskText = $Matches['task'].Trim()
    $reasonText = $Matches['reason'].Trim()
    if ([string]::IsNullOrWhiteSpace($taskText)) {
        return $null
    }

    return [PSCustomObject]@{
        Task = $taskText
        Reason = $reasonText
    }
}

function Get-LoginRequiredRequest {
    param([string]$ResultText)

    if ([string]::IsNullOrWhiteSpace($ResultText)) {
        return $null
    }

    if ($ResultText -notmatch '(?s)\[LOGIN_REQUIRED\]\s*Site:\s*(?<site>[^\r\n]+)\s*Reason:\s*(?<reason>[^\r\n]+)') {
        return $null
    }

    $siteText = $Matches['site'].Trim()
    $reasonText = $Matches['reason'].Trim()
    if ([string]::IsNullOrWhiteSpace($siteText)) {
        $siteText = "the website"
    }

    return [PSCustomObject]@{
        Site = $siteText
        Reason = $reasonText
    }
}

function Get-DraftReadyRequest {
    param([string]$ResultText)

    if ([string]::IsNullOrWhiteSpace($ResultText)) {
        return $null
    }

    if ($ResultText -notmatch '(?s)\[DRAFT_READY\]\s*Site:\s*(?<site>[^\r\n]+)(?:\s*Screenshot:\s*(?<shot>[^\r\n]+))?') {
        return $null
    }

    return [PSCustomObject]@{
        Site = $Matches['site'].Trim()
        Screenshot = $Matches['shot'].Trim()
    }
}

function Get-OrchestratorUsableResultText {
    param([string]$ResultText)

    if ([string]::IsNullOrWhiteSpace($ResultText)) {
        return ""
    }

    $text = $ResultText.Replace("`r", "").Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return ""
    }

    $anchors = @(
        "[PUBLISH_CONFIRMATION_REQUIRED]",
        "[WINDOWS_USE_FALLBACK_REQUIRED]",
        "[LOGIN_REQUIRED]",
        "[DRAFT_READY]",
        "[POSTED]",
        "**All tasks complete.**",
        "All tasks complete.",
        "**Penultimate blog post identified:**",
        "**Latest post identified:**",
        "**X post published**",
        "**Draft tweet:**"
    )

    $bestIndex = -1
    foreach ($anchor in $anchors) {
        $index = $text.LastIndexOf($anchor, [System.StringComparison]::OrdinalIgnoreCase)
        if ($index -gt $bestIndex) {
            $bestIndex = $index
        }
    }

    if ($bestIndex -gt 0) {
        $start = [Math]::Max(0, $bestIndex - 200)
        $text = $text.Substring($start).Trim()
    }

    $lines = @()
    $lastBlank = $false
    foreach ($line in ($text -split "`n")) {
        $trim = $line.Trim()

        if ([string]::IsNullOrWhiteSpace($trim)) {
            if (-not $lastBlank) {
                $lines += ""
            }
            $lastBlank = $true
            continue
        }

        $skip = $false
        $skipPatterns = @(
            '^(> build\b|> browser\b|> social\b)',
            '^# Todos\b',
            '^\[[ xX]\]\s',
            '^\$\s',
            '^%\s',
            '^Skill\s+"[^"]+"$',
            '^Read\s+archives\\',
            '^Write\s+archives\\',
            '^Wrote file successfully\.$',
            '^Found the blog data asset\.',
            '^Let me\b',
            '^There''s a dedicated\b',
            '^<bash_metadata>$',
            '^</bash_metadata>$',
            '^bash tool terminated command after exceeding timeout'
        )

        foreach ($pattern in $skipPatterns) {
            if ($trim -match $pattern) {
                $skip = $true
                break
            }
        }

        if ($skip) { continue }

        $lines += $line
        $lastBlank = $false
    }

    return (($lines -join "`n").Trim())
}

function Get-PublishConfirmationRequest {
    param([string]$ResultText)

    if ([string]::IsNullOrWhiteSpace($ResultText)) {
        return $null
    }

    if ($ResultText -notmatch '(?s)\[PUBLISH_CONFIRMATION_REQUIRED\]\s*Site:\s*(?<site>[^\r\n]+)\s*Task:\s*(?<task>[^\r\n]+)(?:\s*Reason:\s*(?<reason>[^\r\n]+))?') {
        return $null
    }

    $siteText = $Matches['site'].Trim()
    $taskText = $Matches['task'].Trim()
    $reasonText = $Matches['reason'].Trim()
    if ([string]::IsNullOrWhiteSpace($taskText)) {
        return $null
    }

    return [PSCustomObject]@{
        Site = $siteText
        Task = $taskText
        Reason = $reasonText
    }
}

function Get-LocalBrowserWorkflowStateDetails {
    param(
        [string]$Label
    )

    $stateFileName = switch ("$Label") {
        "LinkedIn Draft" { "linkedin-draft-state.json" }
        "X Draft" { "x-draft-state.json" }
        "Web Interactive" { "web-interactive-state.json" }
        default { "" }
    }

    if ([string]::IsNullOrWhiteSpace($stateFileName)) {
        return $null
    }

    $archivesDir = Join-Path (Get-Location) "archives"
    $statePath = Join-Path $archivesDir $stateFileName
    if (-not (Test-Path $statePath)) {
        return $null
    }

    try {
        $state = Get-Content $statePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $state) {
            return $null
        }

        return [PSCustomObject]@{
            Status = "$($state.status)".Trim()
            Reason = "$($state.reason)".Trim()
            Screenshot = "$($state.screenshot)".Trim()
            CurrentUrl = "$($state.currentUrl)".Trim()
        }
    }
    catch {
        return $null
    }
}

function Test-TaskRequestsFinalPublish {
    param([string]$Task)

    if ([string]::IsNullOrWhiteSpace($Task)) {
        return $false
    }

    $normalizedTask = $Task.ToLowerInvariant()
    $mentionsPublish = $normalizedTask -match 'publish|publica|publicar|publishing|post it|send it|submit it|click post|click publish|haz clic en publicar|pulsa publicar|presiona publicar'
    $mentionsNoPublish = $normalizedTask -match "don't publish|do not publish|no publish|no publicar|no lo publiques|sin publicar|leave it as draft|dejalo como borrador|déjalo como borrador|manually publish|manualmente|manualmente"
    return ($mentionsPublish -and -not $mentionsNoPublish)
}

function Get-PublishSiteNameFromTask {
    param([string]$Task)

    if ([string]::IsNullOrWhiteSpace($Task)) {
        return "the website"
    }

    $normalizedTask = $Task.ToLowerInvariant()
    if ($normalizedTask -match 'linkedin') { return "LinkedIn" }
    if ($normalizedTask -match 'x\.com|twitter|\btweet\b|\bthread\b') { return "X.com" }
    if ($normalizedTask -match 'facebook') { return "Facebook" }
    if ($normalizedTask -match 'instagram') { return "Instagram" }
    if ($normalizedTask -match 'reddit') { return "Reddit" }
    return "the website"
}

function New-PublishWindowsUseTaskFromSite {
    param(
        [string]$Site,
        [string]$OriginalTask
    )

    $siteName = if ([string]::IsNullOrWhiteSpace($Site)) { Get-PublishSiteNameFromTask -Task $OriginalTask } else { $Site.Trim() }
    switch -Regex ($siteName.ToLowerInvariant()) {
        'linkedin' {
            return "In the already-open LinkedIn browser window with the verified draft ready, click the final 'Post' or 'Publish' button once to publish it. Do not edit the text first. If a final confirmation dialog appears, approve it."
        }
        'x\.com|twitter|x' {
            return "In the already-open X.com browser window with the verified draft ready, click the final 'Post' button once to publish it. Do not edit the text first. If a final confirmation dialog appears, approve it."
        }
        default {
            return "In the already-open browser window showing the verified draft on $siteName, click the final Publish/Post/Send/Submit button once to complete the action. Do not edit the text first. If a final confirmation dialog appears, approve it."
        }
    }
}

function Offer-WindowsUseEscalation {
    param(
        [object]$JobRecord,
        [string]$TaskText,
        [string]$ReasonText = ""
    )

    if ([string]::IsNullOrWhiteSpace($TaskText)) {
        return $false
    }

    if (-not (Get-Command Test-WindowsUseFallbackAvailable -ErrorAction SilentlyContinue)) {
        return $false
    }
    if (-not (Test-WindowsUseFallbackAvailable)) {
        return $false
    }

    $windowsUseWrapper = Join-Path $workDir "skills\Windows_Use\Invoke-WindowsUse.ps1"
    if (-not (Test-Path $windowsUseWrapper)) {
        return $false
    }

    $quotedWrapper = if (Get-Command Convert-ToPowerShellSingleQuotedLiteral -ErrorAction SilentlyContinue) {
        Convert-ToPowerShellSingleQuotedLiteral -Value $windowsUseWrapper
    }
    else {
        "'" + $windowsUseWrapper.Replace("'", "''") + "'"
    }
    $quotedTask = if (Get-Command Convert-ToPowerShellSingleQuotedLiteral -ErrorAction SilentlyContinue) {
        Convert-ToPowerShellSingleQuotedLiteral -Value $TaskText
    }
    else {
        "'" + $TaskText.Replace("'", "''") + "'"
    }

    $cmd = "powershell -File $quotedWrapper -Task $quotedTask"
    $confirmationId = [guid]::NewGuid().ToString("N")
    Add-PendingConfirmation -ConfirmationId $confirmationId -Payload @{
        Command    = $cmd
        ChatId     = $JobRecord.ChatId
        UserId     = ""
        UserScoped = $false
        CreatedAt  = Get-Date
    }

    $buttons = New-ConfirmationButtons -ConfirmData "confirm_cmd:$confirmationId" -CancelData "cancel_cmd:$confirmationId"
    $safeReason = if ([string]::IsNullOrWhiteSpace($ReasonText)) { "OpenCode reported that local live desktop control is required." } else { $ReasonText.Trim() }
    if ($safeReason.Length -gt 400) {
        $safeReason = $safeReason.Substring(0, 400) + "..."
    }

    $taskPreview = if ([string]::IsNullOrWhiteSpace($TaskText)) { "" } else { $TaskText.Trim() }
    if ($taskPreview.Length -gt 260) {
        $taskPreview = $taskPreview.Substring(0, 260) + "..."
    }

    $message = @(
        "OpenCode pide confirmacion para un clic/accion final con Windows-Use.",
        "",
        "Motivo:",
        $safeReason,
        "",
        "Accion propuesta:",
        $taskPreview,
        "",
        "Si apruebas, el orquestador lo ejecutara en el escritorio."
    ) -join "`n"

    Send-TelegramText -chatId $JobRecord.ChatId -text $message -buttons $buttons
    Add-ChatMemory -chatId $JobRecord.ChatId -role "user" -content "[SYSTEM]: OpenCode requested a Windows-Use escalation for task '$($JobRecord.Task)'. Reason: $safeReason Proposed Windows-Use task: $TaskText"
    Write-DailyLog -message "Windows-Use escalation offered for job $($JobRecord.Job.Id). Reason='$safeReason' task='$TaskText'" -type "WARN"
    return $true
}

function Offer-PublishConfirmation {
    param(
        [object]$JobRecord,
        [string]$SiteName,
        [string]$TaskText,
        [string]$ReasonText = ""
    )

    $reason = if ([string]::IsNullOrWhiteSpace($ReasonText)) {
        "The draft is ready. The final publish click is treated as a separate irreversible desktop action that requires native confirmation."
    }
    else {
        $ReasonText
    }

    return (Offer-WindowsUseEscalation -JobRecord $JobRecord -TaskText $TaskText -ReasonText $reason)
}

function Get-StuckJobs {
    param(
        [array]$ActiveJobs,
        [string]$WorkDir
    )

    $stuckThreshold = 20.0
    $stuckJobs = @()
    $currentTime = Get-Date

    foreach ($j in $ActiveJobs) {
        $elapsedMinutes = ($currentTime - $j.StartTime).TotalMinutes
        $isCriticallyStuck = $elapsedMinutes -ge $stuckThreshold

        if ($j.Type -eq "OpenCode") {
            $heartbeatFile = if ($j.PSObject.Properties["HeartbeatPath"] -and -not [string]::IsNullOrWhiteSpace("$($j.HeartbeatPath)")) {
                "$($j.HeartbeatPath)"
            }
            else {
                "$WorkDir\heartbeat_$($j.Job.Id).json"
            }
            if (Test-Path $heartbeatFile) {
                try {
                    $hb = Get-Content $heartbeatFile -Raw | ConvertFrom-Json
                    $lastHeartbeat = [DateTime]::Parse($hb.timestamp)
                    $heartbeatAgeSeconds = ($currentTime - $lastHeartbeat).TotalSeconds
                    if ($heartbeatAgeSeconds -lt 300) {
                        $isCriticallyStuck = $false
                    }
                }
                catch {}
            }
        }

        if ($isCriticallyStuck -and $j.Job.State -eq "Running") {
            $j | Add-Member -MemberType NoteProperty -Name "ElapsedMinutes" -Value ([int]$elapsedMinutes) -Force -ErrorAction SilentlyContinue
            $stuckJobs += $j
        }
    }

    return $stuckJobs
}

function Update-ActiveJobTelemetry {
    param(
        [string]$WorkDir
    )

    $currentTime = Get-Date
    foreach ($j in (Get-ActiveJobs)) {
        if ($null -eq $j.LastTyping -or ($currentTime - $j.LastTyping).TotalSeconds -ge 4) {
            Send-TelegramTyping -chatId $j.ChatId
            $j.LastTyping = $currentTime
            $elapsedDisplay = [int]($currentTime - $j.StartTime).TotalMinutes
            Write-Host "[JOB $($j.Job.Id) - $($j.Type) - ${elapsedDisplay}min - $($j.Job.State)]: $($j.Task.Substring(0, [Math]::Min(60, $j.Task.Length)))..." -ForegroundColor DarkGray
        }

        if ($null -ne $j.LastReport) {
            $minutesSinceReport = ($currentTime - $j.LastReport).TotalMinutes
            if ($minutesSinceReport -ge 4.0) {
                $j.LastReport = $currentTime
                $totalElapsed = [int]($currentTime - $j.StartTime).TotalMinutes
                $lastLog = Get-Content "$WorkDir\subagent_events.log" -Tail 5 | Where-Object { $_ -match $j.Type } | Select-Object -Last 1
                $emojiDoc = [char]::ConvertFromUtf32(0x1F4DC)
                $logContext = if ($lastLog) { "$emojiDoc *Latest logged event:*`n``$($lastLog.Trim())``" } else { "Waiting for process output..." }
                $emojiWait = [char]::ConvertFromUtf32(0x231B)
                $statusMsg = "$emojiWait *Task in progress ($($j.Type))*`n" +
                    "*$totalElapsed minutes* have passed since the start.`n`n" +
                    "Capability: $($j.Capability)`n" +
                    "Execution mode: $($j.ExecutionMode)`n" +
                    "$logContext`n`n" +
                    "Still working on it. I will send the final result as soon as it is ready."
                Update-TelegramStatus -job $j -text $statusMsg
            }
        }
    }
}

function Complete-ActiveJobs {
    param(
        [string]$WorkDir
    )

    $completedJobs = Get-ActiveJobs | Where-Object { $_.Job.State -ne "Running" }
    foreach ($j in $completedJobs) {
        Write-DailyLog -message "Job finished: Id=$($j.Job.Id) Type=$($j.Type) State=$($j.Job.State) ChatId=$($j.ChatId)" -type "JOB"

        $rawOutput = Receive-Job -Job $j.Job -ErrorAction SilentlyContinue
        $subRes = if ($null -ne $rawOutput) {
            ($rawOutput | ForEach-Object { "$_" }) -join "`n"
        }
        else { "" }
        $subRes = (Repair-JobEncoding -text $subRes).Trim()
        $usageInfo = Get-OpenCodeUsageFromResultText -ResultText $subRes
        $usageTelegram = ""
        if ($usageInfo) {
            $usageLine = Format-OpenCodeUsageLine -Usage $usageInfo
            if (-not [string]::IsNullOrWhiteSpace($usageLine)) {
                Write-Host "[OpenCode Usage] $usageLine" -ForegroundColor DarkCyan
                Write-DailyLog -message "Job $($j.Job.Id) usage: $usageLine" -type "JOB"
            }
            if ($j.Type -eq "OpenCode") {
                $usageTelegram = Format-OpenCodeUsageLine -Usage $usageInfo
            }
            $subRes = Remove-OpenCodeUsageMarker -ResultText $subRes
        }

        $jobErrors = $j.Job.ChildJobs | ForEach-Object { $_.Error } | Where-Object { $null -ne $_ }
        if ($jobErrors) {
            $errStr = ($jobErrors | ForEach-Object { "$_" }) -join "; "
            Write-DailyLog -message "Job $($j.Job.Id) tuvo errores: $errStr" -type "ERROR"
            if ([string]::IsNullOrWhiteSpace($subRes)) {
                $subRes = "[ERROR en el job]: $errStr"
            }
        }

        if ([string]::IsNullOrWhiteSpace($subRes)) {
            $subRes = "The task finished but returned no text. State: $($j.Job.State)"
        }
        Write-DailyLog -message "Job $($j.Job.Id) result captured: len=$($subRes.Length) chars" -type "JOB"

        if ($j.CheckpointPath) {
            $checkpointStatus = if ($subRes -match '\[WINDOWS_USE_FALLBACK_REQUIRED\]') {
                "needs_desktop_control"
            }
            elseif ($subRes -match '\[LOGIN_REQUIRED\]') {
                "waiting_for_login"
            }
            elseif ($subRes -match '^\[ERROR_') {
                "failed"
            }
            else {
                "completed"
            }
            $checkpointAction = switch ($checkpointStatus) {
                "completed" { "Task completed" }
                "needs_desktop_control" { "Task paused pending Windows-Use escalation" }
                "waiting_for_login" { "Task paused pending manual website login" }
                default { "Task finished with error" }
            }
            try {
                Update-TaskCheckpointState -CheckpointPath $j.CheckpointPath -TaskText $j.Task -Status $checkpointStatus -ResultText $subRes -LastAction $checkpointAction -LastError $(if ($checkpointStatus -eq "failed") { $subRes } elseif ($checkpointStatus -eq "needs_desktop_control") { "OpenCode requested Windows-Use escalation." } elseif ($checkpointStatus -eq "waiting_for_login") { "OpenCode paused because manual website login is required." } else { "" })
            }
            catch {
                Write-DailyLog -message "Checkpoint update failed for job $($j.Job.Id): $_" -type "WARN"
            }
        }

        Remove-Job -Job $j.Job -Force -ErrorAction SilentlyContinue

        if ($j.Type -eq "Subagent" -or $j.Type -eq "OpenCode" -or $j.Type -eq "Script") {
            if (-not [string]::IsNullOrWhiteSpace($usageTelegram)) {
                Send-TelegramText -chatId $j.ChatId -text $usageTelegram
                $usageTelegram = ""
            }

            if (($subRes -match "\[ERROR_OPENCODE_CREDITS\]") -or ($subRes -match "\[OpenCode termino sin output\]")) {
                    Write-DailyLog -message "Detected credit error or silent completion in Job $($j.Job.Id). Retrying through the HTTP API." -type "WARN"

                if ($j.Label -notmatch "Fallback") {
                    $emojiRefresh = [char]::ConvertFromUtf32(0x1F504)
                    Update-TelegramStatus -job $j -text "$emojiRefresh *Insufficient credits.* Retrying with the paid model..."

                    [array]$fallbackMcps = @()
                    if ($j.Label -match "MCP:\s*([^\)]+)") {
                        $fallbackMcps = $Matches[1].Split(',') | ForEach-Object { $_.Trim() }
                    }

                    $fallbackAgent = $null
                    $fallbackJob = Start-OpenCodeJob -TaskDescription $j.Task -ChatId $j.ChatId -EnableMCPs $fallbackMcps -Model "opencode/minimax-m2.5" -Agent $fallbackAgent
                    $fallbackJob.Label = "OpenCode (Fallback Paid)"
                    Add-ActiveJob -JobRecord $fallbackJob
                    Write-JobsFile

                    Remove-Job -Job $j.Job -Force -ErrorAction SilentlyContinue
                    Remove-ActiveJobById -JobId $j.Job.Id
                    continue
                }
            }

            $windowsUseEscalation = Get-WindowsUseEscalationRequest -ResultText $subRes
            if ($j.Type -eq "OpenCode" -and $null -ne $windowsUseEscalation) {
                $offered = Offer-WindowsUseEscalation -JobRecord $j -TaskText $windowsUseEscalation.Task -ReasonText $windowsUseEscalation.Reason
                if ($offered) {
                    Remove-ActiveJobById -JobId $j.Job.Id
                    Write-JobsFile
                    continue
                }
            }

            $publishConfirmation = Get-PublishConfirmationRequest -ResultText $subRes
            if (($j.Type -eq "OpenCode" -or $j.Type -eq "Script") -and $null -ne $publishConfirmation) {
                $offered = Offer-PublishConfirmation -JobRecord $j -SiteName $publishConfirmation.Site -TaskText $publishConfirmation.Task -ReasonText $publishConfirmation.Reason
                if ($offered) {
                    Remove-ActiveJobById -JobId $j.Job.Id
                    Write-JobsFile
                    continue
                }
            }

            $loginRequired = Get-LoginRequiredRequest -ResultText $subRes
            if (($j.Type -eq "OpenCode" -or $j.Type -eq "Script") -and $null -ne $loginRequired) {
                $siteName = $loginRequired.Site
                $reasonText = if ([string]::IsNullOrWhiteSpace($loginRequired.Reason)) { "Login is required before the workflow can continue." } else { $loginRequired.Reason }
                $actorName = if ($j.Type -eq "Script") { "El navegador de automatizacion" } else { "OpenCode" }
                Send-TelegramText -chatId $j.ChatId -text "[LOGIN] $actorName dejo el navegador abierto esperando inicio de sesion en $($siteName)`n`nMotivo: $reasonText`n`nInicia sesion en esa ventana y luego dime ``continua`` para retomar desde donde quedo."
                Add-ChatMemory -chatId $j.ChatId -role "system" -content ("SYSTEM: The task paused because login is required on {0}. The browser was left open for manual sign-in. If the user says continue/continua/reanuda, resume the same task from the checkpoint instead of restarting." -f $siteName)
                Remove-ActiveJobById -JobId $j.Job.Id
                Write-JobsFile
                continue
            }

            $draftReady = Get-DraftReadyRequest -ResultText $subRes
            if ($j.Type -eq "Script" -and $null -ne $draftReady) {
                $siteName = if ([string]::IsNullOrWhiteSpace($draftReady.Site)) { "the website" } else { $draftReady.Site }
                if (Test-TaskRequestsFinalPublish -Task $j.Task) {
                    $publishTask = New-PublishWindowsUseTaskFromSite -Site $siteName -OriginalTask $j.Task
                    $offered = Offer-PublishConfirmation -JobRecord $j -SiteName $siteName -TaskText $publishTask -ReasonText "The draft is ready and verified. The final publish click must be separately approved through Windows-Use."
                    if ($offered) {
                        Remove-ActiveJobById -JobId $j.Job.Id
                        Write-JobsFile
                        continue
                    }
                }
                if ("$($j.Label)" -eq "Web Interactive") {
                    Send-TelegramText -chatId $j.ChatId -text "[READY] La pagina quedo lista en $($siteName)`nDeje el navegador abierto para que revises el estado final y continues manualmente si quieres."
                    Add-ChatMemory -chatId $j.ChatId -role "system" -content "[SYSTEM]: A local browser automation script left $siteName open in a verified ready state for manual review. Do not claim it was submitted or published."
                }
                else {
                    Send-TelegramText -chatId $j.ChatId -text "[READY] El borrador quedo listo en $($siteName)`nDeje el navegador abierto para que revises el texto y pulses publicar manualmente si quieres. No publique nada."
                    Add-ChatMemory -chatId $j.ChatId -role "system" -content "[SYSTEM]: A local browser automation script left the $siteName draft open for manual review and publishing. Do not claim it was published."
                }
                Remove-ActiveJobById -JobId $j.Job.Id
                Write-JobsFile
                continue
            }

            if ($j.Type -eq "Script" -and "$($j.Label)" -in @("LinkedIn Draft", "X Draft", "Web Interactive")) {
                $emojiWarn = [char]::ConvertFromUtf32(0x26A0)
                $preview = if ([string]::IsNullOrWhiteSpace($subRes)) { "(empty output)" } else { $subRes.Trim() }
                if ($preview.Length -gt 500) {
                    $preview = $preview.Substring(0, 500) + "..."
                }

                $workflowName = switch ("$($j.Label)") {
                    "X Draft" { "X" }
                    "LinkedIn Draft" { "LinkedIn" }
                    default { "browser workflow" }
                }
                $stateDetails = Get-LocalBrowserWorkflowStateDetails -Label "$($j.Label)"
                $diagnosticLines = @()
                if ($stateDetails) {
                    if (-not [string]::IsNullOrWhiteSpace($stateDetails.Status)) {
                        $diagnosticLines += "Estado detectado: $($stateDetails.Status)"
                    }
                    if (-not [string]::IsNullOrWhiteSpace($stateDetails.Reason)) {
                        $diagnosticLines += "Causa detectada: $($stateDetails.Reason)"
                    }
                    if (-not [string]::IsNullOrWhiteSpace($stateDetails.CurrentUrl)) {
                        $diagnosticLines += "URL actual: $($stateDetails.CurrentUrl)"
                    }
                }
                Update-TelegramStatus -job $j -text "$emojiWarn *$workflowName ended without confirmation.*"
                $warnText = "[WARN] El flujo de $workflowName no confirmo el estado final: no devolvio ``[DRAFT_READY]`` ni ``[LOGIN_REQUIRED]``. Lo detuve aqui para evitar falsos positivos y no lance reintentos automaticos."
                if ($diagnosticLines.Count -gt 0) {
                    $warnText += "`n`n" + ($diagnosticLines -join "`n")
                }
                $warnText += "`n`nUltima salida:`n$preview"
                Send-TelegramText -chatId $j.ChatId -text $warnText
                Add-ChatMemory -chatId $j.ChatId -role "system" -content ("SYSTEM: A {0} script ended without the required [DRAFT_READY] or [LOGIN_REQUIRED] marker. Do not trigger follow-up screenshots, retries, or new browser actions automatically. Report the ambiguous state directly to the user." -f $workflowName)
                Remove-ActiveJobById -JobId $j.Job.Id
                Write-JobsFile
                continue
            }

            if ($j.Type -eq "Script" -and $subRes.Trim() -eq "Script finished without output.") {
                $emojiWarn = [char]::ConvertFromUtf32(0x26A0)
                Update-TelegramStatus -job $j -text "$emojiWarn *Local script finished without output.*"
                Send-TelegramText -chatId $j.ChatId -text "[WARN] El script local termino sin devolver resultado visible. Lo trate como fallo, no como exito. Si vuelve a pasar tras reiniciar el bot, revisare el helper local de navegador."
                Add-ChatMemory -chatId $j.ChatId -role "system" -content "[SYSTEM]: A local script finished without visible output. Treat this as a failure condition instead of a successful completion."
                Remove-ActiveJobById -JobId $j.Job.Id
                Write-JobsFile
                continue
            }

            if ($j.Type -eq "OpenCode" -and $subRes -match '^\[ERROR_OPENCODE\]\s*(.+)$') {
                $safeError = $Matches[1].Trim()
                $emojiWarn = [char]::ConvertFromUtf32(0x26A0)
                Update-TelegramStatus -job $j -text "$emojiWarn *OpenCode failed.* No automatic local fallback was executed."
                $errorNotice = @(
                    "$emojiWarn OpenCode no pudo completar la tarea.",
                    "",
                    "Error:",
                    $safeError,
                    $(if ($usageInfo) { "" } else { $null }),
                    $(if ($usageInfo) { (Format-OpenCodeUsageLine -Usage $usageInfo) } else { $null }),
                    "",
                    "No ejecute ningun fallback local automatico despues del fallo. Si quieres, reintenta OpenCode o revisa el servidor."
                ) -join "`n"
                Send-TelegramText -chatId $j.ChatId -text $errorNotice
                Add-ChatMemory -chatId $j.ChatId -role "system" -content ("SYSTEM: OpenCode failed for task '{0}'. Error: {1}. Do not start local fallback actions automatically after this failure. Wait for explicit user instruction." -f $j.Task, $safeError)
                Remove-ActiveJobById -JobId $j.Job.Id
                Write-JobsFile
                continue
            }

            $emojiCheck = [char]::ConvertFromUtf32(0x2705)
            Update-TelegramStatus -job $j -text "$emojiCheck *Task completed* ($($j.Type)). Analyzing results..."

            $numFilesSent = Send-DetectedFiles -chatId $j.ChatId -text $subRes
            $fileNotice = if ($numFilesSent -gt 0) { "`n`n[SYSTEM]: $numFilesSent file(s) were detected and automatically sent to the user. Do not try to send them again with 'Telegram_Sender' or 'CMD'." } else { "" }
            $usageNotice = if ($usageInfo -and $j.Type -eq "OpenCode") { "`n`n[SYSTEM]: " + (Format-OpenCodeUsageLine -Usage $usageInfo) } else { "" }

            $sanitizedRes = $subRes -replace '(?i)</?(minimax:)?tool_call.*?>', '' -replace '(?i)</?invoke.*?>', ''
            $usableRes = Get-OrchestratorUsableResultText -ResultText $sanitizedRes
            $memorySummary = if (Get-Command New-TaskCompletionMemorySummary -ErrorAction SilentlyContinue) {
                New-TaskCompletionMemorySummary -TaskText $j.Task -ResultText ($usableRes + $fileNotice + $usageNotice)
            }
            else {
                $fallbackCombined = ($usableRes + $fileNotice + $usageNotice)
                if ($fallbackCombined.Length -gt 1800) {
                    $fallbackCombined.Substring(0, 1800).TrimEnd() + "`n[...summary truncated]"
                }
                else {
                    $fallbackCombined
                }
            }
            $sysMsg = ("SYSTEM: Task '{0}' completed by {1}. Result:`n{2}`n`nYou must now analyze this result and reply to the user with a clear English summary. Do not delegate again. Respond directly." -f $j.Task, $j.Type, $memorySummary)
            try {
                Add-ChatMemory -chatId $j.ChatId -role "system" -content $sysMsg
            }
            catch {
                Write-DailyLog -message "Error saving job memory for $($j.Job.Id): $_" -type "ERROR"
                $truncated = if ($subRes.Length -gt 3800) { $subRes.Substring(0, 3800) + "`n`n[...result truncated due to length]" } else { $subRes }
                Send-TelegramText -chatId $j.ChatId -text "*Direct result:*`n$truncated"
            }

            Add-PendingChatId -ChatId $j.ChatId
        }

        Remove-ActiveJobById -JobId $j.Job.Id
        Write-JobsFile
    }
}

function Expire-PendingConfirmations {
    $pendingConfirmations = Get-PendingConfirmations
    foreach ($confirmationId in @($pendingConfirmations.Keys)) {
        $pending = $pendingConfirmations[$confirmationId]
        if ($null -ne $pending -and ((Get-Date) - $pending.CreatedAt).TotalMinutes -ge 10) {
            $pendingConfirmations.Remove($confirmationId)
        }
    }
}

function Remove-StuckJobs {
    param(
        [string]$WorkDir
    )

    $stuckJobs = Get-StuckJobs -ActiveJobs (Get-ActiveJobs) -WorkDir $WorkDir
    foreach ($j in $stuckJobs) {
        $elapsed = [int]((Get-Date) - $j.StartTime).TotalMinutes
        Write-DailyLog -message "Stuck job detected: Id=$($j.Job.Id) Type=$($j.Type) ChatId=$($j.ChatId) Elapsed=${elapsed}min" -type "WARN"

        $possibleCause = ""
        if ($j.Task -match "imagen|foto|ver|analizar.*imagen|image|photo") {
            $possibleCause = "`n`n*Possible cause:* OpenCode/Minimax does not have reliable vision support for this task. The orchestrator can already analyze images directly."
        }
        elseif ($j.Task -match "pdf|document|binary file") {
            $possibleCause = "`n`n*Possible cause:* The model may struggle with binary files."
        }
        else {
            $possibleCause = "`n`n*Possible cause:* The task may require capabilities the model does not have."
        }

        $emojiWarn = [char]::ConvertFromUtf32(0x26A0)
        $errMsg = "$emojiWarn *Stuck task detected* ($($j.Type))`n"
        $errMsg += "The task has been unresponsive for *$elapsed minutes*.`n"
        $errMsg += "_Task:_ $($j.Task.Substring(0, [Math]::Min(100, $j.Task.Length)))..."
        $errMsg += $possibleCause
        $errMsg += "`n`n_The orchestrator cancelled this task._"
        Send-TelegramText -chatId $j.ChatId -text $errMsg

        if ($j.CheckpointPath) {
            try {
                Update-TaskCheckpointState -CheckpointPath $j.CheckpointPath -TaskText $j.Task -Status "stuck" -LastAction "Task cancelled by stuck-job guard" -LastError "OpenCode task became unresponsive after $elapsed minutes."
            }
            catch {
                Write-DailyLog -message ("Checkpoint update failed for stuck job {0}: {1}" -f $j.Job.Id, $_) -type "WARN"
            }
        }

        Stop-Job -Job $j.Job -ErrorAction SilentlyContinue | Out-Null
        Remove-Job -Job $j.Job -Force -ErrorAction SilentlyContinue
        Remove-ActiveJobById -JobId $j.Job.Id
        Write-JobsFile
    }
}

function Get-OpenCodeUsageFromResultText {
    param([string]$ResultText)

    if ([string]::IsNullOrWhiteSpace($ResultText)) {
        return $null
    }

    $pattern = '(?s)\[OPENCODE_USAGE\]\s*sessionId:\s*(?<session>[^\r\n]*)\s*inputTokens:\s*(?<input>\d+)\s*outputTokens:\s*(?<output>\d+)\s*reasoningTokens:\s*(?<reasoning>\d+)\s*cacheReadTokens:\s*(?<cacheRead>\d+)\s*cacheWriteTokens:\s*(?<cacheWrite>\d+)\s*totalTokens:\s*(?<total>\d+)\s*cost:\s*(?<cost>[0-9.]+)\s*\[/OPENCODE_USAGE\]'
    if ($ResultText -notmatch $pattern) {
        return $null
    }

    return [PSCustomObject]@{
        SessionId = $Matches['session'].Trim()
        InputTokens = [int]$Matches['input']
        OutputTokens = [int]$Matches['output']
        ReasoningTokens = [int]$Matches['reasoning']
        CacheReadTokens = [int]$Matches['cacheRead']
        CacheWriteTokens = [int]$Matches['cacheWrite']
        TotalTokens = [int]$Matches['total']
        Cost = [double]$Matches['cost']
    }
}

function Remove-OpenCodeUsageMarker {
    param([string]$ResultText)

    if ([string]::IsNullOrWhiteSpace($ResultText)) {
        return $ResultText
    }

    return ([regex]::Replace($ResultText, '(?s)\n?\n?\[OPENCODE_USAGE\].*?\[/OPENCODE_USAGE\]\s*', '')).Trim()
}

function Format-OpenCodeUsageLine {
    param([object]$Usage)

    if ($null -eq $Usage) {
        return ""
    }

    $costText = ('{0:N6}' -f [double]$Usage.Cost).TrimEnd('0').TrimEnd('.')
    if ([string]::IsNullOrWhiteSpace($costText)) {
        $costText = "0"
    }

    $emojiChart = [char]::ConvertFromUtf32(0x1F4CA)
    $bullet = [char]::ConvertFromUtf32(0x2022)
    return "$emojiChart OpenCode usage`n$bullet Session total: $($Usage.TotalTokens)`n$bullet Fresh input: $($Usage.InputTokens)`n$bullet Output: $($Usage.OutputTokens)`n$bullet Reasoning: $($Usage.ReasoningTokens)`n$bullet Cache read: $($Usage.CacheReadTokens)`n$bullet Cost: `$$costText"
}

function Invoke-JobMaintenanceCycle {
    param(
        [string]$WorkDir
    )

    Update-ActiveJobTelemetry -WorkDir $WorkDir
    Complete-ActiveJobs -WorkDir $WorkDir
    Expire-PendingConfirmations
    Remove-StuckJobs -WorkDir $WorkDir
}
