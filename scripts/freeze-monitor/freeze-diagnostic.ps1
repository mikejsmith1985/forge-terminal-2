# Forge Terminal Freeze Diagnostic Tool
# Run this from a regular PowerShell terminal (NOT inside Forge)
# Usage: .\freeze-diagnostic.ps1 [-Port 8333] [-Interval 1]

param(
    [int]$Port = 8333,
    [int]$Interval = 1
)

$ErrorActionPreference = "SilentlyContinue"

# Output file
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$logFile = "freeze-diagnostic-$timestamp.log"
$csvFile = "freeze-metrics-$timestamp.csv"

Write-Host @"
╔═══════════════════════════════════════════════════════════════════╗
║         FORGE TERMINAL - FREEZE DIAGNOSTIC TOOL                   ║
╠═══════════════════════════════════════════════════════════════════╣
║  Monitoring: http://127.0.0.1:$Port
║  Interval: ${Interval}s
║  Log: $logFile
║  CSV: $csvFile
╠═══════════════════════════════════════════════════════════════════╣
║  Press Ctrl+C to stop and generate report                         ║
╚═══════════════════════════════════════════════════════════════════╝
"@

# Initialize CSV
"Timestamp,HttpLatencyMs,HttpStatus,ProcessCPU,ProcessMemoryMB,ProcessHandles,ProcessThreads,WsTestResult,SystemMemUsedGB,SystemMemPct,DiskQueueLen,FreezeDetected,Notes" | Out-File $csvFile

# State tracking
$lastGoodTime = Get-Date
$freezeCount = 0
$measurements = @()

function Write-Log {
    param($Level, $Message)
    $ts = Get-Date -Format "HH:mm:ss.fff"
    $color = switch ($Level) {
        "INFO" { "Cyan" }
        "WARN" { "Yellow" }
        "ERROR" { "Red" }
        "FREEZE" { "White" }
        default { "White" }
    }
    $bgColor = if ($Level -eq "FREEZE") { "DarkRed" } else { "Black" }

    $line = "[$ts] [$Level] $Message"
    Write-Host $line -ForegroundColor $color -BackgroundColor $bgColor
    $line | Out-File $logFile -Append
}

function Test-HttpEndpoint {
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/api/version" -TimeoutSec 5 -UseBasicParsing
        $stopwatch.Stop()
        return @{
            Success = $true
            LatencyMs = $stopwatch.ElapsedMilliseconds
            StatusCode = $response.StatusCode
        }
    }
    catch {
        $stopwatch.Stop()
        return @{
            Success = $false
            LatencyMs = $stopwatch.ElapsedMilliseconds
            Error = $_.Exception.Message
        }
    }
}

function Test-WebSocket {
    # Quick WebSocket connectivity test using .NET
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $tcp.ConnectAsync("127.0.0.1", $Port).Wait(2000) | Out-Null
        if ($tcp.Connected) {
            $tcp.Close()
            return "OK"
        }
        return "CONNECT_FAILED"
    }
    catch {
        return "ERROR: $($_.Exception.Message)"
    }
}

function Get-ForgeProcessStats {
    # Try multiple possible process names
    $processNames = @("forge", "forge-windows-amd64", "forge-windows", "forge-linux-amd64", "forge-darwin-amd64")
    $proc = $null

    foreach ($name in $processNames) {
        $procs = Get-Process -Name $name -ErrorAction SilentlyContinue
        if ($procs) {
            $proc = $procs | Select-Object -First 1
            break
        }
    }

    if (-not $proc) {
        return $null
    }

    # Get CPU - this requires sampling
    $cpu = 0
    try {
        $counter = "\Process($($proc.ProcessName))\% Processor Time"
        $cpu = (Get-Counter $counter -ErrorAction SilentlyContinue).CounterSamples[0].CookedValue
    } catch { }

    return @{
        PID = $proc.Id
        Name = $proc.ProcessName
        CPU = [math]::Round($cpu, 1)
        MemoryMB = [math]::Round($proc.WorkingSet64 / 1MB, 1)
        Handles = $proc.HandleCount
        Threads = $proc.Threads.Count
    }
}

function Get-SystemStats {
    # Get system-wide memory usage
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $memUsedGB = 0
    $memPct = 0
    if ($os) {
        $totalMem = $os.TotalVisibleMemorySize / 1MB  # Convert KB to GB
        $freeMem = $os.FreePhysicalMemory / 1MB
        $memUsedGB = [math]::Round($totalMem - $freeMem, 1)
        $memPct = [math]::Round((($totalMem - $freeMem) / $totalMem) * 100, 1)
    }

    # Get disk queue length (indicates disk contention)
    $diskQueue = 0
    try {
        $diskQueue = (Get-Counter "\PhysicalDisk(_Total)\Current Disk Queue Length" -ErrorAction SilentlyContinue).CounterSamples[0].CookedValue
        $diskQueue = [math]::Round($diskQueue, 1)
    } catch { }

    return @{
        MemUsedGB = $memUsedGB
        MemPct = $memPct
        DiskQueue = $diskQueue
    }
}

function Get-TopProcesses {
    # Get top 3 CPU-consuming processes (excluding idle/system)
    $procs = Get-Process | Where-Object { $_.ProcessName -notin @("Idle", "System") } |
        Sort-Object CPU -Descending | Select-Object -First 3
    return ($procs | ForEach-Object { "$($_.ProcessName):$([math]::Round($_.WorkingSet64/1MB))MB" }) -join ", "
}

function Check-ForFreeze {
    param($HttpResult, $ProcessStats, $SystemStats, $LastMeasurement)

    $notes = @()
    $freezeDetected = $false

    # Check 1: HTTP latency spike
    if ($HttpResult.Success -and $HttpResult.LatencyMs -gt 500) {
        $notes += "HIGH_HTTP_LATENCY($($HttpResult.LatencyMs)ms)"
    }

    # Check 2: HTTP failure
    if (-not $HttpResult.Success) {
        $notes += "HTTP_FAILED"
        $freezeDetected = $true
    }

    # Check 3: Process stats anomalies
    if ($ProcessStats) {
        # High CPU
        if ($ProcessStats.CPU -gt 80) {
            $notes += "HIGH_CPU($($ProcessStats.CPU)%)"
        }

        # Handle leak (compare to last measurement)
        if ($LastMeasurement -and $LastMeasurement.Handles) {
            $handleGrowth = $ProcessStats.Handles - $LastMeasurement.Handles
            if ($handleGrowth -gt 50) {
                $notes += "HANDLE_GROWTH(+$handleGrowth)"
            }
        }

        # Memory growth
        if ($LastMeasurement -and $LastMeasurement.MemoryMB) {
            $memGrowth = $ProcessStats.MemoryMB - $LastMeasurement.MemoryMB
            if ($memGrowth -gt 50) {
                $notes += "MEMORY_GROWTH(+${memGrowth}MB)"
            }
        }
    }
    else {
        $notes += "PROCESS_NOT_FOUND"
    }

    # Check 4: System-wide issues
    if ($SystemStats) {
        # High system memory (>90%)
        if ($SystemStats.MemPct -gt 90) {
            $notes += "SYSTEM_MEM_HIGH($($SystemStats.MemPct)%)"
        }

        # High disk queue (indicates I/O contention)
        if ($SystemStats.DiskQueue -gt 2) {
            $notes += "DISK_CONTENTION(queue=$($SystemStats.DiskQueue))"
        }
    }

    # Determine if this looks like a freeze
    if ($HttpResult.LatencyMs -gt 2000) {
        $freezeDetected = $true
    }

    return @{
        FreezeDetected = $freezeDetected
        Notes = ($notes -join "; ")
    }
}

Write-Log "INFO" "Starting diagnostic monitoring..."
Write-Log "INFO" "Looking for forge.exe process..."

$iteration = 0
$lastMeasurement = $null

try {
    while ($true) {
        $iteration++
        $now = Get-Date

        # Gather all metrics
        $httpResult = Test-HttpEndpoint
        $wsResult = Test-WebSocket
        $procStats = Get-ForgeProcessStats
        $sysStats = Get-SystemStats

        # Analyze for freeze
        $analysis = Check-ForFreeze -HttpResult $httpResult -ProcessStats $procStats -SystemStats $sysStats -LastMeasurement $lastMeasurement

        # Build measurement
        $measurement = @{
            Timestamp = $now.ToString("HH:mm:ss.fff")
            HttpLatencyMs = $httpResult.LatencyMs
            HttpStatus = if ($httpResult.Success) { "OK" } else { "FAIL" }
            CPU = if ($procStats) { $procStats.CPU } else { "N/A" }
            MemoryMB = if ($procStats) { $procStats.MemoryMB } else { "N/A" }
            Handles = if ($procStats) { $procStats.Handles } else { "N/A" }
            Threads = if ($procStats) { $procStats.Threads } else { "N/A" }
            WsTest = $wsResult
            SysMemGB = $sysStats.MemUsedGB
            SysMemPct = $sysStats.MemPct
            DiskQueue = $sysStats.DiskQueue
            FreezeDetected = $analysis.FreezeDetected
            Notes = $analysis.Notes
        }

        # Log to CSV
        "$($measurement.Timestamp),$($measurement.HttpLatencyMs),$($measurement.HttpStatus),$($measurement.CPU),$($measurement.MemoryMB),$($measurement.Handles),$($measurement.Threads),$($measurement.WsTest),$($measurement.SysMemGB),$($measurement.SysMemPct),$($measurement.DiskQueue),$($measurement.FreezeDetected),`"$($measurement.Notes)`"" | Out-File $csvFile -Append

        # Console output - include system stats
        $statusLine = "HTTP: $($measurement.HttpLatencyMs)ms | ForgeMem: $($measurement.MemoryMB)MB | SysMem: $($measurement.SysMemPct)% | DiskQ: $($measurement.DiskQueue)"

        if ($analysis.FreezeDetected) {
            $freezeCount++
            Write-Log "FREEZE" ">>> FREEZE #$freezeCount DETECTED <<< $statusLine"
            Write-Log "FREEZE" "Notes: $($analysis.Notes)"
            # Log top processes at time of freeze
            $topProcs = Get-TopProcesses
            Write-Log "FREEZE" "Top processes: $topProcs"

            # Beep alert
            [Console]::Beep(1000, 500)
            [Console]::Beep(1500, 500)
        }
        elseif ($analysis.Notes) {
            Write-Log "WARN" "$statusLine | $($analysis.Notes)"
        }
        else {
            # Normal status - less verbose after first few
            if ($iteration -le 5 -or $iteration % 10 -eq 0) {
                Write-Log "INFO" $statusLine
            }
            else {
                # Just show a dot to indicate we're alive
                Write-Host "." -NoNewline -ForegroundColor DarkGray
            }
        }

        $lastMeasurement = $measurement
        Start-Sleep -Seconds $Interval
    }
}
finally {
    Write-Host ""
    Write-Log "INFO" "Stopping diagnostic tool..."
    Write-Log "INFO" "Total freezes detected: $freezeCount"
    Write-Log "INFO" "Log file: $logFile"
    Write-Log "INFO" "CSV file: $csvFile"

    # Generate summary
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "                         SUMMARY REPORT                            " -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "Total Freezes Detected: $freezeCount" -ForegroundColor $(if ($freezeCount -gt 0) { "Red" } else { "Green" })
    Write-Host "Log File: $logFile"
    Write-Host "CSV File: $csvFile"
    Write-Host ""
    Write-Host "To analyze the CSV in Excel or view trends, open: $csvFile"
}
