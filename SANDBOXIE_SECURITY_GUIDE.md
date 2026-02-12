# Sandboxie-Plus Security Integration Guide

## Overview

This guide explains how to run Windows executables through Sandboxie-Plus for enhanced security and isolation. This is recommended when running untrusted or potentially malicious `.exe` files to protect your host system.

## Why Use Sandboxie-Plus?

**Security Benefits:**
- **Process Isolation**: Executables run in an isolated environment
- **File System Protection**: Changes are contained within the sandbox
- **Registry Protection**: Registry modifications don't affect the host
- **Network Monitoring**: Can monitor and restrict network access
- **Rollback Capability**: Can delete sandbox contents to undo all changes
- **Malware Protection**: Prevents malware from infecting the host system

**Use Cases:**
- Running untrusted Discord bots or applications
- Testing potentially malicious executables
- Running applications from unknown sources
- Preventing intentional attacks on the host system
- Isolating applications that modify system files

---

## Prerequisites

### 1. Install Sandboxie-Plus

Download and install from: [https://sandboxie-plus.com/](https://sandboxie-plus.com/)

**Installation Path (Default):**
- 64-bit: `C:\Program Files\Sandboxie-Plus\Start.exe`
- 32-bit: `C:\Program Files (x86)\Sandboxie-Plus\Start.exe`

### 2. Create a Sandbox

1. Open Sandboxie-Plus
2. Click **Sandbox** → **Create New Box**
3. Name it (e.g., `AMPBox` or `UntrustedApps`)
4. Configure security settings (see Configuration section below)

---

## Integration Methods

### Method 1: Wrapper Approach (Recommended) ⭐

Modify the AMP template to automatically run executables through Sandboxie-Plus.

#### Step 1: Modify Template Configuration

Edit `windows-exe-runner.kvp`:

```kvp
# Original (Direct execution)
App.ExecutableWin={{ExecutablePath}}
App.CommandLineArgs={{CommandLineArgs}}

# Modified (Sandboxie wrapper)
App.ExecutableWin=C:\Program Files\Sandboxie-Plus\Start.exe
App.CommandLineArgs=/box:AMPBox /wait {{ExecutablePath}} {{CommandLineArgs}}
```

#### Step 2: Update Configuration JSON

Edit `windows-exe-runnerconfig.json` to add Sandboxie settings:

```json
[
  {
    "DisplayName": "Enable Sandboxie Isolation",
    "Category": "Windows EXE Runner:security",
    "Subcategory": "Security:shield:1",
    "Description": "Run the executable in Sandboxie-Plus for enhanced security and isolation. Requires Sandboxie-Plus to be installed.",
    "Keywords": "sandbox,security,isolation,protection,sandboxie",
    "FieldName": "EnableSandboxie",
    "InputType": "checkbox",
    "ParamFieldName": "EnableSandboxie",
    "DefaultValue": "False",
    "Required": false
  },
  {
    "DisplayName": "Sandbox Name",
    "Category": "Windows EXE Runner:security",
    "Subcategory": "Security:shield:1",
    "Description": "Name of the Sandboxie sandbox to use. The sandbox must be created in Sandboxie-Plus before use.",
    "Keywords": "sandbox,box,name,container",
    "FieldName": "SandboxName",
    "InputType": "text",
    "ParamFieldName": "SandboxName",
    "DefaultValue": "AMPBox",
    "Placeholder": "AMPBox",
    "Required": false
  },
  {
    "DisplayName": "Sandboxie Start.exe Path",
    "Category": "Windows EXE Runner:security",
    "Subcategory": "Security:shield:1",
    "Description": "Full path to Sandboxie-Plus Start.exe. Default installation path is shown.",
    "Keywords": "sandboxie,path,start,executable",
    "FieldName": "SandboxiePath",
    "InputType": "text",
    "ParamFieldName": "SandboxiePath",
    "DefaultValue": "C:\\Program Files\\Sandboxie-Plus\\Start.exe",
    "Placeholder": "C:\\Program Files\\Sandboxie-Plus\\Start.exe",
    "Required": false
  }
]
```

#### Advantages:
- ✅ Automatic sandboxing for all instances
- ✅ Centralized configuration
- ✅ No manual intervention required
- ✅ Works with AMP's Start/Stop/Restart controls

#### Disadvantages:
- ❌ Requires template modification
- ❌ All instances use sandboxing (can't easily disable per-instance)

---

### Method 2: Manual Configuration (Flexible)

Configure each AMP instance individually to use Sandboxie-Plus.

#### Configuration:

In AMP instance settings:

**Application Executable Path:**
```
C:\Program Files\Sandboxie-Plus\Start.exe
```

**Command Line Arguments:**
```
/box:AMPBox /wait C:\Path\To\Your\Application.exe --your-app-args
```

#### Advantages:
- ✅ No template modification needed
- ✅ Can enable/disable per instance
- ✅ Flexible configuration

#### Disadvantages:
- ❌ Manual configuration for each instance
- ❌ More complex for users

---

## Sandboxie-Plus Command Line Reference

### Basic Syntax

```cmd
Start.exe [options] /box:SandboxName program.exe [program arguments]
```

### Important Options

| Option | Description | Example |
|--------|-------------|---------|
| `/box:NAME` | Specify sandbox name | `/box:AMPBox` |
| `/wait` | Wait for program to exit | `/wait` |
| `/silent` | Suppress error messages | `/silent` |
| `/elevate` | Run with admin privileges | `/elevate` |
| `/hide_window` | Hide program window | `/hide_window` |
| `/env:VAR=VALUE` | Set environment variable | `/env:DEBUG=1` |
| `/terminate` | Stop all programs in sandbox | `/terminate` |

### Examples

**Basic execution:**
```cmd
"C:\Program Files\Sandboxie-Plus\Start.exe" /box:AMPBox /wait MyApp.exe
```

**With arguments:**
```cmd
"C:\Program Files\Sandboxie-Plus\Start.exe" /box:AMPBox /wait MyApp.exe --config config.json --verbose
```

**With admin privileges:**
```cmd
"C:\Program Files\Sandboxie-Plus\Start.exe" /box:AMPBox /elevate /wait MyApp.exe
```

**Silent mode (no error popups):**
```cmd
"C:\Program Files\Sandboxie-Plus\Start.exe" /box:AMPBox /silent /wait MyApp.exe
```

---

## Sandbox Configuration

### Recommended Security Settings

Open Sandboxie-Plus → Right-click sandbox → **Sandbox Options**

#### 1. Restrictions Tab

**File Access:**
- ✅ Enable "Block access to files outside sandbox"
- ✅ Enable "Block access to network locations"
- ⚠️ Add exceptions only for necessary directories

**Registry Access:**
- ✅ Enable "Block access to registry keys outside sandbox"

**IPC Access:**
- ✅ Enable "Block access to Windows IPC objects"

#### 2. Resource Access Tab

**File Access:**
```
# Allow read access to application directory (if needed)
OpenFilePath=C:\Apps\MyApp\,*

# Block write access to system directories
ClosedFilePath=C:\Windows\*
ClosedFilePath=C:\Program Files\*
```

**Registry Access:**
```
# Block write access to system registry
ClosedKeyPath=HKEY_LOCAL_MACHINE\*
```

#### 3. Network Access Tab

**Internet Restrictions:**
- ⚠️ Consider enabling "Block internet access" for untrusted applications
- ✅ Or use "Allow only specific programs" to whitelist

#### 4. Delete Invocation Tab

**Auto-Delete:**
- ✅ Enable "Automatically delete contents when all programs stop"
- ⚠️ Or manually delete after each run for maximum security

---

## Console Output Considerations

### ⚠️ Important: Console Output Capture

When running through Sandboxie-Plus with `/wait`, AMP can still capture console output:

**How it works:**
1. AMP launches `Start.exe` (Sandboxie)
2. `Start.exe` launches your `.exe` in sandbox
3. Console output flows: `Your.exe` → `Start.exe` → AMP
4. AMP displays output in console tab

**Limitations:**
- Some applications may have delayed output due to buffering
- ANSI color codes may not work correctly through the wrapper
- Very high-frequency output may be throttled

**Testing:**
```cmd
# Test console output capture
"C:\Program Files\Sandboxie-Plus\Start.exe" /box:AMPBox /wait cmd.exe /c "echo Hello from sandbox"
```

---

## Ready State Detection

### Pattern Detection Through Sandbox

Ready detection patterns work normally through Sandboxie:

**Example Configuration:**
```
Ready Detection Pattern: Bot is ready|Application started|Listening on port
```

**How it works:**
1. Your `.exe` outputs ready message to stdout
2. Sandboxie `Start.exe` forwards output to AMP
3. AMP detects pattern and marks instance as "Started"

**Testing:**
1. Configure ready pattern in AMP
2. Start instance
3. Monitor console for pattern
4. Verify instance status changes to "Started"

---

## Graceful Shutdown

### Stopping Sandboxed Applications

AMP's stop mechanism works with Sandboxie:

**Process:**
1. User clicks Stop in AMP
2. AMP sends WM_CLOSE to `Start.exe`
3. `Start.exe` forwards signal to sandboxed `.exe`
4. Application shuts down gracefully
5. Sandbox terminates

**Timeout:**
- Default: 30 seconds (configured in template)
- If application doesn't respond, AMP force-kills `Start.exe`
- Sandboxie automatically cleans up orphaned processes

**Manual Termination:**
```cmd
# Terminate all programs in specific sandbox
"C:\Program Files\Sandboxie-Plus\Start.exe" /box:AMPBox /terminate

# Terminate all sandboxes
"C:\Program Files\Sandboxie-Plus\Start.exe" /terminate_all
```

---

## Security Best Practices

### 1. Sandbox Isolation Levels

**Low Security (Testing):**
- Allow file system access
- Allow registry access
- Allow network access
- Manual cleanup

**Medium Security (Untrusted Apps):**
- Block system file writes
- Block registry writes
- Allow network access
- Auto-delete on exit

**High Security (Malware Analysis):**
- Block all file system writes
- Block all registry writes
- Block network access
- Auto-delete on exit
- Use encrypted sandbox

### 2. Monitoring and Logging

**Enable Sandboxie Logging:**
1. Sandboxie-Plus → Global Settings → Advanced
2. Enable "Resource Access Monitor"
3. Enable "API Call Log"
4. Review logs after running untrusted applications

**Check for Suspicious Activity:**
- File access attempts outside sandbox
- Registry modification attempts
- Network connection attempts
- Process injection attempts

### 3. Regular Cleanup

**Manual Cleanup:**
```cmd
# Delete sandbox contents
"C:\Program Files\Sandboxie-Plus\Start.exe" /box:AMPBox delete_sandbox
```

**Automatic Cleanup:**
- Configure auto-delete in Sandbox Options
- Or use scheduled task to clean sandboxes daily

### 4. Multiple Sandboxes

**Isolation Strategy:**
- Create separate sandbox for each application type
- Example: `DiscordBots`, `WebServers`, `UntrustedApps`
- Prevents cross-contamination between applications

---

## Troubleshooting

### Issue 1: Application Won't Start

**Symptoms:**
- Instance fails to start
- No console output
- Immediate failure

**Solutions:**
1. **Verify Sandboxie-Plus is installed:**
   ```cmd
   dir "C:\Program Files\Sandboxie-Plus\Start.exe"
   ```

2. **Test Sandboxie manually:**
   ```cmd
   "C:\Program Files\Sandboxie-Plus\Start.exe" /box:AMPBox cmd.exe
   ```

3. **Check sandbox exists:**
   - Open Sandboxie-Plus
   - Verify sandbox name matches configuration

4. **Check file permissions:**
   - Ensure AMP service account can access Sandboxie
   - Ensure sandbox has read access to application directory

### Issue 2: Console Output Not Appearing

**Symptoms:**
- Application runs but no output in AMP console
- Ready state not detected

**Solutions:**
1. **Test output capture:**
   ```cmd
   "C:\Program Files\Sandboxie-Plus\Start.exe" /box:AMPBox /wait cmd.exe /c "echo Test output"
   ```

2. **Check application output:**
   - Some applications don't output to console
   - Check if application writes to log files instead

3. **Disable output buffering:**
   - Some applications buffer console output
   - Check application documentation for unbuffered mode

### Issue 3: Application Can't Access Files

**Symptoms:**
- Application starts but can't read configuration files
- "File not found" errors

**Solutions:**
1. **Add file access permissions:**
   - Sandboxie-Plus → Sandbox Options → Resource Access
   - Add: `OpenFilePath=C:\Path\To\App\,*`

2. **Copy files into sandbox:**
   - Sandboxie-Plus → Sandbox → Box Content
   - Copy necessary files into sandbox

3. **Use absolute paths:**
   - Configure application to use absolute paths
   - Ensure paths are accessible from sandbox

### Issue 4: Network Access Blocked

**Symptoms:**
- Application can't connect to internet
- Network timeout errors

**Solutions:**
1. **Check network restrictions:**
   - Sandboxie-Plus → Sandbox Options → Network Access
   - Ensure "Block internet access" is disabled

2. **Allow specific programs:**
   - Add application to allowed programs list
   - Or disable network restrictions entirely

3. **Check firewall:**
   - Windows Firewall may block sandboxed applications
   - Add exception for Sandboxie-Plus

---

## Performance Considerations

### Overhead

**CPU Overhead:**
- Minimal: ~1-2% additional CPU usage
- Sandboxie uses kernel-level hooks (very efficient)

**Memory Overhead:**
- ~10-20 MB per sandbox
- Plus application's normal memory usage

**Disk I/O Overhead:**
- Minimal for read operations
- Slight overhead for write operations (copy-on-write)

**Startup Time:**
- Additional ~100-500ms startup delay
- Depends on sandbox configuration complexity

### Optimization Tips

1. **Disable unnecessary restrictions:**
   - Only enable restrictions you need
   - More restrictions = more overhead

2. **Use RAM disk for sandbox:**
   - Sandboxie-Plus supports RAM disk sandboxes
   - Faster I/O, auto-cleanup on reboot

3. **Limit sandbox size:**
   - Configure maximum sandbox size
   - Prevents disk space exhaustion

---

## Advanced: Encrypted Sandboxes

For maximum security, use encrypted sandboxes:

### Setup

1. **Create encrypted sandbox:**
   - Sandboxie-Plus → Sandbox → Create New Box
   - Enable "Encrypted Sandbox"
   - Set password

2. **Mount before use:**
   ```cmd
   "C:\Program Files\Sandboxie-Plus\Start.exe" /box:SecureBox /key:YourPassword /mount
   ```

3. **Run application:**
   ```cmd
   "C:\Program Files\Sandboxie-Plus\Start.exe" /box:SecureBox /wait MyApp.exe
   ```

4. **Unmount after use:**
   ```cmd
   "C:\Program Files\Sandboxie-Plus\Start.exe" /box:SecureBox /unmount
   ```

### Benefits

- ✅ Sandbox contents encrypted on disk
- ✅ Protection against offline analysis
- ✅ Secure deletion (just delete encrypted file)

### Limitations

- ❌ Password must be provided in command line (visible in process list)
- ❌ Slight performance overhead
- ❌ More complex to automate

---

## Example Configurations

### Example 1: Discord Bot (Medium Security)

**AMP Configuration:**
```
Application Executable Path: C:\Program Files\Sandboxie-Plus\Start.exe
Command Line Arguments: /box:DiscordBots /wait C:\Bots\MyBot.exe --config config.json
Ready Detection Pattern: Bot is ready|Logged in as
```

**Sandbox Settings:**
- Allow network access (Discord API)
- Allow read access to bot directory
- Block write access to system directories
- Auto-delete on exit: No (preserve bot data)

### Example 2: Untrusted Executable (High Security)

**AMP Configuration:**
```
Application Executable Path: C:\Program Files\Sandboxie-Plus\Start.exe
Command Line Arguments: /box:Untrusted /silent /wait C:\Downloads\suspicious.exe
Ready Detection Pattern: (leave empty)
```

**Sandbox Settings:**
- Block all file writes outside sandbox
- Block all registry writes
- Block network access (or monitor closely)
- Auto-delete on exit: Yes
- Enable resource access logging

### Example 3: Web Server (Low Security)

**AMP Configuration:**
```
Application Executable Path: C:\Program Files\Sandboxie-Plus\Start.exe
Command Line Arguments: /box:WebServers /wait C:\WebServer\server.exe --port 8080
Ready Detection Pattern: Listening on|Server started
```

**Sandbox Settings:**
- Allow network access (web server)
- Allow read/write to web root directory
- Block write access to system directories
- Auto-delete on exit: No (preserve logs)

---

## Conclusion

Sandboxie-Plus provides excellent security isolation for the Windows EXE Runner template. The integration is straightforward and adds minimal overhead while significantly improving security.

**Recommended Approach:**
1. Install Sandboxie-Plus on your AMP server
2. Create dedicated sandboxes for different application types
3. Use Method 1 (Wrapper Approach) for automatic sandboxing
4. Configure appropriate security restrictions per use case
5. Monitor sandbox activity for suspicious behavior
6. Regularly clean up sandbox contents

**When to Use:**
- ✅ Running Discord bots from unknown sources
- ✅ Testing potentially malicious executables
- ✅ Running applications that modify system files
- ✅ Isolating applications from each other
- ✅ Preventing intentional attacks on host system

**When NOT to Use:**
- ❌ Trusted, well-known applications (unnecessary overhead)
- ❌ Applications requiring kernel-level access
- ❌ Applications with anti-sandbox detection
- ❌ Performance-critical applications (minimal but measurable overhead)

---

## Additional Resources

- **Sandboxie-Plus Official Documentation**: [https://sandboxie-plus.github.io/sandboxie-docs/](https://sandboxie-plus.github.io/sandboxie-docs/)
- **Sandboxie-Plus GitHub**: [https://github.com/sandboxie-plus/Sandboxie](https://github.com/sandboxie-plus/Sandboxie)
- **Command Line Reference**: [https://sandboxie-plus.github.io/sandboxie-docs/Content/StartCommandLine/](https://sandboxie-plus.github.io/sandboxie-docs/Content/StartCommandLine/)
- **AMP Documentation**: [https://github.com/CubeCoders/AMP/wiki](https://github.com/CubeCoders/AMP/wiki)

---

**Version**: 1.0  
**Last Updated**: 2026-02-12  
**Compatibility**: Sandboxie-Plus 1.11.0+, AMP 2.6.0.0+
