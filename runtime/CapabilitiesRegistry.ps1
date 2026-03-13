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
            Agent = "coder"
            Model = $null
            Label = "OpenCode Coding"
            RiskLevel = "medium"
            ExpectedTimeoutSec = 1800
            ExecutionMode = "agent"
        },
        @{
            Name = "browser"
            Capability = "browser"
            Patterns = @(
                'web', 'website', 'browser', 'navigate', 'scrape', 'extract', 'crawl',
                'dom', 'html', 'page', 'site'
            )
            Agent = "browse"
            Model = $null
            Label = "OpenCode Browser"
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
            Agent = $null
            Model = "opencode/MiniMax-M2.5-free"
            Label = "OpenCode Document"
            RiskLevel = "low"
            ExpectedTimeoutSec = 900
            ExecutionMode = "model"
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
        "document" {
            return [PSCustomObject]@{
                Level = "low"
                Reason = "Document tasks are mainly extraction and summarization."
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
