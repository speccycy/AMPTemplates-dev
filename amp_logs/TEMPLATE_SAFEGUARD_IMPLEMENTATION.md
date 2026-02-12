# Template Safeguard Implementation - Prevent Double-Trigger Bug

## Overview

Add safeguards to SCUMWrapper.ps1 to prevent duplicate execution and ensure auto-start after updates.

---

## Implementation Plan

### 1. Execution Lock Mechanism

**Purpose**: Prevent multiple wrapper instances from running simultaneously

**Location**: Add at the beginning of SCUMWrapper.ps1 (after parameter declarations)

```powershell
# ============================================================================
# EXECUTION LOCK - Prevent Duplicate Execution
# ============================================================================

$lockFile = Join-Path $PSScriptRoot "wrapper_execution.lock"
$lockTimeout = 3600 # 1 hour in seconds

function Test-ExecutionLock {
    if (Test-Path $lockFile) {
        try {
            $lockData = Get-Content $lockFile -Raw | ConvertFrom-Json
            $lockAge = (Get-Date) - [DateTime]$lockData.Timestamp
            
            # Check if lock is stale (older than timeout)
            if ($lockAge.TotalSeconds -gt $lockTimeout) {
                Write-Log "WARNING" "Stale lock detected (age: $([math]::Round($lockAge.TotalMinutes, 2))m). Removing..."
                Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
                return $false
            }
            
            # Check if locked process is still running
            $lockedPID = $lockData.WrapperPID
            if (-not (Get-Process -Id $lockedPID -ErrorAction SilentlyContinue)) {
                Write-Log "WARNING" "Lock exists but process PID $lockedPID is dead. Removing..."
                Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
                return $false
            }
            
            # Valid lock exists
            Write-Log "ERROR" "Another wrapper instance is already running (PID: $lockedPID, age: $([math]::Round($lockAge.TotalMinutes, 2))m)"
            Write-Log "ERROR" "If this is incorrect, delete: $lockFile"
            return $true
        }
        catch {
            Write-Log "WARNING" "Failed to read lock file: $_. Removing..."
            Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
            return $false
        }
    }
    return $false
}

function Set-ExecutionLock {
    $lockData = @{
        WrapperPID = $PID
        Timestamp = (Get-Date).ToString("o")
        ServerPath = $ServerPath
    }
    $lockData | ConvertTo-Json | Set-Content $lockFile -Force
    Write-Log "DEBUG" "Execution lock created (PID: $PID)"
}

function Remove-ExecutionLock {
    if (Test-Path $lockFile) {
        Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
        Write-Log "DEBUG" "Execution lock removed"
    }
}

# Check for existing lock
if (Test-ExecutionLock) {
    Write-Host "[ERROR] Wrapper execution blocked - another instance is running"
    exit 1
}

# Set lock for this execution
Set-ExecutionLock

# Ensure lock is removed on exit
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    Remove-ExecutionLock
} | Out-Null
```

---

### 2. Minimum Interval Check

**Purpose**: Prevent execution if last run was too recent

**Location**: Add after execution lock check

```powershell
# ============================================================================
# MINIMUM INTERVAL CHECK - Prevent Rapid Re-execution
# ============================================================================

$lastRunFile = Join-Path $PSScriptRoot "last_execution.json"
$minimumIntervalMinutes = 30 # Minimum 30 minutes between executions

function Test-MinimumInterval {
    if (Test-Path $lastRunFile) {
        try {
            $lastRun = Get-Content $lastRunFile -Raw | ConvertFrom-Json
            $lastRunTime = [DateTime]$lastRun.Timestamp
            $timeSinceLastRun = (Get-Date) - $lastRunTime
            
            if ($timeSinceLastRun.TotalMinutes -lt $minimumIntervalMinutes) {
                $waitTime = $minimumIntervalMinutes - $timeSinceLastRun.TotalMinutes
                Write-Log "ERROR" "Last execution was $([math]::Round($timeSinceLastRun.TotalMinutes, 2))m ago"
                Write-Log "ERROR" "Minimum interval: ${minimumIntervalMinutes}m. Please wait $([math]::Round($waitTime, 2))m"
                Write-Log "ERROR" "This prevents duplicate scheduled task execution"
                return $false
            }
            
            Write-Log "INFO" "Last execution: $([math]::Round($timeSinceLastRun.TotalMinutes, 2))m ago (OK)"
            return $true
        }
        catch {
            Write-Log "WARNING" "Failed to read last execution file: $_"
            return $true # Allow execution if file is corrupted
        }
    }
    return $true # No previous execution recorded
}

function Update-LastExecutionTime {
    $executionData = @{
        Timestamp = (Get-Date).ToString("o")
        WrapperPID = $PID
        ServerPID = $serverProcess.Id
    }
    $executionData | ConvertTo-Json | Set-Content $lastRunFile -Force
    Write-Log "DEBUG" "Last execution time updated"
}

# Check minimum interval (only for scheduled executions, not manual starts)
if (-not $SkipIntervalCheck) {
    if (-not (Test-MinimumInterval)) {
        Write-Host "[ERROR] Execution blocked - minimum interval not met"
        Remove-ExecutionLock
        exit 1
    }
}
```

---

### 3. Pre-Start Cleanup Enhancement

**Purpose**: Improve orphan detection and cleanup

**Location**: Enhance existing `Test-OrphanedProcesses` function

```powershell
function Test-OrphanedProcesses {
    Write-Log "DEBUG" "Pre-start check: Looking for orphaned processes..."
    
    # Check PID file
    if (Test-Path $pidFile) {
        try {
            $pidData = Get-Content $pidFile -Raw | ConvertFrom-Json
            $serverPID = $pidData.ServerPID
            
            # Check if process exists
            $process = Get-Process -Id $serverPID -ErrorAction SilentlyContinue
            if ($process -and $process.ProcessName -eq "SCUMServer") {
                Write-Log "WARNING" "Found orphaned process PID: $serverPID (from previous run)"
                
                # Check process age
                $processAge = (Get-Date) - $process.StartTime
                Write-Log "DEBUG" "Orphaned process age: $([math]::Round($processAge.TotalMinutes, 2))m"
                
                # Attempt graceful shutdown first
                Write-Log "INFO" "Attempting graceful shutdown of orphaned process..."
                try {
                    # Send Ctrl+C
                    $result = [ProcessControl]::GenerateConsoleCtrlEvent(0, $serverPID)
                    if ($result) {
                        Write-Log "DEBUG" "Ctrl+C sent to orphaned process"
                        
                        # Wait for graceful exit (max 30s)
                        $waited = 0
                        while ($waited -lt 30) {
                            Start-Sleep -Seconds 2
                            $waited += 2
                            if (-not (Get-Process -Id $serverPID -ErrorAction SilentlyContinue)) {
                                Write-Log "INFO" "Orphaned process exited gracefully"
                                break
                            }
                        }
                    }
                }
                catch {
                    Write-Log "WARNING" "Graceful shutdown failed: $_"
                }
                
                # Force kill if still running
                if (Get-Process -Id $serverPID -ErrorAction SilentlyContinue) {
                    Write-Log "WARNING" "Graceful shutdown timeout. Force killing orphaned process..."
                    Stop-Process -Id $serverPID -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 2
                }
                
                # Verify termination
                if (Get-Process -Id $serverPID -ErrorAction SilentlyContinue) {
                    Write-Log "ERROR" "Failed to terminate orphaned process PID: $serverPID"
                    return $false
                }
                else {
                    Write-Log "INFO" "Successfully terminated orphaned PID: $serverPID"
                }
            }
        }
        catch {
            Write-Log "WARNING" "Error checking PID file: $_"
        }
        
        # Remove stale PID file
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
        Write-Log "DEBUG" "Removed stale PID file"
    }
    
    # Check for any SCUMServer processes not tracked by PID file
    $allSCUMProcesses = Get-Process -Name "SCUMServer" -ErrorAction SilentlyContinue
    if ($allSCUMProcesses) {
        Write-Log "WARNING" "Found $($allSCUMProcesses.Count) untracked SCUMServer process(es)"
        foreach ($proc in $allSCUMProcesses) {
            Write-Log "WARNING" "Terminating untracked process PID: $($proc.Id)"
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 3
    }
    
    Write-Log "DEBUG" "Pre-start check: No orphaned processes found"
    return $true
}
```

---

### 4. Post-Update Auto-Start Verification

**Purpose**: Ensure server starts after update completes

**Location**: Add new function and call after update completion

```powershell
function Verify-ServerStarted {
    param(
        [int]$MaxWaitSeconds = 120,
        [int]$CheckIntervalSeconds = 5
    )
    
    Write-Log "INFO" "Verifying server started after update..."
    
    $startTime = Get-Date
    $checksPerformed = 0
    
    while (((Get-Date) - $startTime).TotalSeconds -lt $MaxWaitSeconds) {
        $checksPerformed++
        
        # Check if server process exists
        $serverProc = Get-Process -Name "SCUMServer" -ErrorAction SilentlyContinue
        if ($serverProc) {
            Write-Log "INFO" "✓ Server process found (PID: $($serverProc.Id))"
            
            # Check if server reached "Started" state (look for ready pattern in log)
            $logContent = Get-Content $logPath -Tail 100 -ErrorAction SilentlyContinue
            if ($logContent -match "LogSCUM: Global Stats") {
                Write-Log "INFO" "✓ Server reached STARTED state"
                return $true
            }
            else {
                Write-Log "DEBUG" "Server process running but not ready yet (check $checksPerformed)"
            }
        }
        else {
            Write-Log "DEBUG" "Server process not found yet (check $checksPerformed)"
        }
        
        Start-Sleep -Seconds $CheckIntervalSeconds
    }
    
    Write-Log "ERROR" "Server failed to start within ${MaxWaitSeconds}s"
    return $false
}

# Call after update completes (if update was performed)
if ($updatePerformed) {
    if (-not (Verify-ServerStarted)) {
        Write-Log "ERROR" "Auto-start verification failed. Manual intervention required."
        # Don't exit - let AMP handle the failure
    }
}
```

---

### 5. Enhanced Cleanup on Exit

**Purpose**: Ensure all locks and state files are cleaned up

**Location**: Enhance existing cleanup section

```powershell
function Cleanup-AllStateFiles {
    Write-Log "DEBUG" "Cleaning up state files..."
    
    # Remove execution lock
    Remove-ExecutionLock
    
    # Remove PID file
    if (Test-Path $pidFile) {
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
        Write-Log "DEBUG" "Removed PID file"
    }
    
    # Remove server ready flag
    if (Test-Path $serverReadyFlag) {
        Remove-Item $serverReadyFlag -Force -ErrorAction SilentlyContinue
        Write-Log "DEBUG" "Removed server ready flag"
    }
    
    # Update last execution time
    Update-LastExecutionTime
    
    Write-Log "DEBUG" "State file cleanup complete"
}

# Register cleanup on exit
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    Cleanup-AllStateFiles
} | Out-Null

# Also cleanup in finally block
try {
    # ... main wrapper logic ...
}
finally {
    Cleanup-AllStateFiles
}
```

---

## Integration Points

### Where to Add in SCUMWrapper.ps1

1. **After line ~50** (after parameter declarations): Add execution lock
2. **After line ~100** (after logging setup): Add minimum interval check
3. **Replace existing `Test-OrphanedProcesses`** (around line ~300): Enhanced version
4. **After line ~800** (after server start): Add auto-start verification
5. **In finally block** (around line ~900): Enhanced cleanup

---

## Configuration Options

Add these parameters to wrapper for flexibility:

```powershell
param(
    [string]$ServerPath = "SCUMServer.exe",
    [switch]$SkipIntervalCheck,      # NEW: Skip minimum interval check
    [int]$MinIntervalMinutes = 30,   # NEW: Minimum interval between executions
    [int]$LockTimeoutSeconds = 3600, # NEW: Lock file timeout
    [switch]$ForceStart               # NEW: Force start even if checks fail
)
```

---

## Testing Checklist

After implementation, test:

- [ ] Single execution works normally
- [ ] Duplicate execution within 30m is blocked
- [ ] Stale lock files are cleaned up automatically
- [ ] Orphaned processes are detected and cleaned
- [ ] Server auto-starts after update
- [ ] Manual start bypasses interval check (use -SkipIntervalCheck)
- [ ] Lock is removed on wrapper crash
- [ ] All state files cleaned up on exit

---

## Rollback Plan

If issues occur:

1. Keep backup of original SCUMWrapper.ps1
2. Test in development environment first
3. Monitor first scheduled execution closely
4. Revert if any issues detected

---

## Expected Behavior After Implementation

### Scenario 1: Normal Scheduled Update
```
05:00:00 - Task triggers
05:00:01 - Wrapper checks lock (none found)
05:00:01 - Wrapper checks interval (OK)
05:00:02 - Wrapper starts, creates lock
05:00:05 - Server stops gracefully
05:00:35 - Update completes
05:00:40 - Server starts
05:01:00 - Wrapper verifies server started (OK)
05:01:05 - Wrapper exits, removes lock
```

### Scenario 2: Duplicate Task Trigger (BUG)
```
05:00:00 - First task triggers
05:00:01 - First wrapper checks lock (none found) ✓
05:00:01 - First wrapper creates lock
05:00:05 - Server stops gracefully
05:01:00 - Second task triggers
05:01:01 - Second wrapper checks lock (FOUND) ✗
05:01:01 - Second wrapper BLOCKED - exits immediately
05:01:05 - First wrapper continues normally
05:01:35 - Update completes, server starts
```

### Scenario 3: Rapid Manual Restart
```
12:00:00 - User clicks "Restart"
12:00:05 - Server stops, restarts
12:00:30 - User clicks "Restart" again
12:00:31 - Wrapper checks interval (last run 31s ago) ✗
12:00:31 - Wrapper BLOCKED - "Please wait 29.5m"
```

---

## Monitoring After Deployment

Watch for these log patterns:

**Success Indicators:**
```
[INFO] Execution lock created (PID: 12345)
[INFO] Last execution: 245.3m ago (OK)
[INFO] ✓ Server reached STARTED state
[DEBUG] Execution lock removed
```

**Block Indicators (Expected):**
```
[ERROR] Another wrapper instance is already running (PID: 12345, age: 0.5m)
[ERROR] Last execution was 5.2m ago
[ERROR] Minimum interval: 30m. Please wait 24.8m
```

**Problem Indicators (Investigate):**
```
[ERROR] Failed to terminate orphaned process PID: 12345
[ERROR] Server failed to start within 120s
[ERROR] Auto-start verification failed
```

---

**Document Created**: 2026-01-15  
**Status**: Ready for implementation  
**Priority**: High (prevents extended downtime)
