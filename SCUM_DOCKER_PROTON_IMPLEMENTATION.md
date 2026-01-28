# SCUM Docker + Proton Implementation Guide

## 🔍 Problem Discovery

**Initial Assumption:** SCUM has native Linux server support
**Reality:** SCUM only provides Windows executable (SCUMServer.exe)
**Environment:** AMP running in Docker container with Proton/Wine

## 🏗️ Architecture Differences

### Windows (Native)
```
AMP → PowerShell Wrapper → SCUMServer.exe
       ├─ Graceful shutdown (Ctrl+C)
       ├─ Watchdog process
       └─ PID file management
```

### Linux (Docker + Proton)
```
AMP → Proton → SCUMServer.exe
       └─ Wine compatibility layer
```

**Key Limitation:** Proton can only execute Windows .exe files, NOT shell scripts!

## ⚙️ Configuration Changes

### Before (Attempted Bash Wrapper)
```kvp
App.ExecutableLinux=/bin/bash
App.LinuxCommandLineArgs=../../SCUM_Scripts/SCUMWrapper.sh SCUM -Port=...
```
**Result:** Exit code 0 immediately (wrapper script cannot be executed by Proton)

### After (Direct Proton Execution)
```kvp
App.ExecutableLinux=.proton/proton
App.LinuxCommandLineArgs=runinprefix "{{$FullBaseDir}}SCUM/Binaries/Win64/SCUMServer.exe" SCUM -Port={{$ServerPort}} -QueryPort={{$QueryPort}} -MaxPlayers={{$MaxUsers}} -log {{nobattleye}}{{AdditionalArgs}}{{$FormattedArgs}}
```
**Result:** SCUMServer.exe runs through Wine/Proton compatibility layer

## 📊 Feature Comparison

| Feature | Windows (Wrapper) | Linux (Proton Direct) |
|---------|-------------------|----------------------|
| **Server Startup** | ✅ Full control | ✅ Works |
| **Graceful Shutdown** | ✅ Ctrl+C signal | ⚠️ OS_CLOSE only |
| **Abort During Startup** | ✅ Immediate kill | ⚠️ Standard AMP behavior |
| **Orphan Prevention** | ✅ Watchdog process | ⚠️ AMP default handling |
| **PID File Management** | ✅ JSON tracking | ❌ Not available |
| **Verbose Logging** | ✅ Wrapper + Watchdog logs | ⚠️ SCUM.log only |
| **Process Monitoring** | ✅ Real-time | ✅ AMP monitors SCUMServer.exe |

## 🔧 Technical Details

### Proton Environment Variables
```kvp
App.EnvironmentVariables={
  "SteamAppId":"513710",
  "STEAM_COMPAT_DATA_PATH":"{{$FullRootDir}}.proton/compatdata",
  "STEAM_COMPAT_CLIENT_INSTALL_PATH":"{{$FullBaseDir}}.steam/steam",
  "HOME":"{{$FullBaseDir}}",
  "XDG_RUNTIME_DIR":"/tmp"
}
```

### Process Monitoring
```kvp
App.MonitorChildProcess=True
App.MonitorChildProcessName=SCUMServer.exe
App.MonitorDirectChildOnly=False
```
AMP will search for `SCUMServer.exe` in the process tree spawned by Proton.

### Exit Method
```kvp
App.ExitMethod=OS_CLOSE
App.ExitTimeout=35
```
- AMP sends OS_CLOSE signal to Proton
- Proton forwards signal to Wine
- Wine attempts to close SCUMServer.exe gracefully
- If timeout (35s), AMP force kills the process

## ⚠️ Known Limitations on Linux

### 1. No Graceful Shutdown Guarantee
**Windows:** Wrapper sends Ctrl+C → Waits for "LogExit: Exiting" → Force kill after 30s
**Linux:** AMP sends OS_CLOSE → Proton/Wine handles it → Force kill after 35s

**Impact:** Database corruption risk is higher on Linux if server doesn't shut down cleanly.

**Mitigation:**
- Increase `App.ExitTimeout` to 60 seconds
- Monitor SCUM.log for "LogExit: Exiting" pattern manually
- Use scheduled restarts during low-traffic periods

### 2. No Abort-During-Startup Protection
**Windows:** Watchdog detects wrapper death → Checks server state → Force kills if starting
**Linux:** Standard AMP behavior → May leave orphaned process

**Impact:** Clicking "Abort" during startup may leave SCUMServer.exe running.

**Mitigation:**
- Manually check for orphaned processes: `ps aux | grep SCUMServer`
- Kill orphaned processes: `kill -9 <PID>`
- Avoid clicking "Abort" during startup phase

### 3. No Wrapper Logs
**Windows:** Detailed logs in `SCUMWrapper_*.log` and `SCUMWatchdog_*.log`
**Linux:** Only SCUM.log available

**Impact:** Harder to troubleshoot startup/shutdown issues.

**Mitigation:**
- Monitor AMP console output
- Check SCUM.log at `/AMP/scum/3792580/SCUM/Saved/Logs/SCUM.log`
- Enable AMP debug logging if needed

## 🚀 Deployment Steps

### 1. Update Template Repository
```bash
# In AMP Admin Panel
Configuration → Repositories → Click "Fetch Latest"
```

### 2. Verify Proton Installation
The template includes pre-start stage "Proton GE Download" which:
- Downloads latest Proton GE from GitHub
- Extracts to `/AMP/scum/.proton/`
- Sets up Wine prefix at `/AMP/scum/.proton/compatdata/pfx`

**Check logs for:**
```
Proton GE version GE-Proton10-29 downloaded
Update stage Proton GE Download completed with status True
```

### 3. Start Server
Click "Start" in AMP Web UI

**Expected behavior:**
```
[15:21:52] Application state changed from Stopped to PreStart
[15:21:52] Application state changed from PreStart to Starting
[15:21:52] Running command line: ".proton/proton runinprefix ..."
[15:22:30] Application state changed from Starting to Started
```

### 4. Verify Server Running
```bash
# Check process
ps aux | grep SCUMServer.exe

# Check log
tail -f /AMP/scum/3792580/SCUM/Saved/Logs/SCUM.log
```

**Look for:**
```
LogSCUM: Global Stats: ...
```

## 🐛 Troubleshooting

### Issue: Exit Code 0 Immediately
**Symptoms:**
- Status changes to "Starting" then immediately to "Stopped"
- Log shows: "The application stopped unexpectedly. Exit code 0"

**Possible Causes:**
1. **Proton not installed**
   - Check: `/AMP/scum/.proton/proton` exists
   - Solution: Wait for "Proton GE Download" stage to complete

2. **Wrong executable path**
   - Check: `App.LinuxCommandLineArgs` points to correct .exe path
   - Verify: `/AMP/scum/3792580/SCUM/Binaries/Win64/SCUMServer.exe` exists

3. **Missing dependencies**
   - Check Docker image: `cubecoders/ampbase:debian`
   - Verify: `jq` is installed (for Proton setup scripts)

### Issue: Server Starts But Doesn't Respond
**Symptoms:**
- Process is running but players can't connect
- No "LogSCUM: Global Stats" in log

**Possible Causes:**
1. **Ports not forwarded**
   - Check: Docker port mappings
   - Verify: Firewall rules allow UDP traffic

2. **Wine prefix corruption**
   - Solution: Delete `/AMP/scum/.proton/compatdata/` and restart
   - Proton will recreate Wine prefix automatically

3. **BattlEye conflict**
   - Check: `{{nobattleye}}` parameter in command line
   - Try: Add `-NoBattlEye` flag manually

### Issue: Orphaned Processes After Stop
**Symptoms:**
- Cannot start new instance
- Multiple SCUMServer.exe processes running

**Solution:**
```bash
# Find orphaned processes
ps aux | grep SCUMServer.exe

# Kill all SCUM processes
pkill -9 -f SCUMServer.exe

# Clean up Wine processes
pkill -9 -f wineserver

# Restart instance
```

## 📝 Comparison with Other Proton Templates

### ARK: Survival Ascended
```kvp
App.ExecutableLinux=.proton/proton
App.LinuxCommandLineArgs=runinprefix "{{$FullBaseDir}}ShooterGame/Binaries/Win64/{{ServerExecutable}}.exe"
App.ExitMethod=String
App.ExitString=DoExit
App.HasWriteableConsole=True
```
**Difference:** ARK has RCON support for graceful shutdown via "DoExit" command.

### Enshrouded
```kvp
App.ExecutableLinux=.proton/proton
App.LinuxCommandLineArgs=runinprefix "{{$FullBaseDir}}enshrouded_server.exe"
App.ExitMethod=OS_CLOSE
App.HasWriteableConsole=False
```
**Similarity:** Same approach as SCUM - no RCON, relies on OS_CLOSE.

### Astroneer
```kvp
App.ExecutableLinux=.proton/proton
App.LinuxCommandLineArgs=runinprefix "{{$FullBaseDir}}Astro/Binaries/Win64/AstroServer-Win64-Shipping.exe"
App.ExitMethod=OS_CLOSE
```
**Similarity:** Same approach as SCUM.

## 🎯 Recommendations

### For Production Use
1. **Increase Exit Timeout:**
   ```kvp
   App.ExitTimeout=60
   ```
   Gives more time for graceful shutdown.

2. **Monitor Logs:**
   - Set up log monitoring for "LogExit: Exiting" pattern
   - Alert if pattern not detected within 30s of stop command

3. **Scheduled Restarts:**
   - Use AMP's scheduled tasks
   - Restart during low-traffic periods (e.g., 4 AM)
   - Reduces risk of data loss during restart

4. **Backup Strategy:**
   - Backup database files before restart
   - Location: `/AMP/scum/3792580/SCUM/Saved/`
   - Use AMP's backup feature or external script

### For Development/Testing
1. **Enable Debug Logging:**
   - AMP Settings → Enable debug logging
   - Helps troubleshoot startup issues

2. **Test Restart Cycles:**
   - Start → Wait for "Started" → Stop → Verify clean shutdown
   - Repeat 5-10 times to ensure stability

3. **Monitor Resource Usage:**
   - Proton adds overhead (~500MB RAM)
   - Wine processes may accumulate over time
   - Consider periodic container restarts

## 📚 Related Documentation

- **AMP Generic Module Wiki:** `Configuring the 'Generic' AMP module · CubeCoders_AMP Wiki.html`
- **Proton GE Releases:** https://github.com/GloriousEggroll/proton-ge-custom/releases
- **SCUM Server Setup:** https://scum.wiki.gg/wiki/Scum_Dedicated_server_setup

## 🔄 Future Improvements

### Potential Solutions for Graceful Shutdown
1. **RCON Implementation:**
   - If SCUM adds RCON support in future
   - Can send shutdown command via RCON
   - Similar to ARK's "DoExit" command

2. **File-Based Signaling:**
   - Create shutdown signal file
   - Server monitors file and shuts down gracefully
   - Requires server-side mod or plugin

3. **Wrapper in Wine:**
   - Create Windows .exe wrapper
   - Wrapper monitors for shutdown signal
   - Sends Ctrl+C to SCUMServer.exe
   - More complex but provides full control

### Community Contributions
- Test on different Docker configurations
- Report issues on GitHub
- Share optimization tips
- Document edge cases

---

**Last Updated:** 2025-01-28
**Template Version:** 3.3 (Docker + Proton)
**Tested On:** AMP in Docker (cubecoders/ampbase:debian)
