# Debian 13 Testing Checklist for SCUM Template

## ✅ Changes Pushed (Commit: 3cc4fb9)
- Fixed Linux path format: `../../SCUM_Scripts/` (forward slashes)
- Removed problematic list-based config fields
- Ready for testing on Debian 13

---

## 🔍 Pre-Test Verification Steps

### 1. Update AMP Template Repository
```bash
# In AMP Admin Panel
Configuration → Repositories → Click "Fetch Latest"
```

### 2. Check Required Dependencies
```bash
# Check if jq is installed (required for JSON parsing)
which jq

# If not installed:
sudo apt update
sudo apt install jq -y
```

### 3. Verify Wrapper Scripts Exist
```bash
# Navigate to instance directory
cd /AMP/scum/3792580/

# Check if SCUM_Scripts folder exists
ls -la SCUM_Scripts/

# Expected files:
# - SCUMWrapper.sh
# - SCUMWatchdog.sh
```

### 4. Make Scripts Executable
```bash
cd /AMP/scum/3792580/SCUM_Scripts/

# Set execute permissions
chmod +x SCUMWrapper.sh
chmod +x SCUMWatchdog.sh

# Verify permissions
ls -la *.sh
# Should show: -rwxr-xr-x (executable)
```

---

## 🚀 Test Procedure

### Test 1: Basic Server Start
1. In AMP Web UI → Click "Start"
2. **Expected Behavior:**
   - Status changes to "Starting..."
   - Wrapper script executes
   - SCUMServer.exe launches
   - Status changes to "Started" after ~30-60 seconds
3. **Check Logs:**
   ```bash
   # Wrapper log
   tail -f /AMP/scum/3792580/SCUM/Binaries/Win64/Logs/SCUMWrapper_*.log
   
   # Watchdog log
   tail -f /AMP/scum/3792580/SCUM/Binaries/Win64/Logs/SCUMWatchdog_*.log
   
   # SCUM server log
   tail -f /AMP/scum/3792580/SCUM/Saved/Logs/SCUM.log
   ```

### Test 2: Graceful Shutdown
1. In AMP Web UI → Click "Stop"
2. **Expected Behavior:**
   - Wrapper receives SIGTERM
   - Watchdog detects wrapper death
   - Watchdog checks for `server_ready.flag`
   - Sends SIGTERM to SCUMServer.exe
   - Waits for "LogExit: Exiting" in SCUM.log (max 30s)
   - Server shuts down gracefully
3. **Check Watchdog Log:**
   ```bash
   grep "GRACEFUL SHUTDOWN SUCCESS" /AMP/scum/3792580/SCUM/Binaries/Win64/Logs/SCUMWatchdog_*.log
   ```

### Test 3: Abort During Startup
1. In AMP Web UI → Click "Start"
2. **Immediately** click "Abort" (within 10 seconds)
3. **Expected Behavior:**
   - Wrapper receives SIGTERM
   - Watchdog detects wrapper death
   - No `server_ready.flag` exists
   - Watchdog force kills SCUMServer.exe immediately
   - No orphaned processes
4. **Verify No Orphans:**
   ```bash
   ps aux | grep SCUMServer
   # Should return nothing (or only the grep command itself)
   ```

### Test 4: Restart Cycle
1. Start server → Wait for "Started" status
2. Click "Restart"
3. **Expected Behavior:**
   - Graceful shutdown (as in Test 2)
   - Automatic restart
   - Server comes back online
4. **Check for Orphans:**
   ```bash
   ps aux | grep -E "(SCUMServer|SCUMWrapper|SCUMWatchdog)"
   # Should only show current processes (no duplicates)
   ```

---

## 🐛 Troubleshooting Guide

### Issue: Server Exits Immediately (Exit Code 0)
**Symptoms:**
- Status changes to "Starting..." then immediately to "Stopped"
- No wrapper logs generated

**Possible Causes:**
1. **Wrapper script not executable**
   ```bash
   chmod +x /AMP/scum/3792580/SCUM_Scripts/SCUMWrapper.sh
   ```

2. **Missing jq dependency**
   ```bash
   sudo apt install jq -y
   ```

3. **Wrong path format in scum.kvp**
   - Check if using forward slashes: `../../SCUM_Scripts/`
   - NOT backslashes: `..\..\SCUM_Scripts\`

4. **Bash interpreter missing**
   ```bash
   which bash
   # Should return: /bin/bash or /usr/bin/bash
   ```

### Issue: Wrapper Logs Show "Permission Denied"
**Solution:**
```bash
# Make scripts executable
chmod +x /AMP/scum/3792580/SCUM_Scripts/*.sh

# Check ownership
ls -la /AMP/scum/3792580/SCUM_Scripts/
# Should be owned by AMP user (usually 'amp')

# If wrong owner:
sudo chown -R amp:amp /AMP/scum/3792580/SCUM_Scripts/
```

### Issue: Watchdog Not Starting
**Check Wrapper Log:**
```bash
grep "Watchdog started" /AMP/scum/3792580/SCUM/Binaries/Win64/Logs/SCUMWrapper_*.log
```

**If missing:**
- Verify SCUMWatchdog.sh exists in SCUM_Scripts/
- Check execute permissions
- Verify bash path in shebang: `#!/bin/bash`

### Issue: Orphaned Processes After Stop
**Symptoms:**
- Multiple SCUMServer.exe processes running
- Cannot start new instance

**Solution:**
```bash
# Find orphaned processes
ps aux | grep SCUMServer

# Kill orphaned processes (replace PID)
kill -9 <PID>

# Clean up PID file
rm /AMP/scum/3792580/SCUM/Binaries/Win64/scum_server.pid

# Restart instance
```

---

## 📊 Success Criteria

✅ **All tests must pass:**
- [ ] Server starts successfully
- [ ] Wrapper and watchdog logs are generated
- [ ] Server reaches "Started" status in AMP
- [ ] Graceful shutdown works (LogExit detected)
- [ ] Abort during startup kills server immediately
- [ ] No orphaned processes after stop/restart
- [ ] Restart cycle works without issues

✅ **Log verification:**
- [ ] Wrapper log shows: `[INFO] SCUM Server PID: <number>`
- [ ] Watchdog log shows: `[WATCHDOG-DEBUG] ✓ Wrapper process found`
- [ ] SCUM.log shows: `LogExit: Exiting. Log file closed`

---

## 📝 Report Template

After testing, please provide:

```
## Test Results (Debian 13)

**System Info:**
- OS: Debian 13
- AMP Version: [version]
- Instance Path: /AMP/scum/3792580/

**Test 1 - Basic Start:** [PASS/FAIL]
- Details: [description]

**Test 2 - Graceful Shutdown:** [PASS/FAIL]
- Details: [description]

**Test 3 - Abort During Startup:** [PASS/FAIL]
- Details: [description]

**Test 4 - Restart Cycle:** [PASS/FAIL]
- Details: [description]

**Logs Attached:**
- Wrapper log: [paste relevant lines]
- Watchdog log: [paste relevant lines]
- SCUM.log: [paste relevant lines]

**Issues Found:**
[List any issues or unexpected behavior]
```

---

## 🔗 Related Documentation
- `SCUM_LINUX_QUICK_TEST_GUIDE.md` - Quick testing guide
- `SCUM_LINUX_SUPPORT_IMPLEMENTATION.md` - Technical implementation details
- `SCUM_PLATFORM_COMPARISON.md` - Windows vs Linux comparison
- `SCUM_LINUX_SUPPORT_TH.md` - Thai language documentation
