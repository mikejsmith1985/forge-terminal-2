# Forge Terminal - Auto Diagnostic Tool
# Just run this and use Forge. When freeze occurs, note the time.
# Press Ctrl+C to stop and it will generate a report.

param([int]$Port = 8333)

$ErrorActionPreference = "SilentlyContinue"
$logFile = "forge-diagnostic-$(Get-Date -Format 'yyyy-MM-dd_HH-mm').log"

Write-Host @"
============================================================
  FORGE AUTO-DIAGNOSTIC - Just use Forge normally
============================================================
  Logging to: $logFile
  When freeze occurs, note the time (shown below)
  Press Ctrl+C to stop and generate report
============================================================
"@ -ForegroundColor Cyan

function Get-Snapshot {
    $now = Get-Date
    $snapshot = @{
        Time = $now.ToString("HH:mm:ss.fff")
        Timestamp = $now
    }

    # HTTP check
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/api/version" -TimeoutSec 3 -UseBasicParsing
        $sw.Stop()
        $snapshot.HttpMs = $sw.ElapsedMilliseconds
        $snapshot.HttpOK = $true
    } catch {
        $snapshot.HttpMs = 9999
        $snapshot.HttpOK = $false
    }

    # Find Forge process
    $forge = Get-Process | Where-Object { $_.ProcessName -match "forge" } | Select-Object -First 1
    if ($forge) {
        $snapshot.ForgePID = $forge.Id
        $snapshot.ForgeMem = [math]::Round($forge.WorkingSet64 / 1MB, 0)
        $snapshot.ForgeHandles = $forge.HandleCount
        $snapshot.ForgeThreads = $forge.Threads.Count

        # CPU requires sampling
        try {
            $cpu = (Get-Counter "\Process($($forge.ProcessName))\% Processor Time" -EA SilentlyContinue).CounterSamples[0].CookedValue
            $snapshot.ForgeCPU = [math]::Round($cpu, 0)
        } catch { $snapshot.ForgeCPU = -1 }
    } else {
        $snapshot.ForgePID = 0
    }

    # System stats
    $os = Get-CimInstance Win32_OperatingSystem -EA SilentlyContinue
    if ($os) {
        $totalGB = $os.TotalVisibleMemorySize / 1MB
        $freeGB = $os.FreePhysicalMemory / 1MB
        $snapshot.SysMemPct = [math]::Round((($totalGB - $freeGB) / $totalGB) * 100, 0)
    }

    # Disk queue
    try {
        $dq = (Get-Counter "\PhysicalDisk(_Total)\Current Disk Queue Length" -EA SilentlyContinue).CounterSamples[0].CookedValue
        $snapshot.DiskQueue = [math]::Round($dq, 1)
    } catch { $snapshot.DiskQueue = -1 }

    # Top CPU processes
    $topProcs = Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 |
        ForEach-Object { "$($_.ProcessName):$([math]::Round($_.WorkingSet64/1MB))MB" }
    $snapshot.TopProcs = $topProcs -join ", "

    return $snapshot
}

function Test-Freeze {
    param($Snapshot, $PrevSnapshot)

    $issues = @()

    # HTTP timeout or slow
    if (-not $Snapshot.HttpOK) { $issues += "HTTP_FAIL" }
    elseif ($Snapshot.HttpMs -gt 500) { $issues += "HTTP_SLOW($($Snapshot.HttpMs)ms)" }

    # High CPU
    if ($Snapshot.ForgeCPU -gt 80) { $issues += "HIGH_CPU($($Snapshot.ForgeCPU)%)" }

    # High system memory
    if ($Snapshot.SysMemPct -gt 90) { $issues += "SYS_MEM($($Snapshot.SysMemPct)%)" }

    # Disk contention
    if ($Snapshot.DiskQueue -gt 2) { $issues += "DISK_Q($($Snapshot.DiskQueue))" }

    # Handle growth
    if ($PrevSnapshot -and $Snapshot.ForgeHandles -and $PrevSnapshot.ForgeHandles) {
        $growth = $Snapshot.ForgeHandles - $PrevSnapshot.ForgeHandles
        if ($growth -gt 100) { $issues += "HANDLE_SPIKE(+$growth)" }
    }

    return @{
        IsFrozen = (-not $Snapshot.HttpOK) -or ($Snapshot.HttpMs -gt 2000)
        Issues = $issues
    }
}

# Main loop
$snapshots = @()
$prev = $null
$freezeCount = 0

"Time,HttpMs,HttpOK,ForgeCPU,ForgeMem,Handles,Threads,SysMemPct,DiskQ,Issues,TopProcs" | Out-File $logFile

try {
    while ($true) {
        $snap = Get-Snapshot
        $analysis = Test-Freeze -Snapshot $snap -PrevSnapshot $prev

        # Format issues
        $issueStr = if ($analysis.Issues.Count -gt 0) { $analysis.Issues -join "; " } else { "OK" }

        # Log to file
        "$($snap.Time),$($snap.HttpMs),$($snap.HttpOK),$($snap.ForgeCPU),$($snap.ForgeMem),$($snap.ForgeHandles),$($snap.ForgeThreads),$($snap.SysMemPct),$($snap.DiskQueue),`"$issueStr`",`"$($snap.TopProcs)`"" | Out-File $logFile -Append

        # Console output
        $timeDisplay = (Get-Date).ToString("HH:mm:ss")

        if ($analysis.IsFrozen) {
            $freezeCount++
            Write-Host "[$timeDisplay] " -NoNewline
            Write-Host ">>> FREEZE #$freezeCount <<<" -ForegroundColor White -BackgroundColor DarkRed -NoNewline
            Write-Host " HTTP:$($snap.HttpMs)ms CPU:$($snap.ForgeCPU)% Mem:$($snap.SysMemPct)%" -ForegroundColor Red
            Write-Host "           Issues: $issueStr" -ForegroundColor Yellow
            Write-Host "           Top: $($snap.TopProcs)" -ForegroundColor Yellow
            [Console]::Beep(1000, 300)
        }
        elseif ($analysis.Issues.Count -gt 0) {
            Write-Host "[$timeDisplay] " -NoNewline -ForegroundColor Gray
            Write-Host "WARN" -NoNewline -ForegroundColor Yellow
            Write-Host " HTTP:$($snap.HttpMs)ms CPU:$($snap.ForgeCPU)% | $issueStr" -ForegroundColor Yellow
        }
        else {
            # Just show time ticking - minimal output
            Write-Host "`r[$timeDisplay] OK - HTTP:$($snap.HttpMs)ms CPU:$($snap.ForgeCPU)% SysMem:$($snap.SysMemPct)%    " -NoNewline -ForegroundColor DarkGray
        }

        $snapshots += $snap
        $prev = $snap

        # Keep only last 500 snapshots in memory
        if ($snapshots.Count -gt 500) {
            $snapshots = $snapshots[-500..-1]
        }

        Start-Sleep -Seconds 1
    }
}
finally {
    Write-Host ""
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  DIAGNOSTIC COMPLETE" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  Log file: $logFile" -ForegroundColor White
    Write-Host "  Freezes detected: $freezeCount" -ForegroundColor $(if ($freezeCount -gt 0) { "Red" } else { "Green" })
    Write-Host ""
    Write-Host "  Share the log file or tell me the time of freeze" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan
}
