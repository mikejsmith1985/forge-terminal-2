# System-wide check for resource hogs
Write-Host "=== TOP CPU PROCESSES ==="
Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 Name, Id, CPU, @{N='Mem_MB';E={[math]::Round($_.WorkingSet64/1MB)}} | Format-Table -AutoSize

Write-Host "`n=== TOP MEMORY PROCESSES ==="
Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10 Name, Id, @{N='Mem_MB';E={[math]::Round($_.WorkingSet64/1MB)}}, @{N='Virtual_MB';E={[math]::Round($_.VirtualMemorySize64/1MB)}} | Format-Table -AutoSize

Write-Host "`n=== HIGH HANDLE COUNT (>500) ==="
Get-Process | Where-Object { $_.HandleCount -gt 500 } | Sort-Object HandleCount -Descending | Select-Object Name, Id, HandleCount | Format-Table -AutoSize

Write-Host "`n=== FORGE SPECIFIC ==="
$forge = Get-Process | Where-Object { $_.ProcessName -match "forge" }
if ($forge) {
    foreach ($p in $forge) {
        Write-Host "Process: $($p.ProcessName) (PID: $($p.Id))"
        Write-Host "  Working Set: $([math]::Round($p.WorkingSet64/1MB)) MB"
        Write-Host "  Virtual Mem: $([math]::Round($p.VirtualMemorySize64/1MB)) MB"
        Write-Host "  Handles: $($p.HandleCount)"
        Write-Host "  Threads: $($p.Threads.Count)"
    }
}
