param(
    [switch]$IncludeProcesses,
    [switch]$IncludePorts,
    [int]$TopProcesses = 10
)

$ErrorActionPreference = "Stop"

function Get-SafeCimInstance {
    param([string]$ClassName)

    try {
        return Get-CimInstance -ClassName $ClassName -ErrorAction Stop
    }
    catch {
        return $null
    }
}

function Get-SafeCommandOutput {
    param([scriptblock]$Script)

    try {
        return & $Script
    }
    catch {
        return $null
    }
}

$os = Get-SafeCimInstance -ClassName "Win32_OperatingSystem"
$computer = Get-SafeCimInstance -ClassName "Win32_ComputerSystem"
$processor = Get-SafeCimInstance -ClassName "Win32_Processor"
$logicalDisks = Get-SafeCommandOutput {
    Get-PSDrive -PSProvider FileSystem |
        Select-Object Name,
            @{ Name = "UsedGB"; Expression = { [Math]::Round(($_.Used / 1GB), 2) } },
            @{ Name = "FreeGB"; Expression = { [Math]::Round(($_.Free / 1GB), 2) } }
}

$bootTime = $null
$uptime = $null
if ($os -and $os.LastBootUpTime) {
    if ($os.LastBootUpTime -is [datetime]) {
        $bootTime = $os.LastBootUpTime
    }
    else {
        $bootTime = [Management.ManagementDateTimeConverter]::ToDateTime($os.LastBootUpTime)
    }
    $uptime = (Get-Date) - $bootTime
}

$result = [ordered]@{
    Timestamp = (Get-Date).ToString("o")
    ComputerName = $env:COMPUTERNAME
    UserName = $env:USERNAME
    OperatingSystem = if ($os) { "$($os.Caption) $($os.Version)" } else { $null }
    BootTime = if ($bootTime) { $bootTime.ToString("o") } else { $null }
    UptimeHours = if ($uptime) { [Math]::Round($uptime.TotalHours, 2) } else { $null }
    Memory = [ordered]@{
        TotalGB = if ($computer) { [Math]::Round(($computer.TotalPhysicalMemory / 1GB), 2) } else { $null }
        FreeGB = if ($os) { [Math]::Round(($os.FreePhysicalMemory * 1KB / 1GB), 2) } else { $null }
    }
    CPU = [ordered]@{
        Name = if ($processor) { $processor.Name } else { $null }
        LogicalCores = if ($processor) { $processor.NumberOfLogicalProcessors } else { $null }
        LoadPercent = if ($processor) { $processor.LoadPercentage } else { $null }
    }
    Storage = $logicalDisks
}

if ($IncludeProcesses) {
    $top = Get-SafeCommandOutput {
        Get-Process |
            Sort-Object CPU -Descending |
            Select-Object -First $TopProcesses Name, Id,
                @{ Name = "CPUSeconds"; Expression = { if ($_.CPU) { [Math]::Round($_.CPU, 2) } else { 0 } } },
                @{ Name = "WorkingSetMB"; Expression = { [Math]::Round(($_.WorkingSet64 / 1MB), 2) } }
    }
    $result.TopProcesses = $top
}

if ($IncludePorts) {
    $ports = Get-SafeCommandOutput {
        Get-NetTCPConnection -State Listen -ErrorAction Stop |
            Sort-Object LocalPort |
            Select-Object -First 40 LocalAddress, LocalPort, OwningProcess
    }
    $result.ListeningPorts = $ports
}

$result | ConvertTo-Json -Depth 6
