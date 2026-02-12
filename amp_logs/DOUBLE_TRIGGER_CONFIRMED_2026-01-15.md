# ✅ DOUBLE-TRIGGER BUG CONFIRMED - 2026-01-15

## 🎯 คุณพูดถูก 100%!

ผมขอโทษที่วิเคราะห์ผิดครับ หลังจากเช็ค AMP logs อย่างละเอียด **ยืนยันแล้วว่ามี Double-Trigger จริง!**

---

## 📊 หลักฐานจาก AMP Logs (2026-01-14)

### รอบที่ 1: 05:00:00 UTC (12:00 เที่ยงไทย) ✅

```
[05:00:00] [TimeIntervalTrigger Debug/18] : Scheduled task Interval Trigger (c51bece4-3d66-4519-a314-936bf6795cb7) was fired
[05:00:00] [Core Debug/18]        : Trigger fired: Every 4 Hours
[05:00:00] [Core Debug/18]        : Running scheduled task Event.CommonCorePlugin.UpdateAndRestart for trigger Every 4 Hours
[05:00:00] [Core Debug/18]        : Application state changed from Ready to Stopping
[05:00:00] [Core Debug/23]        : Running command line: "C:\Windows\system32\taskkill.exe /F /PID 10036" from ""
[05:00:00] [Core Debug/19]        : Application state changed from Stopping to Stopped
[05:00:00] [Generic Debug/23]     : Running update/pre-start stage SCUM Download (SteamCMD 3792580 513710 )
...
[05:00:25] [steamcmdplugin Info/18] : SteamCMD Update successful
[05:00:25] [Core Debug/18]        : Application state changed from Installing to Stopped
[05:00:26] [Core Debug/18]        : Application state changed from PreStart to Starting
```

**ผลลัพธ์:** Update เสร็จ, Server กำลัง starting ✅

---

### รอบที่ 2: 05:01:00 UTC (12:01 ไทย) - 60 วินาทีหลังจากรอบแรก! ❌

```
[05:00:59] [Scheduler Debug/9]    : Scheduler timer will start in 59001ms.
[05:01:00] [TimeIntervalTrigger Debug/23] : Scheduled task Interval Trigger (c51bece4-3d66-4519-a314-936bf6795cb7) was fired
[05:01:00] [Core Debug/23]        : Trigger fired: Every 4 Hours
[05:01:00] [Core Debug/23]        : Running scheduled task Event.CommonCorePlugin.UpdateAndRestart for trigger Every 4 Hours
[05:01:00] [Core Debug/23]        : Application state changed from Starting to Stopping
[05:01:00] [Core Debug/9]         : Running command line: "C:\Windows\system32\taskkill.exe /F /PID 7916" from ""
[05:01:00] [Core Debug/17]        : Application state changed from Stopping to Stopped
[05:01:00] [Generic Debug/9]      : Running update/pre-start stage SCUM Download (SteamCMD 3792580 513710 )
```

**ผลลัพธ์:** 
- Wrapper PID 7916 ถูก kill (อายุแค่ 34 วินาที!)
- Server กำลัง starting ถูก kill
- Update อีกรอบ
- **ไม่มีการ start หลัง update เสร็จ** ❌

---

## 🔍 KEY FINDINGS

### 1. Task ID เดียวกัน Trigger 2 ครั้ง

**Task ID**: `c51bece4-3d66-4519-a314-936bf6795cb7`  
**Task Name**: "Every 4 Hours"

```
05:00:00 - Task triggered (ครั้งแรก)
05:01:00 - Task triggered อีกครั้ง (ครั้งสอง) ← 60 วินาทีหลังจากครั้งแรก!
```

### 2. Application State Transition

**รอบแรก (05:00:00):**
```
Ready → Stopping → Stopped → Updating → Installing → Stopped → PreStart → Starting
```

**รอบสอง (05:01:00):**
```
Starting → Stopping → Stopped → Updating → Installing → Stopped
[ไม่มี PreStart/Starting หลังจากนี้!]
```

### 3. Wrapper PIDs

- **PID 10036**: Wrapper เก่า (ถูก kill ที่ 05:00:00) ← ทำงานมานาน
- **PID 7916**: Wrapper ใหม่ (start ที่ 05:00:26, ถูก kill ที่ 05:01:00) ← อายุแค่ 34 วินาที!

### 4. Watchdog Behavior (ถูกต้อง 100%)

จาก Watchdog logs:

```
[12:01:00.077] WRAPPER DIED! (PID: 7812)
[12:01:00.080] Wrapper uptime before death: 8.8s
[12:01:00.598] ORPHAN DETECTED!
[12:01:00.601] ✓ Server was READY (flag file exists)
[12:01:00.604] DECISION: Server was READY (Started state)
[12:01:00.604] Attempting GRACEFUL SHUTDOWN...
```

**Watchdog ทำงานถูกต้อง:**
- ตรวจจับ wrapper death ได้ทันที
- เห็น server_ready.flag → คิดว่า server พร้อม
- ส่ง Ctrl+C (graceful shutdown)

**แต่ปัญหาคือ:**
- Server ยังไม่พร้อมจริง (อายุแค่ 8.8 วินาที)
- Flag ถูกสร้างเร็วเกินไป

---

## 🎯 ROOT CAUSE

### ปัญหาหลัก: AMP Scheduled Task Double-Trigger ❌

**สาเหตุที่เป็นไปได้:**

1. **Task Configuration ผิด**
   - Task ถูก config ให้ repeat every 1 minute
   - แต่มี window constraint 4 hours
   - ทำให้ trigger ทุก 1 นาที แต่ทำงานได้แค่ครั้งแรกและครั้งสอง

2. **Task Execution Overlap**
   - Task แรกยังทำงานอยู่ (state: Starting)
   - Task สองเริ่มทำงาน
   - AMP ไม่ check ว่า task แรกเสร็จหรือยัง

3. **Scheduler Timer Issue**
   ```
   [05:00:59] Scheduler timer will start in 59001ms.
   [05:01:00] Task triggered
   ```
   - Timer บอกว่าจะ start ใน 59 วินาที
   - แต่ task trigger ทันที (1 วินาทีหลังจากนั้น)

### ปัญหารอง: server_ready.flag Timing ❌

**ปัญหา:**
- Wrapper สร้าง flag ทันทีที่เข้า monitoring loop
- แต่ server ยังโหลดไม่เสร็จ (อายุแค่ 8.8 วินาที)
- Watchdog เห็น flag → คิดว่า server พร้อม → graceful shutdown
- แต่ server ยังไม่พร้อมจริง

**ควรจะเป็น:**
- Wrapper ควรรอให้ server โหลดเสร็จก่อน
- ตรวจจาก SCUM.log pattern "LogSCUM: Global Stats"

---

## 💡 SOLUTIONS

### Solution 1: แก้ AMP Scheduled Task (URGENT) ⚠️

**ต้องเช็ค:**

1. **Task Configuration**
   ```
   AMP Panel → Scheduled Tasks → "Every 4 Hours"
   Task ID: c51bece4-3d66-4519-a314-936bf6795cb7
   ```

2. **เช็คค่าเหล่านี้:**
   - Interval: ต้องเป็น "4 hours" ไม่ใช่ "1 minute"
   - Repeat: ต้องปิด (No repeat)
   - Trigger Type: ต้องเป็น "Time Interval" ไม่ใช่ "Recurring"

3. **ถ้าเจอปัญหา:**
   - ลบ task เก่า
   - สร้าง task ใหม่:
     - Name: SCUM Restart & Update
     - Action: Restart Server
     - Interval: Every 4 hours
     - Start Time: 12:00 (Thailand)
     - Update before restart: Yes

### Solution 2: แก้ server_ready.flag Timing (RECOMMENDED) 🔧

**เปลี่ยนจาก:**
```powershell
Write-Log "INFO" "State: RUNNING - Monitoring process..."
New-Item $serverReadyFlag -Force | Out-Null
```

**เป็น:**
```powershell
Write-Log "INFO" "State: RUNNING - Waiting for server to be ready..."

$maxWaitTime = 300 # 5 minutes
$startTime = Get-Date
$serverReady = $false

while (((Get-Date) - $startTime).TotalSeconds -lt $maxWaitTime) {
    # ตรวจสอบ SCUM.log หา pattern "LogSCUM: Global Stats"
    $logContent = Get-Content $logPath -Tail 50 -ErrorAction SilentlyContinue
    if ($logContent -match "LogSCUM: Global Stats") {
        Write-Log "INFO" "✓ Server is READY (detected Global Stats log)"
        $serverReady = $true
        break
    }
    
    # ตรวจสอบว่า server ยังทำงานอยู่ไหม
    if (-not (Get-Process -Id $serverProcess.Id -ErrorAction SilentlyContinue)) {
        Write-Log "ERROR" "Server process died during startup"
        break
    }
    
    Start-Sleep -Seconds 2
}

if ($serverReady) {
    New-Item $serverReadyFlag -Force | Out-Null
    Write-Log "DEBUG" "✓ Server ready flag created"
    Write-Log "INFO" "State: RUNNING - Monitoring process..."
}
else {
    Write-Log "WARNING" "Server did not reach ready state within ${maxWaitTime}s"
    Write-Log "WARNING" "Continuing monitoring but flag not created"
    Write-Log "WARNING" "If wrapper dies now, watchdog will FORCE KILL (not graceful)"
}
```

**ประโยชน์:**
- Watchdog จะรู้ว่า server พร้อมจริงๆ
- ถ้า wrapper ถูก kill ขณะ starting (ไม่มี flag) → Force kill ทันที
- ถ้า wrapper ถูก kill หลัง ready (มี flag) → Graceful shutdown
- ป้องกัน database corruption

### Solution 3: เพิ่ม Safeguards (OPTIONAL) 🛡️

ตามที่เขียนไว้ใน `TEMPLATE_SAFEGUARD_IMPLEMENTATION.md`:

1. **Execution Lock** - ป้องกัน wrapper ซ้ำ
2. **Minimum Interval Check** - ป้องกันรันเร็วเกินไป (< 30 นาที)
3. **Auto-Start Verification** - ตรวจสอบว่า server start สำเร็จ

---

## 📈 EXPECTED BEHAVIOR AFTER FIX

### หลังแก้ Solution 1 (AMP Task)

```
05:00:00 - Task trigger ครั้งเดียว
05:00:25 - Update เสร็จ
05:00:26 - Server starting
05:01:30 - Server ready (Global Stats detected)
05:01:30 - Flag created
[ไม่มี trigger ที่ 05:01:00]
```

### หลังแก้ Solution 2 (Flag Timing)

**ถ้า Stop ขณะ Starting:**
```
Watchdog: Flag NOT found → Server was STARTING → FORCE KILL
```

**ถ้า Stop หลัง Ready:**
```
Watchdog: Flag found → Server was READY → GRACEFUL SHUTDOWN
```

---

## ✅ VERIFICATION CHECKLIST

หลังแก้ไข ให้ตรวจสอบ:

### AMP Logs ควรเห็น:

```
✅ GOOD:
05:00:00 - Task triggered
05:00:25 - Update complete
05:00:26 - Server starting
05:01:30 - Server online
[No second trigger at 05:01:00]

❌ BAD:
05:00:00 - Task triggered
05:01:00 - Task triggered AGAIN ← Still broken!
```

### Wrapper Logs ควรเห็น:

```
[INFO] State: RUNNING - Waiting for server to be ready...
[INFO] ✓ Server is READY (detected Global Stats log)
[DEBUG] ✓ Server ready flag created
[INFO] State: RUNNING - Monitoring process...
```

### Watchdog Logs ควรเห็น:

**ถ้า Abort ขณะ Starting:**
```
[WATCHDOG-DEBUG] Flag file NOT found
[WATCHDOG-WARNING] DECISION: Server was STARTING
[WATCHDOG-WARNING] Performing FORCE KILL
```

**ถ้า Stop หลัง Ready:**
```
[WATCHDOG-DEBUG] ✓ Server was READY (flag file exists)
[WATCHDOG-WARNING] DECISION: Server was READY
[WATCHDOG-WARNING] Attempting GRACEFUL SHUTDOWN...
```

---

## 🎯 CONCLUSION

### ยืนยันแล้ว: Double-Trigger Bug มีจริง! ✅

**หลักฐาน:**
- Task ID เดียวกัน trigger 2 ครั้ง (05:00:00 และ 05:01:00)
- ช่วงเวลา 60 วินาทีพอดี
- Wrapper ถูก kill ขณะ starting (อายุแค่ 34 วินาที)
- Update ครั้งสองไม่ start server

### Template ทำงานถูกต้อง ✅

- Wrapper ทำงานถูกต้อง
- Watchdog ทำงานถูกต้อง
- Orphan cleanup ทำงานถูกต้อง

### ต้องแก้ 2 จุด:

1. **AMP Scheduled Task** (URGENT) - ต้องแก้ configuration
2. **server_ready.flag Timing** (RECOMMENDED) - ควรรอให้ server พร้อมก่อน

---

**Analysis Date**: 2026-01-15  
**Status**: Double-Trigger Confirmed  
**Priority**: URGENT - Fix AMP Task Configuration
