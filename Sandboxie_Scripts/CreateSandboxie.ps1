# ============================================================================
# CreateSandboxie.ps1 - Auto-create Sandboxie-Plus sandbox for AMP instances
# ============================================================================
# This script is called by AMP before starting the application.
# It creates a Sandboxie sandbox if it doesn't exist and configures security.
#
# Usage: powershell -ExecutionPolicy Bypass -File CreateSandboxie.ps1 -SandboxName "AMPBox"
# ============================================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$SandboxName,
    
    [Parameter(Mandatory=$false)]
    [string]$SandboxiePath = "C:\Program Files\Sandboxie-Plus",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("Low", "Medium", "High")]
    [string]$SecurityLevel = "Medium",
    
    [Parameter(Mandatory=$false)]
    [bool]$AutoDelete = $false,
    
    [Parameter(Mandatory=$false)]
    [bool]$BlockNetwork = $false,
    
    [Parameter(Mandatory=$false)]
    [string]$AllowedPaths = ""
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

function Test-SandboxieInstalled {
    $startExe = Join-Path $SandboxiePath "Start.exe"
    $sbieIniExe = Join-Path $SandboxiePath "SbieIni.exe"
    
    if (-not (Test-Path $startExe)) {
        Write-Log "Sandboxie-Plus Start.exe not found at: $startExe" "ERROR"
        return $false
    }
    
    if (-not (Test-Path $sbieIniExe)) {
        Write-Log "Sandboxie-Plus SbieIni.exe not found at: $sbieIniExe" "ERROR"
        return $false
    }
    
    Write-Log "Sandboxie-Plus installation verified" "SUCCESS"
    return $true
}

function Test-SandboxExists {
    param([string]$BoxName)
    
    $sbieIniExe = Join-Path $SandboxiePath "SbieIni.exe"
    
    # Query all sandboxes
    $result = & $sbieIniExe query "*" 2>&1
    
    if ($result -match $BoxName) {
        Write-Log "Sandbox '$BoxName' already exists" "INFO"
        return $true
    }
    
    Write-Log "Sandbox '$BoxName' does not exist" "INFO"
    return $false
}

function New-Sandbox {
    param([string]$BoxName)
    
    $sbieIniExe = Join-Path $SandboxiePath "SbieIni.exe"
    
    Write-Log "Creating sandbox: $BoxName" "INFO"
    
    # Create sandbox by setting Enabled=y
    $result = & $sbieIniExe set $BoxName Enabled y 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Failed to create sandbox: $result" "ERROR"
        return $false
    }
    
    Write-Log "Sandbox '$BoxName' created successfully" "SUCCESS"
    return $true
}

function Set-SandboxSecurity {
    param([string]$BoxName, [string]$Level)
    
    $sbieIniExe = Join-Path $SandboxiePath "SbieIni.exe"
    
    Write-Log "Configuring security level: $Level" "INFO"
    
    switch ($Level) {
        "Low" {
            # Minimal restrictions - for trusted applications
            Write-Log "Applying Low security settings" "INFO"
            
            # Allow most access
            & $sbieIniExe set $BoxName "Template" "OpenFilePath" 2>&1 | Out-Null
            & $sbieIniExe set $BoxName "Template" "OpenKeyPath" 2>&1 | Out-Null
        }
        
        "Medium" {
            # Balanced security - block system writes, allow app access
            Write-Log "Applying Medium security settings" "INFO"
            
            # Block write access to Windows directory
            & $sbieIniExe append $BoxName "ClosedFilePath" "C:\Windows\*" 2>&1 | Out-Null
            
            # Block write access to Program Files
            & $sbieIniExe append $BoxName "ClosedFilePath" "C:\Program Files\*" 2>&1 | Out-Null
            & $sbieIniExe append $BoxName "ClosedFilePath" "C:\Program Files (x86)\*" 2>&1 | Out-Null
            
            # Block write access to system registry
            & $sbieIniExe append $BoxName "ClosedKeyPath" "HKEY_LOCAL_MACHINE\*" 2>&1 | Out-Null
            
            # Allow network access (default)
            Write-Log "Network access: Allowed" "INFO"
        }
        
        "High" {
            # Maximum security - for untrusted applications
            Write-Log "Applying High security settings" "INFO"
            
            # Block write access to Windows directory
            & $sbieIniExe append $BoxName "ClosedFilePath" "C:\Windows\*" 2>&1 | Out-Null
            
            # Block write access to Program Files
            & $sbieIniExe append $BoxName "ClosedFilePath" "C:\Program Files\*" 2>&1 | Out-Null
            & $sbieIniExe append $BoxName "ClosedFilePath" "C:\Program Files (x86)\*" 2>&1 | Out-Null
            
            # Block write access to system registry
            & $sbieIniExe append $BoxName "ClosedKeyPath" "HKEY_LOCAL_MACHINE\*" 2>&1 | Out-Null
            & $sbieIniExe append $BoxName "ClosedKeyPath" "HKEY_CURRENT_USER\Software\Microsoft\Windows\*" 2>&1 | Out-Null
            
            # Block network access if requested
            if ($BlockNetwork) {
                & $sbieIniExe set $BoxName "BlockNetworkFiles" "y" 2>&1 | Out-Null
                Write-Log "Network access: Blocked" "WARNING"
            }
            
            # Enable auto-delete
            if ($AutoDelete) {
                & $sbieIniExe set $BoxName "AutoDelete" "y" 2>&1 | Out-Null
                Write-Log "Auto-delete enabled" "INFO"
            }
        }
    }
    
    Write-Log "Security configuration applied" "SUCCESS"
}

function Set-SandboxDescription {
    param([string]$BoxName)
    
    $sbieIniExe = Join-Path $SandboxiePath "SbieIni.exe"
    
    $description = "AMP-managed sandbox - Created automatically for Windows EXE Runner"
    & $sbieIniExe set $BoxName "Description" $description 2>&1 | Out-Null
    
    Write-Log "Sandbox description set" "INFO"
}

function Reload-SandboxieConfig {
    $startExe = Join-Path $SandboxiePath "Start.exe"
    
    Write-Log "Reloading Sandboxie configuration" "INFO"
    
    $result = & $startExe /reload 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Log "Configuration reloaded successfully" "SUCCESS"
        return $true
    } else {
        Write-Log "Failed to reload configuration: $result" "WARNING"
        return $false
    }
}

function Set-AllowedPaths {
    param([string]$BoxName, [string]$Paths)
    
    if ([string]::IsNullOrWhiteSpace($Paths)) {
        Write-Log "No allowed paths specified - using default restrictions" "INFO"
        return
    }
    
    $sbieIniExe = Join-Path $SandboxiePath "SbieIni.exe"
    
    # Split paths by comma and trim whitespace
    $pathList = $Paths -split ',' | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    
    if ($pathList.Count -eq 0) {
        Write-Log "No valid paths found in whitelist" "WARNING"
        return
    }
    
    Write-Log "========================================" "INFO"
    Write-Log "Configuring Path Whitelist (Access Control)" "INFO"
    Write-Log "========================================" "INFO"
    
    foreach ($path in $pathList) {
        # Validate path format
        if ($path -notmatch '^[A-Za-z]:\\') {
            Write-Log "  ⚠ Skipping invalid path: $path (must be absolute path)" "WARNING"
            continue
        }
        
        # Add OpenFilePath to allow access
        $result = & $sbieIniExe append $BoxName "OpenFilePath" $path 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "  ✓ Whitelisted: $path" "SUCCESS"
        } else {
            Write-Log "  ✗ Failed to whitelist: $path" "ERROR"
            Write-Log "    Error: $result" "ERROR"
        }
    }
    
    Write-Log "========================================" "INFO"
    Write-Log "Path whitelist configuration completed" "SUCCESS"
    Write-Log "Total paths whitelisted: $($pathList.Count)" "INFO"
    Write-Log "========================================" "INFO"
}

# ============================================================================
# Main Script
# ============================================================================

Write-Log "========================================" "INFO"
Write-Log "Sandboxie Auto-Setup Script" "INFO"
Write-Log "========================================" "INFO"
Write-Log "Sandbox Name: $SandboxName" "INFO"
Write-Log "Security Level: $SecurityLevel" "INFO"
Write-Log "Auto-Delete: $AutoDelete" "INFO"
Write-Log "Block Network: $BlockNetwork" "INFO"
if (-not [string]::IsNullOrWhiteSpace($AllowedPaths)) {
    Write-Log "Allowed Paths: $AllowedPaths" "INFO"
} else {
    Write-Log "Allowed Paths: None (default restrictions)" "INFO"
}
Write-Log "========================================" "INFO"

# Step 1: Verify Sandboxie-Plus is installed
if (-not (Test-SandboxieInstalled)) {
    Write-Log "Sandboxie-Plus is not installed or not found at: $SandboxiePath" "ERROR"
    Write-Log "Please install Sandboxie-Plus from: https://sandboxie-plus.com/" "ERROR"
    exit 1
}

# Step 2: Check if sandbox already exists
$sandboxExists = Test-SandboxExists -BoxName $SandboxName

if ($sandboxExists) {
    Write-Log "Sandbox '$SandboxName' already exists - skipping creation" "INFO"
    Write-Log "If you want to reconfigure, delete the sandbox first in Sandboxie-Plus" "INFO"
    exit 0
}

# Step 3: Create the sandbox
if (-not (New-Sandbox -BoxName $SandboxName)) {
    Write-Log "Failed to create sandbox" "ERROR"
    exit 1
}

# Step 4: Set sandbox description
Set-SandboxDescription -BoxName $SandboxName

# Step 5: Configure security settings
Set-SandboxSecurity -BoxName $SandboxName -Level $SecurityLevel

# Step 6: Configure allowed paths (whitelist)
Set-AllowedPaths -BoxName $SandboxName -Paths $AllowedPaths

# Step 7: Reload Sandboxie configuration
Reload-SandboxieConfig | Out-Null

# Step 8: Verify sandbox was created
Start-Sleep -Seconds 1
if (Test-SandboxExists -BoxName $SandboxName) {
    Write-Log "========================================" "SUCCESS"
    Write-Log "Sandbox setup completed successfully!" "SUCCESS"
    Write-Log "Sandbox Name: $SandboxName" "SUCCESS"
    Write-Log "Security Level: $SecurityLevel" "SUCCESS"
    Write-Log "========================================" "SUCCESS"
    exit 0
} else {
    Write-Log "Sandbox creation verification failed" "ERROR"
    exit 1
}
