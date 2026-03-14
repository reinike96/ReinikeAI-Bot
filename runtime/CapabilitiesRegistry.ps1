function Get-TaskCapabilityProfile {
    param(
        [string]$Task
    )

    $normalizedTask = if ($null -ne $Task) { $Task.ToLowerInvariant() } else { "" }

    $profiles = @(
        @{
            Name = "coding"
            Capability = "code"
            Patterns = @(
                'script', 'code', 'bug', 'error', 'fix', 'refactor', 'debug',
                'api', 'file', 'class', 'module', 'powershell', 'python', 'javascript', 'typescript', 'html',
                'css', 'json', 'sql', 'regex', 'develop', 'implement', 'write.*code', 'create.*code',
                'modify.*code', 'add.*function',
                'endpoint', 'variable', 'algorithm', 'loop', 'array', 'object', 'class', 'method', 'test',
                'unittest', 'parse', 'build.*app', 'create.*app', 'make.*app'
            )
            Agent = "build"
            Model = $null
            Label = "OpenCode Build"
            RiskLevel = "medium"
            ExpectedTimeoutSec = 1800
            ExecutionMode = "agent"
        },
        @{
            Name = "social"
            Capability = "social"
            Patterns = @(
                'linkedin', 'x\.com', 'twitter', 'tweet', 'post on', 'social profile',
                'social media', 'dm on', 'message on linkedin'
            )
            Agent = "social"
            Model = $null
            Label = "OpenCode Social"
            RiskLevel = "medium"
            ExpectedTimeoutSec = 1500
            ExecutionMode = "agent"
        },
        @{
            Name = "computer"
            Capability = "computer"
            Patterns = @(
                'mouse', 'keyboard', 'click', 'double click', 'drag', 'window', 'desktop',
                'application window', 'focus app', 'move cursor', 'type into app'
            )
            Agent = "computer"
            Model = $null
            Label = "OpenCode Computer"
            RiskLevel = "high"
            ExpectedTimeoutSec = 1200
            ExecutionMode = "agent"
        },
        @{
            Name = "browser"
            Capability = "browser"
            Patterns = @(
                'web', 'website', 'browser', 'navigate', 'scrape', 'extract', 'crawl',
                'dom', 'html', 'page', 'site'
            )
            Agent = "browser"
            Model = $null
            Label = "OpenCode Browser"
            RiskLevel = "low"
            ExpectedTimeoutSec = 1200
            ExecutionMode = "agent"
        },
        @{
            Name = "sheets"
            Capability = "sheet"
            Patterns = @(
                'excel', 'xlsx', 'xlsm', 'spreadsheet', 'worksheet', 'workbook', 'csv'
            )
            Agent = "sheets"
            Model = $null
            Label = "OpenCode Sheets"
            RiskLevel = "low"
            ExpectedTimeoutSec = 1200
            ExecutionMode = "agent"
        },
        @{
            Name = "document"
            Capability = "document"
            Patterns = @(
                'pdf', 'docx', 'document', 'file', 'report', 'summary'
            )
            Agent = "docs"
            Model = $null
            Label = "OpenCode Docs"
            RiskLevel = "low"
            ExpectedTimeoutSec = 1200
            ExecutionMode = "agent"
        }
    )

    foreach ($profile in $profiles) {
        foreach ($pattern in $profile.Patterns) {
            if ($normalizedTask -match $pattern) {
                return [PSCustomObject]@{
                    Name = $profile.Name
                    Capability = $profile.Capability
                    Agent = $profile.Agent
                    Model = $profile.Model
                    Label = $profile.Label
                    RiskLevel = $profile.RiskLevel
                    ExpectedTimeoutSec = $profile.ExpectedTimeoutSec
                    ExecutionMode = $profile.ExecutionMode
                }
            }
        }
    }

    return [PSCustomObject]@{
        Name = "general"
        Capability = "general"
        Agent = $null
        Model = "opencode/MiniMax-M2.5-free"
        Label = "OpenCode General"
        RiskLevel = "low"
        ExpectedTimeoutSec = 1200
        ExecutionMode = "model"
    }
}

function New-OpenCodeExecutionPlan {
    param(
        [string]$Task,
        [string[]]$EnableMCPs = @()
    )

    $profile = Get-TaskCapabilityProfile -Task $Task

    return [PSCustomObject]@{
        Capability = $profile.Capability
        Agent = $profile.Agent
        Model = $profile.Model
        Label = $profile.Label
        RiskLevel = $profile.RiskLevel
        ExpectedTimeoutSec = $profile.ExpectedTimeoutSec
        ExecutionMode = $profile.ExecutionMode
        EnableMCPs = @($EnableMCPs)
    }
}

function Get-CapabilityRiskProfile {
    param(
        [string]$Capability
    )

    switch ($Capability) {
        "code" {
            return [PSCustomObject]@{
                Level = "medium"
                Reason = "Code tasks usually touch files, scripts, or generated artifacts."
            }
        }
        "browser" {
            return [PSCustomObject]@{
                Level = "low"
                Reason = "Browser tasks are mainly read-oriented."
            }
        }
        "sheet" {
            return [PSCustomObject]@{
                Level = "low"
                Reason = "Spreadsheet tasks are structured but usually low-risk."
            }
        }
        "document" {
            return [PSCustomObject]@{
                Level = "low"
                Reason = "Document tasks are mainly extraction and summarization."
            }
        }
        "computer" {
            return [PSCustomObject]@{
                Level = "high"
                Reason = "Computer-control tasks can affect live applications and the desktop."
            }
        }
        "social" {
            return [PSCustomObject]@{
                Level = "medium"
                Reason = "Social-site automation is stateful and often more fragile."
            }
        }
        default {
            return [PSCustomObject]@{
                Level = "low"
                Reason = "General OpenCode task."
            }
        }
    }
}
