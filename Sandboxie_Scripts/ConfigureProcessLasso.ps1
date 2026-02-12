# ============================================================================
# ConfigureProcessLasso.ps1 - Configure Process Lasso resource limits
# ============================================================================
# This script is called by AMP before starting the application.
# It configures Process Lasso rules for CPU and memory limits.
#
# Usage: pwsh -ExecutionPolicy Bypass -File ConfigureProcessLasso.ps1 -Enabled $true
# ============================================================================

param(
    [Parameter(Mandatory=$false)]
    [bool]$Enabled = $false,
    
    [Parameter(Mandatory=$false)]
    [string]$ProcessLassoPath = "C:\Program Files\Process Lasso",
    
    [Parameter(Mandatory=$true)]
    [string]$ProcessName = "Application.exe",
    
    [Parameter(Mandatory=$false)]
    [int]$MaxCpuPercent = 0,
    
    [Parameter(Mandatory=$false)]
    [int]$MaxMemoryMB = 0,
    
    [Parameter(Mandatory=$false)]
    [string]$CpuAffinity = "",
    
    [Parameter(Mandatory=$false)]
    [string]$ProcessPriority = "Normal"
)

# ============================================================================
# Functions
# ============================================================================

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "SUCCESS" { "Green" }
        default { "White" }
    }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Test-ProcessLassoInstalled {
    $processLassoExe = Join-Path $ProcessLassoPath "processlasso.exe"
    
    if (-not (Test-Path $processLassoExe)) {
        Write-Log "Process Lasso not found at: $processLassoExe" "ERROR"
        Write-Log "Please install Process Lasso from: https://bitsum.com/" "ERROR"
        return $false
    }
    
    Write-Log "Process Lasso installation verified" "SUCCESS"
    return $true
}

function Get-ProcessNameOnly {
    param([string]$FullPath)
    
    # Extract just the filename from full path
    if ($FullPath -match '[\\/]([^\\/]+)$') {
        return $matches[1]
    }
    
    return $FullPath
}

function Set-ProcessLassoRule {
    param(
        [string]$ProcessName,
        [string]$RuleType,
        [string]$Value
    )
    
    $processLassoExe = Join-Path $ProcessLassoPath "processlasso.exe"
    
    try {
        $result = & $processLassoExe $RuleType $ProcessName $Value 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            return $true
        } else {
            Write-Log "Failed to set $RuleType : $result" "WARNING"
            return $false
        }
    } catch {
        Write-Log "Exception setting $RuleType : $_" "ERROR"
        return $false
    }
}

# ============================================================================
# Main Script
# ============================================================================

Write-Log "========================================" "INFO"
Write-Log "Process Lasso Configuration Script" "INFO"
Write-Log "========================================" "INFO"

# Check if Process Lasso is enabled
if (-not $Enabled) {
    Write-Log "Process Lasso is DISABLED - skipping configuration" "INFO"
    Write-Log "To enable, check 'Enable Process Lasso' in AMP UI" "INFO"
    Write-Log "========================================" "INFO"
    exit 0
}

Write-Log "Process Lasso is ENABLED" "SUCCESS"

# Extract process name from full path
$processNameOnly = Get-ProcessNameOnly -FullPath $ProcessName
Write-Log "Target Process: $processNameOnly" "INFO"

# Display configuration
Write-Log "Configuration:" "INFO"
Write-Log "  Max CPU: $(if ($MaxCpuPercent -gt 0) { "$MaxCpuPercent%" } else { 'Unlimited' })" "INFO"
Write-Log "  Max Memory: $(if ($MaxMemoryMB -gt 0) { "$MaxMemoryMB MB" } else { 'Unlimited' })" "INFO"
Write-Log "  CPU Affinity: $(if ($CpuAffinity) { $CpuAffinity } else { 'All cores' })" "INFO"
Write-Log "  Priority: $ProcessPriority" "INFO"
Write-Log "========================================" "INFO"

# Step 1: Verify Process Lasso is installed
if (-not (Test-ProcessLassoInstalled)) {
    Write-Log "Process Lasso installation check failed" "ERROR"
    Write-Log "Continuing without resource limits..." "WARNING"
    exit 0  # Don't fail the instance start
}

# Step 2: Configure rules
$rulesApplied = 0
$rulesFailed = 0

Write-Log "Applying Process Lasso rules..." "INFO"

# Priority Class
if ($ProcessPriority -ne "Normal") {
    Write-Log "Setting priority class: $ProcessPriority" "INFO"
    if (Set-ProcessLassoRule -ProcessName $processNameOnly -RuleType "/setpriorityclass" -Value $ProcessPriority) {
        Write-Log "  ✓ Priority class set to: $ProcessPriority" "SUCCESS"
        $rulesApplied++
    } else {
        Write-Log "  ✗ Failed to set priority class" "ERROR"
        $rulesFailed++
    }
}

# CPU Limit
if ($MaxCpuPercent -gt 0 -and $MaxCpuPercent -le 100) {
    Write-Log "Setting CPU limit: $MaxCpuPercent%" "INFO"
    if (Set-ProcessLassoRule -ProcessName $processNameOnly -RuleType "/setcpulimit" -Value $MaxCpuPercent) {
        Write-Log "  ✓ CPU limit set to: $MaxCpuPercent%" "SUCCESS"
        $rulesApplied++
    } else {
        Write-Log "  ✗ Failed to set CPU limit" "ERROR"
        $rulesFailed++
    }
} elseif ($MaxCpuPercent -gt 100) {
    Write-Log "  ⚠ Invalid CPU limit: $MaxCpuPercent% (must be 1-100)" "WARNING"
}

# Memory Limit
if ($MaxMemoryMB -gt 0) {
    Write-Log "Setting memory limit: $MaxMemoryMB MB" "INFO"
    if (Set-ProcessLassoRule -ProcessName $processNameOnly -RuleType "/setmemorylimit" -Value $MaxMemoryMB) {
        Write-Log "  ✓ Memory limit set to: $MaxMemoryMB MB" "SUCCESS"
        $rulesApplied++
    } else {
        Write-Log "  ✗ Failed to set memory limit" "ERROR"
        $rulesFailed++
    }
}

# CPU Affinity
if (-not [string]::IsNullOrWhiteSpace($CpuAffinity)) {
    Write-Log "Setting CPU affinity: $CpuAffinity" "INFO"
    if (Set-ProcessLassoRule -ProcessName $processNameOnly -RuleType "/setcpuaffinity" -Value $CpuAffinity) {
        Write-Log "  ✓ CPU affinity set to: $CpuAffinity" "SUCCESS"
        $rulesApplied++
    } else {
        Write-Log "  ✗ Failed to set CPU affinity" "ERROR"
        $rulesFailed++
    }
}

# Step 3: Summary
Write-Log "========================================" "INFO"
if ($rulesApplied -eq 0 -and $rulesFailed -eq 0) {
    Write-Log "No resource limits configured (all set to unlimited)" "INFO"
} else {
    Write-Log "Process Lasso configuration completed!" "SUCCESS"
    Write-Log "Rules applied: $rulesApplied" "SUCCESS"
    if ($rulesFailed -gt 0) {
        Write-Log "Rules failed: $rulesFailed" "WARNING"
    }
}
Write-Log "========================================" "INFO"

# Always exit 0 to not block instance start
exit 0
