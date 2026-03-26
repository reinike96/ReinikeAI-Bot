function Get-CapabilityPackRegistry {
    return @(
        [PSCustomObject]@{
            Name = "docs"
            DisplayName = "Docs pack"
            Description = "PDF and Word workflows for OpenCode."
            Agent = "docs"
            SettingKey = "docs"
            ToolFlags = @("file_converter_*", "word_document_*")
            SuggestedProjects = @(
                "file-converter-mcp",
                "Office-Word-MCP-Server"
            )
            InstallCheckType = "path"
            InstallCheckTarget = @(
                "external\\mcp\\file-converter-mcp\\start_mcp_server.py",
                "external\\mcp\\Office-Word-MCP-Server\\word_mcp_server.py"
            )
        },
        [PSCustomObject]@{
            Name = "sheets"
            DisplayName = "Sheets pack"
            Description = "Excel and spreadsheet workflows for OpenCode."
            Agent = "sheets"
            SettingKey = "sheets"
            ToolFlags = @("excel_master_*")
            SuggestedProjects = @(
                "Excel-MCP-Server-Master"
            )
            InstallCheckType = "command"
            InstallCheckTarget = @("excel-mcp-server")
        },
        [PSCustomObject]@{
            Name = "computer"
            DisplayName = "Computer pack"
            Description = "Mouse, keyboard, window, and desktop control."
            Agent = "computer"
            SettingKey = "computer"
            ToolFlags = @("computer_control_*")
            SuggestedProjects = @(
                "MCPControl",
                "computer-mcp"
            )
            InstallCheckType = "command"
            InstallCheckTarget = @("mcp-control")
        },
        [PSCustomObject]@{
            Name = "social"
            DisplayName = "Social browser pack"
            Description = "Hardened logged-in browser workflows for LinkedIn or X."
            Agent = "social"
            SettingKey = "social"
            ToolFlags = @("playwriter_*")
            SuggestedProjects = @(
                "playwriter",
                "stealth-browser-mcp"
            )
            InstallCheckType = "command"
            InstallCheckTarget = @("playwriter")
        },
        [PSCustomObject]@{
            Name = "browser"
            DisplayName = "Browser pack"
            Description = "General browsing, screenshots, downloads, and page workflows."
            Agent = "browser"
            SettingKey = "browser"
            ToolFlags = @("playwright_browser_*")
            SuggestedProjects = @(
                "playwriter",
                "Playwright"
            )
            InstallCheckType = "path"
            InstallCheckTarget = @("node_modules\\playwright")
        },
        [PSCustomObject]@{
            Name = "research"
            DisplayName = "Deep Research pack"
            Description = "OpenCode research skills and web-search agents for structured multi-step research."
            Agent = "build"
            SettingKey = "research"
            ToolFlags = @()
            SuggestedProjects = @(
                "Deep-Research-skills"
            )
            InstallCheckType = "path"
            InstallCheckTarget = @(
                "$env:USERPROFILE\\.claude\\skills\\research\\SKILL.md",
                "$env:USERPROFILE\\.config\\opencode\\agents\\web-search.md"
            )
        }
    )
}

function Get-CapabilityPackState {
    param(
        [object]$BotConfig,
        [string]$ConfigPath = ""
    )

    $registry = Get-CapabilityPackRegistry
    $configJson = $null
    $resolvedConfigPath = $ConfigPath
    if ([string]::IsNullOrWhiteSpace($resolvedConfigPath) -and $BotConfig -and $BotConfig.OpenCode) {
        $resolvedConfigPath = $BotConfig.OpenCode.ConfigPath
    }

    if (-not [string]::IsNullOrWhiteSpace($resolvedConfigPath) -and (Test-Path $resolvedConfigPath)) {
        try {
            $configJson = Get-Content -Path $resolvedConfigPath -Raw | ConvertFrom-Json
        }
        catch {
            $configJson = $null
        }
    }

    $configuredPacks = @{}
    if ($BotConfig -and $BotConfig.OpenCode -and $BotConfig.OpenCode.Packs) {
        foreach ($prop in $BotConfig.OpenCode.Packs.PSObject.Properties) {
            $configuredPacks[$prop.Name] = [bool]$prop.Value
        }
    }

    $states = @()
    foreach ($pack in $registry) {
        $agentNode = $null
        $allFlagsEnabled = $false
        if ($configJson -and $configJson.agent) {
            $agentNode = $configJson.agent.PSObject.Properties[$pack.Agent]
            if ($pack.ToolFlags.Count -eq 0) {
                $allFlagsEnabled = [bool]($configuredPacks[$pack.SettingKey])
            }
            elseif ($agentNode -and $agentNode.Value.tools) {
                $allFlagsEnabled = $true
                foreach ($flag in $pack.ToolFlags) {
                    $flagProp = $agentNode.Value.tools.PSObject.Properties[$flag]
                    if (-not $flagProp -or -not [bool]$flagProp.Value) {
                        $allFlagsEnabled = $false
                        break
                    }
                }
            }
        }

        $installed = $false
        switch ($pack.InstallCheckType) {
            "command" {
                $installed = $true
                foreach ($cmd in $pack.InstallCheckTarget) {
                    if ($null -eq (Get-Command $cmd -ErrorAction SilentlyContinue)) {
                        $installed = $false
                        break
                    }
                }
            }
            "path" {
                $installed = $true
                foreach ($relPath in $pack.InstallCheckTarget) {
                    $fullPath = if ([System.IO.Path]::IsPathRooted($relPath)) { $relPath } elseif ($BotConfig -and $BotConfig.Paths -and $BotConfig.Paths.WorkDir) { Join-Path $BotConfig.Paths.WorkDir $relPath } else { $relPath }
                    if (-not (Test-Path $fullPath)) {
                        $installed = $false
                        break
                    }
                }
            }
        }

        $states += [PSCustomObject]@{
            Name = $pack.Name
            DisplayName = $pack.DisplayName
            Description = $pack.Description
            Agent = $pack.Agent
            EnabledInSettings = [bool]($configuredPacks[$pack.SettingKey])
            EnabledInOpenCodeConfig = $allFlagsEnabled
            Installed = $installed
            SuggestedProjects = $pack.SuggestedProjects
        }
    }

    return $states
}
