#!/bin/bash
################################################################################
# Squad Server Wrapper for AMP
# Purpose: Parse log file and output player events to STDOUT for AMP monitoring
# Platform: Linux (Debian/Ubuntu)
################################################################################

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="${SCRIPT_DIR}/403240"
SERVER_EXECUTABLE="${SERVER_DIR}/SquadGame/Binaries/Linux/SquadGameServer"
LOG_FILE="${SERVER_DIR}/SquadGame/Saved/Logs/SquadGame.log"
WRAPPER_LOG="${SERVER_DIR}/SquadGame/Saved/Logs/SquadWrapper.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${WRAPPER_LOG}"
}

log_info() {
    log "INFO" "$@"
    echo "[$(date '+%H:%M:%S')] [INFO] $*"
}

log_error() {
    log "ERROR" "$@"
    echo "[$(date '+%H:%M:%S')] [ERROR] $*" >&2
}

log_debug() {
    log "DEBUG" "$@"
}

# Cleanup function
cleanup() {
    log_info "Wrapper shutting down..."
    
    if [ -n "${SERVER_PID:-}" ] && kill -0 "${SERVER_PID}" 2>/dev/null; then
        log_info "Stopping Squad server (PID: ${SERVER_PID})..."
        kill -TERM "${SERVER_PID}" 2>/dev/null || true
        
        # Wait for graceful shutdown (max 30 seconds)
        local count=0
        while kill -0 "${SERVER_PID}" 2>/dev/null && [ $count -lt 30 ]; do
            sleep 1
            ((count++))
        done
        
        # Force kill if still running
        if kill -0 "${SERVER_PID}" 2>/dev/null; then
            log_error "Server didn't stop gracefully, force killing..."
            kill -9 "${SERVER_PID}" 2>/dev/null || true
        else
            log_info "Server stopped gracefully"
        fi
    fi
    
    # Kill log tailer
    if [ -n "${TAILER_PID:-}" ] && kill -0 "${TAILER_PID}" 2>/dev/null; then
        kill -TERM "${TAILER_PID}" 2>/dev/null || true
    fi
    
    log_info "Wrapper shutdown complete"
    exit 0
}

# Trap signals
trap cleanup SIGTERM SIGINT SIGQUIT

# Parse log line and output player events
parse_log_line() {
    local line="$1"
    
    # Player join: LogNet: Login request: ?Name=BB-8 userId: RedpointEOS:0002f9c842e343eb8eefce0622f3b0c8 platform: RedpointEOS
    if echo "$line" | grep -q "LogNet: Login request:"; then
        local username=$(echo "$line" | sed -n 's/.*?Name=\([^ ]*\).*/\1/p')
        local userid=$(echo "$line" | sed -n 's/.*userId: RedpointEOS:\([a-f0-9]*\).*/\1/p')
        
        if [ -n "$username" ] && [ -n "$userid" ]; then
            # Output in AMP-friendly format
            echo "[$(date '+%H:%M:%S')] Player joined: ${username} (${userid})"
            log_debug "Player joined: ${username} (${userid})"
        fi
    fi
    
    # Player leave: LogNet: UNetConnection::Close: ... Driver: Name:GameNetDriver ... UniqueId: RedpointEOS:0002f9c842e343eb8eefce0622f3b0c8
    if echo "$line" | grep -q "LogNet: UNetConnection::Close:.*GameNetDriver.*UniqueId: RedpointEOS:"; then
        local userid=$(echo "$line" | sed -n 's/.*UniqueId: RedpointEOS:\([a-f0-9]*\).*/\1/p')
        
        if [ -n "$userid" ]; then
            # Output in AMP-friendly format
            echo "[$(date '+%H:%M:%S')] Player left: (${userid})"
            log_debug "Player left: ${userid}"
        fi
    fi
    
    # Server ready: LogOnline: GotoState: NewState: Playing
    if echo "$line" | grep -q "LogOnline: GotoState: NewState: Playing"; then
        echo "[$(date '+%H:%M:%S')] Server is ready!"
        log_info "Server reached ready state"
    fi
}

# Main function
main() {
    log_info "=== Squad Wrapper Starting ==="
    log_info "Script Dir: ${SCRIPT_DIR}"
    log_info "Server Dir: ${SERVER_DIR}"
    log_info "Executable: ${SERVER_EXECUTABLE}"
    log_info "Log File: ${LOG_FILE}"
    
    # Check if server executable exists
    if [ ! -f "${SERVER_EXECUTABLE}" ]; then
        log_error "Server executable not found: ${SERVER_EXECUTABLE}"
        exit 1
    fi
    
    # Make executable if not already
    chmod +x "${SERVER_EXECUTABLE}" 2>/dev/null || true
    
    # Build command line arguments from AMP
    # AMP will pass arguments like: MULTIHOME=... Port=... QueryPort=... etc.
    local server_args="$@"
    
    log_info "Starting Squad server with args: ${server_args}"
    
    # Start server in background
    cd "${SERVER_DIR}"
    "${SERVER_EXECUTABLE}" ${server_args} &
    SERVER_PID=$!
    
    log_info "Squad server started (PID: ${SERVER_PID})"
    echo "[$(date '+%H:%M:%S')] Squad server starting..."
    
    # Wait for log file to be created
    local wait_count=0
    while [ ! -f "${LOG_FILE}" ] && [ $wait_count -lt 30 ]; do
        sleep 1
        ((wait_count++))
    done
    
    if [ ! -f "${LOG_FILE}" ]; then
        log_error "Log file not created after 30 seconds: ${LOG_FILE}"
        kill -TERM "${SERVER_PID}" 2>/dev/null || true
        exit 1
    fi
    
    log_info "Log file found, starting log parser..."
    
    # Tail log file and parse in background
    tail -F -n 0 "${LOG_FILE}" 2>/dev/null | while IFS= read -r line; do
        parse_log_line "$line"
    done &
    TAILER_PID=$!
    
    log_debug "Log tailer started (PID: ${TAILER_PID})"
    
    # Wait for server process
    wait "${SERVER_PID}"
    SERVER_EXIT_CODE=$?
    
    log_info "Squad server exited with code: ${SERVER_EXIT_CODE}"
    echo "[$(date '+%H:%M:%S')] Squad server stopped (exit code: ${SERVER_EXIT_CODE})"
    
    # Cleanup
    cleanup
}

# Run main function with all arguments
main "$@"
