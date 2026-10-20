# Process Monitor - Real-time CPU and Memory Viewer
param([int]$Top = 20, [int]$Interval = 3)

function Write-Color($Text, $Color = "White") {
    Write-Host $Text -ForegroundColor $Color
}

function Get-ProcessInfo {
    $procs = Get-Process | Where-Object { $_.Name -ne "Idle" -and $_.Name -ne "System" }
    $results = @()
    
    foreach ($p in $procs) {
        $cpu1 = $p.CPU
        Start-Sleep -Milliseconds 300
        $p.Refresh()
        $cpu2 = $p.CPU
        $cpuPct = [math]::Round(($cpu2 - $cpu1) / 0.3 / $env:NUMBER_OF_PROCESSORS * 100, 1)
        
        $results += [PSCustomObject]@{
            PID = $p.Id
            Name = $p.ProcessName
            CpuPercent = $cpuPct
            MemoryMB = [math]::Round($p.WorkingSet64 / 1MB, 0)
            Threads = $p.Threads.Count
            Priority = $p.PriorityClass
            StartTime = $p.StartTime.ToString("HH:mm:ss")
        }
    }
    
    return $results | Sort-Object CpuPercent -Descending
}

function Show-Header {
    Clear-Host
    Write-Color "================================================================" "Cyan"
    Write-Color "                    PROCESS MONITOR" "Cyan"
    Write-Color "================================================================" "Cyan"
    Write-Color "Press Ctrl+C to exit`n" "Yellow"
    
    # System info
    $cpu = Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction SilentlyContinue
    $os = Get-WmiObject Win32_OperatingSystem
    $memPct = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize * 100, 1)
    
    $cpuPct = if ($cpu) { [math]::Round($cpu.CounterSamples[0].CookedValue, 1) } else { 0 }
    $cpuColor = if ($cpuPct -lt 30) { "Green" } elseif ($cpuPct -lt 70) { "Yellow" } else { "Red" }
    $memColor = if ($memPct -lt 60) { "Green" } elseif ($memPct -lt 85) { "Yellow" } else { "Red" }
    
    Write-Color "CPU Usage: $cpuPct%  |  Memory: $memPct%  |  Processes: $((Get-Process).Count)" $cpuColor
    Write-Color "----------------------------------------------------------------" "DarkGray"
}

function Show-ProcessTable {
    param([array]$Processes, [int]$Count)
    
    $header = "{0,-6} {1,-20} {2,10} {3,10} {4,8} {5,12} {6,10}" -f "PID", "Name", "CPU%", "Memory(MB)", "Threads", "Priority", "Started"
    Write-Color $header "White"
    Write-Color "----------------------------------------------------------------" "DarkGray"
    
    $top = $Processes | Select-Object -First $Count
    foreach ($p in $top) {
        $color = if ($p.CpuPercent -gt 50) { "Red" } elseif ($p.CpuPercent -gt 20) { "Yellow" } elseif ($p.CpuPercent -gt 5) { "Green" } else { "Gray" }
        
        $name = if ($p.Name.Length -gt 20) { $p.Name.Substring(0, 17) + "..." } else { $p.Name }
        $line = "{0,-6} {1,-20} {2,10} {3,10} {4,8} {5,12} {6,10}" -f $p.PID, $name, "$($p.CpuPercent)%", $p.MemoryMB, $p.Threads, $p.Priority, $p.StartTime
        Write-Color $line $color
    }
}

function Show-Summary {
    param([array]$Processes)
    
    $highCpu = $Processes | Where-Object { $_.CpuPercent -gt 20 } | Measure-Object | Select-Object -ExpandProperty Count
    $highMem = $Processes | Where-Object { $_.MemoryMB -gt 200 } | Measure-Object | Select-Object -ExpandProperty Count
    $totalThreads = ($Processes | Measure-Object Threads -Sum).Sum
    
    Write-Color "`n----------------------------------------------------------------" "DarkGray"
    Write-Color "Summary: " "White" -NoNewline
    Write-Color "$highCpu high-CPU" "Red" -NoNewline
    Write-Color " | " "DarkGray" -NoNewline
    Write-Color "$highMem high-memory" "Yellow" -NoNewline
    Write-Color " | " "DarkGray" -NoNewline
    Write-Color "$totalThreads total threads" "Cyan"
    
    # Top CPU consumer
    $top = $Processes | Select-Object -First 1
    if ($top.CpuPercent -gt 10) {
        Write-Color "`nTop CPU Consumer: $($top.Name) (PID $($top.PID)) - $($top.CpuPercent)%" "Red"
    }
    
    # Trae CN analysis
    $trae = $Processes | Where-Object { $_.Name -eq "Trae CN" }
    if ($trae) {
        $traeCount = $trae.Count
        $traeTotalCpu = [math]::Round(($trae | Measure-Object CpuPercent -Sum).Sum, 1)
        $traeTotalMem = [math]::Round(($trae | Measure-Object MemoryMB -Sum).Sum, 0)
        
        Write-Color "`nTrae CN Analysis:" "Magenta"
        Write-Color "  Processes: $traeCount (normal: 8-12)" $(if($traeCount -le 12){"Green"}else{"Yellow"})
        Write-Color "  Total CPU: $traeTotalCpu%" $(if($traeTotalCpu -lt 30){"Green"}elseif($traeTotalCpu -lt 60){"Yellow"}else{"Red"})
        Write-Color "  Total Memory: ${traeTotalMem}MB" "Gray"
    }
}

# Main loop
while ($true) {
    Show-Header
    $procs = Get-ProcessInfo
    Show-ProcessTable -Processes $procs -Count $Top
    Show-Summary -Processes $procs
    
    Write-Color "`nRefreshing every $Interval seconds..." "DarkGray"
    Start-Sleep -Seconds $Interval
}
