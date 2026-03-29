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

function Get-WindowsUseConfirmationRequest {
    param([string]$ResultText)

    if ([string]::IsNullOrWhiteSpace($ResultText)) {
        return $null
    }

    if ($ResultText -notmatch '(?s)\[WINDOWS_USE_CONFIRMATION_REQUIRED\]\s*Task:\s*(?<task>[^\r\n]+)\s*Reason:\s*(?<reason>[^\r\n]+)(?:\s*Risk:\s*(?<risk>[^\r\n]+))?') {
        return $null
    }

    $taskText = $Matches['task'].Trim()
    $reasonText = $Matches['reason'].Trim()
    $riskText = if ($Matches['risk']) { $Matches['risk'].Trim() } else { "" }

    if ([string]::IsNullOrWhiteSpace($taskText)) {
        return $null
    }

    return [PSCustomObject]@{
        Task = $taskText
        Reason = $reasonText
        Risk = $riskText
    }
}

function Get-ToolsMissingRequest {
    param([string]$ResultText)
    if ([string]::IsNullOrWhiteSpace($ResultText)) { return $null }
    if ($ResultText -notmatch '(?s)\[TOOLS_MISSING\]') { return $null }
    $missingTool = ""; $task = ""; $reason = ""
    if ($ResultText -match '(?s)MissingTool:\s*(?<tool>[^\r\n]+)') { $missingTool = $Matches["tool"].Trim() }
    if ($ResultText -match '(?s)Task:\s*(?<t>[^\r\n]+)') { $task = $Matches["t"].Trim() }
    if ($ResultText -match '(?s)Reason:\s*(?<r>[^\r\n]+)') { $reason = $Matches["r"].Trim() }
    return [PSCustomObject]@{ MissingTool = $missingTool; Task = $task; Reason = $reason }
}

function Get-SuggestedAgentForMissingTool {
    param([string]$MissingTool)
    if ([string]::IsNullOrWhiteSpace($MissingTool)) { return $null }
    $tl = $MissingTool.ToLowerInvariant()
    if ($tl -match "playwright|browser|navigate|click|dom") { return [PSCustomObject]@{ Agent = "browser"; ToolName = "Playwright MCP" } }
    if ($tl -match "excel|spreadsheet|xlsx|csv|workbook") { return [PSCustomObject]@{ Agent = "sheets"; ToolName = "Excel MCP" } }
    if ($tl -match "file.converter|pdf|ocr") { return [PSCustomObject]@{ Agent = "docs"; ToolName = "file-converter MCP" } }
    if ($tl -match "word|docx|document generation") { return [PSCustomObject]@{ Agent = "docs"; ToolName = "Word MCP" } }
    if ($tl -match "computer|desktop|mouse|keyboard|gui|window") { return [PSCustomObject]@{ Agent = "computer"; ToolName = "computer-control MCP" } }
    if ($tl -match "stealth|social|linkedin|x\.com") { return [PSCustomObject]@{ Agent = "social"; ToolName = "stealth browser MCP" } }
    return $null
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
        "[LOGIN_REQUIRED]",
        "[TOOLS_MISSING]",
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

    if ($ResultText -notmatch '(?s)\[PUBLISH_CONFIRMATION_REQUIRED\]\s*Site:\s*(?<site>[^\r\n]+)\s*Task:\s*(?<task>[^\r\n]+)(?:\s*Reason:\s*(?<reason>[^\r\n]+))?(?:\s*Screenshot:\s*(?<screenshot>[^\r\n]+))?') {
        return $null
    }

    $siteText = $Matches['site'].Trim()
    $taskText = $Matches['task'].Trim()
    $reasonText = $Matches['reason'].Trim()
    $screenshotText = $Matches['screenshot'].Trim()
    if ([string]::IsNullOrWhiteSpace($taskText)) {
        return $null
    }

    return [PSCustomObject]@{
        Site = $siteText
        Task = $taskText
        Reason = $reasonText
        Screenshot = $screenshotText
    }
}

function Get-OrchestratorParallelPlanRequest {
    param([string]$ResultText)

    if ([string]::IsNullOrWhiteSpace($ResultText)) {
        return $null
    }

    if ($ResultText -notmatch '(?s)\[ORCHESTRATOR_PARALLEL_PLAN\]\s*(?<body>.*?)\s*\[/ORCHESTRATOR_PARALLEL_PLAN\]') {
        return $null
    }

    $body = $Matches['body'].Trim()
    if ([string]::IsNullOrWhiteSpace($body)) {
        return $null
    }

    if ($body -match '(?is)^```json\s*(?<json>.*?)\s*```$') {
        $body = $Matches['json'].Trim()
    }
    elseif ($body -match '(?is)^```\s*(?<json>.*?)\s*```$') {
        $body = $Matches['json'].Trim()
    }

    try {
        $payload = $body | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-DailyLog -message "Parallel plan JSON parse failed: $($_.Exception.Message)" -type "WARN"
        return $null
    }

    if ($null -eq $payload -or -not $payload.PSObject.Properties["tasks"]) {
        return $null
    }

    $rawTasks = @($payload.tasks)
    if ($rawTasks.Count -lt 2 -or $rawTasks.Count -gt 6) {
        Write-DailyLog -message "Parallel plan rejected because task count was $($rawTasks.Count)." -type "WARN"
        return $null
    }

    $allowedRoutes = @("build", "browser", "docs", "sheets", "computer", "social")
    $normalizedTasks = @()
    $index = 0
    foreach ($rawTask in $rawTasks) {
        $index++
        if ($null -eq $rawTask) {
            return $null
        }

        $route = ""
        if ($rawTask.PSObject.Properties["route"]) {
            $route = "$($rawTask.route)".Trim().ToLowerInvariant()
        }
        elseif ($rawTask.PSObject.Properties["agent"]) {
            $route = "$($rawTask.agent)".Trim().ToLowerInvariant()
        }
        if ([string]::IsNullOrWhiteSpace($route)) {
            $route = "build"
        }
        if ($allowedRoutes -notcontains $route) {
            Write-DailyLog -message "Parallel plan rejected because route '$route' is unsupported." -type "WARN"
            return $null
        }

        $taskText = if ($rawTask.PSObject.Properties["task"]) { "$($rawTask.task)".Trim() } else { "" }
        if ([string]::IsNullOrWhiteSpace($taskText)) {
            Write-DailyLog -message "Parallel plan rejected because one child task was empty." -type "WARN"
            return $null
        }

        $title = if ($rawTask.PSObject.Properties["title"] -and -not [string]::IsNullOrWhiteSpace("$($rawTask.title)")) {
            "$($rawTask.title)".Trim()
        }
        else {
            "Parallel task $index"
        }

        $normalizedTasks += [PSCustomObject]@{
            Order = $index
            Title = $title
            Route = $route
            Task  = $taskText
        }
    }

    return [PSCustomObject]@{
        Strategy  = if ($payload.PSObject.Properties["strategy"]) { "$($payload.strategy)".Trim() } else { "" }
        MergeTask = if ($payload.PSObject.Properties["merge_task"]) { "$($payload.merge_task)".Trim() } else { "" }
        Tasks     = @($normalizedTasks)
    }
}

function Test-IsParallelOpenCodeChildJob {
    param([object]$JobRecord)

    return ($null -ne $JobRecord -and "$($JobRecord.Type)" -eq "OpenCode" -and "$($JobRecord.ParallelRole)" -eq "child" -and -not [string]::IsNullOrWhiteSpace("$($JobRecord.ParentParallelGroupId)"))
}

function Test-IsParallelOpenCodeMergeJob {
    param([object]$JobRecord)

    return ($null -ne $JobRecord -and "$($JobRecord.Type)" -eq "OpenCode" -and "$($JobRecord.ParallelRole)" -eq "merge" -and -not [string]::IsNullOrWhiteSpace("$($JobRecord.ParentParallelGroupId)"))
}

function Stop-ParallelOpenCodeGroupChildren {
    param(
        [string]$GroupId,
        [object]$ExcludeJobId = $null
    )

    if ([string]::IsNullOrWhiteSpace($GroupId)) {
        return
    }

    foreach ($jobRecord in @(Get-ActiveJobs | Where-Object {
        "$($_.ParentParallelGroupId)" -eq "$GroupId" -and
        "$($_.ParallelRole)" -eq "child" -and
        $_.Job.Id -ne $ExcludeJobId
    })) {
        try {
            Stop-Job -Job $jobRecord.Job -ErrorAction SilentlyContinue | Out-Null
            Remove-Job -Job $jobRecord.Job -Force -ErrorAction SilentlyContinue
        }
        catch {}
        Remove-ActiveJobById -JobId $jobRecord.Job.Id
    }
}

function New-ParallelOpenCodeMergeTaskText {
    param([object]$Group)

    $children = @()
    if ($null -ne $Group -and $Group.PSObject.Properties["Children"]) {
        $children = @($Group.Children.GetEnumerator() | ForEach-Object { $_.Value } | Sort-Object Order)
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Complete the original task using only the completed parallel branch results below.") | Out-Null
    $lines.Add("Do not rerun the branch work. Merge what is already known, resolve conflicts explicitly, and mention partial failures if any branch failed.") | Out-Null
    if ($Group -and -not [string]::IsNullOrWhiteSpace("$($Group.MergeTask)")) {
        $lines.Add("Merge instructions: $($Group.MergeTask.Trim())") | Out-Null
    }
    if ($Group -and -not [string]::IsNullOrWhiteSpace("$($Group.Strategy)")) {
        $lines.Add("Parallel strategy: $($Group.Strategy.Trim())") | Out-Null
    }
    $lines.Add("") | Out-Null
    $lines.Add("Original task:") | Out-Null
    $lines.Add("$($Group.OriginalTask)".Trim()) | Out-Null

    foreach ($child in $children) {
        $childResult = if ([string]::IsNullOrWhiteSpace("$($child.ResultText)")) {
            "(empty result)"
        }
        elseif (Get-Command Compress-TaskCompletionResult -ErrorAction SilentlyContinue) {
            Compress-TaskCompletionResult -ResultText "$($child.ResultText)" -MaxChars 3200
        }
        else {
            $raw = "$($child.ResultText)".Trim()
            if ($raw.Length -gt 3200) { $raw.Substring(0, 3200).TrimEnd() + "`n[...truncated]" } else { $raw }
        }

        $lines.Add("") | Out-Null
        $lines.Add("Branch $($child.Order): $($child.Title)") | Out-Null
        $lines.Add("Route: $($child.Route)") | Out-Null
        $lines.Add("Task: $($child.Task)") | Out-Null
        $lines.Add("Result:") | Out-Null
        $lines.Add($childResult) | Out-Null
    }

    return ($lines -join "`n").Trim()
}

function Start-ParallelOpenCodeGroupMerge {
    param([object]$Group)

    if ($null -eq $Group) {
        return $null
    }

    $mergeTask = New-ParallelOpenCodeMergeTaskText -Group $Group
    $timeoutSec = if ($Group.PSObject.Properties["TimeoutSec"] -and [int]$Group.TimeoutSec -gt 0) { [int]$Group.TimeoutSec } else { 1800 }
    $mergeJob = Start-OpenCodeJob -TaskDescription $mergeTask -ChatId $Group.ChatId -Agent "build" -TimeoutSec $timeoutSec -AllowParallelPlan:$false
    $mergeJob.Label = "OpenCode Parallel Merge"
    $mergeJob.Capability = "parallel_merge"
    $mergeJob.CapabilityRisk = "medium"
    $mergeJob.ParentParallelGroupId = $Group.GroupId
    $mergeJob.ParallelRole = "merge"
    $mergeJob.AllowParallelPlan = $false
    Add-ActiveJob -JobRecord $mergeJob

    $Group.State = "merging"
    $Group.MergeJobId = $mergeJob.Job.Id
    Write-JobsFile
    Send-TelegramText -chatId $Group.ChatId -text "Las ramas paralelas terminaron. Estoy consolidando el resultado final."
    return $mergeJob
}

function Start-OrchestratorParallelOpenCodePlan {
    param(
        [object]$PlannerJob,
        [object]$Plan
    )

    if ($null -eq $PlannerJob -or $null -eq $Plan) {
        return $null
    }

    $groupId = [guid]::NewGuid().ToString("N")
    $timeoutSec = if ($PlannerJob.PSObject.Properties["TimeoutSec"] -and [int]$PlannerJob.TimeoutSec -gt 0) { [int]$PlannerJob.TimeoutSec } else { 1800 }
    $children = [ordered]@{}

    $group = [PSCustomObject]@{
        GroupId      = $groupId
        ChatId       = $PlannerJob.ChatId
        OriginalTask = $PlannerJob.Task
        Strategy     = "$($Plan.Strategy)".Trim()
        MergeTask    = "$($Plan.MergeTask)".Trim()
        State        = "running_children"
        CreatedAt    = Get-Date
        TimeoutSec   = $timeoutSec
        Children     = $children
        MergeJobId   = $null
    }

    Add-ParallelOpenCodeGroup -GroupId $groupId -GroupRecord $group

    $launched = 0
    foreach ($task in @($Plan.Tasks | Sort-Object Order)) {
        $childTimeout = [Math]::Max(900, $timeoutSec)
        $childJob = Start-OpenCodeJob -TaskDescription $task.Task -ChatId $PlannerJob.ChatId -Agent $task.Route -TimeoutSec $childTimeout -AllowParallelPlan:$false
        $childJob.Label = "OpenCode Parallel Child: $($task.Title)"
        $childJob.Capability = if ($task.Route -eq "build") { "general" } else { $task.Route }
        $childJob.CapabilityRisk = "medium"
        $childJob.ParentParallelGroupId = $groupId
        $childJob.ParallelRole = "child"
        $childJob.ParallelChildTitle = $task.Title
        $childJob.SuppressTelemetry = $true
        $childJob.AllowParallelPlan = $false
        Add-ActiveJob -JobRecord $childJob

        $children["$($childJob.Job.Id)"] = [PSCustomObject]@{
            JobId       = $childJob.Job.Id
            Order       = [int]$task.Order
            Title       = $task.Title
            Route       = $task.Route
            Task        = $task.Task
            Status      = "running"
            StartedAt   = Get-Date
            ResultText  = ""
            UsageLine   = ""
        }
        $launched++
    }

    Write-JobsFile
    Send-TelegramText -chatId $PlannerJob.ChatId -text "OpenCode dividio la tarea en $launched ramas paralelas. Las estoy ejecutando por separado y luego hare un merge final."
    Write-DailyLog -message "Parallel OpenCode group started: group=$groupId chat=$($PlannerJob.ChatId) tasks=$launched" -type "OPENCODE"
    return $group
}

function Handle-ParallelOpenCodeChildCompletion {
    param(
        [object]$JobRecord,
        [string]$ResultText,
        [string]$UsageLine = ""
    )

    if (-not (Test-IsParallelOpenCodeChildJob -JobRecord $JobRecord)) {
        return [PSCustomObject]@{ Handled = $false; ContinueNormalFlow = $true }
    }

    $group = Get-ParallelOpenCodeGroup -GroupId "$($JobRecord.ParentParallelGroupId)"
    if ($null -eq $group) {
        return [PSCustomObject]@{ Handled = $false; ContinueNormalFlow = $true }
    }

    $childKey = "$($JobRecord.Job.Id)"
    if (-not $group.Children.Contains($childKey)) {
        $group.Children[$childKey] = [PSCustomObject]@{
            JobId      = $JobRecord.Job.Id
            Order      = 999
            Title      = if ([string]::IsNullOrWhiteSpace("$($JobRecord.ParallelChildTitle)")) { "Parallel child" } else { "$($JobRecord.ParallelChildTitle)" }
            Route      = if ([string]::IsNullOrWhiteSpace("$($JobRecord.RequestedAgent)")) { "build" } else { "$($JobRecord.RequestedAgent)" }
            Task       = $JobRecord.Task
            Status     = "completed"
            StartedAt  = $JobRecord.StartTime
            ResultText = $ResultText
            UsageLine  = $UsageLine
        }
    }
    else {
        $group.Children[$childKey].Status = "completed"
        $group.Children[$childKey].ResultText = $ResultText
        $group.Children[$childKey].UsageLine = $UsageLine
    }

    $allChildrenDone = @($group.Children.GetEnumerator() | Where-Object { "$($_.Value.Status)" -ne "completed" }).Count -eq 0
    if ($allChildrenDone -and "$($group.State)" -eq "running_children") {
        [void](Start-ParallelOpenCodeGroupMerge -Group $group)
    }

    return [PSCustomObject]@{
        Handled = $true
        ContinueNormalFlow = $false
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

function Get-TelemetryTextPreview {
    param(
        [string]$Text,
        [int]$MaxLength = 180
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }

    $flat = $Text.Replace("`r", " ").Replace("`n", " ").Trim()
    if ([string]::IsNullOrWhiteSpace($flat)) {
        return ""
    }

    if ($flat.Length -le $MaxLength) {
        return $flat
    }

    return ($flat.Substring(0, $MaxLength).TrimEnd() + "...")
}

function Format-TelemetryAgeText {
    param(
        [Nullable[double]]$AgeSeconds
    )

    if ($null -eq $AgeSeconds) {
        return ""
    }

    $seconds = [Math]::Max(0, [int][Math]::Round($AgeSeconds.Value))
    if ($seconds -lt 90) {
        return "${seconds}s"
    }

    $minutes = [Math]::Max(1, [int][Math]::Floor($seconds / 60))
    return "${minutes}m"
}

function Convert-OpenCodeRuntimeStatusToText {
    param([string]$Status)

    $normalized = if ([string]::IsNullOrWhiteSpace($Status)) { "" } else { $Status.Trim().ToLowerInvariant() }
    switch ($normalized) {
        "starting_cli" { return "iniciando CLI" }
        "running_cli" { return "ejecutando CLI" }
        "starting" { return "iniciando job" }
        "creating_session" { return "creando sesion" }
        "session_ready" { return "sesion lista" }
        "sending_message" { return "enviando tarea" }
        "running" { return "trabajando" }
        "pending" { return "pendiente" }
        "waiting_for_login" { return "esperando login manual" }
        "completed" { return "completado" }
        "failed" { return "fallo" }
        "stuck" { return "sin respuesta" }
        "loop_detected" { return "loop detectado" }
        default {
            if ([string]::IsNullOrWhiteSpace($normalized)) {
                return "sin estado"
            }
            return $normalized
        }
    }
}

function Get-OpenCodeHeartbeatSnapshot {
    param(
        [object]$JobRecord,
        [string]$WorkDir
    )

    $heartbeatPath = if ($JobRecord.PSObject.Properties["HeartbeatPath"] -and -not [string]::IsNullOrWhiteSpace("$($JobRecord.HeartbeatPath)")) {
        "$($JobRecord.HeartbeatPath)"
    }
    else {
        Join-Path $WorkDir ("archives\heartbeat_{0}.json" -f $JobRecord.Job.Id)
    }

    $snapshot = [ordered]@{
        Path = $heartbeatPath
        Exists = $false
        Status = ""
        PhaseText = "sin heartbeat"
        Timestamp = $null
        AgeSeconds = $null
        Fresh = $false
    }

    if ([string]::IsNullOrWhiteSpace($heartbeatPath) -or -not (Test-Path $heartbeatPath)) {
        return [PSCustomObject]$snapshot
    }

    try {
        $hb = Get-Content -Path $heartbeatPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $snapshot.Exists = $true
        $snapshot.Status = if ($hb.PSObject.Properties["status"]) { "$($hb.status)".Trim() } else { "" }
        $snapshot.PhaseText = Convert-OpenCodeRuntimeStatusToText -Status $snapshot.Status
        if ($hb.PSObject.Properties["timestamp"] -and -not [string]::IsNullOrWhiteSpace("$($hb.timestamp)")) {
            $snapshot.Timestamp = [DateTime]::Parse($hb.timestamp)
            $snapshot.AgeSeconds = ((Get-Date) - $snapshot.Timestamp).TotalSeconds
            $snapshot.Fresh = $snapshot.AgeSeconds -lt 300
        }
    }
    catch {}

    return [PSCustomObject]$snapshot
}

function Get-OpenCodeCheckpointSnapshot {
    param([string]$CheckpointPath)

    $snapshot = [ordered]@{
        Exists = $false
        Status = ""
        StatusText = ""
        UpdatedAt = $null
        AgeSeconds = $null
        LastAction = ""
        LastError = ""
        LastResultPreview = ""
        CompletedSteps = @()
        PendingSteps = @()
        Notes = @()
        HasObservableProgress = $false
        HasFailureSignal = $false
        HasRetrySignal = $false
        ProgressDigest = ""
    }

    if ([string]::IsNullOrWhiteSpace($CheckpointPath) -or -not (Test-Path $CheckpointPath)) {
        return [PSCustomObject]$snapshot
    }

    $checkpoint = Read-TaskCheckpoint -CheckpointPath $CheckpointPath
    if ($null -eq $checkpoint) {
        return [PSCustomObject]$snapshot
    }

    $snapshot.Exists = $true
    $snapshot.Status = if ($checkpoint.PSObject.Properties["status"]) { "$($checkpoint.status)".Trim() } else { "" }
    $snapshot.StatusText = Convert-OpenCodeRuntimeStatusToText -Status $snapshot.Status
    $snapshot.LastAction = if ($checkpoint.PSObject.Properties["lastAction"]) { Get-TelemetryTextPreview -Text "$($checkpoint.lastAction)" -MaxLength 180 } else { "" }
    $snapshot.LastError = if ($checkpoint.PSObject.Properties["lastError"]) { Get-TelemetryTextPreview -Text "$($checkpoint.lastError)" -MaxLength 180 } else { "" }
    $snapshot.LastResultPreview = if ($checkpoint.PSObject.Properties["lastResultPreview"]) { Get-TelemetryTextPreview -Text "$($checkpoint.lastResultPreview)" -MaxLength 180 } else { "" }
    $snapshot.CompletedSteps = @(
        Convert-ToCheckpointStringArray -Value $checkpoint.completedSteps |
            ForEach-Object { Get-TelemetryTextPreview -Text $_ -MaxLength 120 } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -First 3
    )
    $snapshot.PendingSteps = @(
        Convert-ToCheckpointStringArray -Value $checkpoint.pendingSteps |
            ForEach-Object { Get-TelemetryTextPreview -Text $_ -MaxLength 120 } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -First 3
    )
    $snapshot.Notes = @(
        Convert-ToCheckpointStringArray -Value $checkpoint.notes |
            ForEach-Object { Get-TelemetryTextPreview -Text $_ -MaxLength 140 } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Last 3
    )

    if ($checkpoint.PSObject.Properties["updatedAt"] -and -not [string]::IsNullOrWhiteSpace("$($checkpoint.updatedAt)")) {
        try {
            $snapshot.UpdatedAt = [DateTime]::Parse($checkpoint.updatedAt)
            $snapshot.AgeSeconds = ((Get-Date) - $snapshot.UpdatedAt).TotalSeconds
        }
        catch {}
    }

    $isStartupMarker = (
        $snapshot.Status -in @("", "pending", "running") -and
        $snapshot.LastAction -eq "Task delegated to OpenCode" -and
        $snapshot.CompletedSteps.Count -eq 0 -and
        $snapshot.PendingSteps.Count -eq 0 -and
        $snapshot.Notes.Count -eq 0 -and
        [string]::IsNullOrWhiteSpace($snapshot.LastError) -and
        [string]::IsNullOrWhiteSpace($snapshot.LastResultPreview)
    )

    $snapshot.HasObservableProgress = -not $isStartupMarker -and (
        -not [string]::IsNullOrWhiteSpace($snapshot.LastAction) -or
        -not [string]::IsNullOrWhiteSpace($snapshot.LastError) -or
        -not [string]::IsNullOrWhiteSpace($snapshot.LastResultPreview) -or
        $snapshot.CompletedSteps.Count -gt 0 -or
        $snapshot.PendingSteps.Count -gt 0 -or
        $snapshot.Notes.Count -gt 0 -or
        ($snapshot.Status -notin @("", "pending", "running"))
    )

    $signalText = @(
        $snapshot.LastAction,
        $snapshot.LastError,
        ($snapshot.Notes -join " "),
        ($snapshot.PendingSteps -join " ")
    ) -join " "
    $snapshot.HasFailureSignal = $signalText -match '(?i)\b(fail|failed|error|timeout|timed out|blocked|cannot|could not|no pudo|falla|fallo|atascado)\b'
    $snapshot.HasRetrySignal = $signalText -match '(?i)\b(retry|reintento|attempt|intento|trying|intentando)\b'

    if ($snapshot.HasObservableProgress) {
        $updatedAtText = if ($null -eq $snapshot.UpdatedAt) { "" } else { $snapshot.UpdatedAt.ToUniversalTime().ToString("o") }
        $snapshot.ProgressDigest = @(
            $updatedAtText,
            $snapshot.Status,
            $snapshot.LastAction,
            $snapshot.LastError,
            ($snapshot.CompletedSteps -join "|"),
            ($snapshot.PendingSteps -join "|"),
            ($snapshot.Notes -join "|")
        ) -join "||"
    }

    return [PSCustomObject]$snapshot
}

function Get-OpenCodeDiagnosticsSnapshot {
    param([string]$Path)

    $snapshot = [ordered]@{
        Exists = $false
        UpdatedAt = $null
        ProgressLines = @()
        RecentSummary = ""
        HasObservableProgress = $false
        HasFailureSignal = $false
        HasRetrySignal = $false
        ProgressDigest = ""
    }

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path $Path)) {
        return [PSCustomObject]$snapshot
    }

    try {
        $raw = Get-Content -Path $Path -Raw -Encoding UTF8
        $fileInfo = Get-Item -LiteralPath $Path -ErrorAction Stop
    }
    catch {
        return [PSCustomObject]$snapshot
    }

    $snapshot.Exists = $true
    $snapshot.UpdatedAt = $fileInfo.LastWriteTime

    $sections = @()
    $currentTitle = ""
    $currentLines = @()
    foreach ($line in ($raw -split '\r?\n')) {
        if ($line -match '^##\s+(.+)$') {
            if (-not [string]::IsNullOrWhiteSpace($currentTitle)) {
                $sections += [PSCustomObject]@{
                    Title = $currentTitle
                    Body  = (($currentLines -join "`n").Trim())
                }
            }
            $currentTitle = $Matches[1].Trim()
            $currentLines = @()
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($currentTitle)) {
            $currentLines += $line
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($currentTitle)) {
        $sections += [PSCustomObject]@{
            Title = $currentTitle
            Body  = (($currentLines -join "`n").Trim())
        }
    }

    $progressLines = @()
    foreach ($section in @($sections | Where-Object { "$($_.Title)" -match '^(?i)Progress Log$' })) {
        foreach ($line in ($section.Body -split '\r?\n')) {
            if ($line -match '^\s*-\s+(.+)$') {
                $progressLines += (Get-TelemetryTextPreview -Text $Matches[1] -MaxLength 180)
            }
        }
    }
    $snapshot.ProgressLines = @(
        $progressLines |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Last 4
    )

    $relevantSection = @(
        $sections | Where-Object {
            "$($_.Title)" -match '^(?i)(Completion Error|Unhandled Orchestrator Error|Timeout|Event Capture Warning|Final Response Preview)$'
        } | Select-Object -Last 1
    )[0]
    if ($null -ne $relevantSection) {
        $bodyPreview = Get-TelemetryTextPreview -Text $relevantSection.Body -MaxLength 180
        $snapshot.RecentSummary = if ([string]::IsNullOrWhiteSpace($bodyPreview)) {
            "$($relevantSection.Title)"
        }
        else {
            "$($relevantSection.Title): $bodyPreview"
        }
    }

    $signalText = @(
        ($snapshot.ProgressLines -join " "),
        $snapshot.RecentSummary
    ) -join " "
    $snapshot.HasFailureSignal = $signalText -match '(?i)\b(fail|failed|error|timeout|timed out|blocked|stuck|cannot|could not|no pudo|falla|fallo|atascado)\b'
    $snapshot.HasRetrySignal = $signalText -match '(?i)\b(retry|reintento|attempt|intento|trying|intentando)\b'
    $snapshot.HasObservableProgress = $snapshot.ProgressLines.Count -gt 0 -or -not [string]::IsNullOrWhiteSpace($snapshot.RecentSummary)

    if ($snapshot.HasObservableProgress) {
        $updatedAtText = if ($null -eq $snapshot.UpdatedAt) { "" } else { $snapshot.UpdatedAt.ToUniversalTime().ToString("o") }
        $snapshot.ProgressDigest = @(
            $updatedAtText,
            ($snapshot.ProgressLines -join "|"),
            $snapshot.RecentSummary
        ) -join "||"
    }

    return [PSCustomObject]$snapshot
}

function Get-OpenCodeFallbackLogPreview {
    param([string]$WorkDir)

    $logPath = Join-Path $WorkDir "archives\subagent_events.log"
    if (-not (Test-Path $logPath)) {
        return ""
    }

    try {
        $line = Get-Content -Path $logPath -Tail 40 -Encoding UTF8 |
            Where-Object { $_ -match '\[(OPENCODE|WARN|ERROR)\]' } |
            Select-Object -Last 1
        return (Get-TelemetryTextPreview -Text $line -MaxLength 180)
    }
    catch {
        return ""
    }
}

function Get-OpenCodeTelemetrySnapshot {
    param(
        [object]$JobRecord,
        [string]$WorkDir
    )

    $heartbeat = Get-OpenCodeHeartbeatSnapshot -JobRecord $JobRecord -WorkDir $WorkDir
    $checkpoint = Get-OpenCodeCheckpointSnapshot -CheckpointPath $(if ($JobRecord.PSObject.Properties["CheckpointPath"]) { "$($JobRecord.CheckpointPath)" } else { "" })
    $diagnostics = Get-OpenCodeDiagnosticsSnapshot -Path $(if ($JobRecord.PSObject.Properties["SessionDiagnosticsPath"]) { "$($JobRecord.SessionDiagnosticsPath)" } else { "" })
    $logPreview = ""
    if (-not $checkpoint.HasObservableProgress -and -not $diagnostics.HasObservableProgress) {
        $logPreview = Get-OpenCodeFallbackLogPreview -WorkDir $WorkDir
    }

    $phaseText = if ($checkpoint.HasObservableProgress -and -not [string]::IsNullOrWhiteSpace($checkpoint.StatusText)) {
        $checkpoint.StatusText
    }
    elseif ($heartbeat.Exists) {
        $heartbeat.PhaseText
    }
    else {
        "sin fase visible"
    }

    $progressDigest = ""
    if ($checkpoint.HasObservableProgress) {
        $progressDigest = "checkpoint||$($checkpoint.ProgressDigest)"
    }
    elseif ($diagnostics.HasObservableProgress) {
        $progressDigest = "diagnostics||$($diagnostics.ProgressDigest)"
    }

    return [PSCustomObject]@{
        Heartbeat = $heartbeat
        Checkpoint = $checkpoint
        Diagnostics = $diagnostics
        LogPreview = $logPreview
        PhaseText = $phaseText
        HasObservableProgress = -not [string]::IsNullOrWhiteSpace($progressDigest)
        ProgressDigest = $progressDigest
        HasFailureSignal = ($checkpoint.HasFailureSignal -or $diagnostics.HasFailureSignal)
        HasRetrySignal = ($checkpoint.HasRetrySignal -or $diagnostics.HasRetrySignal)
    }
}

function Update-OpenCodeJobProgressState {
    param(
        [object]$JobRecord,
        [object]$Snapshot,
        [datetime]$CurrentTime
    )

    $lastObservedAction = if ($Snapshot.Checkpoint.LastAction) { $Snapshot.Checkpoint.LastAction } else { "" }
    $lastObservedError = if ($Snapshot.Checkpoint.LastError) { $Snapshot.Checkpoint.LastError } else { "" }
    $lastObservedEvidence = if ($Snapshot.Diagnostics.ProgressLines.Count -gt 0) {
        ($Snapshot.Diagnostics.ProgressLines | Select-Object -Last 2) -join " | "
    }
    elseif (-not [string]::IsNullOrWhiteSpace($Snapshot.Diagnostics.RecentSummary)) {
        $Snapshot.Diagnostics.RecentSummary
    }
    else {
        $Snapshot.LogPreview
    }

    $JobRecord | Add-Member -MemberType NoteProperty -Name "LastObservedAction" -Value $lastObservedAction -Force -ErrorAction SilentlyContinue
    $JobRecord | Add-Member -MemberType NoteProperty -Name "LastObservedError" -Value $lastObservedError -Force -ErrorAction SilentlyContinue
    $JobRecord | Add-Member -MemberType NoteProperty -Name "LastObservedEvidence" -Value $lastObservedEvidence -Force -ErrorAction SilentlyContinue

    $state = [ordered]@{
        ProgressChanged = $false
        StallReports = if ($JobRecord.PSObject.Properties["NoProgressReports"]) { [int]$JobRecord.NoProgressReports } else { 0 }
        StallMinutes = 0
        LoopDetected = $false
        LoopReason = ""
        HasObservableProgress = [bool]$Snapshot.HasObservableProgress
    }

    if (-not $Snapshot.HasObservableProgress) {
        $JobRecord | Add-Member -MemberType NoteProperty -Name "LoopDetected" -Value $false -Force -ErrorAction SilentlyContinue
        $JobRecord | Add-Member -MemberType NoteProperty -Name "LoopReason" -Value "" -Force -ErrorAction SilentlyContinue
        return [PSCustomObject]$state
    }

    $previousDigest = if ($JobRecord.PSObject.Properties["LastObservableProgressDigest"]) { "$($JobRecord.LastObservableProgressDigest)" } else { "" }
    if ([string]::IsNullOrWhiteSpace($previousDigest) -or $previousDigest -ne $Snapshot.ProgressDigest) {
        $JobRecord | Add-Member -MemberType NoteProperty -Name "LastObservableProgressDigest" -Value $Snapshot.ProgressDigest -Force -ErrorAction SilentlyContinue
        $JobRecord | Add-Member -MemberType NoteProperty -Name "LastObservableProgressAt" -Value $CurrentTime -Force -ErrorAction SilentlyContinue
        $JobRecord | Add-Member -MemberType NoteProperty -Name "NoProgressReports" -Value 0 -Force -ErrorAction SilentlyContinue
        $JobRecord | Add-Member -MemberType NoteProperty -Name "LoopDetected" -Value $false -Force -ErrorAction SilentlyContinue
        $JobRecord | Add-Member -MemberType NoteProperty -Name "LoopReason" -Value "" -Force -ErrorAction SilentlyContinue
        $state.ProgressChanged = $true
        $state.StallReports = 0
        return [PSCustomObject]$state
    }

    $noProgressReports = if ($JobRecord.PSObject.Properties["NoProgressReports"]) { [int]$JobRecord.NoProgressReports } else { 0 }
    $noProgressReports++
    $JobRecord | Add-Member -MemberType NoteProperty -Name "NoProgressReports" -Value $noProgressReports -Force -ErrorAction SilentlyContinue
    $state.StallReports = $noProgressReports

    if ($JobRecord.PSObject.Properties["LastObservableProgressAt"] -and $null -ne $JobRecord.LastObservableProgressAt) {
        $state.StallMinutes = [Math]::Max(0, [int][Math]::Floor(($CurrentTime - [DateTime]$JobRecord.LastObservableProgressAt).TotalMinutes))
    }

    $loopReasons = @()
    if ($state.StallReports -ge 2) {
        $loopReasons += "sin progreso verificable durante $($state.StallMinutes) min"
    }
    if ($Snapshot.HasRetrySignal) {
        $loopReasons += "hay reintentos repetidos"
    }
    if ($Snapshot.HasFailureSignal) {
        $loopReasons += "persiste un error o bloqueo"
    }

    $loopDetected = $state.StallReports -ge 2 -and ($Snapshot.HasRetrySignal -or $Snapshot.HasFailureSignal)
    $loopReason = (@($loopReasons | Select-Object -Unique) -join "; ")
    $JobRecord | Add-Member -MemberType NoteProperty -Name "LoopDetected" -Value $loopDetected -Force -ErrorAction SilentlyContinue
    $JobRecord | Add-Member -MemberType NoteProperty -Name "LoopReason" -Value $loopReason -Force -ErrorAction SilentlyContinue

    $state.LoopDetected = $loopDetected
    $state.LoopReason = $loopReason
    return [PSCustomObject]$state
}

function New-OpenCodeTelemetryStatusMessage {
    param(
        [object]$JobRecord,
        [object]$Snapshot,
        [object]$ProgressState,
        [int]$TotalElapsedMinutes
    )

    $emojiWait = [char]::ConvertFromUtf32(0x231B)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("$emojiWait *Tarea en progreso (OpenCode)*") | Out-Null
    $lines.Add("Van *$TotalElapsedMinutes min* desde el inicio.") | Out-Null

    if ($JobRecord.PSObject.Properties["Capability"] -and -not [string]::IsNullOrWhiteSpace("$($JobRecord.Capability)")) {
        $lines.Add("Capacidad: $($JobRecord.Capability)") | Out-Null
    }
    if ($JobRecord.PSObject.Properties["ExecutionMode"] -and -not [string]::IsNullOrWhiteSpace("$($JobRecord.ExecutionMode)")) {
        $lines.Add("Modo: $($JobRecord.ExecutionMode)") | Out-Null
    }

    $lines.Add("") | Out-Null
    $lines.Add("Fase actual: $($Snapshot.PhaseText)") | Out-Null
    if ($Snapshot.Heartbeat.Exists) {
        $lines.Add("Heartbeat: $($Snapshot.Heartbeat.PhaseText) hace $(Format-TelemetryAgeText -AgeSeconds $Snapshot.Heartbeat.AgeSeconds)") | Out-Null
    }
    else {
        $lines.Add("Heartbeat: no visible") | Out-Null
    }

    if ($Snapshot.Checkpoint.Exists) {
        if ($Snapshot.Checkpoint.HasObservableProgress) {
            $checkpointLine = "Checkpoint: $($Snapshot.Checkpoint.StatusText)"
            if ($null -ne $Snapshot.Checkpoint.AgeSeconds) {
                $checkpointLine += " (actualizado hace $(Format-TelemetryAgeText -AgeSeconds $Snapshot.Checkpoint.AgeSeconds))"
            }
            $lines.Add($checkpointLine) | Out-Null
            if (-not [string]::IsNullOrWhiteSpace($Snapshot.Checkpoint.LastAction)) {
                $lines.Add("Ultima accion: $($Snapshot.Checkpoint.LastAction)") | Out-Null
            }
            if ($Snapshot.Checkpoint.CompletedSteps.Count -gt 0) {
                $lines.Add("Hecho: $(($Snapshot.Checkpoint.CompletedSteps | Select-Object -First 2) -join '; ')") | Out-Null
            }
            if ($Snapshot.Checkpoint.PendingSteps.Count -gt 0) {
                $lines.Add("Pendiente: $(($Snapshot.Checkpoint.PendingSteps | Select-Object -First 2) -join '; ')") | Out-Null
            }
            if ($Snapshot.Checkpoint.Notes.Count -gt 0) {
                $lines.Add("Notas: $(($Snapshot.Checkpoint.Notes | Select-Object -Last 2) -join ' | ')") | Out-Null
            }
            if (-not [string]::IsNullOrWhiteSpace($Snapshot.Checkpoint.LastError)) {
                $lines.Add("Ultimo error: $($Snapshot.Checkpoint.LastError)") | Out-Null
            }
        }
        else {
            $lines.Add("Checkpoint: creado, pero OpenCode todavia no lo actualizo con pasos concretos.") | Out-Null
        }
    }
    else {
        $lines.Add("Checkpoint: no visible") | Out-Null
    }

    if ($Snapshot.Diagnostics.ProgressLines.Count -gt 0) {
        $lines.Add("Actividad reciente:") | Out-Null
        foreach ($entry in @($Snapshot.Diagnostics.ProgressLines | Select-Object -Last 2)) {
            $lines.Add("- $entry") | Out-Null
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($Snapshot.Diagnostics.RecentSummary)) {
        $lines.Add("Diagnostico: $($Snapshot.Diagnostics.RecentSummary)") | Out-Null
    }
    elseif (-not [string]::IsNullOrWhiteSpace($Snapshot.LogPreview)) {
        $lines.Add("Log reciente: $($Snapshot.LogPreview)") | Out-Null
    }
    else {
        $lines.Add("Visibilidad: OpenCode todavia no dejo trazas utiles en checkpoint/diagnostics.") | Out-Null
    }

    if ($ProgressState.LoopDetected) {
        $lines.Add("") | Out-Null
        $lines.Add("Senal de loop: $($ProgressState.LoopReason). Si sigue igual, lo cancelare automaticamente.") | Out-Null
    }
    elseif ($ProgressState.StallReports -ge 1 -and $ProgressState.StallMinutes -ge 4) {
        $lines.Add("") | Out-Null
        $lines.Add("Sin progreso verificable desde hace $($ProgressState.StallMinutes) min.") | Out-Null
    }

    $lines.Add("") | Out-Null
    $lines.Add("Seguire monitoreando el job y avisare cuando haya un cambio real o un resultado final.") | Out-Null
    return (($lines | Where-Object { $null -ne $_ }) -join "`n").Trim()
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
        $stuckReason = ""
        $stuckDetail = ""

        if ($j.Type -eq "OpenCode") {
            $loopGuardTriggered = (
                $j.PSObject.Properties["LoopDetected"] -and
                [bool]$j.LoopDetected -and
                $j.PSObject.Properties["NoProgressReports"] -and
                [int]$j.NoProgressReports -ge 3
            )
            if ($loopGuardTriggered) {
                $isCriticallyStuck = $true
                $stuckReason = "loop"
                $stuckDetail = if ($j.PSObject.Properties["LoopReason"]) { "$($j.LoopReason)" } else { "Repeated retries without verified progress." }
            }

            if (-not $loopGuardTriggered) {
                $heartbeat = Get-OpenCodeHeartbeatSnapshot -JobRecord $j -WorkDir $WorkDir
                if ($heartbeat.Exists -and $heartbeat.Fresh) {
                    $isCriticallyStuck = $false
                }
            }

            if ($isCriticallyStuck -and [string]::IsNullOrWhiteSpace($stuckReason)) {
                $stuckReason = "unresponsive"
            }
        }

        if ($isCriticallyStuck -and $j.Job.State -eq "Running") {
            $j | Add-Member -MemberType NoteProperty -Name "ElapsedMinutes" -Value ([int]$elapsedMinutes) -Force -ErrorAction SilentlyContinue
            $j | Add-Member -MemberType NoteProperty -Name "StuckReason" -Value $stuckReason -Force -ErrorAction SilentlyContinue
            $j | Add-Member -MemberType NoteProperty -Name "StuckDetail" -Value $stuckDetail -Force -ErrorAction SilentlyContinue
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
        if ($j.PSObject.Properties["SuppressTelemetry"] -and [bool]$j.SuppressTelemetry) {
            continue
        }

        if ($null -eq $j.LastTyping -or ($currentTime - $j.LastTyping).TotalSeconds -ge 4) {
            Send-TelegramTyping -chatId $j.ChatId
            $j.LastTyping = $currentTime
            $elapsedDisplay = [int]($currentTime - $j.StartTime).TotalMinutes
            Write-Host "[JOB $($j.Job.Id) - $($j.Type) - ${elapsedDisplay}min - $($j.Job.State)]: $($j.Task.Substring(0, [Math]::Min(60, $j.Task.Length)))..." -ForegroundColor DarkGray
        }

        if ($null -ne $j.LastReport) {
            if ($j.Type -eq "LocalCommand") {
                continue
            }

            $minutesSinceReport = ($currentTime - $j.LastReport).TotalMinutes
            if ($minutesSinceReport -ge 4.0) {
                $j.LastReport = $currentTime
                $totalElapsed = [int]($currentTime - $j.StartTime).TotalMinutes
                if ($j.Type -eq "OpenCode") {
                    $snapshot = Get-OpenCodeTelemetrySnapshot -JobRecord $j -WorkDir $WorkDir
                    $progressState = Update-OpenCodeJobProgressState -JobRecord $j -Snapshot $snapshot -CurrentTime $currentTime
                    $statusMsg = New-OpenCodeTelemetryStatusMessage -JobRecord $j -Snapshot $snapshot -ProgressState $progressState -TotalElapsedMinutes $totalElapsed
                }
                else {
                    $lastLog = Get-Content "$WorkDir\archives\subagent_events.log" -Tail 5 | Where-Object { $_ -match $j.Type } | Select-Object -Last 1
                    $emojiDoc = [char]::ConvertFromUtf32(0x1F4DC)
                    $logContext = if ($lastLog) { "$emojiDoc *Latest logged event:*`n``$($lastLog.Trim())``" } else { "Waiting for process output..." }
                    $emojiWait = [char]::ConvertFromUtf32(0x231B)
                    $statusMsg = "$emojiWait *Task in progress ($($j.Type))*`n" +
                        "*$totalElapsed minutes* have passed since the start.`n`n" +
                        "Capability: $($j.Capability)`n" +
                        "Execution mode: $($j.ExecutionMode)`n" +
                        "$logContext`n`n" +
                        "Still working on it. I will send the final result as soon as it is ready."
                }
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
            $checkpointStatus = if ($subRes -match '\[LOGIN_REQUIRED\]') {
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
                "waiting_for_login" { "Task paused pending manual website login" }
                default { "Task finished with error" }
            }
            try {
                Update-TaskCheckpointState -CheckpointPath $j.CheckpointPath -TaskText $j.Task -Status $checkpointStatus -ResultText $subRes -LastAction $checkpointAction -LastError $(if ($checkpointStatus -eq "failed") { $subRes } elseif ($checkpointStatus -eq "waiting_for_login") { "OpenCode paused because manual website login is required." } else { "" })
            }
            catch {
                Write-DailyLog -message "Checkpoint update failed for job $($j.Job.Id): $_" -type "WARN"
            }
        }

        Remove-Job -Job $j.Job -Force -ErrorAction SilentlyContinue
        $isParallelChild = Test-IsParallelOpenCodeChildJob -JobRecord $j
        $isParallelMerge = Test-IsParallelOpenCodeMergeJob -JobRecord $j
        $parallelGroupId = if ($j.PSObject.Properties["ParentParallelGroupId"]) { "$($j.ParentParallelGroupId)" } else { "" }

        if ($j.Type -eq "Subagent" -or $j.Type -eq "OpenCode" -or $j.Type -eq "Script" -or $j.Type -eq "LocalCommand") {
            if ($j.Type -eq "OpenCode" -and -not $isParallelChild -and -not $isParallelMerge -and $j.PSObject.Properties["AllowParallelPlan"] -and [bool]$j.AllowParallelPlan) {
                $parallelPlan = Get-OrchestratorParallelPlanRequest -ResultText $subRes
                if ($null -ne $parallelPlan) {
                    [void](Start-OrchestratorParallelOpenCodePlan -PlannerJob $j -Plan $parallelPlan)
                    Remove-ActiveJobById -JobId $j.Job.Id
                    Write-JobsFile
                    continue
                }
            }

            $publishConfirmation = Get-PublishConfirmationRequest -ResultText $subRes
            $loginRequired = Get-LoginRequiredRequest -ResultText $subRes
            $windowsUseConfirmation = Get-WindowsUseConfirmationRequest -ResultText $subRes

            if ($isParallelChild -and ($null -ne $publishConfirmation -or $null -ne $loginRequired -or $null -ne $windowsUseConfirmation)) {
                Write-DailyLog -message "Parallel child $($j.Job.Id) requested interactive follow-up. Cancelling remaining siblings in group $parallelGroupId." -type "WARN"
                Stop-ParallelOpenCodeGroupChildren -GroupId $parallelGroupId -ExcludeJobId $j.Job.Id
                Remove-ParallelOpenCodeGroup -GroupId $parallelGroupId | Out-Null
                $isParallelChild = $false
            }

            if ($isParallelChild) {
                $childCompletion = Handle-ParallelOpenCodeChildCompletion -JobRecord $j -ResultText $subRes -UsageLine $usageTelegram
                if ($childCompletion.Handled -and -not $childCompletion.ContinueNormalFlow) {
                    Remove-ActiveJobById -JobId $j.Job.Id
                    Write-JobsFile
                    continue
                }
            }

            if (-not [string]::IsNullOrWhiteSpace($usageTelegram)) {
                Send-TelegramText -chatId $j.ChatId -text $usageTelegram
                $usageTelegram = ""
            }

            # TOOLS_MISSING handler: fail-fast re-routing
            if ($j.Type -eq "OpenCode") {
                $toolsMissing = Get-ToolsMissingRequest -ResultText $subRes
                if ($null -ne $toolsMissing) {
                    $missingToolName = $toolsMissing.MissingTool
                    $missingReason = $toolsMissing.Reason
                    if ([string]::IsNullOrWhiteSpace($missingToolName)) { $missingToolName = "unknown" }
                    if ([string]::IsNullOrWhiteSpace($missingReason)) { $missingReason = "Agent lacks required tools." }
                    $currentAgent = if ([string]::IsNullOrWhiteSpace("$($j.RequestedAgent)")) { "build" } else { "$($j.RequestedAgent)" }
                    $suggested = Get-SuggestedAgentForMissingTool -MissingTool $missingToolName

                    if ($null -ne $suggested -and $suggested.Agent -ne $currentAgent) {
                        Write-DailyLog -message "TOOLS_MISSING: missing='$missingToolName' agent=$currentAgent -> reroute to $($suggested.Agent)" -type "WARN"
                        $emoji = [char]::ConvertFromUtf32(0x1F504)
                        Send-TelegramText -chatId $j.ChatId -text "$emoji Herramienta faltante: $($suggested.ToolName). Re-encaminando al agente $($suggested.Agent)..."
                        $reJob = Start-OpenCodeJob -TaskDescription $j.Task -ChatId $j.ChatId -Agent $suggested.Agent -TimeoutSec $j.TimeoutSec -AllowParallelPlan:$false
                        $reJob.Label = "OpenCode (re-route to $($suggested.Agent))"
                        Add-ActiveJob -JobRecord $reJob
                        Write-JobsFile
                        Remove-ActiveJobById -JobId $j.Job.Id
                        Write-JobsFile
                        continue
                    }
                    else {
                        Write-DailyLog -message "TOOLS_MISSING: missing='$missingToolName' agent=$currentAgent - no re-route available" -type "WARN"
                        $emoji = [char]::ConvertFromUtf32(0x26A0)
                        Send-TelegramText -chatId $j.ChatId -text "$emoji Herramienta faltante: $missingToolName. Motivo: $missingReason. Necesitas instalar el MCP correspondiente."
                        Add-ChatMemory -chatId $j.ChatId -role "system" -content ("SYSTEM: OpenCode reported missing tool '{0}' for task '{1}'. No re-route possible." -f $missingToolName, $j.Task)
                        Remove-ActiveJobById -JobId $j.Job.Id
                        Write-JobsFile
                        continue
                    }
                }
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
                    $fallbackJob = Start-OpenCodeJob -TaskDescription $j.Task -ChatId $j.ChatId -EnableMCPs $fallbackMcps -Model "opencode/minimax-m2.5" -Agent $fallbackAgent -AllowParallelPlan:$(if ($j.PSObject.Properties["AllowParallelPlan"]) { [bool]$j.AllowParallelPlan } else { $true })
                    $fallbackJob.Label = "OpenCode (Fallback Paid)"
                    if ($j.PSObject.Properties["ParentParallelGroupId"]) {
                        $fallbackJob.ParentParallelGroupId = $j.ParentParallelGroupId
                    }
                    if ($j.PSObject.Properties["ParallelRole"]) {
                        $fallbackJob.ParallelRole = $j.ParallelRole
                    }
                    if ($j.PSObject.Properties["ParallelChildTitle"]) {
                        $fallbackJob.ParallelChildTitle = $j.ParallelChildTitle
                    }
                    if ($j.PSObject.Properties["SuppressTelemetry"]) {
                        $fallbackJob.SuppressTelemetry = $j.SuppressTelemetry
                    }
                    if ($j.PSObject.Properties["Capability"]) {
                        $fallbackJob.Capability = $j.Capability
                    }
                    if ($j.PSObject.Properties["CapabilityRisk"]) {
                        $fallbackJob.CapabilityRisk = $j.CapabilityRisk
                    }
                    if ($j.PSObject.Properties["ExecutionMode"]) {
                        $fallbackJob.ExecutionMode = $j.ExecutionMode
                    }
                    if (-not [string]::IsNullOrWhiteSpace($parallelGroupId)) {
                        $group = Get-ParallelOpenCodeGroup -GroupId $parallelGroupId
                        if ($null -ne $group) {
                            if ("$($j.ParallelRole)" -eq "child" -and $group.Children.Contains("$($j.Job.Id)")) {
                                $childMeta = $group.Children["$($j.Job.Id)"]
                                $group.Children.Remove("$($j.Job.Id)")
                                $childMeta.JobId = $fallbackJob.Job.Id
                                $childMeta.Status = "running"
                                $childMeta.ResultText = ""
                                $childMeta.UsageLine = ""
                                $group.Children["$($fallbackJob.Job.Id)"] = $childMeta
                            }
                            elseif ("$($j.ParallelRole)" -eq "merge") {
                                $group.MergeJobId = $fallbackJob.Job.Id
                            }
                        }
                    }
                    Add-ActiveJob -JobRecord $fallbackJob
                    Remove-Job -Job $j.Job -Force -ErrorAction SilentlyContinue
                    Remove-ActiveJobById -JobId $j.Job.Id
                    continue
                }
            }

            if (($j.Type -eq "OpenCode" -or $j.Type -eq "Script") -and $null -ne $loginRequired) {
                $siteName = $loginRequired.Site
                $reasonText = if ([string]::IsNullOrWhiteSpace($loginRequired.Reason)) { "Login is required before the workflow can continue." } else { $loginRequired.Reason }
                $actorName = if ($j.Type -eq "Script") { "El navegador de automatizacion" } else { "OpenCode" }
                Send-TelegramText -chatId $j.ChatId -text "[LOGIN] $actorName dejo el navegador abierto esperando inicio de sesion en $($siteName)`n`nMotivo: $reasonText`n`nInicia sesion en esa ventana y luego dime ``continua`` para retomar desde donde quedo."
                Add-ChatMemory -chatId $j.ChatId -role "system" -content ("SYSTEM: The task paused because login is required on {0}. The browser was left open for manual sign-in. If the user says continue/continua/reanuda, resume the same task from the checkpoint instead of restarting." -f $siteName)
                if ($isParallelMerge) {
                    Remove-ParallelOpenCodeGroup -GroupId $parallelGroupId | Out-Null
                }
                Remove-ActiveJobById -JobId $j.Job.Id
                Write-JobsFile
                continue
            }

            if ($j.Type -eq "OpenCode" -and $null -ne $windowsUseConfirmation) {
                $taskPreview = $windowsUseConfirmation.Task
                $reasonText = if ([string]::IsNullOrWhiteSpace($windowsUseConfirmation.Reason)) { "Desktop control required" } else { $windowsUseConfirmation.Reason }
                $riskText = if ([string]::IsNullOrWhiteSpace($windowsUseConfirmation.Risk)) { "Controlará el mouse y teclado" } else { $windowsUseConfirmation.Risk }
                
                if ($taskPreview.Length -gt 300) {
                    $taskPreview = $taskPreview.Substring(0, 300) + "..."
                }
                
                $confirmationId = [guid]::NewGuid().ToString("N")
                $windowsUseScript = Join-Path $workDir ".opencode\skills\Windows_Use\scripts\Invoke-WindowsUse.ps1"
                $quotedScript = "'" + $windowsUseScript.Replace("'", "''") + "'"
                $quotedTask = "'" + $taskPreview.Replace("'", "''") + "'"
                $cmd = "powershell -File $quotedScript -Task $quotedTask"
                
                Add-PendingConfirmation -ConfirmationId $confirmationId -Payload @{
                    Command    = $cmd
                    ChatId     = $j.ChatId
                    UserId     = ""
                    UserScoped = $false
                    CreatedAt  = Get-Date
                    TaskDescription = $taskPreview
                }
                
                $buttons = @(
                    [PSCustomObject]@{ text = "✅ Aprobar Windows-Use"; callback_data = "confirm_windows_use:$confirmationId" },
                    [PSCustomObject]@{ text = "❌ Rechazar"; callback_data = "cancel_windows_use:$confirmationId" }
                )
                
                $message = @(
                    "🖥️ *Windows-Use requiere confirmación*",
                    "",
                    "*Acción:* $taskPreview",
                    "*Motivo:* $reasonText",
                    "*Riesgo:* $riskText",
                    "",
                    "¿Aprobar el control de escritorio?"
                ) -join "`n"
                
                Send-TelegramText -chatId $j.ChatId -text $message -buttons $buttons
                Add-ChatMemory -chatId $j.ChatId -role "system" -content "[SYSTEM]: OpenCode requested Windows-Use desktop control confirmation. Task: $taskPreview. Reason: $reasonText. Risk: $riskText. Awaiting user approval."
                Write-DailyLog -message "Windows-Use confirmation requested for job $($j.Job.Id). Task='$taskPreview'" -type "WARN"
                
                if ($isParallelMerge) {
                    Remove-ParallelOpenCodeGroup -GroupId $parallelGroupId | Out-Null
                }
                Remove-ActiveJobById -JobId $j.Job.Id
                Write-JobsFile
                continue
            }

            # PUBLISH_CONFIRMATION_REQUIRED handler: stop and ask user for approval
            if ($j.Type -eq "OpenCode" -and $null -ne $publishConfirmation) {
                $siteName = if ([string]::IsNullOrWhiteSpace($publishConfirmation.Site)) { "the website" } else { $publishConfirmation.Site }
                $taskPreview = $publishConfirmation.Task
                $reasonText = if ([string]::IsNullOrWhiteSpace($publishConfirmation.Reason)) { "Draft is ready for publishing" } else { $publishConfirmation.Reason }
                $screenshotPath = $publishConfirmation.Screenshot
                
                if ($taskPreview.Length -gt 300) {
                    $taskPreview = $taskPreview.Substring(0, 300) + "..."
                }
                
                # Send screenshot if available
                if (-not [string]::IsNullOrWhiteSpace($screenshotPath)) {
                    $fullScreenshotPath = if ([System.IO.Path]::IsPathRooted($screenshotPath)) { $screenshotPath } else { Join-Path $workDir $screenshotPath }
                    if (Test-Path $fullScreenshotPath) {
                        Send-TelegramPhoto -chatId $j.ChatId -filePath $fullScreenshotPath
                        Write-DailyLog -message "Publish confirmation screenshot sent: $fullScreenshotPath" -type "JOB"
                    }
                }
                
                $emojiReady = [char]::ConvertFromUtf32(0x2705)
                $emojiPublish = [char]::ConvertFromUtf32(0x1F4EF)
                
                $message = @(
                    "$emojiReady *Borrador listo en $siteName*",
                    "",
                    "*Tarea:* $taskPreview",
                    "*Motivo:* $reasonText",
                    "",
                    "El navegador quedo abierto con el boton de publicar visible.",
                    "",
                    "$emojiPublish *¿Quieres que lo publique ahora?* (responde si/no)"
                ) -join "`n"
                
                Send-TelegramText -chatId $j.ChatId -text $message
                Add-ChatMemory -chatId $j.ChatId -role "system" -content "[SYSTEM]: OpenCode prepared a draft on $siteName and is waiting for user confirmation to publish. The browser is open with the publish button visible. Do NOT re-delegate this task or take screenshots. Wait for the user to confirm (si/yes) or reject (no). If user confirms, execute the publish command from the PUBLISH_CONFIRMATION_REQUIRED marker."
                Write-DailyLog -message "Publish confirmation requested for job $($j.Job.Id). Site='$siteName' Task='$taskPreview'" -type "WARN"
                
                if ($isParallelMerge) {
                    Remove-ParallelOpenCodeGroup -GroupId $parallelGroupId | Out-Null
                }
                Remove-ActiveJobById -JobId $j.Job.Id
                Write-JobsFile
                continue
            }

            $draftReady = Get-DraftReadyRequest -ResultText $subRes
            if ($j.Type -eq "Script" -and $null -ne $draftReady) {
                $siteName = if ([string]::IsNullOrWhiteSpace($draftReady.Site)) { "the website" } else { $draftReady.Site }
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

            if ($j.Type -eq "LocalCommand" -and $subRes.Trim() -eq "Script finished without output.") {
                $subRes = "Command completed with no visible output."
            }

            $otherRunningLocalCommands = 0
            if ($j.Type -eq "LocalCommand") {
                $otherRunningLocalCommands = @(
                    Get-ActiveJobs | Where-Object {
                        $_.Type -eq "LocalCommand" -and
                        $_.ChatId -eq $j.ChatId -and
                        $_.Job.Id -ne $j.Job.Id -and
                        $_.Job.State -eq "Running"
                    }
                ).Count
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
                if ($isParallelMerge) {
                    Remove-ParallelOpenCodeGroup -GroupId $parallelGroupId | Out-Null
                }
                Remove-ActiveJobById -JobId $j.Job.Id
                Write-JobsFile
                continue
            }

            $emojiCheck = [char]::ConvertFromUtf32(0x2705)
            
            # Check if this is a file sent notification - update status and suppress LLM response
            if ($subRes -match '\[FILE_SENT\]\s*(.+?)\s*$') {
                $sentFileName = $Matches[1].Trim()
                $fileSentStatus = "$emojiCheck *File sent:* $sentFileName"
                Update-TelegramStatus -job $j -text $fileSentStatus
                Write-DailyLog -message "Job $($j.Job.Id) was a file send - updated status and suppressing LLM response" -type "JOB"
                Remove-ActiveJobById -JobId $j.Job.Id
                Write-JobsFile
                continue
            }
            
            $completionStatus = if ($j.Type -eq "LocalCommand" -and $otherRunningLocalCommands -gt 0) {
                "$emojiCheck *Task completed* ($($j.Type)). Waiting for remaining commands..."
            }
            else {
                "$emojiCheck *Task completed* ($($j.Type)). Analyzing results..."
            }
            Update-TelegramStatus -job $j -text $completionStatus

            $numFilesSent = Send-DetectedFiles -chatId $j.ChatId -text $subRes -JobStartTime $j.StartTime
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
            $sysMsg = ("SYSTEM: Task '{0}' completed by {1}. Result:`n{2}`n`nAnalyze this result. If the task is fully complete, summarize for the user. If more work is needed (e.g., the result shows partial progress, errors, or follow-up required), you MAY delegate again with [OPENCODE: ...] or take other actions. Do not just say you will do something - actually execute the action." -f $j.Task, $j.Type, $memorySummary)
            try {
                Add-ChatMemory -chatId $j.ChatId -role "system" -content $sysMsg
            }
            catch {
                Write-DailyLog -message "Error saving job memory for $($j.Job.Id): $_" -type "ERROR"
                $truncated = if ($subRes.Length -gt 3800) { $subRes.Substring(0, 3800) + "`n`n[...result truncated due to length]" } else { $subRes }
                Send-TelegramText -chatId $j.ChatId -text "*Direct result:*`n$truncated"
            }

            if ($j.Type -ne "LocalCommand" -or $otherRunningLocalCommands -eq 0) {
                Add-PendingChatId -ChatId $j.ChatId
            }

            if ($isParallelMerge) {
                Remove-ParallelOpenCodeGroup -GroupId $parallelGroupId | Out-Null
            }
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
        $isParallelChild = Test-IsParallelOpenCodeChildJob -JobRecord $j
        $isParallelMerge = Test-IsParallelOpenCodeMergeJob -JobRecord $j
        $parallelGroupId = if ($j.PSObject.Properties["ParentParallelGroupId"]) { "$($j.ParentParallelGroupId)" } else { "" }

        if ($isParallelChild) {
            $failureText = "[ERROR_OPENCODE] Parallel child '$($j.ParallelChildTitle)' was cancelled by the stuck-job guard after $elapsed minutes."
            $group = Get-ParallelOpenCodeGroup -GroupId $parallelGroupId
            if ($null -ne $group -and $group.Children.Contains("$($j.Job.Id)")) {
                $group.Children["$($j.Job.Id)"].Status = "completed"
                $group.Children["$($j.Job.Id)"].ResultText = $failureText
                $group.Children["$($j.Job.Id)"].UsageLine = ""
            }

            Stop-Job -Job $j.Job -ErrorAction SilentlyContinue | Out-Null
            Remove-Job -Job $j.Job -Force -ErrorAction SilentlyContinue
            Remove-ActiveJobById -JobId $j.Job.Id
            Write-JobsFile

            if ($null -ne $group) {
                $allChildrenDone = @($group.Children.GetEnumerator() | Where-Object { "$($_.Value.Status)" -ne "completed" }).Count -eq 0
                if ($allChildrenDone -and "$($group.State)" -eq "running_children") {
                    [void](Start-ParallelOpenCodeGroupMerge -Group $group)
                }
            }
            continue
        }

        $possibleCause = ""
        $emojiWarn = [char]::ConvertFromUtf32(0x26A0)
        if ("$($j.StuckReason)" -eq "loop") {
            $stallMinutes = if ($j.PSObject.Properties["LastObservableProgressAt"] -and $null -ne $j.LastObservableProgressAt) {
                [Math]::Max(0, [int][Math]::Floor(((Get-Date) - [DateTime]$j.LastObservableProgressAt).TotalMinutes))
            }
            else {
                $elapsed
            }
            $taskPreview = Get-TelemetryTextPreview -Text $j.Task -MaxLength 140
            $loopDetails = @()
            if (-not [string]::IsNullOrWhiteSpace("$($j.StuckDetail)")) {
                $loopDetails += "Senales: $($j.StuckDetail)"
            }
            if ($j.PSObject.Properties["LastObservedAction"] -and -not [string]::IsNullOrWhiteSpace("$($j.LastObservedAction)")) {
                $loopDetails += "Ultima accion: $($j.LastObservedAction)"
            }
            if ($j.PSObject.Properties["LastObservedError"] -and -not [string]::IsNullOrWhiteSpace("$($j.LastObservedError)")) {
                $loopDetails += "Ultimo error: $($j.LastObservedError)"
            }
            if ($j.PSObject.Properties["LastObservedEvidence"] -and -not [string]::IsNullOrWhiteSpace("$($j.LastObservedEvidence)")) {
                $loopDetails += "Ultima traza: $($j.LastObservedEvidence)"
            }

            $errMsg = "$emojiWarn *Loop detectado* ($($j.Type))`n"
            $errMsg += "No hubo progreso verificable durante *$stallMinutes minutos* y las trazas apuntan a reintentos repetidos.`n"
            $errMsg += "_Tarea:_ $taskPreview"
            if ($loopDetails.Count -gt 0) {
                $errMsg += "`n`n" + ($loopDetails -join "`n")
            }
            $errMsg += "`n`n_El orquestador cancelo esta ejecucion para evitar seguir insistiendo sobre el mismo fallo._"
        }
        else {
            if ($j.Task -match "imagen|foto|ver|analizar.*imagen|image|photo") {
                $possibleCause = "`n`n*Possible cause:* OpenCode/Minimax does not have reliable vision support for this task. The orchestrator can already analyze images directly."
            }
            elseif ($j.Task -match "pdf|document|binary file") {
                $possibleCause = "`n`n*Possible cause:* The model may struggle with binary files."
            }
            else {
                $possibleCause = "`n`n*Possible cause:* The task may require capabilities the model does not have."
            }

            $errMsg = "$emojiWarn *Stuck task detected* ($($j.Type))`n"
            $errMsg += "The task has been unresponsive for *$elapsed minutes*.`n"
            $errMsg += "_Task:_ $($j.Task.Substring(0, [Math]::Min(100, $j.Task.Length)))..."
            $errMsg += $possibleCause
            $errMsg += "`n`n_The orchestrator cancelled this task._"
        }
        Send-TelegramText -chatId $j.ChatId -text $errMsg

        if ($j.CheckpointPath) {
            try {
                $checkpointStatus = if ("$($j.StuckReason)" -eq "loop") { "loop_detected" } else { "stuck" }
                $checkpointAction = if ("$($j.StuckReason)" -eq "loop") { "Task cancelled by loop guard" } else { "Task cancelled by stuck-job guard" }
                $checkpointError = if ("$($j.StuckReason)" -eq "loop") {
                    "OpenCode task was cancelled after repeated retries without verified progress. $($j.StuckDetail)"
                }
                else {
                    "OpenCode task became unresponsive after $elapsed minutes."
                }
                Update-TaskCheckpointState -CheckpointPath $j.CheckpointPath -TaskText $j.Task -Status $checkpointStatus -LastAction $checkpointAction -LastError $checkpointError
            }
            catch {
                Write-DailyLog -message ("Checkpoint update failed for stuck job {0}: {1}" -f $j.Job.Id, $_) -type "WARN"
            }
        }

        Stop-Job -Job $j.Job -ErrorAction SilentlyContinue | Out-Null
        Remove-Job -Job $j.Job -Force -ErrorAction SilentlyContinue
        if ($isParallelMerge) {
            Remove-ParallelOpenCodeGroup -GroupId $parallelGroupId | Out-Null
        }
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
