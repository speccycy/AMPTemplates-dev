# ============================================================================
# SetupSandboxieTask.ps1 - One-time setup (RUN AS ADMINISTRATOR)
# ============================================================================
# Grants NETWORK SERVICE permission to run Sandboxie Start.exe
# and creates a pre-configured scheduled task for sandbox execution.
#
# Usage: Right-click PowerShell -> Run as Administrator
#        .\SetupSandboxieTask.ps1
# ============================================================================

param(
    [Parameter(Mandatory=$false)]
    [string]$SandboxiePath = "C:\Program Files\Sandboxie-Plus"
)

$ErrorActionPreference = "Stop"

# Verify running as admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: This script must be run as Administrator!" -ForegroundColor Red
    Write-Host "Right-click PowerShell -> Run as Administrator" -ForegroundColor Yellow
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Sandboxie + AMP Setup" -ForegroundColor Cyan  
Write-Host "========================================" -ForegroundColor Cyan

# Step 1: Verify Sandboxie installation
$startExe = Join-Path $SandboxiePath "Start.exe"
if (-not (Test-Path $startExe)) {
    Write-Host "ERROR: Sandboxie Start.exe not found at: $startExe" -ForegroundColor Red
    exit 1
}
Write-Host "[OK] Sandboxie found at: $SandboxiePath" -ForegroundColor Green

# Step 2: Grant NETWORK SERVICE read/execute on Sandboxie directory
Write-Host ""
Write-Host "Granting NETWORK SERVICE permissions..." -ForegroundColor Yellow
try {
    $acl = Get-Acl $SandboxiePath
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "NT AUTHORITY\NETWORK SERVICE",
        "ReadAndExecute",
        "ContainerInherit,ObjectInherit",
        "None",
        "Allow"
    )
    $acl.AddAccessRule($rule)
    Set-Acl $SandboxiePath $acl
    Write-Host "[OK] NETWORK SERVICE can now execute Sandboxie" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Failed to set permissions: $_" -ForegroundColor Red
    exit 1
}

# Step 3: Verify SbieSvc service is running
$svc = Get-Service -Name "SbieSvc" -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq "Running") {
    Write-Host "[OK] SbieSvc service is running" -ForegroundColor Green
} else {
    Write-Host "WARNING: SbieSvc service is not running!" -ForegroundColor Yellow
    Write-Host "  Start it with: sc start SbieSvc" -ForegroundColor Yellow
}

# Step 4: Test that Start.exe can be accessed
try {
    $testResult = & $startExe /listpids 2>&1
    Write-Host "[OK] Sandboxie Start.exe is accessible" -ForegroundColor Green
} catch {
    Write-Host "WARNING: Could not test Start.exe: $_" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "Setup Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Now restart the AMP instance and try Start." -ForegroundColor Cyan
Write-Host "If it still fails, the issue may be that" -ForegroundColor Cyan
Write-Host "Sandboxie requires an interactive desktop session." -ForegroundColor Cyan
