# SCUM Linux Quick Test Guide

## Prerequisites Check

```bash
# Check Bash version (need 4.0+)
bash --version

# Check jq installed
jq --version

# If jq not found, install it:
sudo apt install -y jq

# Check AMP is running
systemctl status ampinstmgr
```

## Test 1: Basic Startup

### Steps:
1. Create new SCUM instance in AMP
2. Click "Start" button
3. Wait for "Started" status (30-60 seconds)

### Expected Results:
```
[WRAPPER-INFO] SCUM Server Graceful Shutdown Wrapper v1.0 (Linux)
[WRAPPER-INFO] Wrapper PID: 12345
[WRAPPER-INFO] Starting SCUM Server via Proton...
[WRAPPER-INFO] Server started successfully
[WRAPPER-INFO] SCUM Server PID: 67890
[WRAPPER-DEBUG] ✓ Watchdog started successfully
[WRAPPER-INFO] ✓ Server READY detected in log after 45.2s
[WRAPPER-DEBUG] State: RUNNING - Monitoring process...
```

### Verify:
```bash
# Check wrapper process
ps aux | grep SCUMWrapper.sh

# Check server process (via Proton)
ps aux | grep SCUMServer

# Check watchdog process
ps aux | grep SCUMWatchdog.sh

# Check logs
tail -f /path/to/instance/scum/3792580/SCUM/Binaries/Win64/Logs/SCUMWrapper_*.log
```

## Test 2: Graceful Shutdown

### Steps:
1. Wait for server to reach "Started" state
2. Click "Stop" button in AMP
3. Wait for shutdown (max 30 seconds)

### Expected Results:
```
[WRAPPER-DEBUG] Sending SIGTERM to server...
[WRAPPER-DEBUG] Waiting for LogExit pattern...
[WRAPPER-DEBUG] ✓ LogExit pattern detected after 12s!
[WRAPPER-INFO] Process exited. Code: 0
```

### Verify:
```bash
# Check no orphan processes
ps aux | grep SCUMServer
# Should return nothing

# Check SCUM log for LogExit
tail -n 50 /path/to/instance/scum/3792580/SCUM/Saved/Logs/SCUM.log | grep "LogExit"
# Should show: LogExit: Exiting. Log file closed, MM/DD/YY HH:MM:SS
```

## Test 3: Abort During Startup

### Steps:
1. Click "Start" button
2. **Immediately** click "Abort" (within 5 seconds)
3. Wait 2 seconds

### Expected Results:
```
[WATCHDOG-WARNING] WRAPPER DIED! (PID: 12345)
[WATCHDOG-DEBUG] ✗ Server was NOT READY (no flag file)
[WATCHDOG-DEBUG] DECISION: Server was STARTING (not ready yet)
[WATCHDOG-DEBUG] Step 4: Killing server (startup phase)...
[WATCHDOG-DEBUG] ✓ Server killed successfully
```

### Verify:
```bash
# Check no orphan processes
ps aux | grep SCUMServer
# Should return nothing

# Check watchdog log
tail -n 100 /path/to/instance/scum/3792580/SCUM/Binaries/Win64/Logs/SCUMWatchdog_*.log
```

## Test 4: Restart

### Steps:
1. Start server (wait for "Started")
2. Click "Restart" button
3. Wait for server to restart

### Expected Results:
- Server stops gracefully (LogExit detected)
- New wrapper process starts
- New server process starts
- Server reaches "Started" state again

### Verify:
```bash
# Check PID changed
cat /path/to/instance/scum/3792580/SCUM/Binaries/Win64/scum_server.pid
# Should show new PIDs

# Check no duplicate processes
ps aux | grep SCUMServer | wc -l
# Should return 1 (only one server process)
```

## Test 5: Multiple Instances

### Steps:
1. Create 2 SCUM instances (different ports)
2. Start both instances
3. Verify both running independently

### Expected Results:
- Each instance has its own wrapper process
- Each instance has its own server process
- Each instance has its own PID file
- No port conflicts

### Verify:
```bash
# Check processes
ps aux | grep SCUMWrapper.sh
# Should show 2 wrapper processes

ps aux | grep SCUMServer
# Should show 2 server processes

# Check ports
netstat -tulpn | grep 7042  # Instance 1
netstat -tulpn | grep 8042  # Instance 2
```

## Common Issues & Solutions

### Issue 1: "jq: command not found"

```bash
sudo apt install -y jq
```

### Issue 2: "Permission denied: SCUMWrapper.sh"

```bash
chmod +x /path/to/SCUM/Binaries/Win64/SCUMWrapper.sh
chmod +x /path/to/SCUM/Binaries/Win64/SCUMWatchdog.sh
```

### Issue 3: "Proton not found"

```bash
# Check Proton installation
ls -la /path/to/instance/.proton/

# If missing, trigger AMP update
# AMP will download Proton GE automatically
```

### Issue 4: Orphan processes after abort

```bash
# Kill orphan manually
pkill -9 -f SCUMServer

# Remove stale PID file
rm -f /path/to/instance/scum/3792580/SCUM/Binaries/Win64/scum_server.pid

# Remove flag files
rm -f /path/to/instance/scum/3792580/SCUM/Binaries/Win64/server_ready.flag
```

### Issue 5: Server not reaching "Started" state

```bash
# Check SCUM log for errors
tail -f /path/to/instance/scum/3792580/SCUM/Saved/Logs/SCUM.log

# Check wrapper log
tail -f /path/to/instance/scum/3792580/SCUM/Binaries/Win64/Logs/SCUMWrapper_*.log

# Common causes:
# - Missing game files (run update)
# - Port already in use
# - Insufficient permissions
# - Proton not configured correctly
```

## Performance Monitoring

### Check Resource Usage

```bash
# Wrapper memory
ps aux | grep SCUMWrapper.sh | awk '{print $6/1024 " MB"}'

# Watchdog memory
ps aux | grep SCUMWatchdog.sh | awk '{print $6/1024 " MB"}'

# Server memory
ps aux | grep SCUMServer | awk '{print $6/1024 " MB"}'

# CPU usage
top -p $(pgrep -f SCUMServer)
```

### Expected Resource Usage

- Wrapper: ~5 MB RAM, <0.1% CPU
- Watchdog: ~5 MB RAM, <0.1% CPU
- Server: 2-8 GB RAM (depends on world size), 10-50% CPU

## Log Locations

```bash
# Wrapper logs
/path/to/instance/scum/3792580/SCUM/Binaries/Win64/Logs/SCUMWrapper_YYYY-MM-DD.log

# Watchdog logs
/path/to/instance/scum/3792580/SCUM/Binaries/Win64/Logs/SCUMWatchdog_YYYY-MM-DD.log

# SCUM server logs
/path/to/instance/scum/3792580/SCUM/Saved/Logs/SCUM.log

# AMP logs
/home/amp/.ampdata/instances/{InstanceName}/AMP_Logs/
```

## Success Criteria

✅ **All tests pass if:**

1. Server starts and reaches "Started" state
2. Stop button triggers graceful shutdown with LogExit
3. Abort during startup kills server immediately
4. No orphan processes after any operation
5. Restart works without manual intervention
6. Multiple instances can run simultaneously
7. Logs show expected patterns
8. Resource usage is reasonable

## Reporting Issues

If any test fails, collect these logs:

```bash
# Create debug bundle
cd /path/to/instance
tar -czf scum-debug-$(date +%Y%m%d-%H%M%S).tar.gz \
    scum/3792580/SCUM/Binaries/Win64/Logs/ \
    scum/3792580/SCUM/Saved/Logs/SCUM.log \
    scum/3792580/SCUM/Binaries/Win64/scum_server.pid \
    scum/3792580/SCUM/Binaries/Win64/server_ready.flag

# Share the tar.gz file when reporting issues
```

Include:
- Test number that failed
- Expected vs actual behavior
- Full error messages
- System information (Debian version, AMP version)

---

**Quick Reference:**

- Start: Click "Start" → Wait 30-60s → "Started"
- Stop: Click "Stop" → Wait max 30s → "Stopped"
- Abort: Click "Abort" → Immediate kill → "Stopped"
- Restart: Click "Restart" → Graceful stop + start
- Logs: `tail -f .../Logs/SCUMWrapper_*.log`
