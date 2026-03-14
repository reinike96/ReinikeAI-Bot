function Get-SkillRoutingProfile {
    param(
        [string]$Command
    )

    if ([string]::IsNullOrWhiteSpace($Command)) {
        return [PSCustomObject]@{
            SkillName = $null
            Classification = "none"
            Reason = ""
        }
    }

    $normalized = $Command.Replace("/", "\")
    $profiles = @(
        @{
            SkillName = "DuckSearch"
            Pattern = '(?i)skills\\DuckSearch\\duck_search\.ps1'
            Classification = "orchestrator-only"
            Reason = "DuckSearch is a short deterministic local search helper."
        },
        @{
            SkillName = "Outlook"
            Pattern = '(?i)skills\\Outlook\\.+\.ps1'
            Classification = "OpenCode-preferred"
            Reason = "Outlook workflows usually require checks, branching, or higher-risk side effects."
        },
        @{
            SkillName = "Telegram Sender"
            Pattern = '(?i)skills\\Telegram_Sender\\.+\.ps1'
            Classification = "orchestrator-only"
            Reason = "Telegram sender scripts are direct delivery helpers."
        },
        @{
            SkillName = "OpenCode-Status"
            Pattern = '(?i)skills\\opencode\\OpenCode-Status\.ps1'
            Classification = "orchestrator-only"
            Reason = "Status inspection is a short deterministic local action."
        },
        @{
            SkillName = "System Diagnostics"
            Pattern = '(?i)skills\\System_Diagnostics\\Get-SystemSnapshot\.ps1'
            Classification = "orchestrator-only"
            Reason = "System diagnostics is a direct local inspection helper."
        },
        @{
            SkillName = "File Tools"
            Pattern = '(?i)skills\\File_Tools\\(Pack-Files|List-RecentFiles)\.ps1'
            Classification = "orchestrator-only"
            Reason = "File packaging and listing are deterministic local actions."
        },
        @{
            SkillName = "CSV Tools"
            Pattern = '(?i)skills\\Csv_Tools\\Inspect-Csv\.ps1'
            Classification = "orchestrator-only"
            Reason = "CSV inspection is a short deterministic local analysis helper."
        },
        @{
            SkillName = "Playwright CLI"
            Pattern = '(?i)skills\\Playwright\\playwright-nav\.ps1'
            Classification = "hybrid"
            Reason = "Playwright wrapper is fine for one-shot local actions, but multi-step browser workflows should be delegated to OpenCode."
        }
    )

    foreach ($profile in $profiles) {
        if ($normalized -match $profile.Pattern) {
            return [PSCustomObject]@{
                SkillName = $profile.SkillName
                Classification = $profile.Classification
                Reason = $profile.Reason
            }
        }
    }

    return [PSCustomObject]@{
        SkillName = $null
        Classification = "none"
        Reason = ""
    }
}

function Test-SkillCommandAllowed {
    param(
        [string]$Command
    )

    $profile = Get-SkillRoutingProfile -Command $Command
    if ($profile.Classification -eq "OpenCode-preferred") {
        return [PSCustomObject]@{
            Allowed = $false
            Profile = $profile
            Error = "Skill '$($profile.SkillName)' is classified as OpenCode-preferred and should not be run directly as a local CMD action."
        }
    }

    return [PSCustomObject]@{
        Allowed = $true
        Profile = $profile
        Error = $null
    }
}

function Invoke-SkillRoutingGuard {
    param(
        [string]$ChatId,
        [string]$Command,
        [object]$Profile
    )

    $skillName = if ($Profile.SkillName) { $Profile.SkillName } else { "Unknown skill" }
    $reason = if ($Profile.Reason) { $Profile.Reason } else { "This skill should be delegated through OpenCode." }
    Write-Host "[GUARD] Blocked direct execution of $skillName skill." -ForegroundColor DarkYellow
    Add-ChatMemory -chatId $ChatId -role "user" -content "[SYSTEM]: The command '$Command' was blocked because the $skillName skill is classified as $($Profile.Classification). $reason Use OpenCode instead if the task still needs to continue."
}
