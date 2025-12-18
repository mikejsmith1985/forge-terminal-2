# Quick check of Forge process stats
$forge = Get-Process | Where-Object { $_.ProcessName -match "forge" } | Select-Object -First 1
if ($forge) {
    Write-Host "=== FORGE PROCESS STATUS ==="
    Write-Host "PID: $($forge.Id)"
    Write-Host "Memory (Working Set): $([math]::Round($forge.WorkingSet64/1MB)) MB"
    Write-Host "Memory (Virtual): $([math]::Round($forge.VirtualMemorySize64/1MB)) MB"
    Write-Host "Handles: $($forge.HandleCount)"
    Write-Host "Threads: $($forge.Threads.Count)"
    Write-Host "CPU Time: $($forge.CPU) seconds"
    Write-Host ""
    Write-Host "=== THREAD BREAKDOWN ==="
    $threads = $forge.Threads
    $waiting = ($threads | Where-Object { $_.ThreadState -eq 'Wait' }).Count
    $running = ($threads | Where-Object { $_.ThreadState -eq 'Running' }).Count
    Write-Host "Running: $running"
    Write-Host "Waiting: $waiting"
    Write-Host "Total: $($threads.Count)"
} else {
    Write-Host "Forge process not found"
}
