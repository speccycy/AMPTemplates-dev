#!/bin/bash
#
# SCUM Server Watchdog - External Process Monitor (Linux/Proton)
#
# SYNOPSIS:
#     External watchdog that monitors wrapper and server processes
#
# DESCRIPTION:
#     This watchdog runs as a separate process to monitor the wrapper and server.
#     When the wrapper dies (killed by AMP during Abort), the watchdog immediately
#     kills the SCUMServer.exe process to prevent orphans.
#     
#     This solves the fundamental problem: When AMP kills the wrapper,
#     the wrapper dies before it can clean up. The watchdog survives and does the cleanup.
#
# VERSION: 1.0 (Linux/Proton Port)
# AUTHOR: CubeCoders AMP Template
#
# USAGE:
#     bash SCUMWatchdog.sh <WrapperPID> <ServerPID> <PIDFile> <SCUMLogPath>
#

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

readonly CHECK_INTERVAL_MS=200
readonly GRACE_PERIOD_MS=500
readonly GRACEFUL_SHUTDOWN_TIMEOUT=30

# ============================================================================
# PARAMETERS
# ============================================================================

if [[ $# -ne 4 ]]; then
    echo "ERROR: Invalid arguments"
    echo "Usage: $0 <WrapperPID> <ServerPID> <PIDFile> <SCUMLogPath>"
    exit 1
fi

WRAPPER_PID="$1"
SERVER_PID="$2"
PID_FILE="$3"
SCUM_LOG_PATH="$4"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/Logs"
LOG_FILE="${LOG_DIR}/SCUMWatchdog_$(date +%Y-%m-%d).log"

# ============================================================================
# LOGGING
# ============================================================================

mkdir -p "${LOG_DIR}"

log_watchdog() {
    local level="${1:-INFO}"
    local message="${2}"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')
    
    local log_entry="[${timestamp}] [WATCHDOG-${level}] ${message}"
    echo "${log_entry}"
    echo "${log_entry}" >> "${LOG_FILE}" 2>/dev/null || true
}

# ============================================================================
# MAIN WATCHDOG LOGIC
# ============================================================================

log_watchdog "INFO" "=================================================="
log_watchdog "INFO" "SCUM Server Watchdog Started (Linux)"
log_watchdog "INFO" "=================================================="
log_watchdog "INFO" "Watchdog PID: $$"
log_watchdog "INFO" "Parent Wrapper PID: ${WRAPPER_PID}"
log_watchdog "INFO" "Target Server PID: ${SERVER_PID}"
log_watchdog "INFO" "PID File Path: ${PID_FILE}"
log_watchdog "INFO" "SCUM Log Path: ${SCUM_LOG_PATH}"
log_watchdog "INFO" "Check Interval: ${CHECK_INTERVAL_MS}ms"
log_watchdog "INFO" "Grace Period: ${GRACE_PERIOD_MS}ms"
log_watchdog "INFO" "=================================================="

# Verify wrapper exists at startup
log_watchdog "DEBUG" "Step 1: Verifying wrapper process exists..."
if kill -0 "${WRAPPER_PID}" 2>/dev/null; then
    WRAPPER_CMD=$(ps -p "${WRAPPER_PID}" -o comm= 2>/dev/null || echo "unknown")
    log_watchdog "DEBUG" "✓ Wrapper process found: ${WRAPPER_CMD} (PID: ${WRAPPER_PID})"
else
    log_watchdog "ERROR" "✗ ERROR: Wrapper PID ${WRAPPER_PID} not found at startup!"
    log_watchdog "ERROR" "  Watchdog cannot function without wrapper - exiting"
    exit 1
fi

# Verify server exists at startup
log_watchdog "DEBUG" "Step 2: Verifying server process exists..."
if kill -0 "${SERVER_PID}" 2>/dev/null; then
    SERVER_CMD=$(ps -p "${SERVER_PID}" -o comm= 2>/dev/null || echo "unknown")
    log_watchdog "DEBUG" "✓ Server process found: ${SERVER_CMD} (PID: ${SERVER_PID})"
else
    log_watchdog "ERROR" "✗ ERROR: Server PID ${SERVER_PID} not found at startup!"
    log_watchdog "ERROR" "  Watchdog cannot function without server - exiting"
    exit 1
fi

log_watchdog "INFO" "=================================================="
log_watchdog "INFO" "Step 3: Starting monitoring loop..."
log_watchdog "INFO" "  Watchdog will check every ${CHECK_INTERVAL_MS}ms if wrapper is alive"
log_watchdog "INFO" "  If wrapper dies, watchdog will handle server cleanup"
log_watchdog "INFO" "=================================================="

# ============================================================================
# MONITORING LOOP
# ============================================================================

LOOP_COUNT=0
LAST_HEARTBEAT=$(date +%s)
LAST_DETAILED_CHECK=$(date +%s)

while true; do
    sleep "0.${CHECK_INTERVAL_MS}"
    LOOP_COUNT=$((LOOP_COUNT + 1))
    
    CURRENT_TIME=$(date +%s)
    
    # Heartbeat every 5 seconds
    if [[ $((CURRENT_TIME - LAST_HEARTBEAT)) -ge 5 ]]; then
        LAST_HEARTBEAT=${CURRENT_TIME}
        log_watchdog "DEBUG" "Heartbeat: Monitoring active (checks: ${LOOP_COUNT})"
    fi
    
    # Detailed check every 30 seconds
    if [[ $((CURRENT_TIME - LAST_DETAILED_CHECK)) -ge 30 ]]; then
        LAST_DETAILED_CHECK=${CURRENT_TIME}
        log_watchdog "DEBUG" "Detailed Status Check:"
        log_watchdog "DEBUG" "  - Wrapper: Alive (PID: ${WRAPPER_PID})"
        log_watchdog "DEBUG" "  - Server: Alive (PID: ${SERVER_PID})"
    fi
    
    # Check if wrapper is still alive
    if ! kill -0 "${WRAPPER_PID}" 2>/dev/null; then
        log_watchdog "WARNING" "=================================================="
        log_watchdog "WARNING" "WRAPPER DIED! (PID: ${WRAPPER_PID})"
        log_watchdog "WARNING" "=================================================="
        log_watchdog "WARNING" "Detection Details:"
        log_watchdog "WARNING" "  - Detection time: $(date '+%Y-%m-%d %H:%M:%S.%3N')"
        log_watchdog "WARNING" "  - Total monitoring checks performed: ${LOOP_COUNT}"
        log_watchdog "WARNING" "  - Likely cause: AMP killed wrapper (Abort/Stop button)"
        log_watchdog "WARNING" "=================================================="
        break
    fi
    
    # Check if server is still alive
    if ! kill -0 "${SERVER_PID}" 2>/dev/null; then
        log_watchdog "DEBUG" "=================================================="
        log_watchdog "DEBUG" "Server process exited normally (PID: ${SERVER_PID})"
        log_watchdog "DEBUG" "  - Watchdog no longer needed - exiting"
        log_watchdog "DEBUG" "=================================================="
        exit 0
    fi
done

# ============================================================================
# CLEANUP: Wrapper died, server still running
# ============================================================================

log_watchdog "INFO" "=================================================="
log_watchdog "INFO" "CLEANUP PHASE: Checking server status..."
log_watchdog "INFO" "=================================================="

# Brief grace period
log_watchdog "DEBUG" "Step 1: Grace period - waiting ${GRACE_PERIOD_MS}ms..."
sleep "0.${GRACE_PERIOD_MS}"

# Check if server is still alive
log_watchdog "DEBUG" "Step 2: Checking if server is still alive..."
if ! kill -0 "${SERVER_PID}" 2>/dev/null; then
    log_watchdog "DEBUG" "  - Server already terminated"
    log_watchdog "DEBUG" "  - No cleanup needed"
    exit 0
fi

log_watchdog "WARNING" "=================================================="
log_watchdog "WARNING" "ORPHAN DETECTED!"
log_watchdog "WARNING" "=================================================="
log_watchdog "WARNING" "Server PID ${SERVER_PID} is orphaned (wrapper died but server still running)"

# ============================================================================
# CHECK SERVER READY STATE
# ============================================================================

log_watchdog "DEBUG" "Step 3: Checking server ready state..."

SERVER_READY_FLAG="${SCRIPT_DIR}/server_ready.flag"
log_watchdog "DEBUG" "  - Flag file path: ${SERVER_READY_FLAG}"

SERVER_WAS_READY=false
if [[ -f "${SERVER_READY_FLAG}" ]]; then
    SERVER_WAS_READY=true
    log_watchdog "DEBUG" "  ✓ Server was READY (flag file exists)"
    log_watchdog "DEBUG" "  This means server was in 'Started' state"
else
    log_watchdog "DEBUG" "  ✗ Server was NOT READY (no flag file)"
    log_watchdog "DEBUG" "  This means server was still in 'Starting' state"
fi

# ============================================================================
# DECISION: Graceful shutdown or force kill
# ============================================================================

if [[ "${SERVER_WAS_READY}" == "true" ]]; then
    # Server was ready - attempt graceful shutdown
    log_watchdog "WARNING" "=================================================="
    log_watchdog "WARNING" "DECISION: Server was READY (Started state)"
    log_watchdog "WARNING" "  Attempting GRACEFUL SHUTDOWN..."
    log_watchdog "WARNING" "  Will send SIGTERM and wait for LogExit"
    log_watchdog "WARNING" "=================================================="
    
    log_watchdog "DEBUG" "Step 4: Sending SIGTERM signal to server..."
    
    # Send SIGTERM to server process
    if kill -TERM "${SERVER_PID}" 2>/dev/null; then
        log_watchdog "DEBUG" "  ✓ SIGTERM sent successfully"
        
        # Wait for LogExit pattern
        log_watchdog "DEBUG" "Step 5: Waiting for LogExit pattern (max ${GRACEFUL_SHUTDOWN_TIMEOUT}s)..."
        
        LOGEXIT_FOUND=false
        WAITED=0
        
        while [[ ${WAITED} -lt ${GRACEFUL_SHUTDOWN_TIMEOUT} ]]; do
            sleep 2
            WAITED=$((WAITED + 2))
            
            # Check if server exited
            if ! kill -0 "${SERVER_PID}" 2>/dev/null; then
                log_watchdog "DEBUG" "  ✓ Server exited after ${WAITED}s"
                break
            fi
            
            # Check for LogExit pattern
            if [[ -f "${SCUM_LOG_PATH}" ]]; then
                if tail -n 50 "${SCUM_LOG_PATH}" 2>/dev/null | grep -q "LogExit: Exiting"; then
                    LOGEXIT_FOUND=true
                    log_watchdog "DEBUG" "  ✓ LogExit pattern detected after ${WAITED}s!"
                    break
                fi
            fi
            
            # Log progress every 10 seconds
            if [[ $((WAITED % 10)) -eq 0 ]]; then
                log_watchdog "DEBUG" "  Still waiting for LogExit... (${WAITED}/${GRACEFUL_SHUTDOWN_TIMEOUT}s)"
            fi
        done
        
        # Check final result
        if kill -0 "${SERVER_PID}" 2>/dev/null; then
            # Server still running - force kill
            log_watchdog "ERROR" "  ✗ Server did not exit after ${GRACEFUL_SHUTDOWN_TIMEOUT}s"
            log_watchdog "ERROR" "  Force killing server..."
            kill -9 "${SERVER_PID}" 2>/dev/null || true
            log_watchdog "WARNING" "  ✓ Server force killed (timeout)"
        else
            # Server exited
            if [[ "${LOGEXIT_FOUND}" == "true" ]]; then
                log_watchdog "DEBUG" "  ✓ GRACEFUL SHUTDOWN SUCCESS (LogExit detected)"
            else
                log_watchdog "WARNING" "  ⚠ Server exited without LogExit"
            fi
        fi
    else
        log_watchdog "ERROR" "  ✗ SIGTERM failed - force killing..."
        kill -9 "${SERVER_PID}" 2>/dev/null || true
        log_watchdog "WARNING" "  ✓ Server force killed (SIGTERM failed)"
    fi
else
    # Server was NOT ready - force kill immediately
    log_watchdog "DEBUG" "=================================================="
    log_watchdog "DEBUG" "DECISION: Server was STARTING (not ready yet)"
    log_watchdog "DEBUG" "  Force kill is appropriate for startup phase"
    log_watchdog "DEBUG" "  No data corruption risk"
    log_watchdog "DEBUG" "=================================================="
    
    log_watchdog "DEBUG" "Step 4: Killing server (startup phase)..."
    
    if kill -9 "${SERVER_PID}" 2>/dev/null; then
        log_watchdog "DEBUG" "  ✓ Server killed successfully"
        
        sleep 2
        
        if kill -0 "${SERVER_PID}" 2>/dev/null; then
            log_watchdog "ERROR" "  ✗ WARNING: Server still alive after kill!"
        else
            log_watchdog "DEBUG" "  ✓ Server terminated successfully"
        fi
    else
        log_watchdog "ERROR" "  ✗ Failed to kill server"
    fi
fi

# ============================================================================
# FINAL CLEANUP
# ============================================================================

log_watchdog "INFO" "=================================================="
log_watchdog "INFO" "FINAL CLEANUP PHASE"
log_watchdog "INFO" "=================================================="

log_watchdog "DEBUG" "Step 6: Cleaning up files..."

# Remove PID file
if [[ -f "${PID_FILE}" ]]; then
    rm -f "${PID_FILE}" 2>/dev/null || true
    log_watchdog "DEBUG" "  ✓ PID file removed successfully"
else
    log_watchdog "DEBUG" "  - PID file not found (already cleaned up by wrapper)"
fi

# Remove server ready flag file
if [[ -f "${SERVER_READY_FLAG}" ]]; then
    rm -f "${SERVER_READY_FLAG}" 2>/dev/null || true
    log_watchdog "DEBUG" "  ✓ Server ready flag file removed"
fi

log_watchdog "INFO" "=================================================="
log_watchdog "INFO" "WATCHDOG SHUTDOWN SUMMARY"
log_watchdog "INFO" "=================================================="
log_watchdog "INFO" "Total monitoring checks performed: ${LOOP_COUNT}"
log_watchdog "INFO" "Watchdog completed successfully"
log_watchdog "INFO" "=================================================="

exit 0
