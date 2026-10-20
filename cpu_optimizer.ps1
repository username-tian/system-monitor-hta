# CPU Optimizer - Simple and Stable
param([switch]$Monitor, [int]$Threshold = 80, [int]$Interval = 5)

function Write-Color($Text, $Color = "White") {
    Write-Host $Text -ForegroundColor $Color
}

function Get-CpuUsage {
    $c = Get-Counter '\Processor(_Total)\% Processor Time'
    return [math]::Round($c.CounterSamples[0].CookedValue, 1)
}

function Optimize-Trae {
    $trae = Get-Process -Name "Trae CN" -ErrorAction SilentlyContinue
    if (-not $trae) { return }
    
    $count = $trae.Count
    if ($count -gt 12) {
        Write-Color "Trae CN processes: $count (should be 8-12)" "Yellow"
        $extra = $trae | Sort-Object CPU -Descending | Select-Object -Skip 8
        foreach ($p in $extra) {
            try {
                $p.PriorityClass = "Idle"
                Write-Color "  Lowered PID $($p.Id) priority" "Gray"
            } catch {}
        }
    }
}

function Stop-Services {
    $services = @("WSearch", "DiagTrack", "SysMain", "MapsBroker", "WMPNetworkSvc")
    foreach ($s in $services) {
        $svc = Get-Service -Name $s -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq "Running") {
            try {
                Stop-Service -Name $s -Force -ErrorAction SilentlyContinue
                Write-Color "  Stopped service: $s" "Gray"
            } catch {}
        }
    }
}

function Optimize-Processes {
    $procs = Get-Process | Where-Object {
        $_.CPU -gt 5 -and
        $_.Name -notin @("Trae CN", "explorer", "svchost", "lsass", "csrss", "services", "wininit", "dwm", "System", "Idle") -and
        $_.Name -notlike "*Windows*"
    } | Sort-Object CPU -Descending | Select-Object -First 10
    
    foreach ($p in $procs) {
        try {
            $p.PriorityClass = "BelowNormal"
            Write-Color "  Lowered $($p.Name) PID $($p.Id)" "Gray"
        } catch {}
    }
}

function Show-Report {
    $cpu = Get-CpuUsage
    $mem = [math]::Round((1 - (Get-WmiObject Win32_OperatingSystem).FreePhysicalMemory / (Get-WmiObject Win32_OperatingSystem).TotalVisibleMemorySize) * 100, 1)
    
    Write-Color "`n=== CPU Optimization Report ===" "Cyan"
    Write-Color "CPU Usage: $cpu%" $(if($cpu -lt 50){"Green"}elseif($cpu -lt 80){"Yellow"}else{"Red"})
    Write-Color "Memory Usage: $mem%" $(if($mem -lt 60){"Green"}elseif($mem -lt 85){"Yellow"}else{"Red"})
    
    $traeCount = (Get-Process -Name "Trae CN" -ErrorAction SilentlyContinue).Count
    if ($traeCount -gt 0) {
        Write-Color "Trae Processes: $traeCount" $(if($traeCount -le 12){"Green"}else{"Yellow"})
    }
    Write-Color "==============================`n" "Cyan"
}

function Start-Optimize {
    Write-Color "`n[1/4] Optimizing Trae processes..." "Yellow"
    Optimize-Trae
    
    Write-Color "[2/4] Stopping background services..." "Yellow"
    Stop-Services
    
    Write-Color "[3/4] Lowering other process priorities..." "Yellow"
    Optimize-Processes
    
    Write-Color "[4/4] Optimization complete!" "Yellow"
    Show-Report
}

if ($Monitor) {
    Write-Color "Monitoring mode (Ctrl+C to stop, threshold: $Threshold%)" "Cyan"
    while ($true) {
        $cpu = Get-CpuUsage
        $time = Get-Date -Format "HH:mm:ss"
        $color = if($cpu -lt 30){"Green"}elseif($cpu -lt 60){"Yellow"}else{"Red"}
        Write-Color "[$time] CPU: $cpu%" $color
        
        if ($cpu -gt $Threshold) {
            Write-Color "  High CPU! Auto-optimizing..." "Red"
            Start-Optimize
        }
        Start-Sleep -Seconds $Interval
    }
} else {
    Start-Optimize
}
