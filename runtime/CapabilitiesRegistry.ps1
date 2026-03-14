function Get-OpenCodeTaskEnvelope {
    param(
        [string]$Task
    )

    $normalizedTask = if ($null -ne $Task) { $Task.Trim() } else { "" }
    if ([string]::IsNullOrWhiteSpace($normalizedTask)) {
        return ""
    }

    return @"
Use the `build` agent as the default execution route for this task.
Only if a specialized project agent is clearly needed for part of the work, choose and use it internally as a sub-agent. Available specialized agents: `browser`, `docs`, `sheets`, `computer`, `social`.
Do not switch agents unless there is a concrete need.

Task:
$normalizedTask
"@.Trim()
}

function New-OpenCodeExecutionPlan {
    param(
        [string]$Task,
        [string[]]$EnableMCPs = @()
    )

    $wrappedTask = Get-OpenCodeTaskEnvelope -Task $Task
    if ([string]::IsNullOrWhiteSpace($wrappedTask)) {
        $wrappedTask = $Task
    }

    return [PSCustomObject]@{
        Capability = "general"
        Agent = "build"
        Model = $null
        Label = "OpenCode Build"
        RiskLevel = "medium"
        ExpectedTimeoutSec = 1800
        ExecutionMode = "agent"
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
