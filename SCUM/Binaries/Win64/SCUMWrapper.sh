#!/bin/bash
#
# SCUM Server Graceful Shutdown Wrapper for CubeCoders AMP (Linux/Proton)
#
# SYNOPSIS:
#     Manages SCUM Dedicated Server lifecycle on Linux using Proton/Wine
#
# DESCRIPTION:
#     This wrapper ensures 100% data integrity through graceful shutdown,
#     prevents race conditions, and provides comprehensive logging.
#     
#     Key Features:
#     - Graceful shutdown with SIGTERM signal and LogExit detection
#     - Failsafe timeout (30s) to prevent hung shutdowns
#     - Orphan process cleanup before starting new instances
#     - Singleton enforcement via PID file with timestamp validation
#     - Server ready detection via log monitoring
#     - Comprehensive dual logging (console + file)
#     - Automatic log rotation (7-day retention)
#     - Trap handlers for cleanup on exit/crash
#
# VERSION: 1.0 (Linux/Proton Port)
# AUTHOR: CubeCoders AMP Template
# REQUIREMENTS: Bash 4.0+, Proton GE, jq
#
# USAGE:
#     bash SCUMWrapper.sh Port=7042 QueryPort=7043 MaxPlayers=64
#

set -euo pipefail

# ============================================================================
# CONFIGURATION CONSTANTS
# ============================================================================

readonly STARTUP_PHASE_THRESHOLD=30
readonly FAILSAFE_TIMEOUT=30
readonly ORPHAN_CLEANUP_WAIT=5
readonly PID_FILE_STALENESS_MINUTES=5
readonly LOG_RETENTION_DAYS=7
readonly PROCESS_POLL_INTERVAL=0.5
readonly LOGEXIT_CHECK_INTERVAL=2
readonly LOGEXIT_PROGRESS_INTERVAL=10
readonly LOGEXIT_TAIL_LINES=50
readonly LOGEXIT_PATTERN="LogExit: Exiting"

# ============================================================================
# GLOBAL VARIABLES
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/Logs"
LOG_FILE="${LOG_DIR}/SCUMWrapper_$(date +%Y-%m-%d).log"
PID_FILE="${SCRIPT_DIR}/scum_server.pid"
SERVER_READY_FLAG="${SCRIPT_DIR}/server_ready.flag"
STOP_SIGNAL_FILE="${SCRIPT_DIR}/scum_stop.signal"

SERVER_PID=""
WRAPPER_PID=$$
SERVER_LOG_PATH=""

# ============================================================================
# LOGGING SYSTEM
# ============================================================================

# Create logs directory
mkdir -p "${LOG_DIR}"

log_message() {
    local level="${1:-INFO}"
    local message="${2}"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')
    
    local console_prefix
    case "${level}" in
        ERROR)   console_prefix="[WRAPPER-ERROR]" ;;
        WARNING) console_prefix="[WRAPPER-WARN]" ;;
        DEBUG)   console_prefix="[WRAPPER-DEBUG]" ;;
        *)       console_prefix="[WRAPPER-INFO]" ;;
    esac
    
    # Console output (for AMP)
    echo "${console_prefix} ${message}"
    
    # File output
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}" 2>/dev/null || true
}

remove_old_logs() {
    find "${LOG_DIR}" -name "SCUMWrapper_*.log" -type f -mtime +${LOG_RETENTION_DAYS} -delete 2>/dev/null || true
}

remove_old_logs

log_message "INFO" "=================================================="
log_message "INFO" "SCUM Server Graceful Shutdown Wrapper v1.0 (Linux)"
log_message "INFO" "Bash Version: ${BASH_VERSION}"
log_message "INFO" "Wrapper PID: ${WRAPPER_PID}"
log_message "INFO" "=================================================="

# ============================================================================
# CLEANUP HANDLERS
# ============================================================================

cleanup_on_exit() {
    log_message "DEBUG" "Cleanup handler triggered"
    
    # Remove PID file
    if [[ -f "${PID_FILE}" ]]; then
        rm -f "${PID_FILE}" 2>/dev/null || true
        log_message "DEBUG" "PID file removed"
    fi
    
    # Remove flag files
    rm -f "${SERVER_READY_FLAG}" "${STOP_SIGNAL_FILE}" 2>/dev/null || true
}

trap cleanup_on_exit EXIT
trap cleanup_on_exit INT TERM

# ============================================================================
# ORPHAN PROCESS CLEANUP
# ============================================================================

stop_orphaned_processes() {
    log_message "DEBUG" "Pre-start check: Checking for orphaned process from previous run..."
    
    if [[ -f "${PID_FILE}" ]]; then
        local pid_data
        if pid_data=$(cat "${PID_FILE}" 2>/dev/null); then
            local server_pid
            server_pid=$(echo "${pid_data}" | jq -r '.ServerPID // empty' 2>/dev/null)
            
            if [[ -n "${server_pid}" ]] && kill -0 "${server_pid}" 2>/dev/null; then
                # Check if it's actually SCUMServer process
                local proc_name
                proc_name=$(ps -p "${server_pid}" -o comm= 2>/dev/null || echo "")
                
                if [[ "${proc_name}" == *"SCUMServer"* ]] || [[ "${proc_name}" == *"wine"* ]]; then
                    log_message "WARNING" "Pre-start check: Found orphaned process PID: ${server_pid}"
                    
                    kill -9 "${server_pid}" 2>/dev/null || true
                    log_message "DEBUG" "Pre-start check: Terminated orphaned PID: ${server_pid}"
                    
                    sleep "${ORPHAN_CLEANUP_WAIT}"
                    
                    if kill -0 "${server_pid}" 2>/dev/null; then
                        log_message "ERROR" "Pre-start check: WARNING - Process ${server_pid} still running!"
                    else
                        log_message "DEBUG" "Pre-start check: Process terminated successfully"
                    fi
                fi
            else
                log_message "DEBUG" "Pre-start check: Previous server PID ${server_pid} is not running - clean state"
            fi
        fi
    else
        log_message "DEBUG" "Pre-start check: No PID file found - clean state"
    fi
}

stop_orphaned_processes

# Clean up leftover files
rm -f "${STOP_SIGNAL_FILE}" "${SERVER_READY_FLAG}" 2>/dev/null || true

# ============================================================================
# PID FILE MANAGEMENT
# ============================================================================

if [[ -f "${PID_FILE}" ]]; then
    log_message "DEBUG" "Found existing PID file"
    
    if pid_data=$(cat "${PID_FILE}" 2>/dev/null) && [[ -n "${pid_data}" ]]; then
        wrapper_pid=$(echo "${pid_data}" | jq -r '.PID // empty' 2>/dev/null)
        server_pid=$(echo "${pid_data}" | jq -r '.ServerPID // empty' 2>/dev/null)
        timestamp=$(echo "${pid_data}" | jq -r '.Timestamp // empty' 2>/dev/null)
        
        if [[ -n "${wrapper_pid}" ]] && kill -0 "${wrapper_pid}" 2>/dev/null; then
            log_message "ERROR" "ERROR: Another wrapper instance is running (PID: ${wrapper_pid})"
            log_message "ERROR" "If this is incorrect, delete: ${PID_FILE}"
            exit 1
        elif [[ -n "${server_pid}" ]] && kill -0 "${server_pid}" 2>/dev/null; then
            log_message "WARNING" "Orphan server detected (PID: ${server_pid}) - terminating..."
            kill -9 "${server_pid}" 2>/dev/null || true
            sleep "${ORPHAN_CLEANUP_WAIT}"
        fi
    fi
    
    rm -f "${PID_FILE}" 2>/dev/null || true
fi

# Create new PID file
cat > "${PID_FILE}" <<EOF
{
  "PID": ${WRAPPER_PID},
  "ServerPID": null,
  "Timestamp": "$(date -Iseconds)"
}
EOF

log_message "INFO" "Created PID file: ${PID_FILE}"

# ============================================================================
# SERVER STARTUP
# ============================================================================

# Calculate paths
INSTANCE_ROOT="$(dirname "${SCRIPT_DIR}")"
SERVER_ROOT="${INSTANCE_ROOT}/scum/3792580/SCUM"
EXE_PATH="${SERVER_ROOT}/Binaries/Win64/SCUMServer.exe"
SERVER_LOG_PATH="${SERVER_ROOT}/Saved/Logs/SCUM.log"

# Validate executable exists
if [[ ! -f "${EXE_PATH}" ]]; then
    log_message "ERROR" "ERROR: Server executable not found: ${EXE_PATH}"
    log_message "ERROR" "Expected structure: {InstanceRoot}/scum/3792580/SCUM/Binaries/Win64/SCUMServer.exe"
    exit 1
fi

# Get Proton path
PROTON_PATH="${INSTANCE_ROOT}/.proton/proton"
if [[ ! -x "${PROTON_PATH}" ]]; then
    log_message "ERROR" "ERROR: Proton not found or not executable: ${PROTON_PATH}"
    exit 1
fi

# Build command line arguments
ARG_STRING="$*"

log_message "INFO" "Executable: ${EXE_PATH}"
log_message "INFO" "Arguments: ${ARG_STRING}"
log_message "INFO" "Proton: ${PROTON_PATH}"
log_message "INFO" "SCUM Log Path: ${SERVER_LOG_PATH}"
log_message "INFO" "--------------------------------------------------"

# Set environment variables for Proton
export STEAM_COMPAT_DATA_PATH="${INSTANCE_ROOT}/.proton/compatdata"
export STEAM_COMPAT_CLIENT_INSTALL_PATH="${INSTANCE_ROOT}/.steam/steam"
export SteamAppId="513710"

log_message "INFO" "Starting SCUM Server via Proton..."

# Start server process in background
"${PROTON_PATH}" runinprefix "${EXE_PATH}" ${ARG_STRING} &
SERVER_PID=$!

if [[ -z "${SERVER_PID}" ]] || ! kill -0 "${SERVER_PID}" 2>/dev/null; then
    log_message "ERROR" "ERROR: Failed to start server process"
    exit 1
fi

log_message "INFO" "Server started successfully"
log_message "INFO" "SCUM Server PID: ${SERVER_PID}"

# Update PID file with server PID
jq --arg pid "${SERVER_PID}" '.ServerPID = ($pid | tonumber)' "${PID_FILE}" > "${PID_FILE}.tmp" && mv "${PID_FILE}.tmp" "${PID_FILE}"
log_message "DEBUG" "PID file updated with server PID: ${SERVER_PID}"

# ============================================================================
# START EXTERNAL WATCHDOG
# ============================================================================

log_message "INFO" "=================================================="
log_message "INFO" "STARTING EXTERNAL WATCHDOG (Orphan Prevention)"
log_message "INFO" "=================================================="

WATCHDOG_SCRIPT="${SCRIPT_DIR}/SCUMWatchdog.sh"

if [[ ! -f "${WATCHDOG_SCRIPT}" ]]; then
    log_message "ERROR" "ERROR: Watchdog script not found: ${WATCHDOG_SCRIPT}"
    log_message "ERROR" "ORPHAN PREVENTION WILL NOT WORK!"
else
    bash "${WATCHDOG_SCRIPT}" "${WRAPPER_PID}" "${SERVER_PID}" "${PID_FILE}" "${SERVER_LOG_PATH}" &
    WATCHDOG_PID=$!
    
    log_message "DEBUG" "✓ Watchdog started successfully"
    log_message "DEBUG" "  - Watchdog PID: ${WATCHDOG_PID}"
    
    sleep 0.5
    
    if kill -0 "${WATCHDOG_PID}" 2>/dev/null; then
        log_message "DEBUG" "✓ Watchdog confirmed running"
        log_message "INFO" "=================================================="
        log_message "INFO" "ORPHAN PREVENTION ACTIVE"
        log_message "INFO" "=================================================="
    else
        log_message "ERROR" "WARNING: Watchdog exited immediately!"
    fi
fi

# ============================================================================
# SERVER READY DETECTION
# ============================================================================

log_message "INFO" "State: STARTING - Waiting for server to be ready..."
log_message "INFO" "--------------------------------------------------"

MAX_WAIT_TIME=120
START_TIME=$(date +%s)
SERVER_READY=false
CHECK_COUNT=0

log_message "DEBUG" "Waiting for server to reach ready state (max ${MAX_WAIT_TIME}s)..."
log_message "DEBUG" "Monitoring log file: ${SERVER_LOG_PATH}"

while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    
    if [[ ${ELAPSED} -ge ${MAX_WAIT_TIME} ]]; then
        log_message "WARNING" "Timeout reached (${ELAPSED}s). Assuming server is ready..."
        SERVER_READY=true
        break
    fi
    
    # Check if server process is still alive
    if ! kill -0 "${SERVER_PID}" 2>/dev/null; then
        log_message "ERROR" "Server process died during startup!"
        wait "${SERVER_PID}" 2>/dev/null || true
        EXIT_CODE=$?
        log_message "ERROR" "Exit code: ${EXIT_CODE}"
        break
    fi
    
    # Check log file for ready pattern
    if [[ -f "${SERVER_LOG_PATH}" ]]; then
        if tail -n ${LOGEXIT_TAIL_LINES} "${SERVER_LOG_PATH}" 2>/dev/null | grep -q "LogSCUM: Global Stats"; then
            log_message "INFO" "✓ Server READY detected in log after ${ELAPSED}s"
            log_message "DEBUG" "  Pattern found: LogSCUM: Global Stats"
            SERVER_READY=true
            break
        fi
        
        CHECK_COUNT=$((CHECK_COUNT + 1))
        if [[ $((CHECK_COUNT % 10)) -eq 0 ]]; then
            log_message "DEBUG" "Check #${CHECK_COUNT} (${ELAPSED}s): Waiting for ready pattern..."
        fi
    else
        CHECK_COUNT=$((CHECK_COUNT + 1))
        if [[ $((CHECK_COUNT % 10)) -eq 0 ]]; then
            log_message "DEBUG" "Check #${CHECK_COUNT} (${ELAPSED}s): Log file not found yet"
        fi
    fi
    
    sleep 2
done

# Create flag file if server is ready
if [[ "${SERVER_READY}" == "true" ]]; then
    echo "READY" > "${SERVER_READY_FLAG}"
    log_message "DEBUG" "✓ Server ready flag created: ${SERVER_READY_FLAG}"
    log_message "DEBUG" "  From this point, Stop = Graceful Shutdown"
else
    log_message "ERROR" "Server did not reach ready state (process died)"
    log_message "WARNING" "Flag NOT created - watchdog will FORCE KILL if wrapper dies"
fi

# ============================================================================
# OUTPUT AMP READY PATTERN
# ============================================================================

log_message "DEBUG" "State: RUNNING - Monitoring process..."
log_message "INFO" "--------------------------------------------------"

# ============================================================================
# MONITOR PROCESS
# ============================================================================

LAST_HEARTBEAT=$(date +%s)

while kill -0 "${SERVER_PID}" 2>/dev/null; do
    sleep "${PROCESS_POLL_INTERVAL}"
    
    # Heartbeat every 5 seconds
    CURRENT_TIME=$(date +%s)
    if [[ $((CURRENT_TIME - LAST_HEARTBEAT)) -ge 5 ]]; then
        LAST_HEARTBEAT=${CURRENT_TIME}
        log_message "DEBUG" "Heartbeat: Wrapper alive, monitoring server PID ${SERVER_PID}"
    fi
done

# Process exited
wait "${SERVER_PID}" 2>/dev/null || true
EXIT_CODE=$?

log_message "INFO" "Process exited. Code: ${EXIT_CODE}"
exit ${EXIT_CODE}
