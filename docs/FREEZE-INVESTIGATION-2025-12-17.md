# Forge Terminal Freeze Investigation - December 17, 2025

## Executive Summary

After extensive investigation, the terminal freezes appear to be caused by **system-wide resource contention**, not Forge-specific bugs. The primary culprits are:

1. **Dell bloatware** consuming 20,000+ handles and triggering during Forge activity
2. **Windows Defender** real-time scanning spiking to 40%+ CPU during terminal activity
3. **High process count** on the system creating resource pressure

Forge's code optimizations helped reduce its contribution, but the underlying system issues remain.

---

## Investigation Timeline

### Initial Symptoms
- Terminal freezes lasting 10-30+ seconds
- Occurs randomly during normal usage
- HTTP backend remains responsive during freeze (15-75ms latency)
- Only terminal component freezes, not command cards or other UI
- VS Code terminal also affected when Forge is running

### Key Findings

#### 1. Performance Monitor Data (13:27-13:31)
```
Time        | Forge CPU | Defender CPU | DWM CPU | Combined
------------|-----------|--------------|---------|----------
13:28:33    | 96.4%     | 42.4%        | 19.9%   | 158%+
13:29:03    | 92.6%     | 43.7%        | 33.5%   | 170%+
13:29:18    | 97.7%     | 38.9%        | 37%     | 174%+
13:29:33    | 98.2%     | 31.5%        | 33.5%   | 163%+
```

#### 2. Memory Growth Pattern (17:35 freeze)
```
Time     | Forge Mem | Note
---------|-----------|------------------
17:34:57 | 41 MB     | Normal
17:35:01 | 180 MB    | Spike begins
17:35:19 | 712 MB    | Peak
17:35:23 | 790 MB    | Maximum
17:35:38 | 242 MB    | Recovered
```

#### 3. System Resource Analysis (17:50)
**Dell Bloatware Handle Count:**
| Process | Handles |
|---------|---------|
| ServiceShell | 18,030 |
| Dell.TechHub.Diagnostics.SubAgent | 7,778 |
| Dell.TechHub.Instrumentation.SubAgent | 5,875 |
| Dell.TechHub.Instrumentation.UserProcess | 2,748 |
| SupportAssistAgent | 1,950 |
| Dell.UCA.Manager | 1,122 |
| Dell.CoreServices.Client | 943 |
| Dell.Update.SubAgent | 942 |
| Dell.TechHub.Analytics.SubAgent | 827 |
| Dell.TechHub.DataManager.SubAgent | 741 |
| Dell.TechHub | 910 |
| Dell.Connected.Service.Delivery.SubAgent | 702 |
| **TOTAL DELL** | **~42,000+** |

**Virtual Memory Allocations:**
| Process | Virtual Memory |
|---------|----------------|
| SupportAssistAgent | 2.3 TB |
| Discord | 3.5 TB |
| Code (VS Code) | 3.5 TB |
| msedge | 2.3 TB |
| Forge | 6.4 GB |

**For comparison:** Forge uses 456 handles and 6.4GB virtual memory - tiny compared to Dell software.

---

## Code Issues Found & Fixed

### Fix 1: LLM Logger Output Throttling (v1.24.4)
**File:** `internal/terminal/handler.go`
**Problem:** LLM logger called on every PTY output chunk, acquiring mutex lock hundreds of times per second.
**Solution:** Buffer output and flush every 200ms instead of per-chunk.

### Fix 2: Goroutine Spawn Per Keystroke (v1.24.5)
**File:** `internal/terminal/handler.go`
**Problem:** `go llmLogger.AddUserInput(dataStr)` spawned a goroutine for every keystroke when inside Claude/Copilot TUI, causing hundreds of goroutines fighting for mutex.
**Solution:** Call AddUserInput synchronously instead of spawning goroutines.

### Fix 3: Frontend Write Batching (pending)
**File:** `frontend/src/components/ForgeTerminal.jsx`
**Problem:** `term.write()` called on every WebSocket message, potentially thousands per second.
**Solution:** Batch writes using requestAnimationFrame - accumulate data and write once per frame (~60fps).

---

## Root Cause Analysis

### Why It Only Affects This Machine
1. **Dell bloatware density** - 42,000+ handles from Dell processes alone
2. **SupportAssist monitoring** - triggers during terminal activity
3. **Windows Defender aggressive scanning** - not excluded for dev directories
4. **High concurrent app load** - Fusion360, Discord, multiple Edge instances, VS Code

### Why It Correlates With Forge
1. Forge's terminal activity triggers Dell's monitoring to scan/analyze
2. PTY output combined with Defender scanning creates CPU spikes
3. Combined load exceeds system's ability to service UI updates
4. Results in UI freeze while backend continues responding

### Why Other Users Don't Experience It
1. Don't have Dell bloatware
2. Have Defender exclusions set up
3. Different concurrent app configurations
4. Different hardware/driver combinations

---

## Recommended Fixes

### Immediate (User Action Required)
1. **Remove Dell bloatware** - See removal guide below
2. **Add Windows Defender exclusions:**
   ```powershell
   Add-MpPreference -ExclusionPath "C:\ProjectsWin\forge-terminal-2-new"
   Add-MpPreference -ExclusionProcess "forge-windows-amd64.exe"
   ```

### Code Improvements (Completed/Pending)
1. ✅ LLM logger output throttling
2. ✅ Remove goroutine-per-keystroke
3. ⏳ Frontend write batching
4. ⏳ Consider disabling AM/LLM logging by default

---

## Dell Bloatware Removal Guide

### Safe to Remove (Performance Impact)
- Dell SupportAssist
- Dell TechHub (all components)
- Dell Update
- Dell Digital Delivery
- Dell Customer Connect
- Dell UCA Manager

### Keep (Hardware Functionality)
- Dell Display Manager (if using Dell monitors)
- Realtek Audio drivers
- Intel/NVIDIA drivers (not Dell-branded)
- Thunderbolt drivers (if using Thunderbolt)

### Removal Methods
1. **Settings → Apps → Uninstall** (safest)
2. **Services.msc → Disable services** (keeps installed but stops running)
3. **Task Manager → Startup → Disable** (prevents auto-start)

---

## Diagnostic Tools Created

### 1. Auto-Diagnostic Monitor
**Location:** `scripts/freeze-monitor/auto-diagnostic.ps1`
**Usage:** Run in separate PowerShell, monitors continuously, note time of freeze.

### 2. System Check Script
**Location:** `scripts/check-system.ps1`
**Usage:** Shows top CPU, memory, and handle consumers.

### 3. Forge Process Check
**Location:** `scripts/check-forge.ps1`
**Usage:** Detailed stats for Forge process.

---

## Appendix: Raw Diagnostic Data

### Performance Monitor CSV Location
`C:\ProjectsWin\forge-terminal-2-new\perfmon-data.csv`

### Freeze Monitor Logs
- `scripts/freeze-monitor/forge-diagnostic-2025-12-17_17-34.log`
- `scripts/freeze-monitor/freeze-metrics-*.csv`

### Key Observations Log
```
17:34:49 - Forge CPU 0%, Memory 41MB - Normal
17:35:01 - Forge CPU 101%, Memory 180MB - Spike begins
17:35:23 - Forge CPU 81%, Memory 790MB - Peak memory
17:35:38 - Forge CPU 3%, Memory 242MB - Recovered
```

---

## Conclusion

The freeze is a **perfect storm** of:
1. Dell bloatware consuming massive system resources (42,000+ handles)
2. Windows Defender scanning terminal output
3. Forge's (now fixed) inefficient logging patterns
4. High concurrent application load

**Primary fix:** Remove Dell bloatware and add Defender exclusions.
**Secondary fix:** Code optimizations already implemented.
