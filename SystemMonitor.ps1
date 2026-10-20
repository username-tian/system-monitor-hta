# System Monitor - Auto-refreshing HTML dashboard
# Runs a background loop that updates the HTML file every 2 seconds with real data.
param([int]$Interval = 2)

$host.ui.RawUI.WindowTitle = "System Monitor (Ctrl+C to stop)"

$outputFile = "$env:TEMP\system_monitor_live.html"

$protectedNames = @('System','Idle','Registry','Memory Compression','Secure System','smss','csrss','wininit','winlogon','services','lsass','svchost','dwm','fontdrvhost','WUDFHost','conhost','wininit')

$cpuInfo = Get-CimInstance Win32_Processor | Select-Object -First 1
$cpuName = ($cpuInfo.Name -replace '\s+',' ').Trim()
$coresStr = "$($cpuInfo.NumberOfCores)C / $($cpuInfo.NumberOfLogicalProcessors)T"
$bootTime = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime

$prevCpu = @{}
$prevTime = Get-Date

function Update-Data {
    $now = Get-Date
    $elapsed = ($now - $prevTime).TotalSeconds
    if ($elapsed -lt 0.5) { return $null }

    $procs = Get-Process -ErrorAction SilentlyContinue
    $list = New-Object System.Collections.ArrayList
    $threadSum = 0

    foreach ($p in $procs) {
        try {
            $cpuPct = 0.0
            if ($prevCpu.ContainsKey($p.Id)) {
                $delta = $p.CPU - $prevCpu[$p.Id]
                if ($delta -gt 0) { $cpuPct = [math]::Round($delta / $elapsed / $env:NUMBER_OF_PROCESSORS * 100, 1) }
            }
            $threads = 0; try { $threads = $p.Threads.Count } catch {}
            $threadSum += $threads
            $pri = 'Normal'; try { $pri = [string]$p.PriorityClass } catch {}
            $mem = 0; try { $mem = [math]::Round($p.WorkingSet64 / 1MB, 0) } catch {}

            [void]$list.Add([PSCustomObject]@{
                pid = $p.Id
                name = $p.ProcessName
                cpu = $cpuPct
                mem = $mem
                threads = $threads
                priority = $pri
                trae = ($p.ProcessName -eq 'Trae CN')
                prot = ($protectedNames -contains $p.ProcessName)
            })
        } catch {}
    }

    $prevCpu = @{}
    foreach ($p in $procs) { try { $prevCpu[$p.Id] = $p.CPU } catch {} }
    $prevTime = $now

    $cpuTotal = 0
    try { $cpuTotal = [double](Get-CimInstance Win32_Processor).LoadPercentage } catch {}

    $os = Get-CimInstance Win32_OperatingSystem
    $totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $freeGB = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    $usedGB = [math]::Round($totalGB - $freeGB, 1)
    $memPct = if ($totalGB -gt 0) { [math]::Round($usedGB / $totalGB * 100, 1) } else { 0 }

    $up = $now - $bootTime
    $uptime = "{0}d {1}h {2}m" -f [int]$up.TotalDays, $up.Hours, $up.Minutes

    $top = @($list | Sort-Object cpu -Descending | Select-Object -First 80)

    return [ordered]@{
        time = $now.ToString('HH:mm:ss')
        cpu = [math]::Round($cpuTotal, 1)
        memUsedPct = $memPct
        memUsedGB = $usedGB
        memTotalGB = $totalGB
        procCount = $procs.Count
        threadTotal = $threadSum
        cpuName = $cpuName
        cores = $coresStr
        uptime = $uptime
        processes = $top
    }
}

function Get-CpuClass($v) {
    if ($v -ge 70) { return 'bad' } elseif ($v -ge 30) { return 'warn' } else { return 'ok' }
}

function Build-TableRows($data) {
    $rows = New-Object System.Collections.ArrayList
    foreach ($p in $data.processes) {
        $c = Get-CpuClass $p.cpu
        $nameCls = if ($p.trae) { 'name-trae' } elseif ($p.prot) { 'name-prot' } else { '' }
        $priCls = if ($p.priority -eq 'Idle' -or $p.prot -eq 'BelowNormal') { 'badge low' } elseif ($p.priority -eq 'High' -or $p.priority -eq 'AboveNormal') { 'badge high' } else { 'badge' }
        $barW = [math]::Min($p.cpu, 100)
        $protTag = if ($p.prot) { '<span style="color:var(--muted);font-size:11px">protected</span>' } else { '<button class="btn" onclick="lower(' + $p.pid + ',`' + $p.name + '`)">Lower</button> <button class="btn danger" onclick="askKill(' + $p.pid + ',`' + $p.name + '`)">End</button>' }
        [void]$rows.Add(@"
<tr>
<td class="num mono">$($p.pid)</td>
<td class="$nameCls">$([System.Web.HttpUtility]::HtmlEncode($p.name))</td>
<td class="num"><span class="cbar"><i style="width:$barW%;background:var(--$c)"></i></span><span class="cval mono" style="color:var(--$c)">$($p.cpu)%</span></td>
<td class="num mono">$($p.mem) MB</td>
<td class="num mono">$($p.threads)</td>
<td><span class="$priCls">$($p.priority)</span></td>
<td class="num">$protTag</td>
</tr>
"@)
    }
    return $rows -join "`n"
}

function Build-Page($data) {
    $cpuClass = Get-CpuClass $data.cpu
    $memClass = Get-CpuClass $data.memUsedPct
    $trae = @($data.processes | Where-Object { $_.trae })
    $traeCpu = [math]::Round(($trae | Measure-Object cpu -Sum).Sum, 1)
    $showBanner = ($data.cpu -ge 85) -or ($trae.Count -gt 12)
    $bannerHtml = if ($showBanner) { @"
<div class="banner show">
<span class="tag">HIGH CPU</span>
<span>CPU $($data.cpu)% | Trae CN: $($trae.Count) processes using $traeCpu% CPU. Restarting Trae CN is recommended.</span>
</div>
"@ } else { '' }

    $tableRows = Build-TableRows $data

    return @"
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta http-equiv="refresh" content="$Interval">
<title>$([math]::Round($data.cpu,0))% CPU - System Monitor</title>
<style>
:root{
  --bg:#0d1117; --panel:#161b22; --border:#21262d; --border2:#30363d;
  --text:#e6edf3; --muted:#7d8590; --accent:#58a6ff;
  --ok:#3fb950; --warn:#d29922; --bad:#f85149;
}
*{margin:0;padding:0;box-sizing:border-box}
html,body{height:100%}
body{background:var(--bg);color:var(--text);font:13px/1.5 "Segoe UI",system-ui,-apple-system,sans-serif;-webkit-font-smoothing:antialiased}
.mono{font-family:"Cascadia Code",Consolas,"Courier New",monospace;font-variant-numeric:tabular-nums}

.topbar{height:52px;display:flex;align-items:center;padding:0 20px;background:var(--panel);border-bottom:1px solid var(--border2);position:sticky;top:0;z-index:50}
.brand{font-size:14px;font-weight:600;display:flex;align-items:center;gap:10px}
.brand .dot{width:8px;height:8px;border-radius:50%;background:var(--ok)}
.brand .sub{font-weight:400;color:var(--muted);font-size:12px}
.topstats{margin-left:auto;display:flex;gap:28px}
.ts{display:flex;flex-direction:column;align-items:flex-end;line-height:1.2}
.ts .l{font-size:10px;color:var(--muted);text-transform:uppercase;letter-spacing:.6px}
.ts .v{font-size:15px;font-weight:600}

.wrap{max-width:1200px;margin:0 auto;padding:20px}
.row{display:grid;gap:16px;margin-bottom:16px}
.row.charts{grid-template-columns:2fr 1fr}
.panel{background:var(--panel);border:1px solid var(--border);border-radius:6px;padding:16px}
.panel h2{font-size:11px;font-weight:600;color:var(--muted);text-transform:uppercase;letter-spacing:.8px;margin-bottom:12px;display:flex;align-items:center;justify-content:space-between}
.panel h2 .val{color:var(--text);font-size:12px;letter-spacing:0;text-transform:none}

.kv{display:flex;flex-direction:column}
.kv .item{display:flex;justify-content:space-between;align-items:baseline;padding:7px 0;border-bottom:1px solid var(--border)}
.kv .item:last-child{border-bottom:none}
.kv .k{color:var(--muted);font-size:12px}
.kv .v{font-size:13px;text-align:right;max-width:60%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}

.ubar{margin-top:4px}
.ubar .track{height:6px;background:var(--border);border-radius:3px;overflow:hidden}
.ubar .fill{height:100%;border-radius:3px}
.fill.ok{background:var(--ok)} .fill.warn{background:var(--warn)} .fill.bad{background:var(--bad)}

.toolbar{display:flex;align-items:center;gap:8px;margin-bottom:12px;flex-wrap:wrap}
.search{width:220px;height:30px;padding:0 10px;font-size:12px;color:var(--text);background:var(--bg);border:1px solid var(--border2);border-radius:5px;outline:none}
.search:focus{border-color:var(--accent)}
.chips{display:flex;gap:6px}
.chip{height:30px;padding:0 12px;font-size:12px;color:var(--muted);cursor:pointer;background:var(--bg);border:1px solid var(--border2);border-radius:5px}
.chip:hover{color:var(--text)}
.chip.on{color:var(--accent);border-color:var(--accent);background:rgba(88,166,255,.08)}
.count{margin-left:auto;color:var(--muted);font-size:12px}

.twrap{max-height:520px;overflow-y:auto;border:1px solid var(--border);border-radius:6px}
table{width:100%;border-collapse:collapse;table-layout:fixed}
thead th{position:sticky;top:0;background:var(--panel);z-index:2;padding:8px 12px;font-size:10px;font-weight:600;color:var(--muted);text-transform:uppercase;letter-spacing:.6px;text-align:left;border-bottom:1px solid var(--border2);white-space:nowrap}
td{padding:7px 12px;border-bottom:1px solid var(--border);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
tbody tr:hover{background:#1c2129}
.num{text-align:right}
.name-trae{color:var(--accent)}
.name-prot{color:var(--muted)}

.cbar{display:inline-block;width:56px;height:6px;background:var(--border);border-radius:3px;overflow:hidden;vertical-align:middle;margin-right:8px}
.cbar i{display:block;height:100%;border-radius:3px}
.cval{display:inline-block;width:44px;text-align:right}

.badge{display:inline-block;padding:1px 8px;font-size:11px;border-radius:10px;border:1px solid var(--border2);color:var(--muted)}
.badge.low{color:var(--ok);border-color:rgba(63,185,80,.4)}
.badge.high{color:var(--warn);border-color:rgba(210,153,34,.4)}

.btn{height:26px;padding:0 10px;font-size:11px;cursor:pointer;border-radius:5px;background:var(--border);border:1px solid var(--border2);color:var(--text)}
.btn:hover{background:var(--border2)}
.btn.danger{color:var(--bad)}
.btn.danger:hover{background:rgba(248,81,73,.15);border-color:var(--bad)}
.btn.accent{color:var(--accent);border-color:rgba(88,166,255,.4)}
.btn.accent:hover{background:rgba(88,166,255,.1)}

.banner{display:none;align-items:center;gap:10px;margin-bottom:16px;padding:10px 14px;border-radius:6px;font-size:12px;background:rgba(248,81,73,.08);border:1px solid rgba(248,81,73,.4);color:var(--bad)}
.banner.show{display:flex}
.banner .tag{font-weight:700;font-size:10px;letter-spacing:.8px;border:1px solid currentColor;border-radius:3px;padding:1px 6px}

.log{height:130px;overflow-y:auto;font-size:11px;line-height:1.7;font-family:Consolas,monospace}
.log .t{color:var(--muted);margin-right:8px}
.log .ok{color:var(--ok)} .log .err{color:var(--bad)} .log .info{color:var(--accent)}

.modal{display:none;position:fixed;inset:0;background:rgba(1,4,9,.7);align-items:center;justify-content:center;z-index:100}
.modal.show{display:flex}
.mbox{width:360px;background:var(--panel);border:1px solid var(--border2);border-radius:8px;padding:20px}
.mtitle{font-size:14px;font-weight:600;margin-bottom:8px}
.mtext{font-size:12px;color:var(--muted);margin-bottom:16px;word-break:break-all}
.mbtns{display:flex;justify-content:flex-end;gap:8px}

::-webkit-scrollbar{width:10px;height:10px}
::-webkit-scrollbar-thumb{background:var(--border2);border-radius:5px}
::-webkit-scrollbar-track{background:transparent}

@media(max-width:900px){.row.charts{grid-template-columns:1fr}}
</style>
</head>
<body>

<header class="topbar">
<div class="brand"><span class="dot"></span>System Monitor <span class="sub">$($data.cpuName)</span></div>
<div class="topstats">
<div class="ts"><span class="l">CPU</span><span class="v mono" style="color:var(--$cpuClass)">$([math]::Round($data.cpu,0))%</span></div>
<div class="ts"><span class="l">Memory</span><span class="v mono" style="color:var(--$memClass)">$([math]::Round($data.memUsedPct,0))%</span></div>
<div class="ts"><span class="l">Processes</span><span class="v mono">$($data.procCount)</span></div>
<div class="ts"><span class="l">Threads</span><span class="v mono">$($data.threadTotal)</span></div>
</div>
</header>

<div class="wrap">

$bannerHtml

<div class="row charts">
<div class="panel">
<h2>System Performance</h2>
<div class="kv">
<div class="item"><span class="k">CPU usage</span><span class="v mono" style="color:var(--$cpuClass)">$($data.cpu)%</span></div>
<div class="item"><span class="k">Memory</span><span class="v mono" style="color:var(--$memClass)">$($data.memUsedGB) / $($data.memTotalGB) GB ($($data.memUsedPct)%)</span></div>
<div class="item"><span class="k">Cores</span><span class="v mono">$($data.cores)</span></div>
<div class="item"><span class="k">Uptime</span><span class="v mono">$($data.uptime)</span></div>
</div>
<div class="ubar" style="margin-top:12px">
<div class="k" style="color:var(--muted);font-size:11px;margin-bottom:4px">CPU</div>
<div class="track"><div class="fill $cpuClass" style="width:$([math]::Min($data.cpu,100))%"></div></div>
</div>
<div class="ubar" style="margin-top:10px">
<div class="k" style="color:var(--muted);font-size:11px;margin-bottom:4px">Memory</div>
<div class="track"><div class="fill $memClass" style="width:$([math]::Min($data.memUsedPct,100))%"></div></div>
</div>
</div>
<div class="panel">
<h2>Log</h2>
<div class="log" id="log">
<div><span class="t">[$($data.time)]</span><span class="info">Monitor active</span></div>
</div>
</div>
</div>

<div class="panel">
<h2>Processes</h2>
<div class="twrap">
<table>
<thead><tr>
<th style="width:70px" class="num">PID</th>
<th>Name</th>
<th style="width:150px" class="num">CPU</th>
<th style="width:90px" class="num">Memory</th>
<th style="width:70px" class="num">Threads</th>
<th style="width:100px">Priority</th>
<th style="width:150px" class="num">Actions</th>
</tr></thead>
<tbody>
$tableRows
</tbody>
</table>
</div>
</div>

</div>

<div class="modal" id="modal">
<div class="mbox">
<div class="mtitle">End process</div>
<div class="mtext" id="mtext"></div>
<div class="mbtns">
<button class="btn" onclick="closeModal()">Cancel</button>
<button class="btn danger" id="mok">End process</button>
</div>
</div>
</div>

<script>
let pendingPid = null, pendingName = '';
function askKill(pid, name) {
  pendingPid = pid; pendingName = name;
  document.getElementById('mtext').innerHTML = 'Process <b style="color:var(--text)">' + name + '</b> (PID ' + pid + ') will be terminated. Unsaved work will be lost.';
  document.getElementById('modal').classList.add('show');
}
function closeModal() { document.getElementById('modal').classList.remove('show'); pendingPid = null; }
document.getElementById('mok').onclick = function() {
  var pid = pendingPid; closeModal();
  if (pid) window.location = 'trae-action://kill/' + pid;
};
function lower(pid, name) {
  window.location = 'trae-action://priority/' + pid;
}
</script>

</body>
</html>
"@
}

# main loop
Write-Host "System Monitor starting..."
Write-Host "Press Ctrl+C to stop. Output file: $outputFile"

# first update
$d = Update-Data
if (-not $d) { Start-Sleep -Milliseconds 900; $d = Update-Data }
$firstPage = Build-Page $d
$firstPage | Set-Content -Path $outputFile -Encoding UTF8
Start-Process $outputFile

Write-Host "Browser opened. Updating every $Interval seconds..."

try {
    while ($true) {
        Start-Sleep -Seconds $Interval
        $d = Update-Data
        if ($d) {
            $page = Build-Page $d
            $page | Set-Content -Path $outputFile -Encoding UTF8
        }
    }
} finally {
    Write-Host "Monitor stopped."
}
