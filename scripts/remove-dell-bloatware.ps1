# Dell Bloatware Removal Script
# Run as Administrator for best results

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  DELL BLOATWARE REMOVAL TOOL" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# List all Dell apps from Windows Store (AppX packages)
Write-Host "=== DELL APPX PACKAGES (Windows Store Apps) ===" -ForegroundColor Yellow
$dellAppx = Get-AppxPackage -AllUsers | Where-Object { $_.Name -like "*Dell*" -or $_.Publisher -like "*Dell*" }
if ($dellAppx) {
    $dellAppx | Select-Object Name, Version | Format-Table -AutoSize
} else {
    Write-Host "No Dell AppX packages found" -ForegroundColor Green
}

# List Dell programs from registry (traditional installed programs)
Write-Host "`n=== DELL INSTALLED PROGRAMS ===" -ForegroundColor Yellow
$uninstallPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

$dellPrograms = @()
foreach ($path in $uninstallPaths) {
    $items = Get-ItemProperty $path -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like "*Dell*" -and $_.DisplayName }
    if ($items) {
        $dellPrograms += $items
    }
}

if ($dellPrograms) {
    $dellPrograms | Select-Object DisplayName, DisplayVersion, Publisher |
        Sort-Object DisplayName -Unique | Format-Table -AutoSize
} else {
    Write-Host "No Dell programs found in registry" -ForegroundColor Green
}

# List Dell services
Write-Host "`n=== DELL SERVICES ===" -ForegroundColor Yellow
$dellServices = Get-Service | Where-Object { $_.DisplayName -like "*Dell*" -or $_.Name -like "*Dell*" }
if ($dellServices) {
    $dellServices | Select-Object Name, DisplayName, Status, StartType | Format-Table -AutoSize
} else {
    Write-Host "No Dell services found" -ForegroundColor Green
}

# List Dell scheduled tasks
Write-Host "`n=== DELL SCHEDULED TASKS ===" -ForegroundColor Yellow
$dellTasks = Get-ScheduledTask | Where-Object { $_.TaskName -like "*Dell*" -or $_.TaskPath -like "*Dell*" }
if ($dellTasks) {
    $dellTasks | Select-Object TaskName, State | Format-Table -AutoSize
} else {
    Write-Host "No Dell scheduled tasks found" -ForegroundColor Green
}

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "  REMOVAL OPTIONS" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "To remove Dell software, you have these options:" -ForegroundColor White
Write-Host ""
Write-Host "1. SAFEST: Use Windows Settings" -ForegroundColor Green
Write-Host "   Settings > Apps > Installed apps > Search 'Dell' > Uninstall each"
Write-Host ""
Write-Host "2. QUICK: Stop Dell services (keeps installed, stops running)" -ForegroundColor Yellow
Write-Host "   Run: Stop-Service -Name 'Dell*' -Force"
Write-Host "   Run: Set-Service -Name 'ServiceName' -StartupType Disabled"
Write-Host ""
Write-Host "3. AGGRESSIVE: Remove AppX packages" -ForegroundColor Red
Write-Host "   Get-AppxPackage -AllUsers *Dell* | Remove-AppxPackage -AllUsers"
Write-Host ""

$response = Read-Host "Do you want to STOP all Dell services now? (y/n)"
if ($response -eq 'y') {
    Write-Host "`nStopping Dell services..." -ForegroundColor Yellow
    $dellServices | ForEach-Object {
        Write-Host "  Stopping $($_.Name)..." -NoNewline
        try {
            Stop-Service -Name $_.Name -Force -ErrorAction Stop
            Set-Service -Name $_.Name -StartupType Disabled -ErrorAction SilentlyContinue
            Write-Host " OK" -ForegroundColor Green
        } catch {
            Write-Host " FAILED (may need admin)" -ForegroundColor Red
        }
    }
}

$response2 = Read-Host "`nDo you want to REMOVE Dell AppX packages? (y/n)"
if ($response2 -eq 'y') {
    Write-Host "`nRemoving Dell AppX packages..." -ForegroundColor Yellow
    $dellAppx | ForEach-Object {
        Write-Host "  Removing $($_.Name)..." -NoNewline
        try {
            Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction Stop
            Write-Host " OK" -ForegroundColor Green
        } catch {
            Write-Host " FAILED" -ForegroundColor Red
        }
    }
}

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "  DONE - Restart recommended" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
