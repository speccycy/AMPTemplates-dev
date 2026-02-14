# ============================================================================
# SandboxieWrapper.ps1 - Windows EXE Runner with Sandboxie & Process Lasso
# ============================================================================

# param() MUST be first executable statement
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    $ScriptArgs
)

# Force UTF-8 output
$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ============================================================================
# CONFIGURATION
# ============================================================================

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

$logDir = Join-Path $PSScriptRoot "Logs"
$logFile = Join-Path $logDir "SandboxieWrapper_$(Get-Date -Format 'yyyy-MM-dd').log"

if (!(Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# ============================================================================
# LOGGING
# ============================================================================

function Write-WrapperLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $prefix = switch ($Level) {
        "DEBUG"   { "[WRAPPER-DEBUG]" }
        "WARNING" { "[WRAPPER-WARNING]" }
        "ERROR"   { "[WRAPPER-ERROR]" }
        default   { "[WRAPPER-INFO]" }
    }
    Write-Host "$prefix $Message"
    try { "[$timestamp] [$Level] $Message" | Out-File -FilePath $logFile -Append -Encoding UTF8 } catch {}
}

# Cleanup old logs (7 days)
try {
    Get-ChildItem -Path $logDir -Filter "SandboxieWrapper_*.log" |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
} catch {}

# ============================================================================
# LOAD CONFIGURATION FROM ENVIRONMENT VARIABLES
# ============================================================================

Write-WrapperLog "=========================================="
Write-WrapperLog "Sandboxie Wrapper Starting"
Write-WrapperLog "=========================================="

$sandboxName      = $env:SANDBOX_NAME
$sandboxiePath    = $env:SANDBOXIE_PATH
$securityLevel    = $env:SECURITY_LEVEL
$autoDelete       = $env:AUTO_DELETE -eq "true"
$blockNetwork     = $env:BLOCK_NETWORK -eq "true"
$allowedPaths     = $env:ALLOWED_PATHS
$enableProcessLasso = $env:ENABLE_PROCESS_LASSO -eq "True"
$processLassoPath   = $env:PROCESS_LASSO_PATH
$maxCpuPercent      = $env:MAX_CPU_PERCENT
$maxMemoryMB        = $env:MAX_MEMORY_MB
$cpuAffinity        = $env:CPU_AFFINITY
$processPriority    = $env:PROCESS_PRIORITY
$executablePath     = $env:EXECUTABLE_PATH
$commandLineArgs    = $env:COMMAND_LINE_ARGS

Write-WrapperLog "Configuration:"
Write-WrapperLog "  Sandbox Name: $sandboxName"
Write-WrapperLog "  Security Level: $securityLevel"
Write-WrapperLog "  Executable: $executablePath"
Write-WrapperLog "  Process Lasso: $enableProcessLasso"
Write-WrapperLog "  Running as: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-WrapperLog "  Current Dir: $(Get-Location)"

if ([string]::IsNullOrWhiteSpace($sandboxName) -or [string]::IsNullOrWhiteSpace($executablePath)) {
    Write-WrapperLog "ERROR: Required settings not configured (SandboxName or ExecutablePath)" "ERROR"
    exit 1
}

# ============================================================================
# STEP 1: CREATE/VERIFY SANDBOX
# ============================================================================

Write-WrapperLog "=========================================="
Write-WrapperLog "STEP 1: Creating Sandboxie Sandbox"
Write-WrapperLog "=========================================="

$createSandboxScript = Join-Path $PSScriptRoot "CreateSandboxie.ps1"

if (!(Test-Path $createSandboxScript)) {
    Write-WrapperLog "ERROR: CreateSandboxie.ps1 not found at: $createSandboxScript" "ERROR"
    exit 1
}

try {
    $sandboxArgs = @{
        SandboxName   = $sandboxName
        SandboxiePath = $sandboxiePath
        SecurityLevel = $securityLevel
        AutoDelete    = $autoDelete
        BlockNetwork  = $blockNetwork
    }
    if ($allowedPaths) { $sandboxArgs["AllowedPaths"] = $allowedPaths }

    & $createSandboxScript @sandboxArgs

    if ($LASTEXITCODE -ne 0) {
        Write-WrapperLog "ERROR: Sandbox creation failed (exit code $LASTEXITCODE)" "ERROR"
        exit 1
    }
    Write-WrapperLog "Sandbox ready"
} catch {
    Write-WrapperLog "ERROR: Sandbox creation exception: $_" "ERROR"
    exit 1
}

# ============================================================================
# STEP 2: CONFIGURE PROCESS LASSO (OPTIONAL)
# ============================================================================

if ($enableProcessLasso) {
    Write-WrapperLog "Configuring Process Lasso..."
    $plScript = Join-Path $PSScriptRoot "ConfigureProcessLasso.ps1"
    if (Test-Path $plScript) {
        try {
            $lassoArgs = @{
                Enabled          = $true
                ProcessLassoPath = $processLassoPath
                ProcessName      = $executablePath
                MaxCpuPercent    = $maxCpuPercent
                MaxMemoryMB      = $maxMemoryMB
                ProcessPriority  = $processPriority
            }
            if ($cpuAffinity) { $lassoArgs["CpuAffinity"] = $cpuAffinity }
            & $plScript @lassoArgs
            Write-WrapperLog "Process Lasso configured"
        } catch {
            Write-WrapperLog "WARNING: Process Lasso failed: $_" "WARNING"
        }
    }
} else {
    Write-WrapperLog "Process Lasso disabled"
}

# ============================================================================
# STEP 3: RESOLVE EXECUTABLE PATH
# ============================================================================

Write-WrapperLog "=========================================="
Write-WrapperLog "STEP 3: Resolving Executable"
Write-WrapperLog "=========================================="

$sbieIniExe = Join-Path $sandboxiePath "SbieIni.exe"

if (!(Test-Path $sbieIniExe)) {
    Write-WrapperLog "ERROR: SbieIni.exe not found at: $sbieIniExe" "ERROR"
    exit 1
}

# Resolve relative paths to absolute
if ($executablePath -match '^\./|^\.\\|^[^/\\:]+') {
    $resolvedExe = $executablePath -replace '^\.\/', '' -replace '^\.\\', ''
    $resolvedExe = Join-Path (Get-Location).Path $resolvedExe
    $resolvedExe = [System.IO.Path]::GetFullPath($resolvedExe)
} else {
    $resolvedExe = $executablePath
}

if (!(Test-Path $resolvedExe)) {
    Write-WrapperLog "ERROR: Executable not found: $resolvedExe" "ERROR"
    exit 1
}

$exeName = [System.IO.Path]::GetFileName($resolvedExe)
$exeDir  = [System.IO.Path]::GetDirectoryName($resolvedExe)

Write-WrapperLog "Resolved: $resolvedExe" "DEBUG"
Write-WrapperLog "Exe Name: $exeName" "DEBUG"
Write-WrapperLog "Exe Dir:  $exeDir" "DEBUG"

# ============================================================================
# STEP 4: CONFIGURE ForceProcess & LAUNCH DIRECTLY
# ============================================================================
# Instead of using Start.exe (which fails from NETWORK SERVICE),
# we configure Sandboxie's ForceProcess rule so the kernel driver
# automatically intercepts and sandboxes the process when it launches.
# ============================================================================

Write-WrapperLog "=========================================="
Write-WrapperLog "STEP 4: Starting Application (ForceProcess)"
Write-WrapperLog "=========================================="
Write-WrapperLog "State: STARTING - Configuring ForceProcess rule..."

# Add ForceProcess rule for this executable
Write-WrapperLog "Setting ForceProcess=$exeName on sandbox '$sandboxName'" "DEBUG"
$fpResult = & $sbieIniExe append $sandboxName "ForceProcess" $exeName 2>&1
Write-WrapperLog "ForceProcess result: $fpResult" "DEBUG"

# Also add ForceFolder for the exe directory to catch any child processes
Write-WrapperLog "Setting ForceFolder=$exeDir on sandbox '$sandboxName'" "DEBUG"
$ffResult = & $sbieIniExe append $sandboxName "ForceFolder" $exeDir 2>&1
Write-WrapperLog "ForceFolder result: $ffResult" "DEBUG"

# Reload Sandboxie config so the driver picks up the new rules
$startExe = Join-Path $sandboxiePath "Start.exe"
Write-WrapperLog "Reloading Sandboxie configuration..." "DEBUG"
$reloadResult = & $startExe /reload 2>&1
$reloadExit = $LASTEXITCODE
Write-WrapperLog "Reload result: $reloadResult (exit: $reloadExit)" "DEBUG"
if ($reloadExit -ne 0) {
    # Fallback: try SbieIni.exe reload (SbieSvc reads config directly)
    Write-WrapperLog "Start.exe /reload failed, trying SbieIni.exe reload..." "WARNING"
    $reloadResult2 = & $sbieIniExe reload 2>&1
    Write-WrapperLog "SbieIni reload result: $reloadResult2 (exit: $LASTEXITCODE)" "DEBUG"
}

# Small delay for driver to pick up config
Start-Sleep -Milliseconds 500

# Launch the exe directly - Sandboxie driver will auto-sandbox it
# Redirect stdout/stderr so we can pipe exe output to AMP console
Write-WrapperLog "Launching: $resolvedExe" "DEBUG"
Write-WrapperLog "State: STARTING - Launching application in sandbox..."

$process = $null

function Cleanup-ForceRules {
    try {
        & $sbieIniExe delete $sandboxName "ForceProcess" $exeName 2>&1 | Out-Null
        & $sbieIniExe delete $sandboxName "ForceFolder" $exeDir 2>&1 | Out-Null
        & $startExe /reload 2>&1 | Out-Null
    } catch {}
}

try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $resolvedExe
    if ($commandLineArgs) { $psi.Arguments = $commandLineArgs }
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $exeDir
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::Start($psi)

    if (!$process) {
        Write-WrapperLog "ERROR: Failed to start application" "ERROR"
        Cleanup-ForceRules
        exit 1
    }

    Write-WrapperLog "Application PID: $($process.Id)" "DEBUG"

    # Launch watchdog IMMEDIATELY after getting PID (before any sleep)
    # This ensures watchdog is running even if AMP aborts during Starting phase
    $watchdogScript = Join-Path $PSScriptRoot "SandboxieWatchdog.ps1"
    $wrapperPid = $PID

    if (Test-Path $watchdogScript) {
        try {
            $wdArgs = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$watchdogScript`" " +
                      "-WrapperPID $wrapperPid " +
                      "-ExePID $($process.Id) " +
                      "-ExeName `"$exeName`" " +
                      "-ExeDir `"$exeDir`" " +
                      "-SandboxName `"$sandboxName`" " +
                      "-SandboxiePath `"$sandboxiePath`""

            $wdPsi = New-Object System.Diagnostics.ProcessStartInfo
            $wdPsi.FileName = "C:\Program Files\PowerShell\7\pwsh.exe"
            $wdPsi.Arguments = $wdArgs
            $wdPsi.UseShellExecute = $false
            $wdPsi.CreateNoWindow = $true

            $wdProcess = [System.Diagnostics.Process]::Start($wdPsi)
            Write-WrapperLog "Watchdog started (PID: $($wdProcess.Id))" "DEBUG"
        } catch {
            Write-WrapperLog "WARNING: Failed to start watchdog: $_" "WARNING"
        }
    } else {
        Write-WrapperLog "WARNING: Watchdog not found: $watchdogScript" "WARNING"
    }

    # Give exe a moment to start
    Start-Sleep -Seconds 2

    if ($process.HasExited) {
        # Drain any output before reporting error
        $remainOut = $process.StandardOutput.ReadToEnd()
        $remainErr = $process.StandardError.ReadToEnd()
        if ($remainOut) { Write-Host $remainOut }
        if ($remainErr) { Write-Host $remainErr }
        $ec = $process.ExitCode
        Write-WrapperLog "ERROR: Application exited immediately (Exit Code: $ec)" "ERROR"
        Cleanup-ForceRules
        exit 1
    }

    Write-WrapperLog "Application running (PID: $($process.Id))" "DEBUG"
} catch {
    Write-WrapperLog "ERROR: Exception launching application: $_" "ERROR"
    Cleanup-ForceRules
    exit 1
}

# ============================================================================
# STEP 5: SIGNAL READY TO AMP
# ============================================================================

Write-WrapperLog "=========================================="
Write-WrapperLog "Application Started Successfully"
Write-WrapperLog "=========================================="

# THIS LINE TRIGGERS AMP's Console.AppReadyRegex
Write-WrapperLog "State: RUNNING - Monitoring process..."

# ============================================================================
# STEP 6: MONITOR PROCESS & PIPE OUTPUT
# ============================================================================

# Async output reading using events
$stdoutEvent = Register-ObjectEvent -InputObject $process -EventName OutputDataReceived -Action {
    if ($EventArgs.Data) { Write-Host $EventArgs.Data }
}
$stderrEvent = Register-ObjectEvent -InputObject $process -EventName ErrorDataReceived -Action {
    if ($EventArgs.Data) { Write-Host $EventArgs.Data }
}
$process.BeginOutputReadLine()
$process.BeginErrorReadLine()

# Save exe PID for cleanup — when AMP kills wrapper, we need to kill exe too
$exePid = $process.Id

# Write PID file so external cleanup can find the exe if wrapper dies
$pidFile = Join-Path $PSScriptRoot "sandboxie_exe.pid"
try { $exePid | Out-File -FilePath $pidFile -Encoding ASCII -Force } catch {}

$lastHeartbeat = Get-Date
$wrapperExitCode = 0

try {
    while (!$process.HasExited) {
        Start-Sleep -Milliseconds 500

        $now = Get-Date
        if (($now - $lastHeartbeat).TotalSeconds -ge 30) {
            $lastHeartbeat = $now
            Write-WrapperLog "Heartbeat: PID $exePid alive" "DEBUG"
        }
    }
    $wrapperExitCode = $process.ExitCode
} finally {
    # This runs when wrapper is killed by AMP (taskkill) OR when exe exits naturally
    Write-WrapperLog "Wrapper finalizing - ensuring exe cleanup..." "DEBUG"

    # Kill the exe if it's still running
    try {
        if (!$process.HasExited) {
            Write-WrapperLog "Killing application PID $exePid..." "DEBUG"
            Stop-Process -Id $exePid -Force -ErrorAction SilentlyContinue
            # Wait briefly for it to die
            $process.WaitForExit(5000) | Out-Null
            Write-WrapperLog "Application killed" "DEBUG"
        }
    } catch {}

    # Also kill by name as safety net (in case PID was reused or Sandboxie spawned under different PID)
    try {
        Get-Process -Name ($exeName -replace '\.exe$','') -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -eq $resolvedExe } |
            Stop-Process -Force -ErrorAction SilentlyContinue
    } catch {}

    # Cleanup events
    try {
        Unregister-Event -SourceIdentifier $stdoutEvent.Name -ErrorAction SilentlyContinue
        Unregister-Event -SourceIdentifier $stderrEvent.Name -ErrorAction SilentlyContinue
    } catch {}

    # Remove ForceProcess/ForceFolder rules
    Write-WrapperLog "Cleaning up ForceProcess rules..." "DEBUG"
    Cleanup-ForceRules

    # Remove PID file
    try { Remove-Item -Path $pidFile -Force -ErrorAction SilentlyContinue } catch {}

    Write-WrapperLog "State: STOPPED - Wrapper exiting" 
}

exit $wrapperExitCode
