# ============================================================================
# SandboxieWrapper.ps1 - Windows EXE Runner with Sandboxie & Process Lasso
# ============================================================================

# Force immediate console output (disable buffering)
$OutputEncoding = [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

param(
    [Parameter(ValueFromRemainingArguments = $true)]
    $ScriptArgs
)

# ============================================================================
# IMMEDIATE OUTPUT TEST - MUST APPEAR FIRST
# ============================================================================
# Force output immediately to console
[Console]::WriteLine("[WRAPPER-INFO] ==========================================")
[Console]::WriteLine("[WRAPPER-INFO] Sandboxie Wrapper Starting")
[Console]::WriteLine("[WRAPPER-INFO] ==========================================")
[Console]::WriteLine("[WRAPPER-INFO] PowerShell Version: $($PSVersionTable.PSVersion)")
[Console]::WriteLine("[WRAPPER-INFO] Script Path: $PSCommandPath")
[Console]::WriteLine("[WRAPPER-INFO] Working Directory: $PWD")
[Console]::WriteLine("[WRAPPER-INFO] Script Exists: $(Test-Path $PSCommandPath)")
[Console]::WriteLine("[WRAPPER-INFO] ==========================================")

# ============================================================================
# CONFIGURATION
# ============================================================================

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

# Paths
$logDir = Join-Path $PSScriptRoot "Logs"
$logFile = Join-Path $logDir "SandboxieWrapper_$(Get-Date -Format 'yyyy-MM-dd').log"

# ============================================================================
# LOGGING
# ============================================================================

if (!(Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Write-WrapperLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $consolePrefix = switch ($Level) {
        "DEBUG" { "[WRAPPER-DEBUG]" }
        "WARNING" { "[WRAPPER-WARNING]" }
        "ERROR" { "[WRAPPER-ERROR]" }
        default { "[WRAPPER-INFO]" }
    }
    
    # Console output (AMP reads this)
    Write-Host "$consolePrefix $Message"
    
    # File output
    try {
        "[$timestamp] [$Level] $Message" | Out-File -FilePath $logFile -Append -Encoding UTF8
    }
    catch {
        # Silently fail if log file is locked
    }
}

# ============================================================================
# CLEANUP OLD LOGS
# ============================================================================

try {
    $cutoffDate = (Get-Date).AddDays(-7)
    Get-ChildItem -Path $logDir -Filter "SandboxieWrapper_*.log" | 
        Where-Object { $_.LastWriteTime -lt $cutoffDate } | 
        Remove-Item -Force -ErrorAction SilentlyContinue
}
catch {
    # Ignore cleanup errors
}

# ============================================================================
# LOAD CONFIGURATION FROM AMP
# ============================================================================

Write-WrapperLog "=========================================="
Write-WrapperLog "Sandboxie Wrapper Starting"
Write-WrapperLog "=========================================="

# Read configuration from environment variables (set by AMP)
$sandboxName = $env:SANDBOX_NAME
$sandboxiePath = $env:SANDBOXIE_PATH
$securityLevel = $env:SECURITY_LEVEL
$autoDelete = $env:AUTO_DELETE -eq "true"
$blockNetwork = $env:BLOCK_NETWORK -eq "true"
$allowedPaths = $env:ALLOWED_PATHS
$enableProcessLasso = $env:ENABLE_PROCESS_LASSO -eq "true"
$processLassoPath = $env:PROCESS_LASSO_PATH
$maxCpuPercent = $env:MAX_CPU_PERCENT
$maxMemoryMB = $env:MAX_MEMORY_MB
$cpuAffinity = $env:CPU_AFFINITY
$processPriority = $env:PROCESS_PRIORITY
$executablePath = $env:EXECUTABLE_PATH
$commandLineArgs = $env:COMMAND_LINE_ARGS

Write-WrapperLog "Configuration:"
Write-WrapperLog "  Sandbox Name: $sandboxName"
Write-WrapperLog "  Security Level: $securityLevel"
Write-WrapperLog "  Executable: $executablePath"
Write-WrapperLog "  Process Lasso: $enableProcessLasso"

# ============================================================================
# STEP 1: CREATE SANDBOXIE SANDBOX
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
    $sandboxArgs = @(
        "-SandboxName", $sandboxName,
        "-SandboxiePath", $sandboxiePath,
        "-SecurityLevel", $securityLevel,
        "-AutoDelete", $autoDelete,
        "-BlockNetwork", $blockNetwork
    )
    
    if ($allowedPaths) {
        $sandboxArgs += "-AllowedPaths", $allowedPaths
    }
    
    Write-WrapperLog "Executing: CreateSandboxie.ps1"
    & $createSandboxScript @sandboxArgs
    
    if ($LASTEXITCODE -ne 0) {
        Write-WrapperLog "ERROR: Sandbox creation failed with exit code $LASTEXITCODE" "ERROR"
        exit 1
    }
    
    Write-WrapperLog "✓ Sandbox created/verified successfully"
}
catch {
    Write-WrapperLog "ERROR: Exception during sandbox creation: $_" "ERROR"
    exit 1
}

# ============================================================================
# STEP 2: CONFIGURE PROCESS LASSO (OPTIONAL)
# ============================================================================

if ($enableProcessLasso) {
    Write-WrapperLog "=========================================="
    Write-WrapperLog "STEP 2: Configuring Process Lasso"
    Write-WrapperLog "=========================================="
    
    $processLassoScript = Join-Path $PSScriptRoot "ConfigureProcessLasso.ps1"
    
    if (!(Test-Path $processLassoScript)) {
        Write-WrapperLog "WARNING: ConfigureProcessLasso.ps1 not found - skipping" "WARNING"
    }
    else {
        try {
            $lassoArgs = @(
                "-Enabled", $true,
                "-ProcessLassoPath", $processLassoPath,
                "-ProcessName", $executablePath,
                "-MaxCpuPercent", $maxCpuPercent,
                "-MaxMemoryMB", $maxMemoryMB,
                "-ProcessPriority", $processPriority
            )
            
            if ($cpuAffinity) {
                $lassoArgs += "-CpuAffinity", $cpuAffinity
            }
            
            Write-WrapperLog "Executing: ConfigureProcessLasso.ps1"
            & $processLassoScript @lassoArgs
            
            Write-WrapperLog "✓ Process Lasso configured"
        }
        catch {
            Write-WrapperLog "WARNING: Process Lasso configuration failed: $_" "WARNING"
            Write-WrapperLog "Continuing without resource limits..." "WARNING"
        }
    }
}
else {
    Write-WrapperLog "Process Lasso disabled - skipping resource limits"
}

# ============================================================================
# STEP 3: START APPLICATION IN SANDBOX
# ============================================================================

Write-WrapperLog "=========================================="
Write-WrapperLog "STEP 3: Starting Application"
Write-WrapperLog "=========================================="

Write-WrapperLog "State: STARTING - Launching application in sandbox..."

$sandboxieExe = Join-Path $sandboxiePath "Start.exe"

if (!(Test-Path $sandboxieExe)) {
    Write-WrapperLog "ERROR: Sandboxie Start.exe not found at: $sandboxieExe" "ERROR"
    exit 1
}

# Build command line
$sandboxieArgs = @(
    "/box:$sandboxName",
    "/silent",
    "/wait",
    $executablePath
)

if ($commandLineArgs) {
    $sandboxieArgs += $commandLineArgs -split ' '
}

Write-WrapperLog "Command: $sandboxieExe $($sandboxieArgs -join ' ')"

try {
    $process = Start-Process -FilePath $sandboxieExe `
                             -ArgumentList $sandboxieArgs `
                             -PassThru `
                             -NoNewWindow
    
    if (!$process) {
        Write-WrapperLog "ERROR: Failed to start process" "ERROR"
        exit 1
    }
    
    Write-WrapperLog "✓ Process started (PID: $($process.Id))"
    
    # Wait a moment to ensure process didn't immediately crash
    Start-Sleep -Seconds 2
    
    if ($process.HasExited) {
        Write-WrapperLog "ERROR: Process exited immediately (Exit Code: $($process.ExitCode))" "ERROR"
        exit 1
    }
}
catch {
    Write-WrapperLog "ERROR: Exception starting process: $_" "ERROR"
    exit 1
}

# ============================================================================
# STEP 4: SIGNAL READY TO AMP
# ============================================================================

Write-WrapperLog "=========================================="
Write-WrapperLog "Application Started Successfully"
Write-WrapperLog "=========================================="

# THIS LINE TRIGGERS AMP's Console.AppReadyRegex
# AMP will change status from "Starting" to "Started"
Write-WrapperLog "State: RUNNING - Monitoring process..."

# ============================================================================
# STEP 5: MONITOR PROCESS
# ============================================================================

$lastHeartbeat = Get-Date

while (!$process.HasExited) {
    Start-Sleep -Milliseconds 500
    
    # Heartbeat every 5 seconds
    $now = Get-Date
    if (($now - $lastHeartbeat).TotalSeconds -ge 5) {
        $lastHeartbeat = $now
        Write-WrapperLog "Heartbeat: Monitoring PID $($process.Id)" "DEBUG"
    }
}

# ============================================================================
# STEP 6: PROCESS EXITED
# ============================================================================

$exitCode = $process.ExitCode

Write-WrapperLog "=========================================="
Write-WrapperLog "Application Exited"
Write-WrapperLog "=========================================="
Write-WrapperLog "Exit Code: $exitCode"
Write-WrapperLog "State: STOPPED - Wrapper exiting"

exit $exitCode
