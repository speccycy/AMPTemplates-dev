# Windows EXE Runner - AMP Template

A minimal AMP template for managing Windows executable (.exe) applications on Windows Server. This template allows you to run any Windows executable through AMP's standard Start/Stop/Restart interface without requiring downloads, compilation, or complex setup.

## Features

- **Simple Process Management**: Start, Stop, and Restart any Windows executable through AMP
- **Real-time Console Monitoring**: View your application's console output in real-time
- **Flexible Configuration**: Configure executable path, working directory, and command line arguments
- **Smart Ready Detection**: Automatically detect when your application is ready using regex patterns
- **Graceful Shutdown**: Properly terminates processes with configurable timeout
- **Auto-Retry**: Automatically restarts crashed applications (configurable)
- **No Dependencies**: No downloads or compilation required - use your existing executables

## Requirements

- **AMP Version**: 2.6.0.0 or higher
- **Operating System**: Windows Server (tested on Windows Server 2025)
- **Application**: Any Windows executable (.exe) file

## Installation

### 1. Add Template Repository to AMP

1. Log in to your AMP instance as an administrator
2. Navigate to **Configuration** → **New Instance Defaults** → **Configuration Repositories**
3. Click **Add New Repository**
4. Enter the repository URL (or use the built-in CubeCoders repository if this template is included)
5. Click **Fetch Latest** to download the template files

### 2. Verify Template Installation

1. Go to **Instances** → **Create New Instance**
2. In the **Application** dropdown, look for **Windows EXE Runner**
3. If you see it, the template is installed correctly

## Configuration

### Creating a New Instance

1. Navigate to **Instances** → **Create New Instance**
2. Select **Windows EXE Runner** from the Application dropdown
3. Configure the instance name and other basic settings
4. Click **Create** to create the instance

### Configuring the Executable

After creating the instance, you need to configure it to run your specific executable:

1. Open the instance and go to **Configuration** → **Application Configuration**
2. Configure the following settings:

#### Required Settings

**Application Executable Path**
- **Description**: Full path to your Windows .exe file
- **Format**: Can be relative or absolute
  - Relative: `./MyApplication.exe` (relative to instance directory)
  - Absolute: `C:\Apps\MyApplication.exe`
- **Example**: `C:\Discord\DiscordBot.exe`
- **Note**: The executable must exist at this location for the instance to start

#### Optional Settings

**Working Directory**
- **Description**: The directory where your application will run
- **Default**: `./` (instance directory)
- **Format**: Can be relative or absolute
  - Relative: `./` (instance directory)
  - Absolute: `C:\Apps\MyApp\`
- **Example**: `C:\Discord\`
- **Note**: This is where your application will look for configuration files and data

**Command Line Arguments**
- **Description**: Additional arguments to pass to your executable
- **Default**: Empty (no arguments)
- **Format**: Space-separated arguments
- **Examples**:
  - `--config config.json --verbose`
  - `--port 8080 --host 0.0.0.0`
  - `-c settings.ini -d`
- **Note**: Special characters are automatically escaped

**Ready Detection Pattern** (Advanced)
- **Description**: Regex pattern to detect when your application is ready
- **Default**: Empty (marks ready immediately after launch)
- **Format**: Regular expression pattern
- **Examples**:
  - `Application ready` - Matches exact text
  - `Started successfully|Listening on port` - Matches either pattern (using pipe)
  - `Ready.*port \d+` - Matches "Ready" followed by port number
- **Note**: Leave empty if your application doesn't output a ready message

## Example Configurations

### Example 1: Discord Bot

```
Application Executable Path: C:\Discord\DiscordBot.exe
Working Directory: C:\Discord\
Command Line Arguments: --config config.json
Ready Detection Pattern: Bot is ready|Logged in as
```

### Example 2: Simple Console Application

```
Application Executable Path: ./MyApp.exe
Working Directory: ./
Command Line Arguments: --verbose --log-level debug
Ready Detection Pattern: (leave empty for immediate ready)
```

### Example 3: Web Server Application

```
Application Executable Path: C:\WebServer\server.exe
Working Directory: C:\WebServer\
Command Line Arguments: --port 8080 --host 0.0.0.0
Ready Detection Pattern: Listening on|Server started
```

### Example 4: Game Server

```
Application Executable Path: C:\GameServer\GameServer.exe
Working Directory: C:\GameServer\
Command Line Arguments: -config server.cfg -maxplayers 32
Ready Detection Pattern: Server is ready|Accepting connections
```

### Example 5: Data Processing Application

```
Application Executable Path: ./processor.exe
Working Directory: ./data/
Command Line Arguments: --input input.csv --output output.csv
Ready Detection Pattern: Processing started|Ready to process
```

## Usage

### Starting the Application

1. Open your instance in AMP
2. Click the **Start** button
3. AMP will launch your executable with the configured settings
4. Monitor the console output to see your application's logs
5. The instance status will change to **Started** when:
   - The ready pattern is detected in console output, OR
   - Immediately after launch (if no ready pattern is configured)

### Stopping the Application

1. Click the **Stop** button
2. AMP will send a graceful shutdown signal (WM_CLOSE) to your application
3. AMP will wait up to 30 seconds for the process to terminate
4. If the process doesn't terminate within 30 seconds, AMP will force-kill it

### Restarting the Application

1. Click the **Restart** button
2. AMP will stop the application (graceful shutdown)
3. AMP will wait for the process to fully terminate
4. AMP will start the application again with the same configuration

### Viewing Console Output

- The **Console** tab shows real-time output from your application
- Both stdout and stderr are captured and displayed
- ANSI escape codes are automatically filtered for clean display
- Console output is useful for monitoring status and debugging issues

## Troubleshooting

### Instance Won't Start

**Problem**: Instance fails to start or immediately goes to Failed state

**Solutions**:
1. **Check Executable Path**: Verify the executable exists at the specified path
   - Open File Manager and navigate to the path
   - Ensure the file has a .exe extension
   - Check for typos in the path
2. **Check Working Directory**: Verify the working directory exists
   - Ensure the directory path is valid
   - Check folder permissions
3. **Check Console Output**: Look for error messages in the Console tab
   - Common errors: "File not found", "Access denied", "Missing dependencies"
4. **Test Executable Manually**: Try running the executable from Command Prompt
   - Navigate to the working directory
   - Run the executable with the same arguments
   - Check if it starts successfully

### Ready State Not Detected

**Problem**: Instance stays in "Starting" state and never reaches "Started"

**Solutions**:
1. **Check Ready Pattern**: Verify your regex pattern is correct
   - Look at the console output - does your application output the expected text?
   - Test your regex pattern using an online regex tester
   - Common mistake: Pattern is case-sensitive
2. **Use Immediate Ready Mode**: If your application doesn't output a ready message
   - Leave the Ready Detection Pattern field empty
   - Instance will be marked as ready immediately after launch
3. **Check Console Output**: Ensure your application is actually outputting to console
   - Some applications only write to log files
   - Consider using a wrapper script that outputs to console

### Application Crashes or Stops Unexpectedly

**Problem**: Application runs for a while then crashes or stops

**Solutions**:
1. **Check Console Output**: Look for error messages before the crash
2. **Check Application Logs**: Many applications write detailed logs to files
3. **Auto-Retry Feature**: AMP will automatically restart crashed applications
   - Default: 2 retry attempts
   - After exhausting retries, instance remains in Failed state
4. **Test Outside AMP**: Run the executable manually to see if it's an application issue
5. **Check System Resources**: Ensure sufficient RAM, CPU, and disk space

### Multiple Instances Conflict

**Problem**: Running multiple instances causes port conflicts or other issues

**Solutions**:
1. **Configure Different Ports**: If your application uses network ports
   - Use different port numbers in Command Line Arguments for each instance
   - Example: Instance 1 uses `--port 8080`, Instance 2 uses `--port 8081`
2. **Use Separate Working Directories**: Ensure each instance has its own directory
   - Prevents configuration file conflicts
   - Prevents data file conflicts
3. **Check Application Limitations**: Some applications don't support multiple instances
   - Check your application's documentation
   - Consider using separate servers or virtual machines

### Graceful Shutdown Takes Too Long

**Problem**: Stopping the instance takes the full 30 seconds

**Solutions**:
1. **Check Application Shutdown**: Your application may not be responding to WM_CLOSE
   - Some applications don't handle Windows close signals properly
   - Consider modifying your application to handle shutdown signals
2. **Accept the Timeout**: 30 seconds is a reasonable timeout for most applications
   - AMP will force-kill after timeout to ensure the instance stops
3. **Check for Hung Processes**: Application may be stuck in an infinite loop
   - Check application logs for errors
   - Consider fixing the application code

## Advanced Configuration

### Port Configuration

If your application uses network ports, you can configure them in AMP:

1. Go to **Configuration** → **Ports**
2. Configure the **Custom Port** setting
3. AMP can manage firewall rules for configured ports (optional)

**Note**: Many applications don't need port configuration in AMP. Only configure ports if you need AMP to manage firewall rules or if you want to track which ports are in use.

### Resource Limits

The template includes basic resource management:

- **Auto-Retry Count**: 2 attempts (application will restart automatically if it crashes)
- **Exit Timeout**: 30 seconds (maximum time to wait for graceful shutdown)
- **Max Users**: Not applicable for general executables (set to 0)

These settings are configured in the template and generally don't need to be changed.

### Console Filtering

The template automatically filters ANSI escape codes from console output for clean display. This is useful for applications that use colored console output or terminal control sequences.

## Technical Details

### Process Management

- **Launch Method**: AMP launches your executable as a child process
- **Termination Method**: OS_CLOSE (sends WM_CLOSE signal for graceful shutdown)
- **Exit Timeout**: 30 seconds before force-kill
- **Console Capture**: Both stdout and stderr are captured and displayed

### File Structure

The template consists of five configuration files:

- `windows-exe-runner.kvp` - Main template definition
- `windows-exe-runnerconfig.json` - User-configurable settings
- `windows-exe-runnermetaconfig.json` - Metadata configuration (empty)
- `windows-exe-runnerports.json` - Port definitions
- `windows-exe-runnerupdates.json` - Update sources (empty)

### Template Variables

The template uses the following variables that are replaced at runtime:

- `{{ExecutablePath}}` - User-configured executable path
- `{{WorkingDirectory}}` - User-configured working directory
- `{{CommandLineArgs}}` - User-configured command line arguments
- `{{ReadyPattern}}` - User-configured ready detection regex

## Limitations

- **Windows Only**: This template only works on Windows Server
- **No stdin Support**: Applications cannot receive keyboard input through AMP console
- **No Download/Update**: Template doesn't support automatic downloads or updates
- **No RCON/Admin**: Template doesn't support RCON or remote admin protocols
- **Basic Monitoring**: Only console output monitoring is supported

## Support

For issues or questions:

1. Check the **Console** tab for error messages
2. Review this README for troubleshooting steps
3. Test your executable manually outside of AMP
4. Check AMP logs for detailed error information
5. Consult your application's documentation

## License

This template is provided as-is for use with CubeCoders AMP. See the AMP license for terms and conditions.

## Version History

- **v1.0** - Initial release
  - Basic executable management
  - Console output monitoring
  - Configurable ready detection
  - Graceful shutdown support
