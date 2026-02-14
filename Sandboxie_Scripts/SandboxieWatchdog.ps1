# ============================================================================
# SandboxieWatchdog.ps1 - External Process Monitor for Sandboxie Wrapper
# ============================================================================
# Monitors the wrapper PID. When wrapper dies (AMP kills it during Stop/Abort),
# the watchdog kills the exe process and cleans up ForceProcess rules.
# This solves the orphan process problem during Abort/Stop.
# ============================================================================

param(
    [Parameter(Mandatory=$true)]
    [int]$WrapperPID,

    [Parameter(Mandatory=$true)]
    [int]$ExePID,

    [Parameter(Mandatory=$true)]
    [string]$ExeName,

    [Parameter(Mandatory=$true)]
    [string]$ExeDir,

    [Parameter(Mandatory=$true)]
    [string]$SandboxName,

    [Parameter(Mandatory=$true)]
    [string]$SandboxiePath
)

# ============================================================================
# LOGGING
# ============================================================================

$logDir = Join-Path $PSScriptRoot "Logs"
if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logFile = Join-Path $logDir "SandboxieWatchdog_$(Get-Date -Format 'yyyy-MM-dd').log"

function Write-WatchdogLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    try { "[$timestamp] [WATCHDOG-$Level] $Message" | Out-File -FilePath $logFile -Append -Encoding UTF8 } catch {}
}

# Cleanup old logs
try {
    Get-ChildItem -Path $logDir -Filter "SandboxieWatchdog_*.log" |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
} catch {}

# ============================================================================
# MAIN MONITORING LOOP
# ============================================================================

Write-WatchdogLog "Watchdog started"
Write-WatchdogLog "  Wrapper PID: $WrapperPID"
Write-WatchdogLog "  Exe PID: $ExePID"
Write-WatchdogLog "  Exe Name: $ExeName"
Write-WatchdogLog "  Sandbox: $SandboxName"

$sbieIniExe = Join-Path $SandboxiePath "SbieIni.exe"
$startExe = Join-Path $SandboxiePath "Start.exe"

# Verify wrapper and exe are alive
try {
    $wrapperProc = Get-Process -Id $WrapperPID -ErrorAction Stop
    Write-WatchdogLog "Wrapper process found: $($wrapperProc.ProcessName) (PID: $WrapperPID)"
} catch {
    Write-WatchdogLog "Wrapper already dead at startup - cleaning up immediately" "WARNING"
    # Fall through to cleanup
}

try {
    $exeProc = Get-Process -Id $ExePID -ErrorAction Stop
    Write-WatchdogLog "Exe process found: $($exeProc.ProcessName) (PID: $ExePID)"
} catch {
    Write-WatchdogLog "Exe already dead at startup - nothing to do" "WARNING"
    exit 0
}

# Monitor wrapper - check every 200ms
$checkCount = 0
while ($true) {
    Start-Sleep -Milliseconds 200
    $checkCount++

    # Check if wrapper is still alive
    try {
        Get-Process -Id $WrapperPID -ErrorAction Stop | Out-Null
    } catch {
        # Wrapper is dead - time to clean up
        Write-WatchdogLog "WRAPPER DIED (PID: $WrapperPID) after $checkCount checks" "WARNING"
        break
    }

    # Check if exe died on its own (wrapper should handle this, but just in case)
    try {
        Get-Process -Id $ExePID -ErrorAction Stop | Out-Null
    } catch {
        Write-WatchdogLog "Exe died on its own (PID: $ExePID) - watchdog exiting"
        # Cleanup ForceProcess rules
        try {
            & $sbieIniExe delete $SandboxName "ForceProcess" $ExeName 2>&1 | Out-Null
            & $sbieIniExe delete $SandboxName "ForceFolder" $ExeDir 2>&1 | Out-Null
            & $startExe /reload 2>&1 | Out-Null
        } catch {}
        exit 0
    }

    # Periodic heartbeat every ~30 seconds (150 checks * 200ms)
    if ($checkCount % 150 -eq 0) {
        Write-WatchdogLog "Heartbeat: wrapper=$WrapperPID exe=$ExePID alive (checks: $checkCount)" "DEBUG"
    }
}

# ============================================================================
# WRAPPER DIED - KILL EXE AND CLEANUP
# ============================================================================

Write-WatchdogLog "Killing exe PID $ExePID..." "WARNING"

# Small grace period
Start-Sleep -Milliseconds 300

# Kill the exe
try {
    Stop-Process -Id $ExePID -Force -ErrorAction Stop
    Write-WatchdogLog "Exe killed successfully (PID: $ExePID)"
} catch {
    Write-WatchdogLog "Failed to kill by PID, trying by name..." "WARNING"
    try {
        $exeBaseName = $ExeName -replace '\.exe$', ''
        Get-Process -Name $exeBaseName -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue
        Write-WatchdogLog "Killed by name: $exeBaseName"
    } catch {
        Write-WatchdogLog "Failed to kill exe: $_" "ERROR"
    }
}

# Cleanup ForceProcess/ForceFolder rules
Write-WatchdogLog "Cleaning up ForceProcess rules..."
try {
    & $sbieIniExe delete $SandboxName "ForceProcess" $ExeName 2>&1 | Out-Null
    & $sbieIniExe delete $SandboxName "ForceFolder" $ExeDir 2>&1 | Out-Null
    & $startExe /reload 2>&1 | Out-Null
    Write-WatchdogLog "ForceProcess rules cleaned up"
} catch {
    Write-WatchdogLog "Failed to cleanup rules: $_" "WARNING"
}

# Remove PID file if exists
$pidFile = Join-Path $PSScriptRoot "sandboxie_exe.pid"
try { Remove-Item -Path $pidFile -Force -ErrorAction SilentlyContinue } catch {}

Write-WatchdogLog "Watchdog exiting - cleanup complete"
exit 0
