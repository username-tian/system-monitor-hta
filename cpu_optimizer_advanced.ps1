# ==========================================
# CPU 智能优化守护进程
# 持续监控并自动优化CPU占用
# ==========================================

param(
    [int]$Threshold = 75,
    [int]$Interval = 10,
    [switch]$Silent,
    [switch]$InstallService,
    [switch]$UninstallService
)

$logFile = "$env:TEMP\cpu_optimizer.log"

function Write-Log($Text) {
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$time $Text" | Out-File -Append -FilePath $logFile -Encoding UTF8
}

function Show-Message($Text, $Color = "White") {
    if (-not $Silent) {
        Write-Host $Text -ForegroundColor $Color
    }
    Write-Log $Text
}

function Get-CpuUsage {
    try {
        $c = Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction SilentlyContinue
        return [math]::Round($c.CounterSamples[0].CookedValue, 1)
    } catch {
        return -1
    }
}

function Optimize-TraeProcesses {
    $trae = Get-Process -Name "Trae CN" -ErrorAction SilentlyContinue
    if (-not $trae) { return }
    
    $count = $trae.Count
    if ($count -gt 12) {
        Show-Message "  Trae CN: $count processes (normal: 8-12), optimizing..." "Yellow"
        
        $sorted = $trae | Sort-Object CPU -Descending
        $toLower = $sorted | Select-Object -Skip 8
        
        foreach ($p in $toLower) {
            try {
                $p.PriorityClass = "Idle"
                Show-Message "    PID $($p.Id) -> Idle" "Gray"
            } catch {
                Write-Log "Failed to lower PID $($p.Id): $_"
            }
        }
    }
    
    # Check for runaway threads
    $topProc = $trae | Sort-Object CPU -Descending | Select-Object -First 1
    if ($topProc -and $topProc.Threads.Count -gt 50) {
        Show-Message "  Warning: Trae PID $($topProc.Id) has $($topProc.Threads.Count) threads" "Red"
    }
}

function Stop-UnnecessaryServices {
    $services = @(
        @{Name="WSearch"; Desc="Windows Search"},
        @{Name="DiagTrack"; Desc="Telemetry"},
        @{Name="SysMain"; Desc="SuperFetch"},
        @{Name="MapsBroker"; Desc="Maps"},
        @{Name="WMPNetworkSvc"; Desc="Media Sharing"},
        @{Name="XblAuthManager"; Desc="Xbox Auth"},
        @{Name="XblGameSave"; Desc="Xbox Save"},
        @{Name="XboxNetApiSvc"; Desc="Xbox Network"},
        @{Name="WMPNetworkSvc"; Desc="WMP Sharing"},
        @{Name="TrkWks"; Desc="Link Tracking"},
        @{Name="WerSvc"; Desc="Error Reporting"}
    )
    
    foreach ($s in $services) {
        $svc = Get-Service -Name $s.Name -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq "Running") {
            try {
                Stop-Service -Name $s.Name -Force -ErrorAction SilentlyContinue
                Show-Message "  Stopped: $($s.Desc)" "Gray"
            } catch {
                Write-Log "Failed to stop $($s.Name): $_"
            }
        }
    }
}

function Optimize-OtherProcesses {
    $procs = Get-Process | Where-Object {
        $_.CPU -gt 10 -and
        $_.Name -notin @("Trae CN", "explorer", "svchost", "lsass", "csrss", "services", "wininit", "dwm", "System", "Idle", "Registry", "Memory Compression") -and
        $_.Path -notlike "*Windows*"
    } | Sort-Object CPU -Descending | Select-Object -First 5
    
    foreach ($p in $procs) {
        try {
            $p.PriorityClass = "BelowNormal"
            Show-Message "  Lowered: $($p.Name) (PID $($p.Id))" "Gray"
        } catch {
            Write-Log "Failed to lower $($p.Name): $_"
        }
    }
}

function Set-HighPerformance {
    try {
        # Set power plan to High Performance
        powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
    } catch {
        Write-Log "Failed to set power plan: $_"
    }
}

function Clear-WorkingSets {
    $procs = Get-Process | Where-Object { $_.WorkingSet64 -gt 200MB -and $_.Name -ne "System" }
    foreach ($p in $procs) {
        try {
            $p.MaxWorkingSet = 200MB
        } catch {
            Write-Log "Failed to clear working set for $($p.Name): $_"
        }
    }
}

function Get-OptimizationReport {
    $cpu = Get-CpuUsage
    $os = Get-WmiObject Win32_OperatingSystem
    $memUsed = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize * 100, 1)
    $traeCount = (Get-Process -Name "Trae CN" -ErrorAction SilentlyContinue).Count
    
    return [PSCustomObject]@{
        CpuUsage = $cpu
        MemoryUsage = $memUsed
        TraeProcesses = $traeCount
        Timestamp = Get-Date -Format "HH:mm:ss"
    }
}

function Start-OptimizationCycle {
    $report = Get-OptimizationReport
    
    Show-Message "`n[$($report.Timestamp)] CPU: $($report.CpuUsage)% | Memory: $($report.MemoryUsage)% | Trae: $($report.TraeProcesses)" "Cyan"
    
    if ($report.CpuUsage -gt $Threshold) {
        Show-Message "  High CPU detected! Optimizing..." "Red"
        
        Optimize-TraeProcesses
        Stop-UnnecessaryServices
        Optimize-OtherProcesses
        Clear-WorkingSets
        
        $after = Get-CpuUsage
        Show-Message "  After: $after%" $(if($after -lt $Threshold){"Green"}else{"Yellow"})
    }
}

function Install-AsService {
    $scriptPath = $MyInvocation.MyCommand.Path
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`" -Silent -Threshold $Threshold -Interval $Interval"
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    
    try {
        Register-ScheduledTask -TaskName "CPU_Optimizer" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force
        Show-Message "Service installed! Will run at startup." "Green"
    } catch {
        Show-Message "Failed to install service: $_" "Red"
    }
}

function Uninstall-AsService {
    try {
        Unregister-ScheduledTask -TaskName "CPU_Optimizer" -Confirm:$false -ErrorAction SilentlyContinue
        Show-Message "Service uninstalled." "Green"
    } catch {
        Show-Message "Failed to uninstall service: $_" "Red"
    }
}

# Main execution
if ($InstallService) {
    Install-AsService
    exit
}

if ($UninstallService) {
    Uninstall-AsService
    exit
}

Show-Message "========================================" "Cyan"
Show-Message "    CPU Optimizer Daemon v1.0" "Cyan"
Show-Message "========================================" "Cyan"
Show-Message "Threshold: $Threshold% | Interval: ${Interval}s" "White"
Show-Message "Log file: $logFile" "Gray"
Show-Message "Press Ctrl+C to stop`n" "Yellow"

# Run initial optimization
Set-HighPerformance
Start-OptimizationCycle

# Continuous monitoring
while ($true) {
    Start-Sleep -Seconds $Interval
    Start-OptimizationCycle
}
